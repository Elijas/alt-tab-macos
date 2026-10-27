# AltTab Fork Development

## Docs Index

Detailed guides in `docs/`:
- [`docs/window-debugging-guide.md`](docs/window-debugging-guide.md) — debugging window discovery, ordering, and timing issues. CGWindowList cross-check scripts, architecture diagrams, timing constants, known issues.
- [`docs/tab-hierarchy-guide.md`](docs/tab-hierarchy-guide.md) — macOS native tab internals, why every obvious matching approach fails, the AX forward-lookup algorithm, data flow diagrams, staleness fixes, debugging commands.
- [`docs/group-sort-guide.md`](docs/group-sort-guide.md) — tab-aware sort stability via min() group keys, how it aligns side panel / main popup / CLI scripts, independence from tab display toggles, AX query gating for performance.
- [`docs/post-merge-upstream-v10.9.md`](docs/post-merge-upstream-v10.9.md) — upstream merge (v10.2→v10.9) conflict resolution notes. Covers the singleton migration (`App.app.*` → `App.*`), blacklist→exceptions rename, event throttling, and every file touched.
- [`docs/post-merge-upstream-v10.11.md`](../../post-merge-upstream-v10.11.md) — upstream merge (v10.9→v10.11) conflict resolution notes. Covers the `AXCallScheduler` migration, `TabGroup.swift` coexistence, `TabHierarchy.swift` extraction, MainMenu .xib→programmatic migration, and every file touched. **Read this first if something broke after the merge.**
- [`docs/gesture-tab-filter-fix.md`](docs/gesture-tab-filter-fix.md) — why gesture showed tabs as separate windows but keyboard didn't. Root cause: `showTabHierarchyInMainPanel` silently overriding `showTabsAsWindows` + empty `spaceIds` on inactive tabs leaking through per-shortcut space filters. Diagnostic method: `--detailed-list` CLI + `defaults read`.

In-line below: **Crash Forensics** (IPS → dSYM archive → `app.log` breadcrumbs → `atos`, plus the known race-condition signature).

## Build & Install

```bash
cd /Users/user/Development/_forks/alt-tab-dev && ./rebuild.sh
```

`rebuild.sh` does everything in one go: builds (Release, ad-hoc signed) into a project-local `./DerivedData`, archives the dSYM by UUID, kills the running app, resets TCC, removes the old install, copies fresh, and launches. Read the script for exact steps.

**Why all this dance is necessary:**

- **Always Release, never Debug.** Debug enables `NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints` which poisons UserDefaults (see the "UserDefaults poisoning" gotcha below), and Debug builds skip compiler optimizations making performance profiling meaningless. The `alt-tab-dev` worktree is the daily-driver build — treat every build as production.

- **TCC permission reset is mandatory after every rebuild.** Ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) produces a different CDHash every build. macOS TCC ties permissions to the CDHash, so existing permission entries become stale after rebuild — they look "on" in System Settings but the app can't use them. The script uses `tccutil reset All` (not individual services) and kills the running app BEFORE resetting (resetting while the app is running leaves stale entries).

- **The .app must be removed before copying.** `ditto` over an existing .app can leave stale code signature caches. The script `rm -rf`s the install path first.

- **dSYM must be archived by UUID before next build.** Future crash reports in `~/Library/Logs/DiagnosticReports/at004-*.ips` can be symbolicated even after subsequent rebuilds overwrite the dSYM in DerivedData. The script copies the dSYM to `~/Library/Logs/at004/dsyms/<UUID>/` keyed by its arm64 UUID.

- **Project-local DerivedData (`./DerivedData`).** The script uses `-derivedDataPath ./DerivedData` rather than the shared `~/Library/Developer/Xcode/DerivedData/alt-tab-macos-*` location. Xcode generates new hash directories after toolchain/scheme state changes; without a fixed path, you can end up installing a stale .app whose `.app` dir was touched by post-build steps more recently than a freshly-compiled one (the original `find_newest_product` picker in `rebuild.sh` had exactly that bug — fixed 2026-05-21, see commit `b1b7061c`).

macOS will re-prompt for Accessibility and Screen Recording on launch. Screen Recording may not auto-prompt on macOS Sequoia for ad-hoc signed apps — user must manually add in System Settings.

## Crash Forensics

