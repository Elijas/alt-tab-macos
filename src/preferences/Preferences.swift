import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class Preferences {
    static var defaultValues: [String: Any] = {
        var values: [String: Any] = [
            "shortcutCount": "2",
            "nextWindowGesture": GesturePreference.disabled.indexAsString,
            "focusWindowShortcut": defaultShortcut(returnKeyEquivalent()),
            "previousWindowShortcut": defaultShortcut("⇧"),
            "cancelShortcut": defaultShortcut("⎋"),
            "lockSearchShortcut": defaultShortcut("Space"),
            "closeWindowShortcut": defaultShortcut("W"),
            "minDeminWindowShortcut": defaultShortcut("M"),
            "toggleFullscreenWindowShortcut": defaultShortcut("F"),
            "quitAppShortcut": defaultShortcut("Q"),
            "hideShowAppShortcut": defaultShortcut("H"),
            "searchShortcut": defaultShortcut("S"),
            "arrowKeysEnabled": "true",
            "vimKeysEnabled": "false",
            "mouseHoverEnabled": "false",
            "cursorFollowFocus": CursorFollowFocus.never.indexAsString,
            "hideColoredCircles": "false",
            "windowDisplayDelay": "100",
            "appearanceStyle": AppearanceStylePreference.thumbnails.indexAsString,
            "appearanceSize": AppearanceSizePreference.auto.indexAsString,
            "appearanceTheme": AppearanceThemePreference.system.indexAsString,
            "theme": ThemePreference.macOs.indexAsString,
            "showOnScreen": ShowOnScreenPreference.active.indexAsString,
            "titleTruncation": TitleTruncationPreference.end.indexAsString,
            "showTitles": ShowTitlesPreference.windowTitle.indexAsString,
            "fadeOutAnimation": "false",
            "previewFadeInAnimation": "true",
            "startAtLogin": "true",
            "menubarIcon": MenubarIconPreference.outlined.indexAsString,
            "menubarIconShown": "true",
            "language": LanguagePreference.systemDefault.indexAsString,
            "exceptions": defaultExceptions(),
            "updatePolicy": UpdatePolicyPreference.autoCheck.indexAsString,
            "crashPolicy": CrashPolicyPreference.ask.indexAsString,
            "hideThumbnails": "false",
            "hideSpaceNumberLabels": "false",
            "hideStatusIcons": "false",
            "previewFocusedWindow": "false",
            "captureWindowsInBackground": "true",
            "screenRecordingPermissionSkipped": "false",
            "trackpadHapticFeedbackEnabled": "true",
            "settingsWindowShownOnFirstLaunch": "false",
            "sidePanelEnabled": "true",
            "sidePanelOpacity": "87",
            "sidePanelHoverOpacity": "100",
            "mainPanelOpenOnStartup": "false",
            "sidePanelSeparatorSize": "3",
            "mainPanelSeparatorSize": "7",
            "sidePanelFontSize": "12",
            "mainPanelFontSize": "12",
            "mainPanelTitleWrapping": "false",
            "mainPanelVerticalFill": "true",
            "mainPanelCollapseEmptyScreens": "true",
            "showTabHierarchyInMainPanel": "false",
            "showTabHierarchyInSidePanel": "false",
            "groupTabsInSortOrder": "true",
            "sidePanelHoverJump": "false",
            "sidePanelReturnDelay": "60",
            "separatorColorLight": "999999",
            "separatorColorDark": "666666",
            "activeColorLight": "007AFF",
            "activeColorDark": "0A84FF",
            "selectedColorLight": "808080",
            "selectedColorDark": "A0A0A0",
            "hoverColorLight": "007AFF",
            "hoverColorDark": "0A84FF",
            "minimizedColorLight": "CC8A33",
            "minimizedColorDark": "B3792B",
            "hiddenColorLight": "663399",
            "hiddenColorDark": "8A5CD0",
            "sidePanelCompactWidth": "90",
            "sidePanelCompactLetters": "5",
            "sidePanelCompactLettersIndented": "0",
            "sidePanelDisabledScreens": "[]",
            "spaceLabels": "{}",
        ]
        (0..<maxShortcutCount).forEach { index in
            values[indexToName("holdShortcut", index)] = defaultShortcut("⌥")
            values[indexToName("nextWindowShortcut", index)] = defaultShortcut(index == 0 ? "⇥" : (index == 1 ? keyAboveTabDependingOnInputSource() : ""))
        }
        (0...maxShortcutCount).forEach { index in
            values[indexToName("appsToShow", index)] = index == 1 ? AppsToShowPreference.active.indexAsString : (index == 2 ? AppsToShowPreference.nonActive.indexAsString : AppsToShowPreference.all.indexAsString)
            values[indexToName("spacesToShow", index)] = SpacesToShowPreference.all.indexAsString
            values[indexToName("screensToShow", index)] = ScreensToShowPreference.all.indexAsString
            values[indexToName("showMinimizedWindows", index)] = ShowHowPreference.show.indexAsString
            values[indexToName("showHiddenWindows", index)] = ShowHowPreference.show.indexAsString
            values[indexToName("showFullscreenWindows", index)] = ShowHowPreference.show.indexAsString
            values[indexToName("showWindowlessApps", index)] = ShowHowPreference.showAtTheEnd.indexAsString
            values[indexToName("windowOrder", index)] = WindowOrderPreference.recentlyFocused.indexAsString
            values[indexToName("shortcutStyle", index)] = ShortcutStylePreference.focusOnRelease.indexAsString
            values[indexToName("showAppsOrWindows", index)] = GroupAppsPreference.allWindows.indexAsString
            values[indexToName("showTabsAsWindows", index)] = GroupTabsPreference.singleWindow.indexAsString
            // Override defaults are the FREE-tier value for Pro-gated prefs (so `snapshotAndDowngrade`
            // is a no-op for unset overrides), and the global default for non-gated prefs.
            // `hasOverride(_:_:)` consults `persistentDomain` so registered defaults don't make
            // an unset override look set.
            values[indexToName("appearanceStyleOverride", index)] = AppearanceStylePreference.thumbnails.indexAsString
            values[indexToName("appearanceSizeOverride", index)] = AppearanceSizePreference.medium.indexAsString
            values[indexToName("appearanceThemeOverride", index)] = AppearanceThemePreference.system.indexAsString
            values[indexToName("shortcutStyleOverride", index)] = ShortcutStylePreference.doNothingOnRelease.indexAsString
            values[indexToName("previewFocusedWindowOverride", index)] = "false"
        }
        return values
    }()

    // system preferences
    static var finderShowsQuitMenuItem: Bool { UserDefaults(suiteName: "com.apple.Finder")?.bool(forKey: "QuitMenuItem") ?? false }
    static let staticShortcutKeys = [
        "focusWindowShortcut", "previousWindowShortcut", "cancelShortcut", "lockSearchShortcut", "closeWindowShortcut",
        "minDeminWindowShortcut", "toggleFullscreenWindowShortcut", "quitAppShortcut", "hideShowAppShortcut", "searchShortcut",
    ]
    static var allShortcutPreferenceKeys: [String] {
        staticShortcutKeys + (0..<maxShortcutCount).flatMap { [indexToName("holdShortcut", $0), indexToName("nextWindowShortcut", $0)] }
    }
    static let emptyShortcut = Shortcut(code: .none, modifierFlags: [], characters: nil, charactersIgnoringModifiers: nil)
    private static let shortcutStorageStringField = "string"
    private static let shortcutStorageDataField = "secureData"

    // persisted values
    static var holdShortcut: [Shortcut?] { (0..<shortcutCount).map { CachedUserDefaults.shortcut(indexToName("holdShortcut", $0)) } }
    static var nextWindowShortcut: [Shortcut?] { (0..<shortcutCount).map { CachedUserDefaults.shortcut(indexToName("nextWindowShortcut", $0)) } }
    static var nextWindowGesture: GesturePreference { CachedUserDefaults.macroPref("nextWindowGesture", GesturePreference.allCases) }
    static var focusWindowShortcut: Shortcut? { CachedUserDefaults.shortcut("focusWindowShortcut") }
    static var previousWindowShortcut: Shortcut? { CachedUserDefaults.shortcut("previousWindowShortcut") }
    static var cancelShortcut: Shortcut? { CachedUserDefaults.shortcut("cancelShortcut") }
    static var lockSearchShortcut: Shortcut? { CachedUserDefaults.shortcut("lockSearchShortcut") }
    static var closeWindowShortcut: Shortcut? { CachedUserDefaults.shortcut("closeWindowShortcut") }
    static var minDeminWindowShortcut: Shortcut? { CachedUserDefaults.shortcut("minDeminWindowShortcut") }
    static var toggleFullscreenWindowShortcut: Shortcut? { CachedUserDefaults.shortcut("toggleFullscreenWindowShortcut") }
    static var quitAppShortcut: Shortcut? { CachedUserDefaults.shortcut("quitAppShortcut") }
    static var hideShowAppShortcut: Shortcut? { CachedUserDefaults.shortcut("hideShowAppShortcut") }
    static var searchShortcut: Shortcut? { CachedUserDefaults.shortcut("searchShortcut") }
    // periphery:ignore
    static var arrowKeysEnabled: Bool { CachedUserDefaults.bool("arrowKeysEnabled") }
    // periphery:ignore
    static var vimKeysEnabled: Bool { CachedUserDefaults.bool("vimKeysEnabled") }
    static var mouseHoverEnabled: Bool { CachedUserDefaults.bool("mouseHoverEnabled") }
    static var cursorFollowFocus: CursorFollowFocus { CachedUserDefaults.macroPref("cursorFollowFocus", CursorFollowFocus.allCases) }
    static var trackpadHapticFeedbackEnabled: Bool { CachedUserDefaults.bool("trackpadHapticFeedbackEnabled") }
    static var hideColoredCircles: Bool { CachedUserDefaults.bool("hideColoredCircles") }
    static var windowDisplayDelay: DispatchTimeInterval { DispatchTimeInterval.milliseconds(CachedUserDefaults.int("windowDisplayDelay")) }
    static var fadeOutAnimation: Bool { CachedUserDefaults.bool("fadeOutAnimation") }
    static var previewFadeInAnimation: Bool { CachedUserDefaults.bool("previewFadeInAnimation") }
    static var hideSpaceNumberLabels: Bool { CachedUserDefaults.bool("hideSpaceNumberLabels") }
    static var hideStatusIcons: Bool { CachedUserDefaults.bool("hideStatusIcons") }
    // periphery:ignore
    static var startAtLogin: Bool { CachedUserDefaults.bool("startAtLogin") }
    static var exceptions: [ExceptionEntry] { CachedUserDefaults.json("exceptions", [ExceptionEntry].self) }
    static var previewSelectedWindow: Bool { CachedUserDefaults.bool("previewFocusedWindow") }
    static var captureWindowsInBackground: Bool { CachedUserDefaults.bool("captureWindowsInBackground") }
    static var screenRecordingPermissionSkipped: Bool { CachedUserDefaults.bool("screenRecordingPermissionSkipped") }
    static var settingsWindowShownOnFirstLaunch: Bool { CachedUserDefaults.bool("settingsWindowShownOnFirstLaunch") }
    static var sidePanelEnabled: Bool { CachedUserDefaults.bool("sidePanelEnabled") }
    static var sidePanelOpacity: Int { CachedUserDefaults.int("sidePanelOpacity") }
    static var sidePanelHoverOpacity: Int { CachedUserDefaults.int("sidePanelHoverOpacity") }
    static var mainPanelOpenOnStartup: Bool { CachedUserDefaults.bool("mainPanelOpenOnStartup") }
    static var sidePanelSeparatorSize: Int { CachedUserDefaults.int("sidePanelSeparatorSize") }
    static var mainPanelSeparatorSize: Int { CachedUserDefaults.int("mainPanelSeparatorSize") }
    static var sidePanelFontSize: Int { CachedUserDefaults.int("sidePanelFontSize") }
    static var mainPanelFontSize: Int { CachedUserDefaults.int("mainPanelFontSize") }
    static var mainPanelTitleWrapping: Bool { CachedUserDefaults.bool("mainPanelTitleWrapping") }
    static var mainPanelVerticalFill: Bool { CachedUserDefaults.bool("mainPanelVerticalFill") }
    static var mainPanelCollapseEmptyScreens: Bool { CachedUserDefaults.bool("mainPanelCollapseEmptyScreens") }
    static var showTabHierarchyInMainPanel: Bool { CachedUserDefaults.bool("showTabHierarchyInMainPanel") }
    static var showTabHierarchyInSidePanel: Bool { CachedUserDefaults.bool("showTabHierarchyInSidePanel") }
    static var groupTabsInSortOrder: Bool { CachedUserDefaults.bool("groupTabsInSortOrder") }
    static var sidePanelHoverJump: Bool { CachedUserDefaults.bool("sidePanelHoverJump") }
    static var sidePanelReturnDelay: Int { CachedUserDefaults.int("sidePanelReturnDelay") }
    static var separatorColorLight: String { CachedUserDefaults.string("separatorColorLight") }
    static var separatorColorDark: String { CachedUserDefaults.string("separatorColorDark") }
    static var activeColorLight: String { CachedUserDefaults.string("activeColorLight") }
    static var activeColorDark: String { CachedUserDefaults.string("activeColorDark") }
    static var selectedColorLight: String { CachedUserDefaults.string("selectedColorLight") }
    static var selectedColorDark: String { CachedUserDefaults.string("selectedColorDark") }
    static var hoverColorLight: String { CachedUserDefaults.string("hoverColorLight") }
    static var hoverColorDark: String { CachedUserDefaults.string("hoverColorDark") }
    static var minimizedColorLight: String { CachedUserDefaults.string("minimizedColorLight") }
    static var minimizedColorDark: String { CachedUserDefaults.string("minimizedColorDark") }
    static var hiddenColorLight: String { CachedUserDefaults.string("hiddenColorLight") }
    static var hiddenColorDark: String { CachedUserDefaults.string("hiddenColorDark") }
    static var sidePanelCompactWidth: Int { CachedUserDefaults.int("sidePanelCompactWidth") }
    static var sidePanelCompactLetters: Int { CachedUserDefaults.int("sidePanelCompactLetters") }
    static var sidePanelCompactLettersIndented: Int { CachedUserDefaults.int("sidePanelCompactLettersIndented") }
    static var sidePanelDisabledScreens: [String] { CachedUserDefaults.json("sidePanelDisabledScreens", [String].self) }
    static var spaceLabels: [String: String] { CachedUserDefaults.json("spaceLabels", [String: String].self) }

    static func setSpaceLabel(_ spaceId: CGSSpaceID, _ label: String?) {
        var labels = spaceLabels
        if let label, !label.isEmpty {
            labels[String(spaceId)] = label
        } else {
            labels.removeValue(forKey: String(spaceId))
        }
        set("spaceLabels", jsonEncode(labels))
    }

    static func spaceLabel(for spaceId: CGSSpaceID, displayIndex: SpaceIndex) -> String {
        spaceLabels[String(spaceId)] ?? "Space \(displayIndex)"
    }

    static func pruneSpaceLabels(currentSpaceIds: Set<CGSSpaceID>) {
        let labels = spaceLabels
        let pruned = labels.filter { currentSpaceIds.contains(CGSSpaceID($0.key) ?? 0) }
        if pruned.count != labels.count {
            set("spaceLabels", jsonEncode(pruned))
        }
    }

    // macro values
    static var appearanceStyle: AppearanceStylePreference { ProGatedPreferences.appearanceStyle.read() }
    static var appearanceSize: AppearanceSizePreference { ProGatedPreferences.appearanceSize.read() }
    static var appearanceTheme: AppearanceThemePreference { CachedUserDefaults.macroPref("appearanceTheme", AppearanceThemePreference.allCases) }
    // periphery:ignore
    static var theme: ThemePreference { ThemePreference.macOs/*CachedUserDefaults.macroPref("theme", ThemePreference.allCases)*/ }
    static var showOnScreen: ShowOnScreenPreference { CachedUserDefaults.macroPref("showOnScreen", ShowOnScreenPreference.allCases) }
    static var titleTruncation: TitleTruncationPreference { CachedUserDefaults.macroPref("titleTruncation", TitleTruncationPreference.allCases) }
    static var showTitles: ShowTitlesPreference { CachedUserDefaults.macroPref("showTitles", ShowTitlesPreference.allCases) }
    static var updatePolicy: UpdatePolicyPreference { CachedUserDefaults.macroPref("updatePolicy", UpdatePolicyPreference.allCases) }
    static var crashPolicy: CrashPolicyPreference { CachedUserDefaults.macroPref("crashPolicy", CrashPolicyPreference.allCases) }
    static var appsToShow: [AppsToShowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("appsToShow", $0), AppsToShowPreference.allCases) } }
    static var spacesToShow: [SpacesToShowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("spacesToShow", $0), SpacesToShowPreference.allCases) } }
    static var screensToShow: [ScreensToShowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("screensToShow", $0), ScreensToShowPreference.allCases) } }
    static var showMinimizedWindows: [ShowHowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("showMinimizedWindows", $0), ShowHowPreference.allCases) } }
    static var showHiddenWindows: [ShowHowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("showHiddenWindows", $0), ShowHowPreference.allCases) } }
    static var showFullscreenWindows: [ShowHowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("showFullscreenWindows", $0), ShowHowPreference.allCases) } }
    static var showWindowlessApps: [ShowHowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("showWindowlessApps", $0), ShowHowPreference.allCases) } }
    static var windowOrder: [WindowOrderPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("windowOrder", $0), WindowOrderPreference.allCases) } }

    static func showMinimizedWindows(_ i: Int) -> ShowHowPreference { CachedUserDefaults.macroPref(indexToName("showMinimizedWindows", i), ShowHowPreference.allCases) }
    static func showHiddenWindows(_ i: Int) -> ShowHowPreference { CachedUserDefaults.macroPref(indexToName("showHiddenWindows", i), ShowHowPreference.allCases) }
    static func showFullscreenWindows(_ i: Int) -> ShowHowPreference { CachedUserDefaults.macroPref(indexToName("showFullscreenWindows", i), ShowHowPreference.allCases) }
    static func showWindowlessApps(_ i: Int) -> ShowHowPreference { CachedUserDefaults.macroPref(indexToName("showWindowlessApps", i), ShowHowPreference.allCases) }
    static func windowOrder(_ i: Int) -> WindowOrderPreference { CachedUserDefaults.macroPref(indexToName("windowOrder", i), WindowOrderPreference.allCases) }
    static func groupApps(_ i: Int) -> GroupAppsPreference { CachedUserDefaults.macroPref(indexToName("showAppsOrWindows", i), GroupAppsPreference.allCases) }
    static func groupTabs(_ i: Int) -> GroupTabsPreference { CachedUserDefaults.macroPref(indexToName("showTabsAsWindows", i), GroupTabsPreference.allCases) }
    static var shortcutStyle: ShortcutStylePreference { ProGatedPreferences.shortcutStyle.read() }
    static var menubarIcon: MenubarIconPreference { CachedUserDefaults.macroPref("menubarIcon", MenubarIconPreference.allCases) }
    static var menubarIconShown: Bool { CachedUserDefaults.bool("menubarIconShown") }
    static var language: LanguagePreference { CachedUserDefaults.macroPref("language", LanguagePreference.allCases) }

    static let minShortcutCount = 1
    static let maxShortcutCount = 9
    static var shortcutCount: Int {
        max(minShortcutCount, min(maxShortcutCount, CachedUserDefaults.int("shortcutCount")))
    }

    static let gestureIndex = maxShortcutCount

    static func initialize() {
        PreferencesMigrations.removeCorruptedPreferences()
        PreferencesMigrations.migratePreferences()
        registerDefaults()
    }

    static func resetAll() {
        UserDefaults.standard.removePersistentDomain(forName: App.bundleIdentifier)
        invalidateAllCache()
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaultValues)
    }

    static func markSettingsWindowShownOnFirstLaunch() {
        set("settingsWindowShownOnFirstLaunch", "true", false)
    }

    static func defaultShortcut(_ keyEquivalent: String) -> [String: Any] {
        shortcutStorage(shortcutFromKeyEquivalent(keyEquivalent), keyEquivalent)
    }

    static func setShortcut(_ key: String, _ shortcut: Shortcut?, _ notify: Bool = true) {
        setShortcut(key, shortcut, stringRepresentation: nil, notify)
    }

    static func setShortcut(_ key: String, _ shortcut: Shortcut?, stringRepresentation: String?, _ notify: Bool = true) {
        UserDefaults.standard.set(shortcutStorage(shortcut, stringRepresentation), forKey: key)
        CachedUserDefaults.removeFromCache(key)
        invalidateAllCache()
        if notify {
            PreferencesEvents.preferenceChanged(key)
        }
    }

    static func setShortcut(_ key: String, keyEquivalent: String, _ notify: Bool = true) {
        setShortcut(key, shortcutFromKeyEquivalent(keyEquivalent), stringRepresentation: keyEquivalent, notify)
    }

    static func shortcut(_ key: String) -> Shortcut? {
        CachedUserDefaults.shortcut(key)
    }

    static func set<T>(_ key: String, _ value: T, _ notify: Bool = true) where T: Encodable {
        UserDefaults.standard.set(key == "exceptions" ? jsonEncode(value) : value, forKey: key)
        CachedUserDefaults.removeFromCache(key)
        invalidateAllCache()
        if notify {
            PreferencesEvents.preferenceChanged(key)
        }
    }

    static func remove(_ key: String, _ notify: Bool = true) {
        UserDefaults.standard.removeObject(forKey: key)
        CachedUserDefaults.removeFromCache(key)
        invalidateAllCache()
        if notify {
            PreferencesEvents.preferenceChanged(key)
        }
    }

    static let ownedKeys: Set<String> = Set(defaultValues.keys)

    /// `persistentDomain(forName:)` rebuilds a full snapshot dictionary on every call, which adds
    /// up: every `hasOverride` / `effectiveAppearanceStyle` consults `all`, and the switcher show
    /// path triggers a cascade of these per show. Cache the filtered snapshot; the only paths that
    /// mutate the domain (`set`, `setShortcut`, `remove`, `resetAll`) clear `cachedAll` below.
    private static var cachedAll: [String: Any]?

    static var all: [String: Any] {
        if let cachedAll { return cachedAll }
        let domain = UserDefaults.standard.persistentDomain(forName: App.bundleIdentifier) ?? [:]
        let filtered = domain.filter { ownedKeys.contains($0.key) }
        cachedAll = filtered
        return filtered
    }

    static func invalidateAllCache() {
        cachedAll = nil
    }

    static func onlyShowMainWindows(_ index: Int = SwitcherSession.activeShortcutIndex) -> Bool {
        return groupApps(index) == .mainWindow
    }

    // MARK: - Per-shortcut appearance overrides

    /// The 5 override base names. Their indexed forms (e.g. `appearanceStyleOverride2`) live in
    /// `Preferences.all` only when the user has explicitly set an override on that shortcut.
    static let appearanceOverrideBaseNames = [
        "appearanceStyleOverride", "appearanceSizeOverride", "appearanceThemeOverride",
        "shortcutStyleOverride", "previewFocusedWindowOverride",
    ]

    /// Reverse lookup from an override base name to the global key it overrides.
    static let overrideToGlobalKey: [String: String] = [
        "appearanceStyleOverride": "appearanceStyle",
        "appearanceSizeOverride": "appearanceSize",
        "appearanceThemeOverride": "appearanceTheme",
        "shortcutStyleOverride": "shortcutStyle",
        "previewFocusedWindowOverride": "previewFocusedWindow",
    ]

    /// True when the user has explicitly set an override for `baseName` on shortcut `index`.
    /// Reads from `persistentDomain` (`Preferences.all`) which excludes registered defaults, so
    /// an untouched override correctly reports `false` even though its key has a registered default.
    static func hasOverride(_ baseName: String, _ index: Int) -> Bool {
        all[indexToName(baseName, index)] != nil
    }

    /// Remove an override (the user "unlinks" it from the global). For the 3 Pro-gated overrides on
    /// shortcut 0, also clear the remembered Pro index in `ProTransitionState` — otherwise an
    /// unrelated unlock pass would re-create the override from that snapshot.
    static func removeOverride(_ baseName: String, _ index: Int) {
        remove(indexToName(baseName, index))
        if index == 0, let rememberedKey = overrideRememberedKey(baseName) {
            ProTransitionState.setInt(rememberedKey, nil)
        }
    }

    /// Maps the 3 Pro-gated index-0 override base names to their remembered-key in `ProTransitionState`.
    /// Returns nil for the 2 non-gated overrides and for index >= 1.
    private static func overrideRememberedKey(_ baseName: String) -> String? {
        switch baseName {
        case "appearanceStyleOverride": return ProGatedPreferences.appearanceStyleOverride0.gate?.rememberedKey
        case "appearanceSizeOverride": return ProGatedPreferences.appearanceSizeOverride0.gate?.rememberedKey
        case "shortcutStyleOverride": return ProGatedPreferences.shortcutStyleOverride0.gate?.rememberedKey
        default: return nil
        }
    }

    /// Indices (0..shortcutCount) whose stored override value differs from the current global.
    /// Used to render "Overridden in Shortcut: 1, 3" labels in AppearanceTab.
    static func shortcutIndicesWithDifferentValue(_ baseName: String, globalKey: String) -> [Int] {
        let globalValue = UserDefaults.standard.string(forKey: globalKey)
        return (0..<shortcutCount).filter { index in
            let key = indexToName(baseName, index)
            guard let overrideValue = all[key] as? String else { return false }
            return overrideValue != globalValue
        }
    }

    static func effectiveAppearanceStyle(_ index: Int) -> AppearanceStylePreference {
        guard hasOverride("appearanceStyleOverride", index) else { return appearanceStyle }
        if index == 0 { return ProGatedPreferences.appearanceStyleOverride0.read() }
        return CachedUserDefaults.macroPref(indexToName("appearanceStyleOverride", index), AppearanceStylePreference.allCases)
    }

    static func effectiveAppearanceSize(_ index: Int) -> AppearanceSizePreference {
        guard hasOverride("appearanceSizeOverride", index) else { return appearanceSize }
        if index == 0 { return ProGatedPreferences.appearanceSizeOverride0.read() }
        return CachedUserDefaults.macroPref(indexToName("appearanceSizeOverride", index), AppearanceSizePreference.allCases)
    }

    static func effectiveAppearanceTheme(_ index: Int) -> AppearanceThemePreference {
        guard hasOverride("appearanceThemeOverride", index) else { return appearanceTheme }
        return CachedUserDefaults.macroPref(indexToName("appearanceThemeOverride", index), AppearanceThemePreference.allCases)
    }

    static func effectiveShortcutStyle(_ index: Int) -> ShortcutStylePreference {
        guard hasOverride("shortcutStyleOverride", index) else { return shortcutStyle }
        if index == 0 { return ProGatedPreferences.shortcutStyleOverride0.read() }
        return CachedUserDefaults.macroPref(indexToName("shortcutStyleOverride", index), ShortcutStylePreference.allCases)
    }

    static func effectivePreviewSelectedWindow(_ index: Int) -> Bool {
        guard hasOverride("previewFocusedWindowOverride", index) else { return previewSelectedWindow }
        return CachedUserDefaults.bool(indexToName("previewFocusedWindowOverride", index))
    }

    /// Which Screen-Recording-dependent features any shortcut's effective settings rely on: the
    /// Thumbnails appearance style (window screenshots) and/or the "preview selected window" overlay.
    /// These are the only features needing the permission, so when none are configured the menubar
    /// callout that nags about the missing permission is pointless and is suppressed (see #5623). The
    /// result also drives which feature(s) the callout names. We OR each flag across every shortcut
    /// slot, so a per-shortcut override that enables Thumbnails/Preview on any one slot flips it on.
    /// The pure classification lives in `PermissionCalloutResolver` (unit-tested).
    static var screenRecordingDependentFeatures: PermissionCalloutResolver.DependentFeatures {
        var usesThumbnails = false
        var usesPreviews = false
        for index in 0...maxShortcutCount {
            usesThumbnails = usesThumbnails || effectiveAppearanceStyle(index) == .thumbnails
            usesPreviews = usesPreviews || effectivePreviewSelectedWindow(index)
            if usesThumbnails && usesPreviews { break }
        }
        return PermissionCalloutResolver.dependentFeatures(usesThumbnails: usesThumbnails, usesPreviews: usesPreviews)
    }

    /// key-above-tab is ` on US keyboard, but can be different on other keyboards
    static func keyAboveTabDependingOnInputSource() -> String {
        return LiteralKeyCodeTransformer.shared.transformedValue(NSNumber(value: kVK_ANSI_Grave)) ?? "`"
    }

    static func returnKeyEquivalent() -> String {
        return LiteralKeyCodeTransformer.shared.transformedValue(NSNumber(value: kVK_Return)) ?? "↩"
    }

    static func defaultExceptions() -> String {
        return jsonEncode([
            ExceptionEntry(bundleIdentifier: "com.apple.finder", hide: .whenNoOpenWindow, ignore: .none),
            ExceptionEntry(bundleIdentifier: "com.apple.ScreenSharing", hide: .none, ignore: .whenFullscreen),
            ExceptionEntry(bundleIdentifier: "com.microsoft.rdc.macos", hide: .none, ignore: .whenFullscreen),
            ExceptionEntry(bundleIdentifier: "com.teamviewer.TeamViewer", hide: .none, ignore: .whenFullscreen),
            ExceptionEntry(bundleIdentifier: "org.virtualbox.app.VirtualBoxVM", hide: .none, ignore: .whenFullscreen),
            ExceptionEntry(bundleIdentifier: "com.parallels.", hide: .none, ignore: .whenFullscreen),
            ExceptionEntry(bundleIdentifier: "com.citrix.XenAppViewer", hide: .none, ignore: .whenFullscreen),
            ExceptionEntry(bundleIdentifier: "com.citrix.receiver.icaviewer.mac", hide: .none, ignore: .whenFullscreen),
            ExceptionEntry(bundleIdentifier: "com.nicesoftware.dcvviewer", hide: .none, ignore: .whenFullscreen),
            ExceptionEntry(bundleIdentifier: "com.vmware.fusion", hide: .none, ignore: .whenFullscreen),
            ExceptionEntry(bundleIdentifier: "com.utmapp.UTM", hide: .none, ignore: .whenFullscreen),
            ExceptionEntry(bundleIdentifier: "com.McAfee.McAfeeSafariHost", hide: .always, ignore: .none),
        ])
    }

    static func jsonEncode<T>(_ value: T) -> String where T: Encodable {
        return String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }

    static func archiveShortcut(_ shortcut: Shortcut?) -> Data {
        if #available(macOS 10.13, *) {
            return try! NSKeyedArchiver.archivedData(withRootObject: shortcut ?? emptyShortcut, requiringSecureCoding: true)
        }
        return NSKeyedArchiver.archivedData(withRootObject: shortcut ?? emptyShortcut)
    }

    static func shortcutStorage(_ shortcut: Shortcut?, _ stringRepresentation: String?) -> [String: Any] {
        [
            shortcutStorageStringField: stringRepresentation ?? shortcut?.readableStringRepresentation(isASCII: true) ?? "",
            shortcutStorageDataField: archiveShortcut(shortcut),
        ]
    }

    static func decodeShortcutStorage(_ value: Any) -> (Bool, Shortcut?) {
        guard let storage = value as? [String: Any], let data = storage[shortcutStorageDataField] as? Data else { return (false, nil) }
        return unarchiveShortcut(data)
    }

    static func unarchiveShortcut(_ data: Data) -> (Bool, Shortcut?) {
        let shortcut: Shortcut?
        if #available(macOS 10.13, *) {
            shortcut = try? NSKeyedUnarchiver.unarchivedObject(ofClass: Shortcut.self, from: data)
        } else {
            shortcut = NSKeyedUnarchiver.unarchiveObject(with: data) as? Shortcut
        }
        guard let shortcut else { return (false, nil) }
        return (true, shortcut.keyCode == .none && shortcut.modifierFlags == [] ? nil : shortcut)
    }

    static func shortcutFromKeyEquivalent(_ keyEquivalent: String) -> Shortcut? {
        keyEquivalent.isEmpty ? nil : Shortcut(keyEquivalent: keyEquivalent)
    }

    static func indexToName(_ baseName: String, _ index: Int) -> String {
        return baseName + (index == 0 ? "" : String(index + 1))
    }

    static func nameToIndex(_ name: String) -> Int {
        let digits = String(name.reversed().prefix { $0.isNumber }.reversed())
        guard !digits.isEmpty, let number = Int(digits) else { return 0 }
        return number - 1
    }
}

