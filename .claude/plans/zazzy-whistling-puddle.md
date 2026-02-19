# Plan V3: "Enable Multiple Shortcuts" Checkbox — Smart Override Resolution

## Context

V2 implemented the always-visible sidebar approach, but the user found several issues:
1. **Layout**: Gesture row stuck at bottom of sidebar with a big gap — should be adjacent to Shortcut row, both top-aligned
2. **Naming**: "Shortcut 1" should be "Shortcut" in simple mode (no number when there's only one)
3. **Checkbox label**: Should be "Enable multiple shortcuts" (not "Enable Multiple Shortcuts and Gestures")
4. **Gesture editor**: Should show ALL settings (trigger + filtering), not trigger-only
5. **Smart override resolution**: Toggle should preserve Defaults, resolve values for Shortcut/Gesture, and reconstruct overrides on re-enable

### Critical Architecture Detail

`Preferences.indexToName("x", 0)` returns `"x"` (no suffix). This means **Shortcut 0 and Defaults share the same UserDefaults keys**. Index 1 → `"x2"`, index 9 (gesture) → `"x10"`. This shapes the entire toggle design — we must save/restore a "Defaults snapshot" to preserve true Defaults values through Shortcut 0's override pollution.

## Design

### Simple Mode (checkbox unchecked — default)
- **Sidebar**: "Shortcut" and "Gesture" top-aligned in scrollable rows stack (no gap)
- **Hidden**: Defaults row, Defaults separator, +/- buttons, fixed gesture section (separator + row)
- **Editors**:
  - Shortcut → `simpleModeEditorView` (Trigger + Appearance + Filtering + Behavior + Multiple Screens — already uses correct keys since index 0 = base key)
  - Gesture → `simpleGestureEditorView` (Trigger + Filtering with per-gesture keys like `appsToShow10`)
- **Checkbox label**: "Enable multiple shortcuts"

### Multi Mode (checkbox checked)
- **Sidebar**: "Defaults" at top, "Shortcut 1-N" in scrollable area, "Gesture" fixed at bottom, +/- buttons
- **Editors**: Override-wrapped editors (unchanged from V2)

### Toggle: Disable (multi → simple)

1. Save `defaultsSnapshot` to UserDefaults as JSON key `"savedDefaultsSnapshot"`
2. **Resolve** effective values for shortcuts 1+ and gesture into their per-shortcut/gesture keys
   - For each OverridableRowView: read control's current display value → write to per-key
   - Shortcut 0: skip (shares base keys, already has effective values)
3. Save shortcutCount to `savedShortcutCount`, set shortcutCount to 1
4. Hide multi-mode elements, select Shortcut, refreshUi

### Toggle: Enable (simple → multi)

1. Load saved snapshot from `"savedDefaultsSnapshot"`
2. **Capture** Shortcut 0's current base key values (before restoring)
3. **Restore** base keys from saved snapshot (fixes Defaults pollution from overrides)
4. Rebuild live `defaultsSnapshot` via `snapshotAllDefaults()`
5. Restore shortcutCount from `savedShortcutCount`
6. **Reconstruct overrides** for all shortcuts and gesture:
   - Shortcut 0: compare pre-restore values to snapshot → if different = override
   - Shortcuts 1+: compare per-shortcut key to snapshot → if different = override
   - Gesture: compare per-gesture key to snapshot → if different = override
   - For overrides: `setControlValue()` + `setOverridden(true)`
   - For inherited: `setOverridden(false)` (refreshControl restores Defaults value)
7. Show multi-mode elements, select Defaults, refreshUi

### Example Walkthrough

**Multi mode state:** Defaults A=1 B=2, Shortcut1 A=inherit B=override(3), Gesture A=override(5) B=inherit

**Disable:**
- Save snapshot: {A:1, B:2}
- Shortcut 0: base keys have A=1, B=3 (B polluted by override) — skip
- Gesture: resolve A=5→`appsToShow10`, B=2→per-gesture key
- Simple mode shows: Shortcut A=1 B=3, Gesture A=5 B=2 ✓

**Re-enable (user didn't change anything):**
- Pre-restore base keys: A=1, B=3
- Restore from snapshot: base keys → A=1, B=2
- Shortcut 0: A: 1==1→inherited, B: 3!=2→override(3) ✓
- Gesture: A: 5!=1→override(5), B: 2==2→inherited ✓
- Defaults shows: A=1, B=2 ✓

**Accepted loss:** An override deliberately set to match Defaults becomes inherited on re-enable.

## Files to Modify

1. **`src/ui/settings-window/tabs/shortcuts/OverridableRow.swift`** — Add public accessors for control value
2. **`src/ui/settings-window/tabs/shortcuts/ShortcutsTab.swift`** — Main changes
3. **`src/logic/Preferences.swift`** — Add `savedDefaultsSnapshot` default

## Implementation Steps

### Step 1: Add Control Value Accessors to OverridableRowView

In `OverridableRow.swift`, add two methods to `OverridableRowView`:

```swift
var currentControlValue: Int? {
    if let dropdown = wrappedControl as? NSPopUpButton {
        return dropdown.indexOfSelectedItem
    } else if let segmented = wrappedControl as? NSSegmentedControl {
        return segmented.selectedSegment
    }
    return nil
}

func setControlValue(_ index: Int) {
    if let dropdown = wrappedControl as? NSPopUpButton, index >= 0, index < dropdown.numberOfItems {
        dropdown.selectItem(at: index)
    } else if let segmented = wrappedControl as? NSSegmentedControl, index >= 0, index < segmented.segmentCount {
        segmented.selectedSegment = index
    }
}
```

### Step 2: Add `savedDefaultsSnapshot` Preference

In `Preferences.swift` `defaultValues`, add:
```swift
"savedDefaultsSnapshot": "",
```

### Step 3: Rename Checkbox Label

In `initTab()` (line 210), change:
```swift
"Enable Multiple Shortcuts and Gestures"  →  "Enable multiple shortcuts"
```

### Step 4: Mode-Aware Shortcut Naming

Change `shortcutTitle(_:)` to check mode:
```swift
private static func shortcutTitle(_ index: Int) -> String {
    let isSimpleMode = !CachedUserDefaults.bool("multipleShortcutsEnabled")
    if isSimpleMode {
        return NSLocalizedString("Shortcut", comment: "")
    }
    return NSLocalizedString("Shortcut", comment: "") + " " + String(index + 1)
}
```

### Step 5: Sidebar Layout — Gesture in Scrollable Rows (Simple Mode)

**New static vars:**
```swift
private static var simpleGestureSidebarRow: ShortcutSidebarRow?
private static var gestureSidebarSeparator: NSView?
```

**Store gesture separator ref** in `makeShortcutSidebar()` — the separator above the gesture row.

**Update `setMultiModeElements(visible:)`** — also toggle the fixed gesture section:
```swift
private static func setMultiModeElements(visible: Bool) {
    defaultsSidebarRow?.isHidden = !visible
    defaultsSidebarSeparator?.isHidden = !visible
    buttonsRowView?.isHidden = !visible
    // Fixed gesture section: visible in multi mode, hidden in simple mode
    // (simple mode puts gesture in the scrollable rows stack)
    gestureSidebarSeparator?.isHidden = !visible
    gestureSidebarRow?.isHidden = !visible
}
```

**Update `refreshShortcutRows()`** — in simple mode, add gesture row to the stack:
```swift
private static func refreshShortcutRows() {
    guard let rows = shortcutRowsStackView else { return }
    clearArrangedSubviews(rows)
    shortcutRows.removeAll(keepingCapacity: true)
    simpleGestureSidebarRow = nil
    let isSimpleMode = !CachedUserDefaults.bool("multipleShortcutsEnabled")
    for index in 0..<Preferences.shortcutCount {
        let row = ShortcutSidebarRow()
        row.setContent(shortcutTitle(index), shortcutSummary(index))
        // ... same click/hover handlers ...
        rows.addArrangedSubview(row)
        // ... same constraints + separators ...
        shortcutRows.append(row)
        if index < Preferences.shortcutCount - 1 { /* separator */ }
    }
    // Simple mode: add gesture row to the stack (top-aligned with shortcut)
    if isSimpleMode {
        // Separator
        let sep = NSView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
        rows.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        sep.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth).isActive = true
        // Gesture row
        let gestureRow = ShortcutSidebarRow()
        let gestureIndex = Int(UserDefaults.standard.string(forKey: "nextWindowGesture") ?? "0") ?? 0
        let gesture = GesturePreference.allCases[safe: gestureIndex] ?? .disabled
        gestureRow.setContent(NSLocalizedString("Gesture", comment: ""), gesture.localizedString)
        gestureRow.onClick = { _, _ in selectGesture() }
        gestureRow.onMouseEntered = { _, _ in gestureRow.setHovered(true) }
        gestureRow.onMouseExited = { _, _ in gestureRow.setHovered(false) }
        rows.addArrangedSubview(gestureRow)
        gestureRow.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        gestureRow.heightAnchor.constraint(equalToConstant: sidebarRowHeight).isActive = true
        simpleGestureSidebarRow = gestureRow
    }
}
```

**Update `refreshSelection()`** — also set `simpleGestureSidebarRow` selection:
```swift
if isSimpleMode {
    // ...existing logic...
    simpleGestureSidebarRow?.setSelected(selectedIndex == gestureSelectionIndex)
}
```

**Update `refreshGestureRow()`** — also update `simpleGestureSidebarRow`:
```swift
simpleGestureSidebarRow?.setContent(title, summary)
simpleGestureSidebarRow?.setSelected(selectedIndex == gestureSelectionIndex)
```

### Step 6: Expand Simple Gesture Editor (Trigger + Filtering)

Replace the trigger-only `makeSimpleGestureEditor()` with trigger + filtering using per-gesture keys:

```swift
private static func makeSimpleGestureEditor() -> NSView {
    let width = shortcutEditorWidth
    let gestureIdx = Preferences.gestureIndex
    let table = TableGroupView(width: width)

    // TRIGGER section
    table.addNewTable()
    let gesture = LabelAndControl.makeDropdown("nextWindowGesture", GesturePreference.allCases)
    // ... info button + popover (same as current) ...
    table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Trigger", comment: ""),
        rightViews: [gestureWithTooltip]))

    // FILTERING section — bound to per-gesture keys
    table.addNewTable()
    table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Filtering", comment: ""), bold: true)], rightViews: nil)
    table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from applications", comment: ""))],
        rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("appsToShow", gestureIdx), AppsToShowPreference.allCases)])
    table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from Spaces", comment: ""))],
        rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("spacesToShow", gestureIdx), SpacesToShowPreference.allCases)])
    table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from screens", comment: ""))],
        rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("screensToShow", gestureIdx), ScreensToShowPreference.allCases)])
    table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show minimized windows", comment: ""),
        rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("showMinimizedWindows", gestureIdx), ShowHowPreference.allCases)]))
    table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show hidden windows", comment: ""),
        rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("showHiddenWindows", gestureIdx), ShowHowPreference.allCases)]))
    table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show fullscreen windows", comment: ""),
        rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("showFullscreenWindows", gestureIdx),
            ShowHowPreference.allCases.filter { $0 != .showAtTheEnd })]))
    table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show apps with no open window", comment: ""),
        rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("showWindowlessApps", gestureIdx), ShowHowPreference.allCases)]))
    table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Order windows by", comment: ""),
        rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("windowOrder", gestureIdx), WindowOrderPreference.allCases)]))

    return table
}
```

### Step 7: Override Resolution Helpers

Add to `ShortcutsTab.swift`:

```swift
/// Indexed settings that have per-shortcut keys (via indexToName)
private static let indexedSettingBaseNames = [
    "appsToShow", "spacesToShow", "screensToShow",
    "showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows",
    "showWindowlessApps", "windowOrder", "shortcutStyle",
]

private static func saveDefaultsSnapshot() {
    if let data = try? JSONEncoder().encode(defaultsSnapshot),
       let json = String(data: data, encoding: .utf8) {
        Preferences.set("savedDefaultsSnapshot", json, false)
    }
}

private static func loadSavedDefaultsSnapshot() -> [String: Int]? {
    let json = UserDefaults.standard.string(forKey: "savedDefaultsSnapshot") ?? ""
    guard let data = json.data(using: .utf8),
          let snapshot = try? JSONDecoder().decode([String: Int].self, from: data) else { return nil }
    return snapshot.isEmpty ? nil : snapshot
}

/// Reads effective values from multi-mode override editors and writes
/// them to per-shortcut/per-gesture UserDefaults keys.
private static func resolveOverridesToPerShortcutKeys() {
    // Shortcuts 1+ (index 0 shares keys with Defaults — already correct)
    for shortcutIndex in 1..<Preferences.shortcutCount {
        guard shortcutIndex < shortcutEditorViews.count else { continue }
        var rows = [OverridableRowView]()
        findOverridableRows(in: shortcutEditorViews[shortcutIndex], result: &rows)
        for row in rows {
            guard let value = row.currentControlValue else { continue }
            Preferences.set(row.settingName, String(value), false)
        }
    }
    // Gesture
    if let gestureEditorView {
        var rows = [OverridableRowView]()
        findOverridableRows(in: gestureEditorView, result: &rows)
        for row in rows {
            guard let value = row.currentControlValue else { continue }
            Preferences.set(row.settingName, String(value), false)
        }
    }
}

/// Compares per-shortcut/gesture values to Defaults snapshot and sets
/// override state on each OverridableRowView accordingly.
private static func reconstructOverrides(savedSnapshot: [String: Int], shortcut0PreRestoreValues: [String: Int]) {
    // Helper: find base name for an indexed setting key
    func baseName(for settingName: String) -> String? {
        // For index 0: settingName == baseName (e.g., "appsToShow")
        if indexedSettingBaseNames.contains(settingName) { return settingName }
        // For index 1+: settingName has suffix (e.g., "appsToShow2")
        return indexedSettingBaseNames.first { settingName.hasPrefix($0) && settingName != $0 }
    }

    // Shortcut 0: compare pre-restore base key values to snapshot
    if let editor = shortcutEditorViews.first {
        var rows = [OverridableRowView]()
        findOverridableRows(in: editor, result: &rows)
        for row in rows {
            guard let base = baseName(for: row.settingName) else {
                row.setOverridden(false) // Non-indexed (appearance, showOnScreen): inherited
                continue
            }
            let preRestoreValue = shortcut0PreRestoreValues[base] ?? 0
            let defaultsValue = savedSnapshot[base] ?? 0
            if preRestoreValue != defaultsValue {
                row.setControlValue(preRestoreValue)
                row.setOverridden(true)
            } else {
                row.setOverridden(false)
            }
        }
    }

    // Shortcuts 1+: compare per-shortcut keys to snapshot
    for shortcutIndex in 1..<Preferences.shortcutCount {
        guard shortcutIndex < shortcutEditorViews.count else { continue }
        var rows = [OverridableRowView]()
        findOverridableRows(in: shortcutEditorViews[shortcutIndex], result: &rows)
        for row in rows {
            guard let base = baseName(for: row.settingName) else {
                row.setOverridden(false)
                continue
            }
            let perShortcutValue = Int(UserDefaults.standard.string(forKey: row.settingName) ?? "0") ?? 0
            let defaultsValue = savedSnapshot[base] ?? 0
            if perShortcutValue != defaultsValue {
                row.setControlValue(perShortcutValue)
                row.setOverridden(true)
            } else {
                row.setOverridden(false)
            }
        }
    }

    // Gesture: compare per-gesture keys to snapshot
    if let gestureEditorView {
        var rows = [OverridableRowView]()
        findOverridableRows(in: gestureEditorView, result: &rows)
        for row in rows {
            guard let base = baseName(for: row.settingName) else {
                row.setOverridden(false)
                continue
            }
            let perGestureValue = Int(UserDefaults.standard.string(forKey: row.settingName) ?? "0") ?? 0
            let defaultsValue = savedSnapshot[base] ?? 0
            if perGestureValue != defaultsValue {
                row.setControlValue(perGestureValue)
                row.setOverridden(true)
            } else {
                row.setOverridden(false)
            }
        }
    }
}
```

### Step 8: Rewrite Toggle Handlers

```swift
private static func disableMultipleShortcuts() {
    // 1. Save Defaults snapshot (true Defaults values, before pollution)
    saveDefaultsSnapshot()
    // 2. Resolve effective values for shortcuts 1+ and gesture
    resolveOverridesToPerShortcutKeys()
    // 3. Save and set shortcut count
    Preferences.set("savedShortcutCount", String(Preferences.shortcutCount), false)
    Preferences.set("shortcutCount", "1", false)
    Preferences.set("multipleShortcutsEnabled", "false")
    setMultiModeElements(visible: false)
    selectedIndex = 0
    refreshUi()
}

private static func enableMultipleShortcuts() {
    guard let savedSnapshot = loadSavedDefaultsSnapshot() else {
        // First-time enable or no saved state
        Preferences.set("multipleShortcutsEnabled", "true")
        let saved = CachedUserDefaults.int("savedShortcutCount")
        if saved > 1 { Preferences.set("shortcutCount", String(saved), false) }
        setMultiModeElements(visible: true)
        selectedIndex = defaultsSelectionIndex
        refreshUi()
        return
    }
    // 1. Capture Shortcut 0's current values (before restoring Defaults)
    var shortcut0Values = [String: Int]()
    for baseName in indexedSettingBaseNames {
        shortcut0Values[baseName] = Int(UserDefaults.standard.string(forKey: baseName) ?? "0") ?? 0
    }
    // 2. Restore base keys from saved snapshot (fixes Defaults pollution)
    for (key, value) in savedSnapshot {
        Preferences.set(key, String(value), false)
    }
    // 3. Rebuild live snapshot
    snapshotAllDefaults()
    // 4. Restore shortcut count
    let saved = CachedUserDefaults.int("savedShortcutCount")
    if saved > 1 { Preferences.set("shortcutCount", String(saved), false) }
    Preferences.set("multipleShortcutsEnabled", "true")
    // 5. Reconstruct overrides
    reconstructOverrides(savedSnapshot: savedSnapshot, shortcut0PreRestoreValues: shortcut0Values)
    setMultiModeElements(visible: true)
    selectedIndex = defaultsSelectionIndex
    refreshUi()
}
```

### Step 9: Update initTab() for Simple Mode Gesture Resolution

On first load in simple mode, gesture per-keys might not have resolved values yet. Add resolution to `initTab()`:

```swift
if !isMultiEnabled {
    if UserDefaults.standard.string(forKey: "savedShortcutCount") == nil {
        Preferences.set("savedShortcutCount", String(Preferences.shortcutCount), false)
    }
    // Ensure Defaults snapshot exists for first-time disable
    if loadSavedDefaultsSnapshot() == nil {
        snapshotAllDefaults()
        saveDefaultsSnapshot()
        resolveOverridesToPerShortcutKeys()
    }
    Preferences.set("shortcutCount", "1", false)
    selectedIndex = 0
} else {
    // Multi mode: reconstruct overrides from saved state
    if let savedSnapshot = loadSavedDefaultsSnapshot() {
        var shortcut0Values = [String: Int]()
        for baseName in indexedSettingBaseNames {
            shortcut0Values[baseName] = Int(UserDefaults.standard.string(forKey: baseName) ?? "0") ?? 0
        }
        for (key, value) in savedSnapshot { Preferences.set(key, String(value), false) }
        snapshotAllDefaults()
        reconstructOverrides(savedSnapshot: savedSnapshot, shortcut0PreRestoreValues: shortcut0Values)
    }
    selectedIndex = defaultsSelectionIndex
}
```

### Step 10: Remove Dead Code from V2

Remove from V2 that's no longer needed:
- `preActivateDemoOverrides` call in `makeShortcutEditor` — overrides now reconstructed dynamically

## Verification

1. Build: `xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Debug -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY="-" -derivedDataPath /Users/user/Library/Developer/Xcode/DerivedData/alt-tab-macos-gubybsmxjrlleueerlvdotbafqno build`
2. Run: `pkill -f "AltTab Fork" 2>/dev/null; sleep 1; open /Users/user/Library/Developer/Xcode/DerivedData/alt-tab-macos-gubybsmxjrlleueerlvdotbafqno/Build/Products/Debug/AltTab\ Fork.app`
3. Open Settings → Shortcuts tab
4. **Simple mode (default)**: Sidebar shows "Shortcut" + "Gesture" top-aligned, no gap. Checkbox says "Enable multiple shortcuts".
5. Click "Gesture" → full editor with trigger dropdown + 8 filtering controls
6. **Check checkbox** → "Defaults" appears, "Shortcut" becomes "Shortcut 1", gesture moves to bottom, +/- buttons appear
7. Override some settings on Shortcut 1 and Gesture. Note the values.
8. **Uncheck checkbox** → instant transition. Shortcut shows resolved values (Defaults values for inherited, override values for overridden). Gesture shows its resolved values.
9. **Re-check** → overrides reconstructed correctly. Defaults unchanged. Gesture overrides preserved.
10. Change a filtering setting in simple mode on Shortcut, then re-check → changed value appears as override on Shortcut 1.
11. Quit and relaunch → mode and all state persist correctly

## KNOWN UNKNOWNS

- KNOWN UNKNOWN: `showFullscreenWindows` dropdown uses a filtered allCases. `indexOfSelectedItem` maps to the filtered list, not the full enum. Need to verify during implementation that the stored preference index aligns correctly — if the dropdown stores the raw enum index (via LabelAndControl) this is fine, but if it stores the dropdown position, filtered dropdowns may need special handling.