**AppCenter is wired but doesn't upload** — `Info.plist` has the literal placeholder `AppCenterSecret = #APPCENTER_SECRET#`, so nothing leaves the machine. **However, AppCenter still writes local crash dumps** in PLCrashReporter format. Combined with macOS IPS files, you have two on-disk signals:

### Where things live
- **IPS crash files**: `~/Library/Logs/DiagnosticReports/at004-*.ips` (recent), `Retired/` (rotated by macOS). May not appear immediately — sometimes takes a minute, occasionally not at all.
- **AppCenter local crash dumps**: `~/Library/Application Support/com.lwouis.alt-tab-macos.at004/com.microsoft.appcenter/crashes/<id>` — binary PLCrashReporter format (`plcrash\x01` magic + protobuf payload). **⚠️ Usually already purged by the time you look** — the "Send a crash report?" dialog is a *tombstone*, not proof the dump is still readable. See "Why crashes get lost" below before relying on this path.
- **App logs**: `~/Library/Logs/at004/app.log` — `.info`+ via SwiftyBeaver `FileDestination` configured in `src/api-wrappers/Logger.swift:initialize()`. **No rotation** (SwiftyBeaver 1.9.0 lacks `logFileAmount`); the file grows indefinitely — `rm` it manually when needed. Survives Finder/Dock launches where the `ConsoleDestination` (stdout) goes nowhere.
- **Archived dSYMs**: `~/Library/Logs/at004/dsyms/<UUID>/at004.app.dSYM`, written by `./rebuild.sh`. Each rebuild produces a new UUID (ad-hoc signing changes the CDHash and the dSYM UUID), and DerivedData overwrites the prior dSYM in-place — so without this archive, every previous build's symbols are gone.

### Investigating a new IPS
1. Extract `slice_uuid` from the first JSON line of the IPS file.
2. Match against `~/Library/Logs/at004/dsyms/<slice_uuid>/at004.app.dSYM`. **If missing, the symbols are gone** — the next IPS from this build is the only recoverable one.
3. Read the `usedImages` entry where `name == "at004"` to find the binary `base` address.
4. For each frame in `faultingThread.frames` (or `lastExceptionBacktrace`) with `imageIndex` matching the at004 entry:
   ```
   atos -arch arm64 -o <dSYM>/Contents/Resources/DWARF/at004 -l <base> $((<base> + <imageOffset>))
   ```
5. Cross-reference with `app.log` entries from the minute before the IPS `captureTime` — `.info`-level breadcrumbs on the main thread (window/AX events) help reconstruct what the app was doing.

### Investigating an AppCenter dump (when no IPS yet)
PLCrashReporter format = `plcrash\x01` magic + protobuf payload. There's no shipped CLI to parse it, but the schema is small enough to read with raw protobuf:
- Top-level field 3 = Threads (repeated). Crashed thread has nested field 3 = `1` (bool).
- Top-level field 4 = BinaryImages (repeated): nested `1`=base, `2`=size, `3`=path string, `4`=uuid bytes.
- Top-level field 6 = Signal (with name like `SIGTRAP` and code like `TRAP_BRKPT`).
- StackFrame: nested field 3 = PC.

A quick `uvx --with protobuf python3` script can extract crashed-thread PCs and the at004 base, then you `atos -arch arm64 -o <DWARF> -l <base> <pc>` per-frame just like an IPS. **Important**: `dwarfdump --uuid <dSYM>` lists x86_64 first, then arm64 — `./rebuild.sh` filters with `awk '/arm64/'` to archive under the correct UUID for Apple Silicon crashes.

### Known crash signature: cross-thread Swift `Dictionary` race
- **Exception**: `NSInvalidArgumentException` / `EXC_CRASH (SIGABRT)`
- **Message**: `-[NSIndirectTaggedPointerString objectForKey:]: unrecognized selector sent to instance 0x8000000000000000`
- **Stack**: `__CocoaDictionary.lookup(_:)` (libswiftCore) called from at004 inside `-[NSBlockOperation main]` running on `_dispatch_worker_thread2`.
- **Root cause class**: a Swift `Dictionary` static (e.g. `Spaces.screenSpacesMap`, `Spaces.currentSpaceForScreen`, `TabHierarchy.lastParentMap`) is mutated on the main thread while a background queue (`accessibilityCommandsQueue`, `axCallsFast`, `axCallsRetry`) reads it. Copy-on-Write reallocates storage; the reader chases freed memory; the runtime resolves the slot to whatever tagged pointer happens to live there, often `NSIndirectTaggedPointerString`.
- **Hot suspects**: `Window.swift:227-258` (background block on `accessibilityCommandsQueue` reading `Windows.list`); `Window.swift:316,327` reading `Spaces.idsAndIndexes`/`Spaces.screenSpacesMap` from `updateSpacesAndScreen()` callable on background queues; `Spaces.swift:46-72` mutates the static dicts without locks.
- **Fix shape**: with a symbolicated frame in hand, either marshal the read to the main thread (`DispatchQueue.main.sync`) or wrap the dict in an `NSLock`/serial queue. Don't lock everything blindly — pin the fix to whatever line the symbolication actually names.