class CachedUserDefaults {
    static var cache = ConcurrentMap<String, Any>()

    static func removeFromCache(_ key: String) {
        cache.withLock { $0.removeValue(forKey: key) }
    }

    /// retrieve strings in the globalDomain (e.g. defaults read -g KeyRepeat)
    /// these may be nil since we they don't have default values from AltTab
    static func globalString(_ key: String) -> String? {
        if let cached = cache.withLock({ $0[key] }) {
            return cached as? String
        }
        if let string = UserDefaults.standard.string(forKey: key) {
            cache.withLock { $0[key] = string }
        }
        return nil
    }

    static func string(_ key: String) -> String {
        if let cachedFinalValue = cache.withLock({ $0[key] }) {
            return cachedFinalValue as! String
        }
        let finalValue = UserDefaults.standard.string(forKey: key)!
        cache.withLock { $0[key] = finalValue }
        return finalValue
    }

    static func shortcut(_ key: String) -> Shortcut? {
        if let cachedFinalValue = cache.withLock({ $0[key] }) {
            return cachedFinalValue as? Shortcut
        }
        guard let objectValue = UserDefaults.standard.object(forKey: key) else {
            cache.withLock { $0[key] = NSNull() }
            return nil
        }
        let (isValid, finalValue) = Preferences.decodeShortcutStorage(objectValue)
        if isValid {
            cache.withLock { $0[key] = finalValue ?? NSNull() }
            return finalValue
        }
        UserDefaults.standard.removeObject(forKey: key)
        return shortcut(key)
    }

