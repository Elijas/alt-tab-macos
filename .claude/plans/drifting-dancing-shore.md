# Fix: Slow tab selection after space switch in focus()

## Context

After clicking a tab child in the side panel (or main panel), the space switch to the parent's space is instant, but selecting the specific tab takes ~1-2 seconds. The delay comes from `self.axUiElement?.focusWindow()` in Step 2 of the tab-child focus code.

**Root cause**: `focusWindow()` calls `performAction(kAXRaiseAction)` — a synchronous Mach IPC call that blocks until the app responds or times out. Tab children have stale `axUiElement` references (captured when the tab was inactive/invisible), so the app is slow to respond or doesn't respond at all. The AX messaging timeout is 1 second (`AXUIElement.swift:13`).

Parent windows don't have this problem because their `axUiElement` is fresh and valid.

## Fix

In the tab-child branch of `Window.focus()`, run `self.axUiElement?.focusWindow()` **asynchronously** instead of synchronously. `makeKeyWindow(&psn)` alone should handle tab selection (it sends raw Window Server events with the tab's cgWindowId). The async AXRaise serves as a belt-and-suspenders fallback — if the axUiElement is valid it helps, if stale it times out harmlessly on another thread.

### File: `src/logic/Window.swift` (~line 250-254)

Current code (Step 2 of tab-child focus):
```swift
// Select the specific tab
self.makeKeyWindow(&psn)
try? self.axUiElement?.focusWindow()
```

Replace with:
```swift
// Select the specific tab. makeKeyWindow sends raw WS events (fast).
// AXRaise runs async — tab axUiElements are often stale, and the
// synchronous 1s AX timeout was causing the perceived delay.
self.makeKeyWindow(&psn)
BackgroundWork.accessibilityCommandsQueue.addOperation { [weak self] in
    try? self?.axUiElement?.focusWindow()
}
```

KNOWN UNKNOWN: Whether `makeKeyWindow` alone is sufficient for tab selection in all cases. If it is, the async AXRaise is unnecessary overhead (but harmless). If `makeKeyWindow` sometimes fails and AXRaise is needed, the async approach ensures it still happens without blocking.

## Verification

1. Build: `xcodebuild -workspace ... -scheme Release -configuration Release build CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""`
2. Reinstall with TCC reset
3. Test same-space: click an indented tab on the current space — should feel instant
4. Test cross-space: click an indented tab on another space — space switch + tab select, no multi-second delay
5. Test non-tab windows still work as before (regression check)
