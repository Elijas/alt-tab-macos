# Window Debugging Guide

How to diagnose window discovery, ordering, and timing issues in the AltTab fork.

## Quick Reference: The Two Independent Views

| Source | What it sees | API | Limitations |
|--------|-------------|-----|-------------|
| **Window Server** (CGWindowListCopyWindowInfo) | ALL windows, all spaces, all apps | CoreGraphics (public) | No space assignment, titles often blank |
| **AltTab** (Windows.list via CLI) | Only windows it discovered via AX | `--detailed-list` CLI | Misses windows with AX element IDs outside brute-force range |

When debugging "missing" or "wrong" windows, always compare both. Discrepancies point to the bug.

## Toolkit

### 1. Query AltTab's view (what the side panel uses)

```bash
/Applications/at004.app/Contents/MacOS/at004 --detailed-list 2>/dev/null | python3 -m json.tool
```

Key fields in the response:
- `windows[].spaceIndexes` — which space(s) each window is on
- `windows[].screenId` — which physical screen
- `screenSpacesMap` — maps screen UUID to space indexes (Mission Control order)
- `currentSpaceIndex`, `visibleSpaceIndexes` — what's active now

### 2. Query the Window Server's view (ground truth)

```bash
uvx --with pyobjc-framework-Quartz python3 -c "
import Quartz
all_windows = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionAll | Quartz.kCGWindowListExcludeDesktopElements,
    Quartz.kCGNullWindowID
)
for w in all_windows:
    layer = w.get('kCGWindowLayer', -1)
    if layer != 0: continue
    bounds = w.get('kCGWindowBounds', {})
    bw, bh = bounds.get('Width', 0), bounds.get('Height', 0)
    if bw < 50 or bh < 50: continue
    alpha = w.get('kCGWindowAlpha', 1.0)
    if alpha <= 0: continue
    wid = w.get('kCGWindowNumber', 0)
    owner = w.get('kCGWindowOwnerName', '')
    name = w.get('kCGWindowName', '') or '(untitled)'
    pid = w.get('kCGWindowOwnerPID', 0)
    print(f'  [{wid:>6}] {owner:<20} {name[:50]:<50}  pos=({bounds.get(\"X\",0):.0f},{bounds.get(\"Y\",0):.0f}) {bw:.0f}x{bh:.0f}  pid={pid}')
"
```

Note: `kCGWindowName` is usually blank — macOS doesn't expose titles through CGWindowList for most apps (needs Screen Recording permission AND the app has to cooperate). Don't rely on it for identification; use `kCGWindowOwnerName` + `kCGWindowNumber` instead.

### 3. Cross-reference: find windows AltTab is missing

```bash
# Get AltTab's known WIDs
ALTTAB_WIDS=$(/Applications/at004.app/Contents/MacOS/at004 --detailed-list 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data['windows']:
    if w['id']: print(w['id'])
")

# Get Window Server's WIDs and diff
uvx --with pyobjc-framework-Quartz python3 -c "
import Quartz, sys
known = set(int(x) for x in '''$ALTTAB_WIDS'''.strip().split())
all_windows = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionAll | Quartz.kCGWindowListExcludeDesktopElements,
    Quartz.kCGNullWindowID
)
print('=== Missing from AltTab ===')
for w in all_windows:
    layer = w.get('kCGWindowLayer', -1)
    if layer != 0: continue
    bounds = w.get('kCGWindowBounds', {})
    bw, bh = bounds.get('Width', 0), bounds.get('Height', 0)
    if bw < 50 or bh < 50: continue
    wid = w.get('kCGWindowNumber', 0)
    if wid not in known:
        owner = w.get('kCGWindowOwnerName', '')
        pid = w.get('kCGWindowOwnerPID', 0)
        print(f'  [{wid:>6}] {owner:<20}  {bw:.0f}x{bh:.0f}  pid={pid}')
"
```

### 4. Filter to a specific screen

Screen positions from AltTab CLI (`screens[].frame`):
- Frame format: `[x, y, width, height]` in Quartz coordinates (origin = top-left of primary screen)
- To find which screen a window is on: check if window center falls within screen bounds

```python
# Example: filter to U4323QE at (1920, -697) 1080x1920
sx, sy, sw, sh = 1920, -697, 1080, 1920
cx, cy = bx + bw/2, by + bh/2
on_screen = (sx <= cx <= sx+sw and sy <= cy <= sy+sh)
```

