# Post-Merge Notes: Upstream v10.9.0 → v10.11.0 (2026-04-09)

Merged 23 upstream commits (through 49a41bd6) into dev. Safety branch: `dev-pre-upstream-merge-v10.11`.

## Key Upstream Changes Adopted

### 1. AXCallScheduler replaces retryAxCallUntilTimeout

The old `retryAxCallUntilTimeout` retry loop is replaced by `AXCallScheduler` — a key-based throttle (200ms) with exponential backoff retry (200ms → 1s → 2s → 5s, 60s timeout).

**All callers migrated:** Application.swift, Window.swift, Applications.swift, AccessibilityEvents.swift, DockEvents.swift, Windows.swift.

**BackgroundWork changes:** Removed `axCallsFirstAttemptQueue`, `axCallsRetriesQueue`, `axCallsManualDiscoveryQueue`. These queues are no longer needed since AXCallScheduler handles its own dispatch.

**If AX operations feel sluggish or unresponsive:** The backoff schedule (200ms → 1s → 2s → 5s) means a failing AX call won't retry for increasingly long intervals. If an app's AX interface is transiently slow (not broken), it may take up to 60s to recover.

### 2. TabGroup.swift: event-driven tab detection

New upstream file introducing a peer-based tab model using `tabbedSiblingWids`. `TabGroup.updateState()` is called from `AccessibilityEvents.handleEventWindow()` and `Applications.updateWindowAttributes()`.

**Coexistence with fork:** This sits alongside the fork's parent→child `TabHierarchy` system. Upstream's TabGroup populates `window.tabbedSiblingWids`; the fork's TabHierarchy populates `window.parentWindowId` and `window.isTabChild`. Both are active and serve different purposes — TabGroup drives upstream's tab display, TabHierarchy drives the fork's hierarchical sort and side panel grouping.

### 3. MainMenu.swift: .xib → programmatic menu construction

`resources/MainMenu.xib` removed. Menu is now built programmatically in `MainMenu.swift`.

**Fork impact:** The fork had 4 commits fixing keyboard shortcuts in the search bar (edit menu items). Upstream's programmatic migration may have independently addressed some of these. Needs manual verification — if Cmd+A/Cmd+C/Cmd+V stop working in the search bar, the programmatic menu may need the same fixes the xib-based menu had.

### 4. Applications.swift restructured throttlers

| Old | New |
|-----|-----|
| Old throttler names | `manualRefreshThrottler` (200ms) |
| | `appListUpdateThrottler` (200ms) |
| | `windowListUpdateThrottler` (200ms) |

New `updateWindowAttributes()` is a unified fetch method with TabGroup integration. New `reviewExistingWindows()` replaces previous window review logic.

**Note:** Throttler delays changed from 1000ms to 200ms. Monitor for increased CPU usage if many apps are open.

### 5. New files

| File | Purpose |
|------|---------|
| `UsageStats.swift` | Usage telemetry |
| `SleepWakeEvents.swift` | Sleep/wake event handling |
| `WindowDiscriminator.swift` | Window type discrimination logic |

### 6. Throttler.swift: main queue precondition

Added `dispatchPrecondition` for main queue. If any fork code calls a Throttler from a background queue, it will now crash with a precondition failure instead of silently misbehaving.

### 7. Bug fixes adopted

