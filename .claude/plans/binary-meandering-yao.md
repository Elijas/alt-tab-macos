# Plan: Show Tabs as Indented Items in Panels

## Context

Ghostty (and other apps using macOS native tabs like Finder, Preview) creates real `NSWindow` instances for each tab. AltTab currently **hides** these tabbed windows by default (`isTabbed` filter at `Windows.swift:199`). The user wants to **show** them as indented child items under their parent window, configurable separately for the main AltTab panel and the side panel.

The key breakthrough: `SLSWindowIteratorGetParentID` — a private WindowServer API already declared in `src/experimentations/PrivateApis.swift:255` and **production-proven in yabai** (`/tmp/yabai/src/window.c:872-897`) — returns the parent CGWindowID for tab child windows. This gives us real parent→child relationships instead of heuristics.

---

## Step 1: Promote SLS Window Query APIs to Production

**Files:**
- `src/api-wrappers/private-apis/SkyLight.framework.swift` — add declarations
- `src/experimentations/PrivateApis.swift` — remove duplicate declarations (lines 240-262) to avoid duplicate `@_silgen_name` compiler errors

Add to `SkyLight.framework.swift` (after line 151, near other CGS functions):

```swift
@_silgen_name("SLSWindowQueryWindows")
func SLSWindowQueryWindows(_ cid: CGSConnectionID, _ wids: CFArray, _ windowsCount: UInt) -> CFTypeRef

@_silgen_name("SLSWindowQueryResultCopyWindows")
func SLSWindowQueryResultCopyWindows(_ query: CFTypeRef) -> CFTypeRef

@_silgen_name("SLSWindowIteratorGetCount")
func SLSWindowIteratorGetCount(_ iterator: CFTypeRef) -> UInt32

@_silgen_name("SLSWindowIteratorAdvance")
func SLSWindowIteratorAdvance(_ iterator: CFTypeRef) -> CGError

@_silgen_name("SLSWindowIteratorGetParentID")
func SLSWindowIteratorGetParentID(_ iterator: CFTypeRef) -> CGWindowID

@_silgen_name("SLSWindowIteratorGetWindowID")
func SLSWindowIteratorGetWindowID(_ iterator: CFTypeRef) -> CGWindowID
```

Keep `SLSWindowIteratorGetTags`, `CGSCopyWindowGroup`, `SLSCopyAssociatedWindows` in experimentations (not needed for this feature).

KNOWN UNKNOWN: Whether `SLSWindowIteratorGetCount` exists on macOS 12 and below. Yabai uses it on macOS 13+. May need `if #available(macOS 13.0, *)` guard — test empirically.

---

## Step 2: Data Model — Add `parentWindowId` to Window

**File:** `src/logic/Window.swift`

After line 22 (`var isTabbed: Bool = false`), add:

```swift
var parentWindowId: CGWindowID = 0  // 0 = standalone, non-zero = tab child of this parent
var isTabChild: Bool { parentWindowId != 0 }
```

Matches the C API convention (0 = no parent). No init changes needed — set externally like `isTabbed`.

---

## Step 3: Tab Parent Discovery via SLS

**File:** `src/logic/Windows.swift`

### 3a. New batch query function

```swift
/// Queries WindowServer for parent-child tab relationships.
/// Returns [childWID: parentWID] for windows that have a non-zero parent.
static func queryTabParentIds(_ windowIds: [CGWindowID]) -> [CGWindowID: CGWindowID] {
    guard !windowIds.isEmpty else { return [:] }
    let query = SLSWindowQueryWindows(CGS_CONNECTION, windowIds as CFArray, UInt(windowIds.count))
    let iterator = SLSWindowQueryResultCopyWindows(query)
    var result = [CGWindowID: CGWindowID]()
    while SLSWindowIteratorAdvance(iterator) == .success {
        let wid = SLSWindowIteratorGetWindowID(iterator)
        let parentWid = SLSWindowIteratorGetParentID(iterator)
        if parentWid != 0 {
            result[wid] = parentWid
        }
    }
    return result
}
```

### 3b. Integrate into `updatesBeforeShowing()` (line ~122)

After the existing per-window loop that calls `detectTabbedWindows`, add:

```swift
let allWids = list.compactMap { $0.cgWindowId }
let parentMap = queryTabParentIds(allWids)
for window in list {
    if let wid = window.cgWindowId {
        window.parentWindowId = parentMap[wid] ?? 0
    }
}
```

### 3c. Integrate into `SidePanelManager.refreshPanelsNow()` (line ~142)

After building the `windowByCgId` map, run the same query:

```swift
let allWids = Array(windowByCgId.keys)
let parentMap = Windows.queryTabParentIds(allWids)
for (wid, window) in windowByCgId {
    window.parentWindowId = parentMap[wid] ?? 0
}
```

---

## Step 4: New Preferences

**File:** `src/logic/Preferences.swift`

Defaults (add near line 81):
```swift
"showTabHierarchyInMainPanel": "false",
"showTabHierarchyInSidePanel": "false",
```

Accessors (add near line 144):
```swift
static var showTabHierarchyInMainPanel: Bool { CachedUserDefaults.bool("showTabHierarchyInMainPanel") }
static var showTabHierarchyInSidePanel: Bool { CachedUserDefaults.bool("showTabHierarchyInSidePanel") }
```

**File:** `src/ui/settings-window/tabs/PanelTab.swift`