### 5. Identify your screens

```bash
/Applications/at004.app/Contents/MacOS/at004 --detailed-list 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for s in data['screens']:
    f = s['frame']
    spaces = data.get('screenSpacesMap', {}).get(s['id'], [])
    print(f\"{s['id'][:12]}...  {f[2]:.0f}x{f[3]:.0f} at ({f[0]:.0f},{f[1]:.0f})  spaces={spaces}\")
"
```

Map these to physical monitors by resolution and position:
- 1920x1080 = likely the XG43UQ (main, no rotation)
- 1080x1920 = Dell U4320Q or U4323QE (rotated 90/270)
- ~1168x755 = Built-in Retina (scaled)

## Common Issues and Where to Look

### Side panel shows spaces in wrong order during space switches

**Root cause**: CGS APIs (`CGSCopyWindowsWithOptionsAndTags`) return stale window-space mappings during the ~400ms space transition animation. AX events fire immediately, triggering a refresh that reads this stale data. The side panel's deduplication (`seen` set, first-occurrence-wins) assigns windows to whichever space is queried first.

**Fix location**: `SidePanelManager.swift` — space change cooldown (`lastSpaceChangeNanos`, `notifySpaceChange()`)

**Relevant code**:
- `SpacesEvents.swift` — `handleEvent` calls `notifySpaceChange()` before debounce
- `SidePanelManager.refreshPanels()` — cooldown check before allowing immediate refresh
- Cooldown value: `spaceChangeCooldownMs = 400` (may need tuning)

### Side panel shows spaces as "(empty)" after restart

**Root cause**: AltTab discovers windows via AX brute-force scanning, iterating element IDs 0..N per app. Apps that create many windows (like Ghostty with 10+ terminals) can have AX element IDs > the scan range, causing those windows to never be found.

The `CGSCopyWindowsWithOptionsAndTags` API does return the correct WIDs for those spaces — but without a matching `Window` object in `Windows.list` (which requires AX discovery), the side panel treats them as nonexistent.

**Fix location**:
- `AXUIElement.swift:windowsByBruteForce()` — scan range (currently 0..<10000)
- `SidePanelManager.discoverMissingWindows()` — uses CGWindowListCopyWindowInfo to detect gaps and trigger targeted re-discovery

**Diagnosis**: Run the cross-reference script above. If Window Server sees windows that AltTab doesn't, it's a discovery issue.

### Spaces rearrange themselves after clicking a window in the side panel

**Root cause**: macOS setting, not a code bug. **System Settings → Desktop & Dock → Mission Control → "Automatically rearrange Spaces based on most recent use"** — when enabled, macOS reshuffles space order every time a space is "used" (including when AltTab focuses a window on that space via the side panel). A space that was index 7 can jump to index 4.

**Fix**: Disable the setting. Space order then only changes via manual drag in Mission Control.

**How to verify**: Open Mission Control (F3 or swipe up) before and after clicking a window in the panel. With the setting on, spaces will have moved. With it off, they stay put.

### `isTabbed` false positives

**Root cause**: `CGSCopyWindowsWithOptionsAndTags` snapshot is timing-dependent. AltTab calls it once to get "visible" windows, marks anything NOT in that list as tabbed. Random visible windows can be missed by the snapshot.

**Impact on side panel**: Windows marked `isTabbed` are filtered out in `buildScreenGroups()` (the `!isVisible` check). False positive = window disappears from panel.

**Documented in**: `CLAUDE.md` under "Known issue: isTabbed false positives"

## Architecture: How Windows Get Discovered

```
App Launch
    |
    v
Applications.addMissingWindows()          -- initial pass, all apps
    |
    v  (for each Application)
Application.manuallyUpdateWindows()       -- dispatches to background queue
    |
    v
AXUIElement.allWindows(pid)
    |--- kAXWindowsAttribute              -- fast, but MISSES other-space windows
    |--- windowsByBruteForce(pid)         -- iterates AX element IDs 0..<10000
    |         |                              creates AXUIElement per ID, checks subrole
    |         v
    |    _AXUIElementCreateWithRemoteToken(remoteToken)
    |
    v
Window.init() -> updateSpacesAndScreen()
    |--- CGSCopySpacesForWindows()        -- maps CGWindowID -> space IDs
    |
    v
Windows.list populated  <-- side panel reads from here
```

