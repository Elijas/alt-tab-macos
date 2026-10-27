# Gesture vs Keyboard Tab Filter Divergence — Root Cause & Fix

**Context**: AltTab fork — 3-finger gesture trigger showed tabbed windows as separate items while keyboard shortcut correctly hid them.
**Fixed**: 2026-04-08
**Files changed**: `src/logic/Windows.swift` (lines 408-414 in `refreshIfWindowShouldBeShownToTheUser`)

## Symptom

With `showTabsAsWindows = false`:
- **⌥⇥ (keyboard, Shortcut 1)** → Finder/Ghostty tabs correctly collapsed into 1 switcher item
- **3-finger swipe (Gesture)** → each tab shown as a separate switcher item

## The Red Herring

Both triggers call `App.showUiOrCycleSelection()` → `Windows.updatesBeforeShowing()` → same `detectTabbedWindows()` → same `refreshIfWindowShouldBeShownToTheUser()`. No divergent code path. Initial hypothesis was CGS snapshot timing flakiness on the gesture path — this was wrong.

## Actual Root Cause: Two Unrelated Settings Colluding

### Problem 1: `showTabHierarchyInMainPanel` silently overrode `showTabsAsWindows`

Line 414 (old):
```swift
(Preferences.showTabsAsWindows || Preferences.showTabHierarchyInMainPanel || !window.isTabbed)
```

When `showTabHierarchyInMainPanel = true`, this expression is always `true` regardless of `showTabsAsWindows`. The hierarchy mode needed tab children visible for indented display, but the implementation made `showTabsAsWindows` a dead switch whenever hierarchy was on.

### Problem 2: Empty `spaceIds` leaked through the visible-space filter inconsistently

Lines 411-412 (old):
```swift
!(spacesToShow == .visible && !Spaces.visibleSpaces.contains { vs in window.spaceIds.contains { $0 == vs } })
```

Inactive OS tabs have `spaceIds = []` (CGS doesn't assign spaces to them — see `tab-hierarchy-guide.md`). An empty `spaceIds` array means `.contains` always returns `false`, so these windows are classified as "not on any visible space" and filtered out.

But this only matters when `spacesToShow == .visible`. The user's config:
- **Shortcut 1**: `spacesToShow = .visible` → inactive tabs filtered out by space filter (accidentally correct behavior)
- **Gesture**: `spacesToShow = .all` (default) → inactive tabs pass space filter → shown as separate items

So the divergence wasn't in the tab filter at all — it was the space filter catching tab children as collateral damage, but only for one trigger.

### The full interaction

| Setting | Shortcut 1 (keyboard) | Gesture |
|---|---|---|
| `showTabsAsWindows = false` | Dead (overridden by hierarchy) | Dead (overridden by hierarchy) |
| `showTabHierarchyInMainPanel = true` | Forces all tabs through line 414 | Forces all tabs through line 414 |
| `spacesToShow = .visible` (Shortcut 1 only) | Catches inactive tabs at line 411 (empty spaceIds) | N/A (`.all`) |
| **Net effect** | 1 item (space filter hides tab children) | 3 items (nothing stops them) |

## The Fix

### Change 1 — Make `showTabsAsWindows` authoritative (line 414)

```diff
- (Preferences.showTabsAsWindows || Preferences.showTabHierarchyInMainPanel || !window.isTabbed)
+ (Preferences.showTabsAsWindows || !window.isTabbed)
```

`showTabHierarchyInMainPanel` no longer overrides. The four setting combinations now compose:

| `showTabsAsWindows` | `showTabHierarchyInMainPanel` | Behavior |
|---|---|---|
| OFF | OFF | Tab children hidden |
| OFF | ON | Tab children hidden (hierarchy has nothing to indent — parent shown alone) |
| ON | OFF | Tab children shown, flat list |
| ON | ON | Tab children shown, indented under parent |

### Change 2 — Exempt empty `spaceIds` from space filter (lines 411-412)

```diff
- !(spacesToShow == .visible && !Spaces.visibleSpaces.contains { ... })
+ !(spacesToShow == .visible && !window.spaceIds.isEmpty && !Spaces.visibleSpaces.contains { ... })
```

Same pattern for `.nonVisible`. Windows with no space assignment (inactive tabs, freshly created windows before CGS assigns them) are no longer treated as "wrong space" — they're simply exempt from the space filter. Whether they ultimately appear depends on the tab filter (Change 1).

## How We Found It

The CLI `--detailed-list` API was the key diagnostic tool. It bypasses `shouldShowTheUser` and returns the raw `Windows.list` with all fields:

```bash
/Applications/at004.app/Contents/MacOS/at004 --detailed-list 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data['windows']:
    print(json.dumps({
        'app': w['appName'], 'title': w.get('title','?')[:50],
        'isTabbed': w['isTabbed'], 'parentWindowId': w.get('parentWindowId'),
        'spaceIndexes': w.get('spaceIndexes'),
    }, ensure_ascii=False))
"
```

This showed:
1. Inactive tabs had `spaceIndexes: []` — the space-filter collateral damage
2. `isTabbed` was correctly set for both triggers — no CGS timing issue
3. `showTabHierarchyInMainPanel` was `true` in the live pref dump (`defaults read com.lwouis.alt-tab-macos.at004`)

Adding `Logger.debug` lines initially failed because:
- Default log level is `.error` (requires `--logs=debug` CLI flag)
- SwiftyBeaver `ConsoleDestination` writes to stdout, which is `/dev/null` when launched via `open`
- The in-app Debug Tools window uses `DebugWindowDestination` (`.debug` level) but requires manual inspection

**Lesson**: For filter-behavior bugs, `--detailed-list` + `defaults read` is faster and more reliable than adding temporary log lines. The CLI shows what the app *sees*; `defaults read` shows what it's *configured* with. Together they localize which filter clause is responsible.

## Related

- `tab-hierarchy-guide.md` — explains why inactive tabs have `spaceIds = []` (CGS architecture)
- `window-debugging-guide.md` — general window discovery debugging
- `CLAUDE.md` → "Known issue: `isTabbed` false positives" — the CGS flakiness we initially suspected but wasn't the cause here
