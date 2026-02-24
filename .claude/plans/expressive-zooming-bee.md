# Fix: Scrolling breaks row highlighting in side panel

## Context

Scrolling the side panel's window list completely breaks hover highlighting — after scrolling, the yellow highlight either covers the wrong rows or extends across multiple rows. This is because `SidePanelRow`'s `NSTrackingArea` doesn't account for scroll offset, and reused rows carry stale hover state.

## Root Cause

Two bugs in `src/ui/side-panel/SidePanelRow.swift`:

### 1. Missing `.inVisibleRect` on tracking areas (line 131)

```swift
// CURRENT — broken after scroll
trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
```

Rows live inside an `NSScrollView` (via `WindowListView`). Without `.inVisibleRect`, the tracking area uses `bounds` (local coordinates, origin 0,0) which becomes disconnected from the actual screen position after scrolling. Mouse enter/exit events fire for the wrong visual row.

The parent `SidePanel` already uses `.inVisibleRect` correctly (line 42) — this just wasn't applied to the child rows.

### 2. Stale `isHovered` on reused rows

`WindowListView` uses a row pool (`rowPool`) — rows are created once, then reused by calling `update()` or `showEmpty()` with new data. Neither method resets `isHovered`, so a previously-hovered row keeps its highlight background when it's recycled for a different window.

## Changes

### File: `src/ui/side-panel/SidePanelRow.swift`

1. **`updateTrackingAreas()`** (line 128-133): Add `.inVisibleRect` to the options and use `rect: .zero` (standard pattern — the system manages the rect automatically when `.inVisibleRect` is set):

   ```swift
   override func updateTrackingAreas() {
       super.updateTrackingAreas()
       if let trackingArea { removeTrackingArea(trackingArea) }
       trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
       addTrackingArea(trackingArea!)
   }
   ```

2. **`update()`** (line 66): Reset `isHovered = false` at the start of the method, before `updateBackground()` is called.

3. **`showEmpty()`** (line 85): Reset `isHovered = false` at the start, same reason.

## Verification

1. Build: `xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -configuration Release build CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""`
2. Reinstall with fresh TCC (kill → reset → rm → cp → open)
3. Manual test:
   - Open enough windows to make the side panel scrollable
   - Scroll up and down
   - Hover over rows — highlight should track the correct row at all scroll positions
   - Scroll while hovering — highlight should not stick to the old row
