@include ./AGENTS.md

# Running the App

```bash
pkill -f "AltTab Fork" 2>/dev/null; sleep 1; open /Users/user/Library/Developer/Xcode/DerivedData/alt-tab-macos-gubybsmxjrlleueerlvdotbafqno/Build/Products/Debug/AltTab\ Fork.app
```

# Building

```bash
xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Debug -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY="-" -derivedDataPath /Users/user/Library/Developer/Xcode/DerivedData/alt-tab-macos-gubybsmxjrlleueerlvdotbafqno build
```

# Codebase Map

## Settings Window (the main UI work area)

- `src/ui/settings-window/tabs/` — Each tab (Shortcuts, Controls, etc.) is a subfolder
- `src/ui/settings-window/tabs/shortcuts/ShortcutsTab.swift` — **Main file for the Shortcuts tab.** Contains sidebar, editor pane, simple/multi mode toggle, override resolution logic. ~1500 lines, all static methods on `ShortcutsTab`.
- `src/ui/settings-window/tabs/shortcuts/OverridableRow.swift` — Override system: `OverridableRowView` (wraps a control with inherited/overridden state, grey-out, reset button) and `OverrideTracker` (counts overrides, manages Reset All, updates footer/section labels).

## Preferences

- `src/logic/Preferences.swift` — All UserDefaults keys and their default values. Key function: `indexToName("key", index)` — index 0 returns `"key"`, index 1 returns `"key2"`, index 9 (gesture) returns `"key10"`. This means **Shortcut 0 and Defaults share the same UserDefaults keys**.

## UI Building Blocks

- `src/ui/generic-components/TableGroupView.swift` — macOS-style grouped settings table (rounded corners, separators). Used everywhere in settings editors.
- `src/ui/generic-components/LabelAndControl.swift` — Factory methods for dropdowns, segmented controls, shortcut recorders, etc. `makeDropdown(key, cases)` creates an NSPopUpButton bound to a UserDefaults key.
- `src/ui/generic-components/ImageTextButtonView.swift` — Image radio button group (used for appearance style: thumbnails/titles/icons).

## Architecture Notes

- **Simple mode vs Multi mode**: Controlled by `multipleShortcutsEnabled` preference. Simple mode shows one shortcut + gesture with shared settings. Multi mode shows Defaults + Shortcut 1-N + Gesture with per-shortcut overrides.
- **Override resolution on toggle**: When switching modes, a JSON snapshot of Defaults values is saved/restored via `savedDefaultsSnapshot` to handle the Shortcut 0 / Defaults key-sharing problem. See `saveDefaultsSnapshot()`, `loadSavedDefaultsSnapshot()`, `resolveOverridesToPerShortcutKeys()`, `reconstructOverrides()` in ShortcutsTab.swift.
- **Gesture index**: `Preferences.gestureIndex` = `maxShortcutCount` = 9. So gesture keys are like `appsToShow10`.