### Why crashes get lost — and the `app.log` breadcrumb that prevents it

**Anomaly (observed 2026-06-19):** by the time the "Send a crash report?" dialog appears, the on-disk crash dump is usually **already gone**. All four signals can be empty *simultaneously*:
- **No IPS** — macOS frequently writes none for at004 (`DiagnosticReports/` and `Retired/` both empty). The "occasionally not at all" caveat above is the common case here, not the rare one.
- **PLCrashReporter `.plcrash` purged** — AppCenter consumes and deletes `~/Library/Caches/com.plausiblelabs.crashreporter.data/com.lwouis.alt-tab-macos.at004/` during the launch-time processing pass that *triggers* the dialog.
- **AppCenter `crashes/<id>` empty** and **`crasheslogbuffer/*` flushed to 0 bytes** on the same launch.
- **`Logs.sqlite`** holds only `MSACStartServiceLog` telemetry (these accumulate forever since nothing uploads) — never a crash payload.

Dump lifetime is: crash → next launch's AppCenter processing reads it into memory → **purges it from disk** → shows the dialog. Investigating *after* the dialog appears is too late.

**Mitigation (added 2026-06-19):** `AppCenterCrash.logCrashReports()` (`src/logic/AppCenterCrashes.swift`) writes the crash details to `app.log` from the `userConfirmationHandler` — *before* the dialog and before any purge. Grep:
```
grep "CRASH IN PREVIOUS SESSION" ~/Library/Logs/at004/app.log
```
Fields: `incidentId`; `pid` (= `appProcessIdentifier` — locate the crashed session's breadcrumbs in the same file); `signal`; `isAppKill` (true ⇒ watchdog/OOM kill, not an exception); `exception`/`reason` (the `NSException` name + message — for the Dictionary race this is `NSInvalidArgumentException` + the `unrecognized selector … NSIndirectTaggedPointerString` text, which IDs the bug **without** a stack); `appStart`/`appError` (local time, matching the breadcrumb format).

**Ordering requirement:** `Logger.initialize()` must run **before** `AppCenterCrash()` in `App.applicationDidFinishLaunching` (`src/ui/App.swift`). AppCenter's confirmation callback can fire during/just after `AppCenter.start`; if `app.log`'s `FileDestination` isn't up yet the breadcrumb is silently dropped. These two lines were reordered 2026-06-19 — don't swap them back.

**Limitation — KNOWN UNKNOWN:** `ErrorReport` exposes no per-frame backtrace, so the breadcrumb gives exception name/reason + signal but **not** a symbolicated stack. For an `NSException` crash (the common at004 case) the reason usually names the failing selector — enough to pin the bug. For a pure signal crash (e.g. `SIGSEGV` with no exception) you still need an IPS/`.plcrash`, i.e. you must catch it before purge; the next step there would be a `CrashesDelegate.shouldProcessErrorReport`-time copy of the `.plcrash` to a durable path.

### Case study: 2026-06-19 05:43 crash (stack unrecoverable)
The crash that motivated the breadcrumb above. Reconstructed purely from `app.log` because every dump was already purged:
- Crashed instance **pid 50063**; log ends abruptly at **05:43:14.823** with no shutdown marker; relaunch at **05:46:06.812**.
- Final ~40s: rapid Mission Control `setState()` toggling (`showAllWindows`⇄`showDesktop`⇄`inactive`, ~10×/27s) + a `--detailed-list` / `--open-main-panel` CLI invocation + a burst of Main Panel `AXWindowMoved`.
- **Hypothesis (unconfirmed — no stack):** the cross-thread `Dictionary` race above. Rapid Space churn mutates `Spaces.*` dicts on the main thread while the panel-open path + side-panel discovery queue read them. Consistent with the signature but **not proven** — the new breadcrumb would have confirmed or refuted it via `exception`/`reason`.

## Renaming the Build

To bump the app name (e.g. at004 → at005), change two places:

1. `alt-tab-dev/config/base.xcconfig` — `PRODUCT_NAME` and `PRODUCT_BUNDLE_IDENTIFIER`
2. `personal-workbench/w260126_alttab_workaround/src/alttab-trigger.sh` and `alttab-trigger-shift.sh` — `APP_NAME` variable

These are self-adjusting and don't need manual updates:
- `CliEvents.swift` — port name derives from `Bundle.main.bundleIdentifier` at runtime
- `cycle-next.jq` / `cycle-prev.jq` — blacklist uses prefix `com.lwouis.alt-tab-macos.at` to match all at* builds

## Worktrees

`alt-tab-dev` is the daily-driver build (treat as production). It's called "dev" only because `master` tracks the upstream public release — not because `dev` is unstable.

| Path | Branch | Purpose |
|------|--------|---------|
| `alt-tab-macos` | `master` | Upstream tracking (public release) |
| `alt-tab-dev` | `dev` | **Daily-driver build — treat as production** |
| `alt-tab-cli-api` | `cli-data-api` | CLI data API feature |
| `alt-tab-sidepanel-pr` | `sidepanel-pr` | Clean side panel (shareable) |
| `alt-tab-sidepanel-collapse-fix` | `fix/sidepanel-collapse` | Fix: side-panel reserve expanded hover area |
| `alt-tab-tab-hierarchy-fix` | `fix/tab-hierarchy-stability` | Fix: stabilize tab hierarchy parent mapping |
| `alt-tab-ui-experiments` | `ui-experimentation` | UI experiments — incl. stranded feature below |

> **Branch cleanup (2026-06-22):** `disable-screenshots` (a misnamed `dev` continuation — the name came from its first commit, "disable window-content capture to stop ScreenCaptureKit freeze") was fast-forward-folded into `dev` and deleted (local + remote). The old `alt-tab-sidepanel` worktree + `sidepanel` branch (Feb 2026 "side panel with debug logging" dev snapshot, 199 commits behind `dev`) was removed — superseded by `dev`, preserved as tag `archive/sidepanel-debug-snapshot-2026-02-22` (pushed to origin). Local-only `pr-5318` (an exact dup of `cli-data-api`) was dropped.

> **Stranded feature (`ui-experimentation`, not integrated):** a multiple-shortcuts-with-overrides Settings redesign — custom `tabs/shortcuts/ShortcutsTab.swift` + `OverridableRow.swift` (~1700 lines): per-shortcut settings that inherit/override base defaults via a simple↔multi mode toggle (`multipleShortcutsEnabled` pref). Orphaned because it was built on the v10.1.0 settings UI, which upstream replaced the next day with its "new settings experience" (#5287, now `tabs/controls/ControlsTab.swift`). **Not mergeable as-is** — references since-deleted `ControlsSection`/`PoliciesTab`/`BlacklistsTab`. Reviving = reimplementing the override UX on today's `ControlsTab`, not a merge. Kept as idea-archive (feature commits: `5fa9dcee`, `5eeb0b79`, `b2fddb6c`).

## Window Cycling (`--cycle`)

skhd shortcuts `Ctrl+Opt+9` / `Ctrl+Opt+0` cycle windows on the current screen.

- skhd config: `~/.skhdrc` (under "AltTab Workaround")
- Shell scripts: `personal-workbench/w260126_alttab_workaround/src/alttab-trigger.sh` / `alttab-trigger-shift.sh`
- Server implementation: `CliEvents.swift` — `enqueueCycle()` / `executeCycle()`
- Legacy jq scripts (still present, no longer used by shell): `cycle-next.jq` / `cycle-prev.jq`

### Architecture: server-side cycle with leading-edge batching

The shell scripts are trivial one-liners: `at004 --cycle=1` / `at004 --cycle=-1`. All logic lives server-side in `CliEvents.swift`.

**The `--cycle=N` command** (positive = next, negative = prev) enqueues N steps into a batching state machine on the main thread:

```
State machine (CliEvents.swift):
  IDLE + press → executeCycle(N) immediately, start 30ms batch timer (BATCHING)
  BATCHING + press → just accumulate pendingCycleSteps (timer handles it)
  Timer fires, pending > 0 → executeCycle(pending), restart timer
  Timer fires, pending == 0 → IDLE
```

**Why leading-edge**: First press in a burst executes with zero added latency. Rapid follow-ups batch into a single `focus()` call every 30ms. This avoids visual jank from rapid window raises AND handles unreliable message delivery (each CLI call just increments a counter and returns immediately — no focus operation blocks the IPC response).

**`executeCycle()` does**: `Spaces.refresh()` (~1-5ms CGS call), cheap-filter `Windows.list` (windowless/minimized/hidden/excluded), refresh each survivor's `updateSpacesAndScreen()`, then filter by mouse screen + visible space, sort by `creationOrder`, find current via `min(lastFocusOrder)`, advance N steps with wrap-around, `focus()` + `updateLastFocusOrder()`.

### Why `updateLastFocusOrder` is called eagerly

`window.focus()` dispatches the actual AX/CGS work to `accessibilityCommandsQueue` asynchronously. The `lastFocusOrder` array normally updates only when macOS fires `kAXFocusedWindowChangedNotification` back (~50-250ms roundtrip). By calling `updateLastFocusOrder()` synchronously right after `focus()`, the next cycle call sees fresh state. This is idempotent — when the AX notification arrives later, the guard `focusedWindow.lastFocusOrder != 0` short-circuits.

### Per-window space refresh (was a trade-off, now done)

`--cycle` originally skipped per-window `updateSpacesAndScreen()` for performance and relied on AX event callbacks (move/resize/focus) + the 10-second discovery timer to keep `spaceIds`/`screenId` fresh. **This was wrong**: `screenId` is cached and only updated when an AX event fires, so a window that changed monitors keeps a stale `screenId` *indefinitely* — not just "while you're cycling". The stale window then leaks into the wrong monitor's cycle (observed 2026-06-15: a Chrome window that had moved screens bled into the center monitor's cycle; closing it made the symptom vanish). The old assumption "the user isn't moving windows while rapidly cycling" missed that the move can have happened at any earlier point.

Fix (`CliEvents.swift` `executeCycle()`): cheap-filter first (no IPC), then call `updateSpacesAndScreen()` on each survivor before the screen/space match — same pattern `--detailed-list` already used. Cost is one CGS `cgWindowId.spaces()` call per *eligible* window (not all windows, and not AX brute-force), on the main thread, at most once per 30ms batch tick. **Note this means `--detailed-list` no longer reveals the bug** — it refreshes the same state, so a divergence between live cycling and the diagnostic was itself the tell.

### Known issue: `isTabbed` false positives

Since v10.11, upstream uses event-driven tab detection via `TabGroup.updateState()` (called from `AccessibilityEvents.handleEventWindow()`). This sets `isTabbed` and `tabbedSiblingWids` based on AX tab group children, replacing the old heuristic `detectTabbedWindows()`. The old heuristic (CGS visible-window list check) is preserved in `TabHierarchy.detectTabbedWindows()` for the `--debug-tabs` diagnostic only.

The `--cycle` command intentionally **does not filter on `isTabbed`** because of this (same as the legacy jq scripts). If windows start getting skipped during cycling, check whether an `isTabbed` filter was introduced.

## Quick-Reference Gotchas

### Window Discovery
- AX brute-force scan range is `0..<10000` (`AXUIElement.windowsByBruteForce`). Apps with many windows (Ghostty) can exceed this.
- `kAXWindowsAttribute` does NOT return windows on other spaces. Brute-force is the only path for cross-space discovery.
- `CGWindowListCopyWindowInfo` sees ALL windows (public API) — use it as ground truth when AltTab's view seems wrong.
- `SidePanelManager.discoverMissingWindows()` cross-checks CGWindowList vs Windows.list on staggered intervals after launch.

### CGS API Timing
- CGS window-space APIs return stale data for ~400ms during space transitions.
- Space change cooldown in `SidePanelManager.refreshPanels()` defers refreshes during this window.
- Same class of issue as `isTabbed` false positives and the `applicationHiddenOrShown` 200ms delay.

### Tab Hierarchy
- **Two tab systems coexist**: upstream's `TabGroup.swift` (peer-based, event-driven, sets `isTabbed`/`tabbedSiblingWids`) and the fork's `TabHierarchy.swift` (parent→child, on-demand AX query, sets `parentWindowId`/`isTabChild`). They serve different purposes and don't conflict.
- Fork tab logic lives in `src/logic/TabHierarchy.swift` — extracted from `Windows.swift` to minimize merge conflicts. Called via `TabHierarchy.computeAndApply()` from `Windows.updatesBeforeShowing()`.
- Inactive tabs have `spaces = []` — CGS doesn't assign them to any space. Upstream's `TabGroup.updateState()` now propagates `spaceIds` from active tab to inactive siblings, partly fixing this. The fork's `!window.spaceIds.isEmpty` guard in `refreshIfWindowShouldBeShownToTheUser` catches any remaining cases.
- AX forward lookup (parent's AXTabGroup → child titles) is the only reliable tab matching. See `docs/tab-hierarchy-guide.md`.
- Newly active tabs may have nil `axUiElement` (stale from when invisible). Fix: `visibleOnSpace` overrides stale parent assignment.

### Build Configuration: Debug UserDefaults Poisoning
- `App.swift` has `#if DEBUG` code that writes `UserDefaults.standard.set(true, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")`. This **persists forever** in the app's UserDefaults domain — even after switching to Release builds. A single Debug build taints all future launches.
- Symptom: purple constraint debugging overlay, "Layout is ambiguous" banner, "Exercise Ambiguity" button in any NSPanel/NSWindow.
- Fix: `defaults delete com.lwouis.alt-tab-macos.at004 NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints`
- `tccutil reset All` does NOT clear UserDefaults — only TCC privacy database.
- If you ever build with Debug configuration, always run the `defaults delete` after switching back to Release.

### Side Panel Performance Profile (measured on M2 Max, 5 monitors)
- **Background polling**: single 10-second timer (`SidePanelManager.discoveryTimer`) runs `discoverMissingWindows()` + `refreshPanels()`.
- **Why 10s**: only needed for cross-space discovery. Windows on the current space arrive instantly via AX event callbacks. The staggered launch bursts (1s, 3s, 5s, 7s, 10s) handle initial population.
- **CPU**: 0% idle, 10-42% spikes for ~200ms per tick → ~1-2% average sustained.
- **Memory**: ~410MB stable, 406-425MB oscillation during ticks (transient AX response buffers).
- **Disk I/O**: ~200 KB/h to `~/Library/Logs/at004/app.log` from SwiftyBeaver `FileDestination` (`.info`+, mostly AX event logs). Negligible. The legacy `ConsoleDestination` still writes to stdout but is silent when launched from Finder.
- **AX IPC cost**: `TabHierarchy.queryAXTabGroups()` does per-window Mach messages. Gated on `needsTabInfo` — skipped entirely when all three tab prefs are off (`showTabHierarchyInSidePanel`, `showTabHierarchyInMainPanel`, `groupTabsInSortOrder`). Upstream's `AXCallScheduler` handles throttling (200ms per-key) and retry with backoff.
- **Main Panel collapsed columns**: empty monitors auto-collapse to 20px vertical bars, giving more space to active monitors. Exception: single-monitor or all-empty layouts stay full-width.

### Debugging with pyobjc
- System python3 may not have Quartz. Use: `uvx --with pyobjc-framework-Quartz python3 -c "..."`
- Never install into project venvs or system-wide.

### Swift static-var init order with `DispatchTime.now()` → SIGTRAP on first call
- **Pattern that traps**: `private static var t0 = DispatchTime.now()` combined with `DispatchTime.now().uptimeNanoseconds - Self.t0.uptimeNanoseconds`.
- **Why**: Swift evaluates LHS first. On the very first call, the static is uninitialized; the RHS access triggers `swift_once` which calls `DispatchTime.now()` *after* the LHS already captured an earlier time. `T_lhs < T_rhs` → `UInt64` underflow → Swift fatal error → `SIGTRAP / TRAP_BRKPT`.
- **Symptom**: app crashes on first event after instrumentation is added. AppCenter dialog appears next launch. Easy to misdiagnose because `DispatchTime` "should" be monotonic.
- **Fix**: initialize the static to a sentinel `0` and assign on first call:
  ```swift
  private static var t0Ns: UInt64 = 0
  let nowNs = DispatchTime.now().uptimeNanoseconds
  if Self.t0Ns == 0 { Self.t0Ns = nowNs }
  let elapsedMs = Double(nowNs - Self.t0Ns) / 1_000_000
  ```