    static func int(_ key: String) -> Int {
        return getThenConvertOrReset(key, { s in Int(s) })
    }

    static func bool(_ key: String) -> Bool {
        return getThenConvertOrReset(key, { s in Bool(s) })
    }

    static func double(_ key: String) -> Double {
        return getThenConvertOrReset(key, { s in Double(s) })
    }

    static func macroPref<A>(_ key: String, _ macroPreferences: [A]) -> A {
        return getThenConvertOrReset(key, { s in Int(s).flatMap { macroPreferences[safe: $0] } })
    }

    /// some UI elements (e.g. dropdown, radios) need an int. We find the right int from the MacroPreference index
    static func intFromMacroPref(_ key: String, _ macroPreferences: [MacroPreference]) -> Int {
        let macroPref = macroPref(key, macroPreferences)
        return macroPreferences.firstIndex { $0.localizedString == macroPref.localizedString }!
    }

    static func json<T>(_ key: String, _ type: T.Type) -> T where T: Decodable {
        return getThenConvertOrReset(key, { s in jsonDecode(s, type) })
    }

    private static func getThenConvertOrReset<T>(_ key: String, _ getterFn: (String) -> T?) -> T {
        if let cachedFinalValue = cache.withLock({ $0[key] }) {
            return cachedFinalValue as! T
        }
        let stringValue = UserDefaults.standard.string(forKey: key)!
        if let finalValue = getterFn(stringValue) {
            cache.withLock { $0[key] = finalValue }
            return finalValue
        }
        // value couldn't be read properly; we remove it and work with the default
        UserDefaults.standard.removeObject(forKey: key)
        let defaultStringValue = UserDefaults.standard.string(forKey: key)!
        let defaultFinalValue = getterFn(defaultStringValue)!
        cache.withLock { $0[key] = defaultFinalValue }
        return defaultFinalValue
    }

