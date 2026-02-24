# Per-Monitor "Selected Window" Highlighting in SidePanel

## Context

The Ctrl+Opt+9/0 cycling scripts focus windows per-screen (based on mouse position), but the side panel only highlights the single globally-focused window — and only subtly (8% alpha). When cycling on Monitor B while Monitor A has OS focus, there's no visual anchor showing which window is "current" on Monitor B.

**Goal**: One highlighted window per monitor. The globally active window gets accent color; other monitors' "current" windows get dark grey. This makes the panel useful as a persistent per-screen window indicator.

## Changes (3 files)

### 1. `src/ui/side-panel/SidePanelRow.swift`

- Add `HighlightState` enum: `.active`, `.selected`, `.none`
- Replace `isFocused: Bool` with `highlightState: HighlightState`
- Change `update(_ window:)` → `update(_ window:, highlightState:)`
- Update `showEmpty()` to set `highlightState = .none`
- Update `updateBackground()`:

| Priority | State | Color |
|----------|-------|-------|
| 1 | Hovered | accent (unchanged) |
| 2 | `.active` | accent color |
| 3 | `.selected` | `NSColor(white: 0.5, alpha: 0.3)` |
| 4 | `.none` | transparent |

### 2. `src/ui/side-panel/SidePanel.swift`

- Change `updateContents(_ groups:)` → `updateContents(_ groups:, selectedWindowId:, isActiveScreen:)`
- In the window layout loop, compute `HighlightState` per row:
  ```
  if window.cgWindowId == selectedWindowId → .active or .selected (based on isActiveScreen)
  else → .none
  ```
- Pass state to `row.update(window, highlightState:)`

### 3. `src/ui/side-panel/SidePanelManager.swift`

- In `refreshPanelsNow()`, after building groups per screen, scan all windows in groups to find the one with the lowest `lastFocusOrder` → that's the per-screen "selected" window
- `isActiveScreen = (lowestFocusOrder == 0)`
- Pass both values to `panel.updateContents()`

## Why this works

`lastFocusOrder` is a global recency counter (0 = most recent). For each screen, the window with the lowest value is the most-recently-focused window on that screen. If that value is 0, it's also the globally active window → accent. Otherwise → dark grey.

## Edge cases

- **Empty screen**: `selectedWindowId` stays nil, all rows are `.none` ✓
- **isOnAllSpaces windows**: Can be selected/active on multiple panels simultaneously ✓
- **Single monitor**: Selected window has `lastFocusOrder == 0` → shows `.active` ✓
- **Focus changes**: `refreshPanels()` fires on AX focus events, updates within 200ms throttle ✓

## KNOWN UNKNOWN

The selected grey (`white: 0.5, alpha: 0.3`) needs visual tuning — the `.sidebar` vibrancy material and the panel's `alphaValue = 0.2` will affect how it renders. May need adjustment after build.

## Verification

1. Build: `xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -configuration Release build CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""`
2. Reset TCC: `tccutil reset Accessibility "com.lwouis.alt-tab-macos.at004" && tccutil reset ScreenCapture "com.lwouis.alt-tab-macos.at004"`
3. Copy to /Applications, launch, grant permissions
4. With 2 monitors: focus a window on Monitor A → its row shows accent. Check Monitor B's panel → the most-recently-used window there shows dark grey. Use Ctrl+Opt+0 on Monitor B → the new target becomes active (accent), Monitor A's previous window becomes selected (dark grey)
