# Plan: MainPanel "Stretch rows to fill" toggle

## Context

The MainPanel's `WindowListView` has a 3-tier layout system in `relayoutForBounds()`:
- **Tier 1** (proportional fill): rows expand proportionally to fill vertical space (wrapping preserved)
- **Tier 2** (compact proportional): rows still proportional but wrapping disabled
- **Tier 3** (fixed + scroll): rows at compact fixed height, scrollbar appears

When a column has few buttons, tiers 1/2 spread them vertically ("fill mode"). With many buttons, tier 3 kicks in ("tight mode with scrollbar"). The user wants a toggle to **always** use tight/top-aligned layout, only showing a scrollbar when content overflows.

## Approach

Add a `verticalFillEnabled` property to `WindowListView`. When `false`, `relayoutForBounds()` skips tiers 1 & 2 and always uses fixed row heights (respecting the wrapping preference). Controlled by a new `mainPanelVerticalFill` preference with a toggle in PanelTab settings.

## Changes

### 1. `src/logic/Preferences.swift`
- Add `"mainPanelVerticalFill": "true"` to `defaultValues` (line ~84, near other mainPanel prefs)
- Add static accessor: `static var mainPanelVerticalFill: Bool { CachedUserDefaults.bool("mainPanelVerticalFill") }`

### 2. `src/ui/side-panel/WindowListView.swift`
- Add property: `var verticalFillEnabled: Bool = true` (near `showTabHierarchy` on line 22)
- In `relayoutForBounds()` (line 58), when `verticalFillEnabled` is false, skip tiers 1 & 2:
  - Use `rowHeight` as the fixed row height (this respects wrapping setting, unlike `compactRowHeight`)
  - Calculate `contentHeight` based on fixed row heights + separator space
  - Preserve wrapping as-is (don't force `useWrapping = false` like tier 3 does)
  - Scrollbar appears naturally when `contentHeight > bounds.height`

### 3. `src/ui/side-panel/MainPanel.swift`
- In `update()` line 52, after creating each `WindowListView`, set `listView.verticalFillEnabled = Preferences.mainPanelVerticalFill`
- This must also apply to existing columns when preferences change (rebuild handles this via `applySeparatorSizes` → `rebuildPanelsForScreenChange` → closes and reopens MainPanel)

### 4. `src/ui/settings-window/tabs/PanelTab.swift`
- Add toggle in Main Panel section (after "Wrap titles" on line 91):
  ```swift
  let verticalFillSwitch = LabelAndControl.makeSwitch("mainPanelVerticalFill", extraAction: mainPanelRebuildAction)
  windowTable.addRow(leftText: "Stretch rows to fill space", rightViews: [verticalFillSwitch])
  ```
- Uses existing `mainPanelRebuildAction` which calls `applySeparatorSizes()` → full rebuild

## Key design decisions

- **`verticalFillEnabled` lives on `WindowListView` instance**, not as a global check — keeps SidePanel unaffected and allows future per-panel control
- **Respects wrapping**: unlike tier 3 which forces `useWrapping = false`, the compact-always path uses `rowHeight` (which factors in wrapping) so the user's wrapping preference still works
- **Default `true`** preserves existing behavior — existing users see no change

## Verification

1. Build with `xcodebuild -workspace ... -scheme Release -configuration Release`
2. Open Main Panel → verify default behavior (rows stretch to fill = current behavior)
3. Toggle off "Stretch rows to fill space" in settings → Main Panel rows should be top-aligned at fixed height
4. Add many windows to a column → scrollbar should appear
5. Toggle "Wrap titles" on/off → row height should adjust appropriately in both fill modes
6. Multiple monitors → each column should respect the setting independently
