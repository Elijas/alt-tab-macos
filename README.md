# AltTab Fork

Personal fork of [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos). For what AltTab itself does, see upstream.

This fork adds persistent window visibility — always-on panels that show what's running across all spaces and screens, without needing to trigger a keyboard shortcut.

## What's different from upstream

### Side Panels

A floating overlay per monitor showing every window grouped by Space. Non-activating (`NSPanel`), always-on-top, vibrancy-backed. Click a row to focus that window; middle-click to close it. Each panel tracks which window was most recently focused on its screen (accent highlight for the globally active window, grey for per-screen most-recent).

Panels reposition with arrow buttons, toggle left/right edge, hide temporarily, or disable per-screen. Opacity and hover-opacity are configurable.

### Main Panel

A regular window showing all screens side-by-side in columns. Each column lists windows grouped by Space for that monitor. Empty monitors auto-collapse to narrow bars. Opens via settings, CLI (`--open-main-panel`), or startup preference.

### Tab Hierarchy

macOS native tabs (Safari, Finder, etc.) appear as indented children under their parent window. Two detection algorithms:

- **AX forward lookup** (UI path): walks each visible window's `AXTabGroup` children and matches tabs by `(pid, title)`. More accurate but requires Accessibility IPC per window.
- **PID-based inference** (CLI path): groups windows by process, assigns invisible (tabbed) windows to the visible window with lowest focus order. Cheaper, no AX overhead.

Tab groups share a `min()` sort key across members so they cluster together in sort order regardless of individual focus timestamps.

### Enhanced CLI

`--detailed-list` returns a full environment snapshot: windows, screens, spaces, visible space indexes, screen-to-space mapping, frontmost app, mouse screen, and blacklist. Tab parent relationships are included. All space/screen data is refreshed before responding (upstream returns stale cached data).

`--debug-tabs` dumps AX element trees for every window — roles, subroles, attribute names, parent chains, linked elements, tab group contents. Useful for understanding why tab detection succeeds or fails for a given app.

### Space Labels

Space headers in side panels are clickable to rename (e.g., "Space 1" → "Code"). Labels persist by `CGSSpaceID` and are pruned on launch when spaces no longer exist.

### Other changes

- **Brute-force AX scan range**: `1000 → 10000` to catch apps with many windows (e.g., Ghostty terminal with dozens of splits)
- **Fullscreen space detection**: spaces with `type == 4` are tracked; their headers are hidden in panels since they contain a single obvious window
- **Configurable separator colors**: hex color pickers for light/dark mode, applied to both panel types
- **Font size and wrapping**: per-panel font size (9–30pt) and title wrapping with a 3-tier layout fallback (proportional → compact → scroll)
- **Group-aware sorting**: tab group members get `min(lastFocusOrder)` as their sort key, so focusing one tab pulls the whole group forward
- **Cross-space tab focus**: focusing an inactive tab switches to the parent's space first, polling CGS until the transition completes, then selects the tab
- **Settings tab**: "Panel" tab in preferences with controls for all of the above

## Build

See `CLAUDE.md` for build commands, worktree layout, and known gotchas (TCC reset after every build, Debug UserDefaults poisoning, CGS timing windows).

The app is renamed to `at004` with bundle ID `com.lwouis.alt-tab-macos.at004`. This isn't for running two instances simultaneously — it's so you can hot-swap between stock AltTab and this fork by quitting one and launching the other, without them fighting over the same bundle ID, preferences domain, or CLI port. The CLI port name derives from the bundle ID at runtime.
