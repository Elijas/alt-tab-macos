# Plan: "Enable Multiple Shortcuts and Gestures" Checkbox

## Context

The shortcuts tab currently always shows the full multi-shortcut UI (sidebar with Defaults, Shortcut 1-N, Gesture). We want to add a checkbox above the tabbed box that toggles between simple mode (single shortcut, no sidebar) and advanced mode (current multi-shortcut UI). This makes the default experience simpler for users who only need one shortcut.

## Behavior Summary

- **Checkbox unchecked** (simple mode): No sidebar, no Defaults/Gesture split. Just a flat editor for the single shortcut ("Shortcut 0" conceptually — the Defaults settings ARE the shortcut).
- **Checkbox checked** (multi mode): Current UI — sidebar with Defaults, Shortcut 1+, Gesture.
- **Enabling** (unchecked → checked): Current single-shortcut settings move into "Defaults". A new "Shortcut 1" is created with all defaults (no overrides).
- **Disabling** (checked → unchecked):
  - **No modal needed** if: gestures disabled AND only Shortcut 1 exists AND Shortcut 1 has all defaults (no overrides).
  - **Modal warning** otherwise, listing what will be lost:
    - Extra shortcuts (if shortcutCount > 1)
    - Gesture settings (if gesture != disabled)
    - Per-shortcut overrides (if any exist on Shortcut 1)
  - On confirm: collapse back to simple mode, keep Defaults values as the single shortcut.

## Files to Modify

1. **`src/logic/Preferences.swift`** — Add `"multipleShortcutsEnabled"` preference (default: `"false"`)
2. **`src/ui/settings-window/tabs/shortcuts/ShortcutsTab.swift`** — Main changes

## Implementation

### Step 1: Add Preference Key

In `Preferences.swift`, add to `defaultValues`:
```swift
"multipleShortcutsEnabled": "false",
```

### Step 2: Add Checkbox Above the Tabbed Box

In `ShortcutsTab.initTab()`, create a checkbox and place it before the `shortcutsView` in the `TableGroupSetView`:

```swift
static func initTab() -> NSView {
    // ... existing editor creation ...
    let shortcutsView = makeShortcutsView()
    let checkbox = NSButton(checkboxWithTitle: NSLocalizedString("Enable Multiple Shortcuts and Gestures", comment: ""), target: self, action: #selector(multipleShortcutsToggled(_:)))
    checkbox.state = CachedUserDefaults.bool("multipleShortcutsEnabled") ? .on : .off
    multipleShortcutsCheckbox = checkbox
    let view = TableGroupSetView(originalViews: [checkbox, shortcutsView],
        bottomPadding: 0, othersAlignment: .leading)
    // ...
}
```

Store references:
```swift
private static var multipleShortcutsCheckbox: NSButton?
private static var shortcutsContentView: ShortcutsContentView? // ref to toggle visibility
```

### Step 3: Toggle Handler with Modal Logic

Add `@objc multipleShortcutsToggled(_:)` method:

**When enabling (unchecked → checked):**
1. Set `"multipleShortcutsEnabled"` to `"true"`
2. Show the multi-shortcut UI (unhide `shortcutsContentView`)
3. Current single shortcut settings are already in "Defaults" keys — they stay
4. Ensure shortcutCount is at least 1 (it already is by default)
5. Call `refreshUi()`

**When disabling (checked → unchecked):**
1. Check if modal is needed:
   - `gestureEnabled = UserDefaults.standard.string(forKey: "nextWindowGesture") != GesturePreference.disabled.indexAsString`
   - `hasMultipleShortcuts = Preferences.shortcutCount > 1`
   - `hasOverrides = shortcut1HasAnyOverrides()` — check if any per-shortcut key for index 0 differs from the Defaults key
2. If none of these → skip modal, just disable
3. If any → show `NSAlert`:
   - `messageText`: "Disable Multiple Shortcuts?"
   - `informativeText`: Build dynamically from what will be lost:
     - "• N extra shortcut(s) will be removed" (if hasMultipleShortcuts)
     - "• Gesture trigger will be disabled" (if gestureEnabled)
     - "• Custom overrides on Shortcut 1 will be reset" (if hasOverrides)
   - Buttons: "Disable" (destructive), "Cancel"
4. On confirm:
   - Reset gesture to disabled: `Preferences.set("nextWindowGesture", GesturePreference.disabled.indexAsString)`
   - Remove extra shortcuts (set shortcutCount to 1, clear their prefs)
   - Reset Shortcut 1 overrides (remove per-shortcut keys so they inherit Defaults)
   - Set `"multipleShortcutsEnabled"` to `"false"`
   - Hide the multi-shortcut UI
   - Call `refreshUi()`
5. On cancel: revert checkbox to `.on`

### Step 4: UI Visibility Toggle

When `multipleShortcutsEnabled` is false, hide the `ShortcutsContentView` (the sidebar+editor panel). The Defaults editor settings are still the active settings since there's only one shortcut and it inherits everything from Defaults.

KNOWN UNKNOWN: Whether "simple mode" should show a simplified inline editor (just the Trigger + Defaults sections without the sidebar), or whether hiding the entire panel is sufficient. For V1, hiding the entire multi-shortcut panel is simplest — the user already sees their shortcut configured via the Defaults values. We can add an inline simple editor later if needed.

### Step 5: Helper — Check for Overrides on Shortcut 1

```swift
private static func shortcut1HasAnyOverrides() -> Bool {
    let index = 0
    for baseName in perShortcutPreferences {
        let perKey = Preferences.indexToName(baseName, index)
        let defaultKey = baseName
        // If per-shortcut key exists and differs from default, it's an override
        if let perValue = UserDefaults.standard.string(forKey: perKey),
           let defaultValue = UserDefaults.standard.string(forKey: defaultKey),
           perValue != defaultValue {
            return true
        }
    }
    return false
}
```

## Existing Patterns Reused

- **NSAlert pattern**: Matches `ControlsTab.swift:790-801` (`.warning` style, destructive first button, cancel with Escape key equivalent)
- **Checkbox creation**: `NSButton(checkboxWithTitle:target:action:)` as in `LabelAndControl.swift:118`
- **Preference storage**: `CachedUserDefaults.bool()` / `Preferences.set()` as used throughout
- **TableGroupSetView**: Non-TableGroupView items (like the checkbox) go into the `continuousOthers` horizontal stack with leading alignment — already handled by the existing layout logic
- **Shortcut removal**: Reuse existing `resetShortcutPreferences()` and `perShortcutPreferences`

## Verification

1. Build and run the app
2. Open Settings → Shortcuts tab
3. Checkbox should appear above the tabbed box, unchecked by default
4. Check the checkbox → multi-shortcut UI appears (sidebar + editors)
5. Add a second shortcut, enable a gesture, override some settings
6. Uncheck → modal appears listing what will be lost
7. Confirm → extra shortcuts removed, gesture disabled, overrides reset, panel hidden
8. Uncheck when only Shortcut 1 with all defaults + gesture disabled → no modal, just hides
9. Check again → UI reappears with clean Shortcut 1
10. Quit and relaunch → checkbox state persists
