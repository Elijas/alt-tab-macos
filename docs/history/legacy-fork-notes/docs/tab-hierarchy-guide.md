# macOS Native Tab Hierarchy — Implementation Guide

**Context**: AltTab fork side panel / window panel — "Show tabs as indented items" feature.
**Last updated**: 2026-02-24

## How macOS Native Tabs Work (Window Server Level)

Each native tab is a **separate CGWindow**. The Window Server tracks them independently:

| State | `kCGWindowIsOnscreen` | `spaces` (CGS) | AX `axUiElement` |
|-------|----------------------|-----------------|-------------------|
| Active tab | `true` | `[spaceId]` | valid, queryable |
| Inactive tab | `false` | `[]` (empty!) | nil or stale |

**Critical**: Inactive tabs have `spaces = []`. CGS does not assign them to any space. This means per-space window enumeration (`Spaces.windowsInSpaces`) never sees them — they must be pulled in separately via their parent relationship.

## Why Every "Obvious" Matching Approach Fails

### CGWindowList `parentWindowId` — WRONG
CGS reports a `parentWindowId` for tabbed windows, but it's **unreliable**:
- Finder: both inactive tabs point to the **same** parent (wrong for one of them)
- Ghostty: all inactive tabs point to a **completely unrelated window on a different space**

### Frame matching (position + size) — WRONG
- Inactive tabs retain their **pre-tabbing frame** (different size from the active/parent window)
- Two maximized windows of the same app on the same screen have **identical frames** — no disambiguation

### Window ID proximity — WRONG
Tested: `window1-tab2-inactive` (ID 157936) is numerically closer to `window2-tab1-active` (157959) than to its actual parent `window1-tab1-active` (156967).

### PID-based inference — WRONG (for multi-group)
Assigning all tabbed windows to the "most recently focused visible window" of the same app conflates tab groups. If Finder has 2 windows with 2 tabs each, all 4 tabs get assigned to one parent.

### AXIdentifier — WRONG (not available on tab buttons)
Investigated 2026-02-24. `AXIdentifier` exists on hidden **window** elements (`isTabbed=true`), but NOT on tab **buttons** (`AXRadioButton` inside `AXTabGroup`). Since the forward lookup reads from tab buttons and matches against hidden windows, there's no shared identifier to use. Furthermore, Ghostty's window-level `AXIdentifier` is always `"TerminalWindowRestoration"` — a restoration class name, not a per-window unique ID.

### Exotic AX attributes — EXHAUSTIVE SEARCH (2026-02-24)
Dumped all AX attribute values on both tab buttons and hidden windows to find any shared unique signal:

| Attribute | Tab Button (AXRadioButton) | Hidden Window (AXWindow) | Verdict |
|-----------|---------------------------|--------------------------|---------|
| AXTitle | ✅ tab title | ✅ window title | **Only shared unique signal** |
| AXIdentifier | ❌ not present | ✅ but same for all windows | Useless |
| AXDocument | ❌ not present | ✅ CWD path (not unique per tab) | One-sided |
| AXPosition/Size | ✅ position in tab bar | ✅ window position | Different coordinate spaces |
| AXHelp | ✅ mirrors title | ❌ not present | One-sided duplicate |
| AXChildren | `[AXButton, AXGroup, AXStaticText]` | window children | Generic, no unique IDs |

The fundamental asymmetry — one side is a UI button, the other an invisible window — means title is the only bridge. No fingerprint/hash approach helps because there's no extra data to hash on both sides.

## The Working Approach: AX Forward Lookup

Each **visible** window with tabs has an `AXTabGroup` child element containing `AXRadioButton` entries with titles matching each tab's window title.

```
Visible AXWindow (parent)
  └─ AXTabGroup
       ├─ AXRadioButton  title="tab1"  value="1" (active)
       ├─ AXRadioButton  title="tab2"  value="0" (inactive)
       └─ AXButton       axDescription="new tab" (the + button)
```

**Forward lookup**: parent → children (via AXTabGroup titles).
**Backward lookup**: child → parent — ALL dead ends (axParentChain goes to AXApplication with windowId=0).

### Algorithm (`Windows.queryAXTabGroups`)

```
1. For each window with a queryable axUiElement:
   - Walk AXChildren for AXTabGroup
   - Read each AXRadioButton's AXTitle
   - Build map: "pid:title" → parentWid
   - Track parentWids set

2. For each window NOT in parentWids:
   - Look up "pid:title" in the map
   - Match → that window is a tab child of the matched parent
```

### Known Limitation: Title Collisions
If the same app has two tab groups each containing a tab with identical title (e.g., two Finder windows both with a "Downloads" tab), first match wins. Rare in practice. An exhaustive search of all AX attributes (2026-02-24) confirmed there is no alternative signal to disambiguate — see "Exotic AX attributes" section above.

