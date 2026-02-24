# Fix: Side panel shows spaces in temporarily wrong order during space switches

## Context

When switching macOS Spaces, the side panel briefly shows windows grouped under the wrong space (e.g. Space 1, Space 3, Space 2 order). It corrects itself after ~500ms.

**Root cause**: During a space transition, AX events (window focus, app activation) fire *immediately* — before macOS finishes updating its internal window-space mappings. These AX events trigger `SidePanelManager.refreshPanels()`, which calls the private CGS APIs (`CGSCopyWindowsWithOptionsAndTags`) to enumerate windows per space. During the transition animation (~300-500ms), these APIs return inconsistent data — a window on Space 2 may temporarily appear in Space 3's query result. Because the side panel deduplicates windows via a `seen` set (first occurrence wins), the window gets assigned to the wrong space group, making it look like spaces are swapped.

The existing 200ms throttle doesn't help because it lets the *first* call through immediately — which is the one that hits the stale CGS data.

This is the same class of CGS timing issue already documented in CLAUDE.md for `isTabbed` false positives, and the same reason `applicationHiddenOrShown` has a 200ms delay (`AccessibilityEvents.swift:71`).

## Fix

Add a "space change cooldown" to `SidePanelManager`. When `activeSpaceDidChangeNotification` fires, mark a timestamp. If `refreshPanels()` is called within the cooldown window, defer instead of firing immediately.

### 1. `SpacesEvents.swift` — notify side panel immediately on space change

At the top of `handleEvent`, before the debounce block, call `SidePanelManager.shared.notifySpaceChange()`. This must happen outside the debounce so it reaches the side panel *before* any AX-triggered refreshes.

```swift
@objc private static func handleEvent(_ notification: Notification) {
    SidePanelManager.shared.notifySpaceChange()  // ← add
    ScreensEvents.debouncerScreenAndSpace.debounce(.spaceEvent) {
        // ... existing code unchanged ...
    }
}
```

### 2. `SidePanelManager.swift` — add cooldown logic

Add a property and method:
```swift
private var lastSpaceChangeNanos: UInt64 = 0

func notifySpaceChange() {
    lastSpaceChangeNanos = DispatchTime.now().uptimeNanoseconds
}
```

Modify `refreshPanels()` to defer during cooldown:
```swift
func refreshPanels() {
    guard Preferences.sidePanelEnabled else { return }
    let throttleDelayInMs = 200

    // During space transitions, CGS APIs return inconsistent window-space data.
    // Defer all refreshes until the transition animation settles.
    let spaceChangeCooldownMs: UInt64 = 400
    let msSinceSpaceChange = (DispatchTime.now().uptimeNanoseconds - lastSpaceChangeNanos) / 1_000_000
    let inSpaceCooldown = msSinceSpaceChange < spaceChangeCooldownMs

    let timeSinceLastRefreshInMs = Float(DispatchTime.now().uptimeNanoseconds - lastRefreshTimeInNanoseconds) / 1_000_000
    if !inSpaceCooldown && timeSinceLastRefreshInMs >= Float(throttleDelayInMs) {
        lastRefreshTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
        refreshPanelsNow()
        return
    }
    guard !nextRefreshScheduled else { return }
    nextRefreshScheduled = true
    let delayMs = inSpaceCooldown ? Int(spaceChangeCooldownMs - msSinceSpaceChange) + 10 : throttleDelayInMs + 10
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) {
        self.nextRefreshScheduled = false
        self.refreshPanels()
    }
}
```

**How it works:**
- Normal window events (open, close, resize, focus): immediate refresh — unchanged behavior
- Space change detected: all refreshes deferred until 400ms after the space change, coalesced by the existing `nextRefreshScheduled` flag. The recursive `self.refreshPanels()` call fires after cooldown expires, sees the cooldown has passed, and executes the refresh with settled CGS data.

### Files to modify

| File | Change |
|------|--------|
| `src/ui/side-panel/SidePanelManager.swift` | Add `lastSpaceChangeNanos`, `notifySpaceChange()`, modify `refreshPanels()` |
| `src/logic/events/SpacesEvents.swift` | Add `SidePanelManager.shared.notifySpaceChange()` call |

### KNOWN UNKNOWN

`spaceChangeCooldownMs = 400` — The macOS space transition animation duration varies by hardware and "Reduce motion" settings. 400ms should cover most cases but may need tuning. If the issue persists, try 500-600ms.

## Verification

1. Rebuild: `xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -configuration Release build CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""`
2. Reset TCC: `tccutil reset Accessibility "com.lwouis.alt-tab-macos.at004" && tccutil reset ScreenCapture "com.lwouis.alt-tab-macos.at004"`
3. Copy to `/Applications`, launch, grant permissions
4. Open several windows across 3+ Spaces
5. Switch spaces rapidly (Ctrl+Left/Right) while watching the side panel
6. Verify: spaces should never appear in wrong order (the panel may show stale data for ~400ms during a switch, but never *wrong* ordering)