Add toggle to "Side Panel" section:
```swift
let tabHierarchySideSwitch = LabelAndControl.makeSwitch("showTabHierarchyInSidePanel", extraAction: { _ in
    SidePanelManager.shared.refreshPanels()
})
sideTable.addRow(leftText: "Show tabs under parent windows", rightViews: [tabHierarchySideSwitch])
```

Add toggle to "Window Panel" section:
```swift
let tabHierarchyMainSwitch = LabelAndControl.makeSwitch("showTabHierarchyInMainPanel")
windowTable.addRow(leftText: "Show tabs under parent windows", rightViews: [tabHierarchyMainSwitch])
```

---

## Step 5: Main Panel — Visibility + Ordering + Indentation

### 5a. Allow tabbed windows through the filter when hierarchy enabled

**File:** `src/logic/Windows.swift` — `refreshIfWindowShouldBeShownToTheUser` (line 199)

Change:
```swift
(Preferences.showTabsAsWindows || !window.isTabbed)
```
To:
```swift
(Preferences.showTabsAsWindows || Preferences.showTabHierarchyInMainPanel || !window.isTabbed)
```

### 5b. Reorder `Windows.list` for hierarchy

After the `sort()` call in `updatesBeforeShowing()`, if hierarchy enabled, reorder so tab children follow their parent:

```swift
if Preferences.showTabHierarchyInMainPanel {
    reorderListForTabHierarchy()
}
```

New helper `reorderListForTabHierarchy()`: builds `[parentWID: [Window]]` map from list, then iterates root windows inserting their children immediately after.

### 5c. Indent tab tiles

**File:** `src/ui/main-window/TilesView.swift` — `layoutTileViews` (line 450)

After setting a tile's frame origin, if the window `isTabChild` and hierarchy is enabled, offset `x` by 20px (respecting LTR/RTL via `userInterfaceLayoutDirection`).

**File:** `src/ui/main-window/TileView.swift`

Add `var isTabChild = false` property, set in `updateRecycledCellWithNewContent`.

KNOWN UNKNOWN: 20px indent may conflict with small `interCellPadding`. Needs visual testing — may need to reduce indent or adjust padding.

---

## Step 6: Side Panel — Visibility + Ordering + Indentation

### 6a. Include tab children in `buildScreenGroups`

**File:** `src/ui/side-panel/SidePanelManager.swift` — lines 218-224

Change the `dominated` filter to conditionally allow tab children:

```swift
let isTab = window.isTabChild
let showTabs = Preferences.showTabHierarchyInSidePanel

let dominated = seen.contains(wid)
    || window.isWindowlessApp
    || window.isMinimized
    || window.isHidden
    || (!isVisible && !(showTabs && isTab))
    || self.isBlacklisted(window)
    || panelWindowNumbers.contains(Int(wid))
```

### 6b. Reorder groups for hierarchy

After building each group, when `showTabHierarchyInSidePanel` is enabled, reorder using the same parent→children pattern. New static helper `orderWithTabHierarchy(_ windows: [Window]) -> [Window]` on SidePanelManager.

### 6c. Indent tab rows

**File:** `src/ui/side-panel/WindowListView.swift` — line 132

Pass indentation info to row:
```swift
let isIndented = Preferences.showTabHierarchyInSidePanel && window.isTabChild
row.update(window, highlightState: state, isIndented: isIndented)
```

**File:** `src/ui/side-panel/SidePanelRow.swift`

- Store `titleLeadingConstraint` as a property (currently anonymous in `NSLayoutConstraint.activate`)
- Add `isIndented` stored property
- In `update(_, highlightState:, isIndented:)`: shift `iconLayer.frame.origin.x` and `titleLeadingConstraint.constant` by 20px when indented
- Update `layout()` override to account for indent

---

## Step 7: CLI Output

**File:** `src/logic/events/CliEvents.swift`

Add `parentWindowId` to `JsonWindowFull` struct (after `isTabbed`). Map as:
```swift
parentWindowId: $0.parentWindowId == 0 ? nil : $0.parentWindowId
```

Backwards-compatible: field is `null` for standalone windows.

---

## Edge Cases

- **Parent window closed**: Children become orphans → `queryTabParentIds` returns 0 on next refresh → they become standalone windows. `orderWithTabHierarchy` handles orphans via fallback append.
- **Tab switching**: Doesn't change `parentWindowId` — all tabs still reference the same parent. Only `isTabbed` / visibility state changes.
- **Space transitions**: Same 400ms CGS staleness applies. Side panel cooldown handles this. Main panel runs on-demand.
- **Non-native tabs** (Chrome, VS Code): `SLSWindowIteratorGetParentID` returns 0 → correctly treated as standalone windows.

---

## Implementation Order

1. Steps 1-2 (API declarations + data model) — prerequisites
2. Step 3 (tab parent discovery) — core logic
3. Step 4 (preferences) — needed by rendering steps
4. Step 6 (side panel) — simpler list layout, fast validation
5. Step 5 (main panel) — complex grid layout, do last
6. Step 7 (CLI) — quick, low-risk

---

## Verification

1. Build and launch with a tabbed Finder window (merge 2+ Finder windows)
2. Open side panel → confirm tabs appear indented under parent
3. Toggle `showTabHierarchyInSidePanel` off → tabs disappear
4. Open AltTab main panel with `showTabHierarchyInMainPanel` enabled → tabs appear indented
5. Close a tab → verify parent/children update on next refresh
6. Switch tabs → verify correct window gets highlight
7. Test with Ghostty tabs, Preview tabs, Terminal tabs
8. Test CLI: `--detailed-list` should show `parentWindowId` field
