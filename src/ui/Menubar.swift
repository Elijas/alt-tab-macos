import Cocoa

class Menubar {
    static var statusItem: NSStatusItem!
    static var menu: NSMenu!
    static var permissionCalloutMenuItems: [NSMenuItem]?

    static func addMenuItem(_ title: String, _ action: Selector, _ keyEquivalent: String, _ symbolName: String?, _ color: NSColor? = nil, _ target: AnyObject? = nil) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if #available(macOS 26.0, *), let symbolName {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            if let color {
                item.image = item.image?.withSymbolConfiguration(.init(paletteColors: [color]))
            }
        }
    }

    static func initialize() {
        menu = NSMenu()
        menu.title = App.name // perf: prevent going through expensive code-path within appkit
        let permissionCalloutMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        permissionCalloutMenuItem.view = PermissionCallout()
        let calloutSeparator = NSMenuItem.separator()
        permissionCalloutMenuItems = [permissionCalloutMenuItem, calloutSeparator]
        // Fork: side/main panel controls as a flat section at the very top.
        PanelMenu.shared.installTopSection(in: menu)
        addMenuItem(NSLocalizedString("Show", comment: "Menubar option"), #selector(App.showUiFromShortcut0), "", "eye", nil, App.self)
        menu.addItem(NSMenuItem.separator())
        addMenuItem(NSLocalizedString("Settings…", comment: "Menubar option"), #selector(App.showSettingsWindow), ",", "gear", nil, App.self)
        addMenuItem(NSLocalizedString("Check for updates…", comment: "Menubar option"), #selector(App.checkForUpdatesNow), "", "checkmark.arrow.trianglehead.clockwise", nil, App.self)
        addMenuItem(NSLocalizedString("Check permissions…", comment: "Menubar option"), #selector(App.checkPermissions), "", "hand.raised", nil, App.self)
        menu.addItem(NSMenuItem.separator())
        addMenuItem(String(format: NSLocalizedString("About %@", comment: "Menubar option. %@ is AltTab"), App.name), #selector(App.showAboutWindow), "", "info.circle", nil, App.self)
        addMenuItem(NSLocalizedString("Debug tools", comment: "Menubar option"), #selector(App.showDebugWindow), "", "scope", nil, App.self)
        addMenuItem(NSLocalizedString("Send feedback…", comment: "Menubar option"), #selector(App.showFeedbackPanel), "", "text.bubble", nil, App.self)
        addMenuItem(NSLocalizedString("Support this project", comment: "Menubar option"), App.supportProjectAction, "", "heart.fill", .red, App.self)
        menu.addItem(NSMenuItem.separator())
        addMenuItem(String(format: NSLocalizedString("Quit %@", comment: "Menubar option. %@ is AltTab"), App.name), #selector(NSApplication.terminate(_:)), "q", nil) // "xmark.rectangle" is not necessary; macos automatically recognizes Quit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.target = self
        statusItem.button!.action = #selector(statusItemOnClick)
        statusItem.button!.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    // NSMenuItem.isHidden isn't reliable with custom views. We add/remove to hide/show these items
    static func togglePermissionCallout(_ show: Bool) {
        permissionCalloutMenuItems?.enumerated().forEach { offset, element in
            if show && !menu.items.contains(element) {
                menu.insertItem(element, at: offset)
            }
            if !show && menu.items.contains(element) {
                menu.removeItem(element)
            }
        }
    }

    @objc static func statusItemOnClick() {
        // NSApp.currentEvent == nil if the icon is "clicked" through VoiceOver
        if let type = NSApp.currentEvent?.type, type != .leftMouseDown {
            App.showUiFromShortcut0()
        } else {
            statusItem.popUpMenu(Menubar.menu)
        }
    }

    static func menubarIconCallback(_: NSControl?) {
        if Preferences.menubarIconShown {
            loadPreferredIcon()
        } else {
            statusItem.isVisible = false
        }
        if let menubarIconDropdown = GeneralTab.menubarIconDropdown {
            menubarIconDropdown.isEnabled = Preferences.menubarIconShown
        }
    }

    static private func loadPreferredIcon() {
        let i = Preferences.menubarIcon.indexAsString
        let image = NSImage(named: "menubar-\(i)")!
        image.isTemplate = i != "2"
        statusItem.button!.image = image
        statusItem.isVisible = true
        statusItem.button!.imageScaling = .scaleProportionallyUpOrDown
    }
}

class PermissionCallout: StackView {
    convenience init() {
        let label = NSTextField(wrappingLabelWithString: NSLocalizedString("AltTab is running without Screen Recording permissions. Thumbnails won’t show.", comment: "Menubar callout"))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.preferredMaxLayoutWidth = 250
        label.isSelectable = false
        label.addOrUpdateConstraint(label.widthAnchor, 250)
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.attributedTitle = NSAttributedString(string: NSLocalizedString("Grant permission", comment: "Menubar callout button"), attributes: [NSAttributedString.Key.foregroundColor: NSColor.white])
        button.onAction = { _ in
            Preferences.remove("screenRecordingPermissionSkipped")
            App.restart()
        }
        self.init([label, button], .vertical, true, top: 8, right: 15, bottom: 10, left: 15)
        wantsLayer = true
        layer!.backgroundColor = NSColor.purple.cgColor
    }
}

/// Fork: surfaces every side/main panel toggle in the menubar menu as a flat top
/// section, plus split Enable/Disable side-panel actions. The side-effect closures
/// mirror PanelTab's switch extraActions so menu and Settings stay in sync.
class PanelMenu: NSObject, NSMenuDelegate {
    static let shared = PanelMenu()

    /// Carried on each toggle item's representedObject: the pref key + its side effect.
    private class ToggleRef: NSObject {
        let key: String
        let apply: () -> Void
        init(_ key: String, _ apply: @escaping () -> Void) {
            self.key = key
            self.apply = apply
        }
    }

    private struct Toggle {
        let title: String
        let key: String
        let apply: () -> Void
    }

    private let toggles: [Toggle] = [
        Toggle(title: "Side Panel: Show Tabs as Indented Items", key: "showTabHierarchyInSidePanel", apply: { SidePanelManager.shared.refreshPanels() }),
        Toggle(title: "Side Panel: Group Tabs in Sort Order", key: "groupTabsInSortOrder", apply: { SidePanelManager.shared.refreshPanels() }),
        Toggle(title: "Side Panel: Hover Jumps to Other Side", key: "sidePanelHoverJump", apply: {}),
        Toggle(title: "Main Panel: Open on Startup", key: "mainPanelOpenOnStartup", apply: {}),
        Toggle(title: "Main Panel: Wrap Titles", key: "mainPanelTitleWrapping", apply: { SidePanelManager.shared.applySeparatorSizes() }),
        Toggle(title: "Main Panel: Stretch Rows to Fill Space", key: "mainPanelVerticalFill", apply: { SidePanelManager.shared.applySeparatorSizes() }),
        Toggle(title: "Main Panel: Collapse Empty Screens", key: "mainPanelCollapseEmptyScreens", apply: { SidePanelManager.shared.refreshPanels() }),
        Toggle(title: "Main Panel: Show Tabs as Indented Items", key: "showTabHierarchyInMainPanel", apply: { SidePanelManager.shared.refreshPanels() }),
    ]

    func installTopSection(in menu: NSMenu) {
        menu.delegate = self
        addAction(menu, "Enable Side Panel", #selector(enableSidePanel))
        addAction(menu, "Disable Side Panel", #selector(disableSidePanel))
        addAction(menu, "Open All-Screen Overview", #selector(openAllScreenOverview))
        for toggle in toggles {
            let item = NSMenuItem(title: toggle.title, action: #selector(toggleItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ToggleRef(toggle.key, toggle.apply)
            item.state = CachedUserDefaults.bool(toggle.key) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
    }

    private func addAction(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    // Reflect current pref state as checkmarks each time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            if let ref = item.representedObject as? ToggleRef {
                item.state = CachedUserDefaults.bool(ref.key) ? .on : .off
            }
        }
    }

    @objc private func toggleItem(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? ToggleRef else { return }
        let newValue = !CachedUserDefaults.bool(ref.key)
        Preferences.set(ref.key, newValue ? "true" : "false") // bools are persisted as strings
        ref.apply()
        sender.state = newValue ? .on : .off
    }

    // "Enable" is a full re-enable: it clears per-screen disables and any temporary
    // hides by tearing down and rebuilding. setup() is NOT idempotent (it would leak
    // its repeating discoveryTimer), so we must tearDown() before setup().
    @objc private func enableSidePanel() {
        Preferences.set("sidePanelEnabled", "true")
        Preferences.set("sidePanelDisabledScreens", Preferences.jsonEncode([String]()))
        SidePanelManager.shared.tearDown()
        SidePanelManager.shared.setup()
    }

    @objc private func disableSidePanel() {
        Preferences.set("sidePanelEnabled", "false")
        SidePanelManager.shared.tearDown()
    }

    @objc private func openAllScreenOverview() {
        SidePanelManager.shared.openMainPanel()
    }
}