    private static func jsonDecode<T>(_ value: String, _ type: T.Type) -> T? where T: Decodable {
        return value.data(using: .utf8).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

struct ExceptionEntry: Codable {
    var bundleIdentifier: String
    var hide: ExceptionHidePreference
    var ignore: ExceptionIgnorePreference
    var windowTitleContains: [String]?

    init(bundleIdentifier: String, hide: ExceptionHidePreference, ignore: ExceptionIgnorePreference, windowTitleContains: [String]? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.hide = hide
        self.ignore = ignore
        self.windowTitleContains = windowTitleContains
    }

    // Permissive decoder so we can read both the legacy single-string shape
    // (windowTitleContains: String?) and the current array shape ([String]?). Without this,
    // a decode failure on legacy data would cause `getThenConvertOrReset` in Preferences to
    // wipe the entry back to defaultExceptions(), losing the user's patterns.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        self.hide = try c.decode(ExceptionHidePreference.self, forKey: .hide)
        self.ignore = try c.decode(ExceptionIgnorePreference.self, forKey: .ignore)
        if let array = try? c.decode([String].self, forKey: .windowTitleContains) {
            self.windowTitleContains = array.isEmpty ? nil : array
        } else if let string = try? c.decode(String.self, forKey: .windowTitleContains), !string.isEmpty {
            self.windowTitleContains = [string]
        } else {
            self.windowTitleContains = nil
        }
    }
}

enum ExceptionFilter {
    private static let mainAltTabBundleId = "com.lwouis.alt-tab-macos"
    private static let altTabBuildBundlePrefix = "com.lwouis.alt-tab-macos.at"

