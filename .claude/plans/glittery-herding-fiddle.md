# Side Panel: Middle-Click to Close Window

## Context

The side panel (both SidePanel and WindowPanel) displays window rows grouped by space. Currently left-click focuses a window. The user wants **middle-click on a window row** to close that window.

Space operations (close empty space, create new space + move window) are deferred — no reliable macOS API exists without SIP disabled or fragile Mission Control AX automation.

## Scope

- Middle-click on a window row → close that window via `Window.close()` (existing method at `Window.swift:131`)
- Middle-click on an "(empty)" space row → no-op (space ops deferred)
- Left-click behavior unchanged (focus)

## Implementation

### Change 1: SidePanelRow — add middle-click handler

**File**: `src/ui/side-panel/SidePanelRow.swift`

Add a `onMiddleClick` callback property (same pattern as existing `onClick`):

```swift
private var onMiddleClick: (() -> Void)?
```

Add `otherMouseUp` override:
```swift
override func otherMouseUp(with event: NSEvent) {
    if event.buttonNumber == 2 { onMiddleClick?() }
}
```

In `update(_ window:, highlightState:)` — set the callback:
```swift
onMiddleClick = { [weak window] in window?.close() }
```

In `showEmpty(highlightState:)` — clear it:
```swift
onMiddleClick = nil
```

### Change 2: SidePanelRow — add tracking area for otherMouseUp

`otherMouseUp` requires the view to be a first responder OR have an appropriate tracking area. The existing tracking area uses `.mouseEnteredAndExited` only. We need to verify that `otherMouseUp` fires — if not, we may need `NSView.acceptsFirstMouse` or to handle the event at the `WindowListView` level with hit-testing.

Fallback plan: If `otherMouseUp` doesn't fire on `SidePanelRow` (since the panel is `canBecomeKey: false` for SidePanel), handle it at `WindowListView` level with `otherMouseUp` + hit-test to find which row was clicked, then look up the associated window.

**Testing will determine which approach is needed.**

## Files to Modify

| File | Changes |
|------|---------|
| `src/ui/side-panel/SidePanelRow.swift` | Add `onMiddleClick`, `otherMouseUp`, set/clear in `update`/`showEmpty` |

## Verification

1. Build with xcodebuild, TCC reset + install per CLAUDE.md
2. **Middle-click window**: middle-click a window row → that window closes
3. **Middle-click empty row**: middle-click "(empty)" row → nothing happens
4. **Left-click unchanged**: left-click still focuses windows as before
5. **Both panels**: verify in both WindowPanel (floating) and SidePanel (screen-edge)
6. **Fullscreen window**: middle-click a fullscreen window row → should de-fullscreen then close (existing `Window.close()` behavior)