- Double-open crash (#5491)
- Scroll crash
- About-window crash
- Show more apps in exceptions

## Conflicts Resolved

### 1. .gitignore

Kept fork's `.claude/` ignore. Upstream had `/.claude/worktrees/`.

### 2. README.md

Kept fork's description. Upstream had download badge table.

### 3. Application.swift

Removed dead `manuallyUpdateWindow()` instance method — replaced by `Applications.updateWindowAttributes()`. SidePanelManager WID check added to new location.

### 4. Window.swift

Kept both: upstream's `tabbedSiblingWids` AND fork's `parentWindowId`/`isTabChild`. Both coexist — no conflict in practice since they're separate properties.

### 5. Windows.swift (MAJOR)

Extracted all fork tab hierarchy code to `TabHierarchy.swift`. This was the largest conflict area.

- `updatesBeforeShowing()` now calls `TabHierarchy.computeAndApply()`
- `sort()` calls `TabHierarchy.effectiveLastFocusOrder()` / `effectiveCreationOrder()`

This extraction was necessary because upstream's Windows.swift changed substantially (new TabGroup integration, new updateWindowAttributes flow), making inline fork code unmaintainable.

### 6. AccessibilityEvents.swift

Accepted upstream's AXCallScheduler approach. Added SidePanelManager WID guard to `handleEvent()`. Removed fork's `ThrottlerWithKey` wrapper — redundant with AXCallScheduler's built-in throttling.

## Structural Changes

### TabHierarchy.swift (new fork-only file)

All fork tab hierarchy logic extracted from Windows.swift into `src/logic/TabHierarchy.swift`:

| Function | Purpose |
|----------|---------|
| `queryAXTabGroups()` | AX forward-lookup for child→parent mapping |
| `groupSortKeys()` | min(key) across tab group members |
| `effectiveLastFocusOrder()` | Group-key lookup for lastFocusOrder |
| `effectiveCreationOrder()` | Group-key lookup for creationOrder |
| `orderWithTabHierarchy()` | Parent→child list reordering |
| `detectTabbedWindows()` | Old heuristic (kept for `--debug-tabs` diagnostic only) |
| `inferTabParentIds()` | Old parent inference (kept for CLI) |
| `computeAndApply()` | Main entry point, called from `Windows.updatesBeforeShowing()` |

### Updated call sites

| File | Old call | New call |
|------|----------|----------|
| `SidePanelManager.swift` | `Windows.queryAXTabGroups()` | `TabHierarchy.queryAXTabGroups()` |
| `CliEvents.swift` (`--detailed-list`) | `detectTabbedWindows` + `inferTabParentIds` | `TabHierarchy.queryAXTabGroups()` |
| `CliEvents.swift` (`--debug-tabs`) | — | `TabHierarchy.detectTabbedWindows()` |

## Deliberate Divergences from Upstream

1. **Brute-force scan range:** Kept 10000. Upstream reduced to 1000, but Ghostty and other apps with many windows can exceed 1000.
2. **CLI port name:** Kept dynamic `(Bundle.main.bundleIdentifier ?? ...) + ".cli"`. Upstream hardcoded.
3. **Window.parentWindowId / isTabChild:** Fork-only properties, not in upstream.
4. **Tab hierarchy preferences:** `showTabHierarchyInMainPanel`, `showTabHierarchyInSidePanel`, `groupTabsInSortOrder` — fork-only.
5. **Side panel files (6 files):** Fork-only, no upstream counterpart.

## Known Issues

1. **TabGroup spaceId propagation overlap.** Upstream's `TabGroup.updateState()` propagates `spaceIds` from active to inactive tabs. This may make the fork's `!window.spaceIds.isEmpty` guard in `refreshIfWindowShouldBeShownToTheUser` partly redundant for tabs handled by TabGroup. The guard is still needed for tabs not yet processed by TabGroup events.

2. **ThrottlerWithKey delay change.** Applications throttlers changed from 1000ms to 200ms. Monitor for performance impact — higher CPU spikes possible with many apps open.

3. **MainMenu edit-menu fixes.** Fork had 4 commits for keyboard shortcuts in search bar. Upstream's programmatic migration may have independently addressed some. Needs manual verification.

## If Something Breaks

1. **AX calls timing out** — AXCallScheduler backoff goes up to 5s between retries with 60s total timeout. If an app's AX interface is slow but functional, recovery may feel delayed compared to the old `retryAxCallUntilTimeout`.
2. **Side panel tab grouping wrong** — `TabHierarchy.computeAndApply()` is the new entry point. Check that it's being called in `updatesBeforeShowing()` and that `queryAXTabGroups()` returns correct parent mappings.
3. **Throttler crash on background queue** — New `dispatchPrecondition` in Throttler.swift. If fork code invokes a Throttler from a background queue, it will crash. Move the call to main queue.
4. **Search bar keyboard shortcuts broken** — MainMenu.xib was removed. If Cmd+A/C/V don't work in the search bar, the programmatic menu needs the same edit-menu fixes the old xib had.
5. **Tab detection disagreement** — Both upstream's TabGroup (`tabbedSiblingWids`) and fork's TabHierarchy (`parentWindowId`) are active. If they produce contradictory results (e.g., TabGroup says "not tabbed" but TabHierarchy says "child tab"), check timing — TabGroup.updateState() runs on AX events, TabHierarchy.computeAndApply() runs in updatesBeforeShowing().
