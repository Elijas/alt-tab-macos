# Fix: Tab child click in MainPanel drags parent window across spaces

## Context

When clicking an indented tab row in the MainPanel that belongs to a window on another space, macOS drags the entire tab group (parent + all tabs) to the current space instead of switching to the parent's space and selecting that tab.

**Root cause**: `Window.focus()` (Window.swift:222-243) makes three sequential calls:
1. `_SLPSSetFrontProcessWithOptions(&psn, cgWindowId, ...)` — tells Window Server to activate this window
2. `self.makeKeyWindow(&psn)` — sends raw `SLPSPostEventRecordTo` events with `self.cgWindowId` embedded (line 252)
3. `self.axUiElement!.focusWindow()` — AXRaise

The initial fix only changed call #1 to use the parent's cgWindowId. But call #2 (`makeKeyWindow`) still embeds the **tab's** cgWindowId in the raw event bytes. The tab has `spaceIndexes: ()` (no space assignment), so this SLPSPostEventRecordTo event causes macOS to drag the parent window to the current space — undoing the space switch from call #1.

Non-indented (parent) windows work correctly because all three calls use the parent's own cgWindowId, which has a valid space assignment.

## Fix

Modify `Window.focus()` to handle tab children in two phases:

**Phase 1** — Switch to parent's space and make parent key:
- `_SLPSSetFrontProcessWithOptions(&psn, parentCgId, ...)` (already done)
- `parentWindow.makeKeyWindow(&psn)` — uses parent's cgWindowId in the raw bytes

**Phase 2** — Select the specific tab:
- `self.makeKeyWindow(&psn)` — now safe because we're already on the parent's space
- `self.axUiElement?.focusWindow()` — AXRaise to select the tab

Phase 2 runs after a delay (~500ms) to let the space transition settle. CLAUDE.md notes "CGS window-space APIs return stale data for ~400ms during space transitions" — calling `makeKeyWindow` with the tab's cgWindowId during this window could still trigger the drag.

### File: `src/logic/Window.swift`

Replace lines 226-239 (the current broken fix) with:

```swift
if self.isTabChild,
   let parentWindow = Windows.list.first(where: { $0.cgWindowId == self.parentWindowId }),
   let parentCgId = parentWindow.cgWindowId {
    // Phase 1: switch to parent's space and make it key
    _SLPSSetFrontProcessWithOptions(&psn, parentCgId, SLPSMode.userGenerated.rawValue)
    parentWindow.makeKeyWindow(&psn)
    // Phase 2: after space switch settles, select the specific tab
    Thread.sleep(forTimeInterval: 0.5)
    self.makeKeyWindow(&psn)
    try? self.axUiElement?.focusWindow()
} else {
    _SLPSSetFrontProcessWithOptions(&psn, self.cgWindowId!, SLPSMode.userGenerated.rawValue)
    self.makeKeyWindow(&psn)
    try? self.axUiElement!.focusWindow()
}
```

`parentWindow.makeKeyWindow(&psn)` works because `makeKeyWindow` is `private` in Swift but callable from other instances of the same type in the same file. It reads `self.cgWindowId` — when called on `parentWindow`, that's the parent's ID.

The `Thread.sleep` is on `BackgroundWork.accessibilityCommandsQueue` (a background OperationQueue), so it won't block the UI.

### KNOWN UNKNOWN

Whether `makeKeyWindow` with the tab's cgWindowId still triggers space-dragging even after the space switch completes. If it does, we'd need to rely solely on AXRaise for tab selection (remove the `self.makeKeyWindow` call in Phase 2). AXRaise on an inactive tab's axUiElement should select it, but the axUiElement may be stale.

## Verification

1. Build: `xcodebuild -workspace ... -scheme Release -configuration Release build CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""`
2. Reinstall with TCC reset (per CLAUDE.md)
3. Test: from Space 2, click an indented Ghostty tab that lives under a Space 1 parent in the MainPanel
4. Expected: macOS switches to Space 1 and the clicked tab becomes active
5. Also test: clicking a non-indented window from another space still works as before
