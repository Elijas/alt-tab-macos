# Plan: Separate Font Size Sliders + Title Wrapping Checkbox

## Context

Both the Side Panel (edge-of-screen per-monitor list) and Window Panel (all-screens overview) use `SidePanelRow` with a hardcoded 12pt font. The user wants:
1. **Font size slider for Side Panel** — controls text size in the per-monitor side panels
2. **Font size slider for Window Panel** — controls text size in the all-screen overview panel
3. **Title wrapping checkbox for Window Panel** — allows 2-line titles instead of truncation

All controls go in `PanelTab.swift` under their respective groups.

## New Preferences

| Key | Type | Default | Accessor |
|-----|------|---------|----------|
| `sidePanelFontSize` | Int | `"12"` | `Preferences.sidePanelFontSize` |
| `windowPanelFontSize` | Int | `"12"` | `Preferences.windowPanelFontSize` |
| `windowPanelTitleWrapping` | Bool | `"false"` | `Preferences.windowPanelTitleWrapping` |

## Files to Modify

### 1. `src/logic/Preferences.swift`
- Add 3 entries to `defaultValues` (after line 81)
- Add 3 computed property accessors (after line 144)

### 2. `src/ui/side-panel/SidePanelRow.swift`
- Change `rowHeight` from static `let` to a **static function** `rowHeight(fontSize:wrapping:) -> CGFloat`
- Add `fontSize` and `wrapping` parameters to `init`
- Use `fontSize` for `titleLabel.font` instead of hardcoded `12`
- When `wrapping`, set `maximumNumberOfLines = 2` and `lineBreakMode = .byWordWrapping`
- Row height formula (non-wrapping): `max(28, round(fontSize * 2.2))`
- Row height formula (wrapping): `max(42, round(fontSize * 3.5))`

### 3. `src/ui/side-panel/WindowListView.swift`
- Add stored properties: `rowHeight: CGFloat`, `fontSize: CGFloat`, `wrapping: Bool`
- Accept `fontSize` and `wrapping` in `init` (alongside existing `separatorHeight`)
- Compute `rowHeight` at init from `SidePanelRow.rowHeight(fontSize:wrapping:)`
- Replace all `SidePanelRow.rowHeight` references with stored `rowHeight`
- Pass `fontSize` and `wrapping` when creating new `SidePanelRow` instances

### 4. `src/ui/side-panel/SidePanel.swift`
- Pass `fontSize: CGFloat(Preferences.sidePanelFontSize), wrapping: false` when creating `WindowListView`

### 5. `src/ui/side-panel/WindowPanel.swift`
- Pass `fontSize: CGFloat(Preferences.windowPanelFontSize), wrapping: Preferences.windowPanelTitleWrapping` when creating `WindowListView`
- Use `CGFloat(Preferences.windowPanelFontSize)` for header font size (line 44) instead of hardcoded `12`

### 6. `src/ui/settings-window/tabs/PanelTab.swift`
- Add to "Side Panel" group: font size slider (`sidePanelFontSize`, range 9–20, suffix "pt")
- Add to "Window Panel" group: font size slider (`windowPanelFontSize`, range 9–20, suffix "pt")
- Add to "Window Panel" group: wrapping switch (`windowPanelTitleWrapping`)
- extraAction callbacks: `SidePanelManager.shared.rebuildPanelsForScreenChange()` for side panel changes; rebuild + close/reopen window panel for window panel changes

## Key Design Decisions

- **`SidePanelRow` gets parameterized** — font size and wrapping are passed at construction, not read from Preferences at class level. This lets the same class serve both panels with different settings.
- **Row height is a function, not a constant** — different font sizes and wrapping mode need different row heights. The formula provides proportional scaling.
- **Wrapping uses `maximumNumberOfLines = 2`** — uniform row height for all rows regardless of whether each individual title wraps. Keeps layout simple (no variable-height rows).
- **Rebuild panels on change** — matches the existing pattern used by opacity/separator sliders. Panels are destroyed and recreated with new settings.

## Verification

1. Build: `xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -configuration Release build CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""`
2. Reinstall with TCC reset (per CLAUDE.md)
3. Open Settings → Panel tab → verify sliders and checkbox appear
4. Change side panel font size → side panels should rebuild with new font
5. Change window panel font size → open Window Panel, verify larger/smaller text
6. Toggle wrapping → open Window Panel with long-titled windows, verify 2-line wrapping
7. Test edge cases: minimum font (9pt), maximum font (20pt), wrapping with short titles