### Known Limitation: `axUiElement` Staleness
Windows discovered while invisible have nil `axUiElement`. After becoming the active tab, AltTab's cached Window object still has the nil element — so the AX query can't read its AXTabGroup, and it gets misclassified as a child instead of a parent.

**Fix**: Use `visibleOnSpace` (from `Spaces.windowsInSpaces(_, false)`) as ground truth. A visible window can **never** be a tab child in native macOS tabs — only one tab is on-screen per group. Reset `parentWindowId = 0` for all visible windows before filtering.

## Architecture: Data Flow in Side Panel Path

```
SidePanelManager.refreshPanelsNow()
  │
  ├─ for each screen:
  │    buildScreenGroups(screenUuid, windowByCgId, ..., showTabHierarchy: Bool)
  │      │
  │      ├─ Windows.queryAXTabGroups(windows)     ← builds child→parent map
  │      ├─ Apply parentWindowId to windows
  │      │
  │      └─ Per-space loop:
  │           ├─ visibleOnSpace = Spaces.windowsInSpaces([spaceId], false)
  │           ├─ Reset parentWindowId=0 for visible windows  ← staleness fix
  │           ├─ Filter: include visible windows + tab children
  │           ├─ Pull in spaces=[] tab children whose parent is in group
  │           └─ orderWithTabHierarchy() — children placed after parent
  │
  ├─ Side panel gets:  showTabHierarchy = Preferences.showTabHierarchyInSidePanel
  └─ Window panel gets: showTabHierarchy = Preferences.showTabHierarchyInMainPanel
```

## Architecture: Data Flow in Main Panel Path (⌥Tab Switcher)

```
Windows.updatesBeforeShowing()
  ├─ detectTabbedWindows()          ← sets isTabbed flag (CGS visible vs all)
  ├─ refreshWhichWindowsToShowTheUser()
  ├─ sort()
  └─ if showTabHierarchyInMainPanel:
       ├─ queryAXTabGroups(list)    ← same AX function
       ├─ Apply parentWindowId
       └─ reorderListForTabHierarchy()
```

Note: The main panel path calls `detectTabbedWindows` which sets `isTabbed`. The side panel path does NOT — so `queryAXTabGroups` must be self-contained and not depend on `isTabbed`.

## Key Files

| File | What's There |
|------|-------------|
| `src/logic/Windows.swift` | `queryAXTabGroups()`, `orderWithTabHierarchy()`, `detectTabbedWindows()` |
| `src/logic/Window.swift` | `parentWindowId`, `isTabChild` computed property |
| `src/ui/side-panel/SidePanelManager.swift` | `buildScreenGroups()` — per-space grouping with tab hierarchy |
| `src/ui/side-panel/SidePanelRow.swift` | `applyIndent()` — visual indentation (20px offset) |
| `src/ui/side-panel/WindowListView.swift` | `showTabHierarchy` property, row indentation logic |
| `src/ui/settings-window/tabs/PanelTab.swift` | Independent toggles for each panel |
| `src/logic/Preferences.swift` | `showTabHierarchyInSidePanel`, `showTabHierarchyInMainPanel` |

## Preference Keys

| Key | Controls | Default |
|-----|----------|---------|
| `showTabHierarchyInSidePanel` | Side panel tab indentation | `false` |
| `showTabHierarchyInMainPanel` | Window panel tab indentation | `false` |

Despite the name "MainPanel", this key is used for the **Window Panel** (the all-screen overview). There is no "main panel" — the user uses "main panel" and "window panel" interchangeably.

## Debugging

### CLI diagnostic
```bash
# Dump AX tab group data for all windows (added by --debug-tabs flag)
echo '{"action":"debug-tabs"}' | nc -U /tmp/at004-cli.sock
```

### CGWindowList cross-check
```bash
# See all windows the Window Server knows about (ground truth)
uvx --with pyobjc-framework-Quartz python3 -c "
from Quartz import CGWindowListCopyWindowInfo, kCGWindowListOptionAll, kCGNullWindowID
for w in CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID):
    layer = w.get('kCGWindowLayer', -1)
    if layer == 0:
        print(f'{w[\"kCGWindowNumber\"]:>6}  pid={w[\"kCGWindowOwnerPID\"]}  {w.get(\"kCGWindowOwnerName\",\"?\")}  \"{w.get(\"kCGWindowName\",\"\")}\"  onscreen={w.get(\"kCGWindowIsOnscreen\", False)}')
"
```

### Key timing constants
- **Space change cooldown**: 400ms — CGS APIs return stale window-space data during transitions
- **Refresh throttle**: 200ms — minimum interval between panel refreshes
- **Discovery timer**: 10s repeating — periodic AX re-scan for missed windows
- **Separator debounce**: 300ms — delay before rebuilding panels after separator size change

## Investigation Artifacts

- `/tmp/ax-tab-analysis.md` — full AX investigation results (Finder + Ghostty test data)
- `/tmp/debug-tabs-output.json` — raw AX diagnostic JSON from `--debug-tabs`