    static func resolvedEntries(includeAltTabBuilds: Bool = false) -> [ExceptionEntry] {
        var entries = Preferences.exceptions
        addMainAltTabEntries(&entries)
        if includeAltTabBuilds { entries.append(altTabBuildEntry()) }
        return entries
    }

    static func isExcluded(_ window: Window, from entries: [ExceptionEntry]) -> Bool {
        guard let bundleId = window.application.bundleIdentifier else { return false }
        return entries.contains { isExcluded(window, bundleId, $0) }
    }

    private static func addMainAltTabEntries(_ entries: inout [ExceptionEntry]) {
        guard let mainDefaults = UserDefaults(suiteName: mainAltTabBundleId),
              let json = mainDefaults.string(forKey: "exceptions"),
              let data = json.data(using: .utf8),
              let mainEntries = try? JSONDecoder().decode([ExceptionEntry].self, from: data) else { return }
        let existingIds = Set(entries.map { $0.bundleIdentifier })
        for entry in mainEntries where !existingIds.contains(entry.bundleIdentifier) {
            entries.append(entry)
        }
    }

    private static func altTabBuildEntry() -> ExceptionEntry {
        return ExceptionEntry(bundleIdentifier: altTabBuildBundlePrefix, hide: .always, ignore: .none, windowTitleContains: nil)
    }

    private static func isExcluded(_ window: Window, _ bundleId: String, _ entry: ExceptionEntry) -> Bool {
        guard entry.hide != .none else { return false }
        guard bundleId.hasPrefix(entry.bundleIdentifier) else { return false }
        switch entry.hide {
        case .none: return false
        case .always: return true
        case .whenNoOpenWindow: return window.isWindowlessApp
        case .windowTitleContains:
            guard let titleFilters = entry.windowTitleContains, !titleFilters.isEmpty else { return false }
            return titleFilters.contains { !$0.isEmpty && window.title.contains($0) }
        }
    }
}
