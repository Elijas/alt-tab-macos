# Highlight Empty Rows for the Current/Visible Space

## Context

The WindowPanel (and SidePanel) show "(empty)" rows for spaces without windows, but all empty rows look identical — no background color. When a screen has multiple spaces and some are empty, there's no visual indicator of *which* empty space is the one you're currently viewing.

The user wants the current/visible space's empty row to be highlighted:
- **Accent color** (`.active`) when it's on the active screen (has global focus)
- **Grey** (`.selected`) when it's on a non-active screen

This mirrors exactly how window rows already behave with `HighlightState`.

## The Gap

`Spaces.refreshAllIdsAndIndexes()` already reads "Current Space" per screen from `CGSCopyManagedDisplaySpaces` (line 56), but stores it in a flat `visibleSpaces` array — losing the screen UUID mapping. The UI layer has no way to look up which space is current for a given screen.

## Files to Modify

| File | Changes |
|------|---------|
| `src/logic/Spaces.swift` | Add `currentSpaceForScreen` dict, populate alongside `visibleSpaces` |
| `src/ui/side-panel/SidePanelManager.swift` | Look up current space index per screen, propagate through return value and `ScreenColumnData` |
| `src/ui/side-panel/WindowPanel.swift` | Add `currentSpaceGroupIndex` to `ScreenColumnData` |
| `src/ui/side-panel/WindowListView.swift` | Accept `currentSpaceGroupIndex`, apply highlight to empty rows at that index |
| `src/ui/side-panel/SidePanelRow.swift` | Add `highlightState` parameter to `showEmpty()` |
| `src/ui/side-panel/SidePanel.swift` | Pass `currentSpaceGroupIndex` through to `listView.updateContents()` |

---

## Change 1: Spaces.swift — per-screen current space lookup

Add a new static property alongside the existing ones (line 7):
```swift
static var currentSpaceForScreen = [ScreenUuid: CGSSpaceID]()
```

In `refreshAllIdsAndIndexes()`, clear it at the top (alongside the other `.removeAll()` calls), and populate it inside the screen loop right after line 56:
```swift
currentSpaceForScreen[display] = (screen["Current Space"] as! NSDictionary)["id64"] as! CGSSpaceID
```

## Change 2: SidePanelManager.swift — find current space group index

### 2a. `buildScreenGroups()` — return current space group index

After building `sortedSpaces` (line 169-173), look up which space ID is the current one for this screen:
```swift
let currentSpaceId = Spaces.currentSpaceForScreen[screenUuid]
```

After building the `groups` array (line 176-203), find which index corresponds to the current space:
```swift
let currentSpaceGroupIndex: Int? = currentSpaceId.flatMap { csId in
    sortedSpaces.firstIndex(of: csId)
}
```

Add `currentSpaceGroupIndex` to the return tuple.

### 2b. `refreshPanelsNow()` — propagate to SidePanel and ScreenColumnData

At line 137, pass `currentSpaceGroupIndex` to `panel.updateContents()`.

At line 148-153, add `currentSpaceGroupIndex` to the `ScreenColumnData` initializer.

## Change 3: WindowPanel.swift — add field to ScreenColumnData

Add `let currentSpaceGroupIndex: Int?` to `ScreenColumnData` (line 3-8).

In `update()`, pass it through to `listView.updateContents()` at line 81.

## Change 4: SidePanelRow.swift — accept highlight state in showEmpty()

Change `showEmpty()` signature to accept an optional highlight state:
```swift
func showEmpty(highlightState: HighlightState = .none) {
    // ... existing code ...
    self.highlightState = highlightState  // was hardcoded to .none
    updateBackground()
    // ...
}
```

## Change 5: WindowListView.swift — apply highlight to empty current-space rows

Add `currentSpaceGroupIndex: Int? = nil` parameter to `updateContents()`. The default value means SidePanel's existing call site works without changes (though we'll update it too).

In the empty-group branch (around line 104-112), check if this group is the current space:
```swift
if group.isEmpty {
    // ... existing frame setup ...
    let emptyState: HighlightState
    if gi == currentSpaceGroupIndex {
        emptyState = isActiveScreen ? .active : .selected
    } else {
        emptyState = .none
    }
    row.showEmpty(highlightState: emptyState)
    // ...
}
```

## Change 6: SidePanel.swift — pass currentSpaceGroupIndex

Update `updateContents()` signature to accept `currentSpaceGroupIndex: Int?` and pass it through to `listView.updateContents()`.

## Verification

1. Build with xcodebuild
2. TCC reset + install + launch per CLAUDE.md
3. **Active screen, current empty space**: Switch to an empty space on the main monitor → that row shows accent-color highlight
4. **Non-active screen, current empty space**: Secondary monitor showing an empty space → grey highlight
5. **Non-current empty spaces**: Other empty spaces on the same screen remain unhighlighted
6. **No empty spaces**: Screens with all spaces having windows → no change in behavior
