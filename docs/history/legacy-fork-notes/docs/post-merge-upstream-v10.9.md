# Post-Merge Notes: Upstream v10.2.0 → v10.9.0 (2026-04-02)

Merged 47 upstream commits into dev. This doc captures the architectural changes that could cause subtle issues if something breaks after this merge.

## Upstream Architectural Changes

### 1. Singleton migration: `App.app.*` → static `App.*`

**Before:** `App.app.tilesPanel`, `App.app.previewPanel`, `App.app.shortcutIndex`, `App.app.refreshOpenUiAfterExternalEvent()`
**After:** `TilesPanel.shared`, `PreviewPanel.shared`, `App.shortcutIndex`, `App.refreshOpenUiAfterExternalEvent()`

All dev code was updated, but if you see `App.app.` anywhere it's a stale reference that will crash at runtime (the property no longer exists).

**Quick check:** `grep -r "App\.app\." src/`

### 2. "blacklist" → "exceptions" rename

| Old | New |
|-----|-----|
| `Preferences.blacklist` | `Preferences.exceptions` |
| `BlacklistEntry` | `ExceptionEntry` |
| `BlacklistHidePreference` | `ExceptionHidePreference` |
| `BlacklistIgnorePreference` | `ExceptionIgnorePreference` |
| `BlacklistsTab` | `ExceptionsTab` |
| `PoliciesTab` | *(removed entirely)* |

**Exception:** The CLI JSON API still emits `"blacklist"` as a field name in `--detailed-list` output for backward compatibility with jq scripts. The `PreferencesMigrations.swift` also references the old `"blacklist"` key intentionally (migrating old prefs to new key).

**Quick check:** `grep -r "Preferences\.blacklist\|BlacklistEntry\|BlacklistsTab" src/`

### 3. Event throttling

Upstream added throttling to prevent event floods:
- `AccessibilityEvents.throttler` — `ThrottlerWithKey(delayInMs: 200)`, keyed by `type-pid` or `type-wid`
- `SpacesEvents.throttler` — `Throttler(delayInMs: 200)`
- `App.refreshOpenUiThrottler` — `Throttler(delayInMs: 200)`

**If side panels feel laggy or miss updates:** The 200ms throttle could swallow rapid events. Dev's `SidePanelManager.shared.notifySpaceChange()` is called *before* the SpacesEvents throttler (fires immediately), but `SidePanelManager.shared.refreshPanels()` is inside `App.refreshOpenUiAfterExternalEvent()` which is throttled.

### 4. `manuallyUpdateWindows` moved

**Before:** `app.manuallyUpdateWindows()` (instance method on Application)
**After:** `Applications.manuallyUpdateWindows(app)` (static method on Applications)

SidePanelManager's `discoverMissingWindows()` was updated to use the new static call.

### 5. `Application.fetchAppIcon()` is now lazy

Upstream deferred icon fetching to `fetchAppIcon()` which only runs when `icon == nil`. If side panel rows show missing icons, this might be the cause — the icon may not have been fetched yet when the panel renders.

### 6. Shortcuts: String → typed `Shortcut?`

`Preferences.holdShortcut` and `nextWindowShortcut` changed from `String` to `Shortcut?`. The `defaultValues` dict changed from `[String: String]` to `[String: Any]` to accommodate `[String: Any]` shortcut storage dicts. Dev's panel preference keys are all still plain strings, so this shouldn't affect them — but if you add new shortcut-type preferences, use `defaultShortcut()` and `Preferences.setShortcut()`.

### 7. Window destroyed handling restructured

`AccessibilityEvents.handleEventWindow` now returns early for `kAXUIElementDestroyedNotification` before reading AX attributes. Previously it fell through to the same attribute-reading path. The dev's SidePanelManager window filter still runs before this early return (guard at top of method).

## Files Touched During Conflict Resolution

| File | What changed |
|------|-------------|
| `Application.swift:163` | `TilesPanel.shared` + SidePanelManager filter |
| `AccessibilityEvents.swift:91-101` | `TilesPanel.shared` + SidePanelManager filter + early return for windowDestroyed |
| `SpacesEvents.swift:12-13` | `notifySpaceChange()` before throttler |
| `App.swift:44-46` | Static `resetPreferencesDependentComponents` + SidePanelManager rebuild |
| `App.swift:276-278` | Static `refreshOpenUiAfterExternalEvent` + SidePanelManager refresh |
| `App.swift:375` | `SidePanelManager.shared.setup()` in launch sequence |
| `Preferences.swift:6-95` | Upstream's `[String: Any]` format + dev's 17 panel pref keys |
| `Windows.swift:328-338` | Tab hierarchy reordering after sort |
| `Windows.swift:411-416` | `App.shortcutIndex` (static) + `showTabHierarchyInMainPanel` condition |
| `SettingsWindow.swift:719-720` | ExceptionsTab + PanelTab |
| `project.pbxproj:1621-1623` | ExceptionsTab + PanelTab file refs |

## Dev-Only Files Updated (stale pattern fixes)

| File | Fix |
|------|-----|
| `SidePanelManager.swift:484` | `App.app.tilesPanel.windowNumber` → `TilesPanel.shared.windowNumber` |
| `SidePanelManager.swift:434-466` | `blacklist()`/`isBlacklisted()` → `exceptions()`/`isExcluded()`, `BlacklistEntry` → `ExceptionEntry` |
| `SidePanelManager.swift:529` | `app.manuallyUpdateWindows()` → `Applications.manuallyUpdateWindows(app)` |
| `CliEvents.swift:120-121` | `Preferences.blacklist` → `Preferences.exceptions` |
| `CliEvents.swift:236-254` | `blacklistPrefixes` → `exceptionPrefixes` |

## If Something Breaks

1. **Crash on `App.app`** — stale reference missed during merge. Grep and fix.
2. **Side panel not updating** — check if `refreshPanels()` is still called inside `refreshOpenUiAfterExternalEvent()` (throttled at 200ms).
3. **Exceptions not working** — UserDefaults migration from `"blacklist"` → `"exceptions"` key happens in `PreferencesMigrations.swift`. If user had old prefs, they should auto-migrate on launch.
4. **Settings crash** — `PoliciesTab` was removed upstream. If any code references it, it won't compile, but stale nibs or plists could cause runtime issues.
5. **Tab hierarchy not showing** — `showTabHierarchyInMainPanel` condition was preserved in `refreshIfWindowShouldBeShownToTheUser`. If tabs are filtered out, check that `isTabbed` detection still works with upstream's new throttling.
6. **Window order wrong** — upstream changed `updateLastFocusOrder` logic. If cycling feels off, compare the new focus order arithmetic with the old.