After initial discovery, `SidePanelManager.discoverMissingWindows()` runs at [1, 3, 5, 7, 10] seconds:

```
CGWindowListCopyWindowInfo()  -->  all WIDs from Window Server
         |
         v
    diff against Windows.list
         |
         v
    missing WIDs grouped by PID
         |
         v
    targeted manuallyUpdateWindows() for those PIDs only
```

## Architecture: How the Side Panel Renders

```
SidePanelManager.refreshPanelsNow()
    |
    +-- Spaces.refresh()
    |     |-- CGSCopyManagedDisplaySpaces()     --> screenSpacesMap
    |     |-- CGSManagedDisplayGetCurrentSpace() --> currentSpaceId
    |
    +-- for each NSScreen:
          buildScreenGroups(screenUuid)
            |
            +-- screenSpacesMap[uuid] --> ordered space IDs
            |
            +-- for each spaceId:
                  Spaces.windowsInSpaces([spaceId], true)   --> allOnSpace (CGWindowIDs)
                  Spaces.windowsInSpaces([spaceId], false)  --> visibleOnSpace
                  |
                  +-- for each wid in allOnSpace:
                        windowByCgId[wid] --> Window?    <-- nil = silently skipped
                        filter: dominated, windowless, minimized, hidden, !visible, blacklisted
                        |
                        v
                  sorted by creationOrder descending
                  --> WindowGroup per space
```

Key insight: `windowByCgId[wid]` returning nil is the "empty space" symptom. The CGS API knows the window exists on that space, but there's no Window object because AX discovery failed.

## Key Files

| File | What it does |
|------|-------------|
| `SidePanelManager.swift` | Panel lifecycle, refresh throttle, cooldown, CGWindowList audit |
| `SpacesEvents.swift` | macOS space change notification handler |
| `Spaces.swift` | CGS space API wrappers, screenSpacesMap, refresh |
| `AXUIElement.swift` | AX brute-force window discovery |
| `Application.swift` | Per-app window discovery (manuallyUpdateWindows) |
| `Windows.swift` | Windows.list, findOrCreate |
| `CliEvents.swift` | CLI server (--list, --detailed-list) |
| `AccessibilityEvents.swift` | AX event handlers (window focus, app activation) |
| `SkyLight.framework.swift` | Private CGS API declarations |

## CGS Private APIs Used

| API | Purpose | Reliability |
|-----|---------|-------------|
| `CGSCopyManagedDisplaySpaces` | Get all spaces per screen | Reliable, returns correct data immediately |
| `CGSManagedDisplayGetCurrentSpace` | Get active space on a screen | Reliable |
| `CGSCopyWindowsWithOptionsAndTags` | Get window IDs on a space | Stale during space transitions (~400ms) |
| `CGSCopySpacesForWindows` | Get space IDs for a window | Stale during space transitions |

## Coordinate Systems

macOS uses two coordinate systems — getting them confused causes "wrong screen" bugs:

| System | Origin | Used by |
|--------|--------|---------|
| **AppKit** (NSScreen) | Bottom-left of primary screen | NSScreen.frame, NSWindow.frame |
| **Quartz** (CGWindow) | Top-left of primary screen | CGWindowListCopyWindowInfo, CGDisplay* |

Conversion: `quartzY = primaryScreenHeight - appKitY - windowHeight`

The AltTab CLI `--detailed-list` already converts to Quartz coordinates.

## Timing Constants

| Constant | Value | Location | Purpose |
|----------|-------|----------|---------|
| Space change cooldown | 400ms | `SidePanelManager.refreshPanels()` | Defer refresh during space transition |
| Refresh throttle | 200ms | `SidePanelManager.refreshPanels()` | Coalesce rapid refresh requests |
| AX brute-force range | 0..<10000 | `AXUIElement.windowsByBruteForce()` | Max AX element ID to try |
| Discovery passes | [1,3,5,7,10]s | `SidePanelManager.setup()` | Staggered CGWindowList audit intervals |
| applicationHiddenOrShown delay | 200ms | `AccessibilityEvents.swift:71` | Same class of CGS timing issue |

KNOWN UNKNOWN: Space change cooldown of 400ms is tuned for typical hardware. "Reduce motion" accessibility setting and slower machines may need 500-600ms.

KNOWN UNKNOWN: AX brute-force range of 10000 covers most apps, but there's no hard upper bound on AX element IDs. An app that has created and destroyed thousands of windows could have IDs > 10000.
