# Per-Screen Side Panel On/Off

## Context

The side panel "off" button (`SidePanel.swift:131`) currently sets `Preferences.sidePanelEnabled = false` which tears down ALL panels on ALL screens. The user wants:
- **Per-screen off**: clicking "off" on a specific side panel hides only that screen's panel, persisted across restarts
- **Global off**: remains in Settings as the master toggle

## Approach

Store a set of disabled screen UUIDs in UserDefaults (JSON-encoded array, following the blacklist pattern). The "off" button on each SidePanel adds that screen's UUID to the disabled set. The global toggle in Settings remains as-is — it's the master gate.

## Files to Modify

### 1. `src/logic/Preferences.swift`
- Add default: `"sidePanelDisabledScreens": "[]"`
- Add accessor: `static var sidePanelDisabledScreens: [String] { CachedUserDefaults.json("sidePanelDisabledScreens", [String].self) }`

### 2. `src/ui/side-panel/SidePanelManager.swift`
- Add `disableScreen(_ uuid: ScreenUuid)` — appends UUID to the disabled set, persists, removes that one panel
- Add `enableScreen(_ uuid: ScreenUuid)` — removes UUID from disabled set, persists, creates panel for that screen
- In `rebuildPanelsForScreenChange()`: skip screens whose UUID is in the disabled set (line ~88, inside the `for screen in NSScreen.screens` loop)

### 3. `src/ui/side-panel/SidePanel.swift`
- Change `turnOff()` (line 131-134): instead of setting global `sidePanelEnabled` to false, call `SidePanelManager.shared.disableScreen(uuid)` for this panel's screen
- The panel already has `targetScreen` — get UUID via `targetScreen.cachedUuid()`

## Detailed Changes

### Preferences.swift — add preference (~2 lines)
```
Default: "sidePanelDisabledScreens": "[]"
Accessor: static var sidePanelDisabledScreens: [String] { CachedUserDefaults.json("sidePanelDisabledScreens", [String].self) }
```

### SidePanelManager.swift — per-screen disable/enable

```swift
func disableScreen(_ uuid: ScreenUuid) {
    var disabled = Preferences.sidePanelDisabledScreens
    let key = uuid as String
    if !disabled.contains(key) { disabled.append(key) }
    Preferences.set("sidePanelDisabledScreens", disabled)
    // remove just this panel
    panels[uuid]?.orderOut(nil)
    panels.removeValue(forKey: uuid)
}

func enableScreen(_ uuid: ScreenUuid) {
    var disabled = Preferences.sidePanelDisabledScreens
    disabled.removeAll { $0 == uuid as String }
    Preferences.set("sidePanelDisabledScreens", disabled)
    rebuildPanelsForScreenChange()
}
```

In `rebuildPanelsForScreenChange()`, add check inside the loop:
```swift
let disabledScreens = Set(Preferences.sidePanelDisabledScreens)
for screen in NSScreen.screens {
    guard let uuid = screen.cachedUuid() else { continue }
    guard !disabledScreens.contains(uuid as String) else { continue }  // ← new
    ...
}
```

### SidePanel.swift — change turnOff()
```swift
@objc private func turnOff() {
    guard let uuid = targetScreen.cachedUuid() else { return }
    SidePanelManager.shared.disableScreen(uuid)
}
```

## Re-enabling

Per-screen re-enable isn't exposed in UI yet. Options to re-enable a screen's panel:
- The global off/on toggle in Settings resets (call `enableAllScreens()` which clears the disabled set when toggling on)
- Or: add a "Disabled Screens" list in PanelTab settings

For simplicity, toggling the global switch off then on will clear all per-screen disables — this is the most discoverable recovery path.

### Implementation: in PanelTab or SidePanelManager.setup()
When the global toggle is turned ON, clear the disabled set:
```swift
// In PanelTab extraAction for sidePanelEnabled:
if Preferences.sidePanelEnabled {
    Preferences.set("sidePanelDisabledScreens", [String]())
    SidePanelManager.shared.setup()
}
```

## Verification
1. Open side panels on multi-monitor setup
2. Click "off" on one screen's panel → only that panel disappears
3. Restart app → that screen's panel stays off
4. Toggle global off/on in Settings → all panels come back (disabled set cleared)
5. Single monitor: "off" button hides the only panel; global toggle restores it
