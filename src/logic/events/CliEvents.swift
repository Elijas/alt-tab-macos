class CliEvents {
    static let portName = (Bundle.main.bundleIdentifier ?? "com.lwouis.alt-tab-macos") + ".cli"

    static func observe() {
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        if let messagePort = CFMessagePortCreateLocal(nil, portName as CFString, handleEvent, &context, nil),
           let source = CFMessagePortCreateRunLoopSource(nil, messagePort, 0) {
            CFRunLoopAddSource(BackgroundWork.cliEventsThread.runLoop, source, .commonModes)
        } else {
            Logger.error { "Can't listen on message port. Is another AltTab already running?" }
            // TODO: should we quit or restart here?
            // It's complex since AltTab can be restarted sometimes,
            // and the new instance may coexist with the old for some duration
            // There is also the case of multiple instances at login
        }
    }

    private static let handleEvent: CFMessagePortCallBack = { (_: CFMessagePort?, _: Int32, _ data: CFData?, _: UnsafeMutableRawPointer?) in
        Logger.debug { "" }
        if let data,
           let message = String(data: data as Data, encoding: .utf8) {
            Logger.info { message }
            let output = CliServer.executeCommandAndSendReponse(message)
            if let responseData = try? CliServer.jsonEncoder.encode(output) as CFData {
                return Unmanaged.passRetained(responseData)
            }
        }
        Logger.error { "Failed to decode message" }
        return nil
    }
}

class CliServer {
    static let jsonEncoder = JSONEncoder()
    static let error = "error"
    static let noOutput = "noOutput"

    static func executeCommandAndSendReponse(_ rawValue: String) -> Codable {
        var output: Codable = ""
        DispatchQueue.main.sync {
            output = executeCommandAndSendReponse_(rawValue)
        }
        return output
    }

    private static func executeCommandAndSendReponse_(_ rawValue: String) -> Codable {
        if rawValue == "--list" {
            return JsonWindowList(windows: Windows.list
                .filter { !$0.isWindowlessApp }
                .map { JsonWindow(id: $0.cgWindowId, title: $0.title) }
            )
        }
        if rawValue == "--detailed-list" {
            // refresh space/screen assignments so CLI returns fresh data
            Spaces.refresh()
            let spaceIdsAndIndexes = Spaces.idsAndIndexes.map { $0.0 }
            let cgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes)
            let visibleCgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes, false)
            for window in Windows.list {
                window.updateSpacesAndScreen()
                Windows.detectTabbedWindows(window, cgsWindowIds, visibleCgsWindowIds)
            }
            // infer tab parent relationships from isTabbed state
            let parentMap = Windows.inferTabParentIds(Windows.list)
            for window in Windows.list {
                if let wid = window.cgWindowId {
                    window.parentWindowId = parentMap[wid] ?? 0
                }
            }
            let windows = Windows.list
                .filter { !$0.isWindowlessApp }
                .map {
                    JsonWindowFull(
                        id: $0.cgWindowId,
                        title: $0.title,
                        appName: $0.application.localizedName,
                        appBundleId: $0.application.bundleIdentifier,
                        spaceIndexes: $0.spaceIndexes,
                        lastFocusOrder: $0.lastFocusOrder,
                        creationOrder: $0.creationOrder,
                        isTabbed: $0.isTabbed,
                        parentWindowId: $0.parentWindowId == 0 ? nil : $0.parentWindowId,
                        isHidden: $0.isHidden,
                        isFullscreen: $0.isFullscreen,
                        isMinimized: $0.isMinimized,
                        isOnAllSpaces: $0.isOnAllSpaces,
                        position: $0.position,
                        size: $0.size,
                        screenId: $0.screenId as String?,
                        appPid: $0.application.pid,
                        dockLabel: $0.application.dockLabel
                    )
                }

            let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
            let screens = NSScreen.screens.compactMap { screen -> JsonScreen? in
                guard let uuid = screen.cachedUuid() else { return nil }
                let f = screen.frame
                let quartzY = primaryScreenHeight - f.origin.y - f.height
                let vf = screen.visibleFrame
                let quartzVisibleY = primaryScreenHeight - vf.origin.y - vf.height
                return JsonScreen(
                    id: uuid as String,
                    frame: [Double(f.origin.x), quartzY, Double(f.width), Double(f.height)],
                    visibleFrame: [Double(vf.origin.x), quartzVisibleY, Double(vf.width), Double(vf.height)]
                )
            }

            let visibleSpaceIndexes = Spaces.visibleSpaces.compactMap { spaceId in
                Spaces.idsAndIndexes.first { $0.0 == spaceId }?.1
            }

            let screenSpacesMap = Dictionary(uniqueKeysWithValues: Spaces.screenSpacesMap.map { (key, value) in
                (key as String, value.compactMap { spaceId in
                    Spaces.idsAndIndexes.first { $0.0 == spaceId }?.1
                })
            })

            let blacklistEntries = Preferences.blacklist
            let blacklist: [[String: String]]? = blacklistEntries.isEmpty ? nil : blacklistEntries.map { entry in
                var dict: [String: String] = [
                    "bundleIdentifier": entry.bundleIdentifier,
                    "hide": entry.hide.rawValue,
                    "ignore": entry.ignore.rawValue,
                ]
                if let title = entry.windowTitleContains {
                    dict["windowTitleContains"] = title
                }
                return dict
            }

            let mouseScreenId = NSScreen.withMouse()?.cachedUuid() as String?

            return JsonDetailedList(
                windows: windows,
                screens: screens,
                currentSpaceIndex: Spaces.currentSpaceIndex,
                visibleSpaceIndexes: visibleSpaceIndexes,
                screenSpacesMap: screenSpacesMap,
                frontmostAppPid: Applications.frontmostPid,
                mouseScreenId: mouseScreenId,
                blacklist: blacklist
            )
        }
        if rawValue == "--debug-tabs" {
            return debugTabs()
        }
        if rawValue.hasPrefix("--focus="),
           let id = CGWindowID(rawValue.dropFirst("--focus=".count)), let window = (Windows.list.first { $0.cgWindowId == id }) {
            window.focus()
            return noOutput
        }
        if rawValue.hasPrefix("--focusUsingLastFocusOrder="),
           let lastFocusOrder = Int(rawValue.dropFirst("--focusUsingLastFocusOrder=".count)), let window = (Windows.list.first { $0.lastFocusOrder == lastFocusOrder }) {
            window.focus()
            return noOutput
        }
        if rawValue.hasPrefix("--show="),
           let shortcutIndex = Int(rawValue.dropFirst("--show=".count)), (0..<Preferences.shortcutCount).contains(shortcutIndex) {
            App.app.showUi(shortcutIndex)
            return noOutput
        }
        return error
    }

    private struct JsonWindowList: Codable {
        var windows: [JsonWindow]
    }

    private struct JsonWindow: Codable {
        var id: CGWindowID?
        var title: String
    }

    private struct JsonDetailedList: Codable {
        var windows: [JsonWindowFull]
        var screens: [JsonScreen]
        var currentSpaceIndex: SpaceIndex
        var visibleSpaceIndexes: [SpaceIndex]
        var screenSpacesMap: [String: [SpaceIndex]]
        var frontmostAppPid: Int32?
        var mouseScreenId: String?
        var blacklist: [[String: String]]?
    }

    private struct JsonScreen: Codable {
        var id: String
        var frame: [Double]
        var visibleFrame: [Double]
    }

    private struct JsonWindowFull: Codable {
        var id: CGWindowID?
        var title: String
        // -- additional properties
        var appName: String?
        var appBundleId: String?
        var spaceIndexes: [SpaceIndex]
        var lastFocusOrder: Int
        var creationOrder: Int
        var isTabbed: Bool
        var parentWindowId: CGWindowID?
        var isHidden: Bool
        var isFullscreen: Bool
        var isMinimized: Bool
        var isOnAllSpaces: Bool
        var position: CGPoint?
        var size: CGSize?
        var screenId: String?
        var appPid: Int32?
        var dockLabel: String?
    }

    // MARK: - debug-tabs

    private static func debugTabs() -> Codable {
        // Refresh space/screen and detect tabbed state (same as --detailed-list)
        Spaces.refresh()
        let spaceIdsAndIndexes = Spaces.idsAndIndexes.map { $0.0 }
        let cgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes)
        let visibleCgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes, false)
        for window in Windows.list {
            window.updateSpacesAndScreen()
            Windows.detectTabbedWindows(window, cgsWindowIds, visibleCgsWindowIds)
        }

        var entries = [DebugTabEntry]()

        for window in Windows.list {
            guard let wid = window.cgWindowId, let axElement = window.axUiElement else { continue }

            var entry = DebugTabEntry(
                id: wid,
                title: window.title,
                appName: window.application.localizedName,
                pid: window.application.pid,
                isTabbed: window.isTabbed
            )

            // Query role and subrole for every window
            if let attrs = try? axElement.attributes([kAXRoleAttribute, kAXSubroleAttribute]) {
                entry.axRole = attrs.role
                entry.axSubrole = attrs.subrole
            }

            if !window.isTabbed {
                // --- VISIBLE window: walk children looking for AXTabGroup ---
                entry = debugVisibleWindow(axElement, entry)
            } else {
                // --- TABBED window: explore AX attributes for linking signals ---
                entry = debugTabbedWindow(axElement, entry)
            }

            entries.append(entry)
        }

        return DebugTabsResponse(windows: entries)
    }

    /// For a visible (non-tabbed) window, find AXTabGroup children and enumerate their tabs.
    private static func debugVisibleWindow(_ axElement: AXUIElement, _ entry: DebugTabEntry) -> DebugTabEntry {
        var entry = entry
        guard let attrs = try? axElement.attributes([kAXChildrenAttribute]),
              let children = attrs.children else { return entry }

        entry.childCount = children.count
        var tabGroups = [DebugTabGroup]()

        for child in children {
            guard let childAttrs = try? child.attributes([kAXRoleAttribute]),
                  childAttrs.role == "AXTabGroup" else { continue }

            var tabGroup = DebugTabGroup()
            tabGroup.axAttributeNames = axAttributeNames(child)

            // Get the tab group's children (should be AXRadioButton elements)
            if let tgAttrs = try? child.attributes([kAXChildrenAttribute]),
               let tabChildren = tgAttrs.children {
                tabGroup.tabCount = tabChildren.count
                var tabs = [DebugTabItem]()

                for tab in tabChildren {
                    var tabItem = DebugTabItem()
                    if let tabAttrs = try? tab.attributes([kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute]) {
                        tabItem.title = tabAttrs.title
                        tabItem.role = tabAttrs.role
                        tabItem.subrole = tabAttrs.subrole
                    }
                    // Value (selected state) — not in AXAttributes, query directly
                    tabItem.value = axStringValue(tab, kAXValueAttribute)
                    // Description
                    tabItem.axDescription = axStringValue(tab, kAXDescriptionAttribute)
                    // Identifier (if available)
                    tabItem.identifier = axStringValue(tab, "AXIdentifier")
                    // All attribute names for discovery
                    tabItem.axAttributeNames = axAttributeNames(tab)
                    tabs.append(tabItem)
                }
                tabGroup.tabs = tabs
            }
            tabGroups.append(tabGroup)
        }

        if !tabGroups.isEmpty {
            entry.tabGroups = tabGroups
        }
        return entry
    }

    /// For a tabbed (invisible) window, dump all AX attributes and walk the parent chain.
    private static func debugTabbedWindow(_ axElement: AXUIElement, _ entry: DebugTabEntry) -> DebugTabEntry {
        var entry = entry

        // All attribute names on this element
        entry.axAttributeNames = axAttributeNames(axElement)

        // Walk parent chain (up to 3 levels)
        var parentChain = [DebugAXElement]()
        var current = axElement
        for _ in 0..<3 {
            guard let parentAttrs = try? current.attributes([kAXParentAttribute]),
                  let parent = parentAttrs.parent else { break }

            var info = DebugAXElement()
            if let pAttrs = try? parent.attributes([kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute]) {
                info.role = pAttrs.role
                info.subrole = pAttrs.subrole
                info.title = pAttrs.title
            }
            info.windowId = try? parent.cgWindowId()
            info.axAttributeNames = axAttributeNames(parent)
            parentChain.append(info)
            current = parent
        }
        if !parentChain.isEmpty {
            entry.axParentChain = parentChain
        }

        // Try kAXLinkedUIElementsAttribute — might link to the tab group
        entry.linkedElements = axLinkedElements(axElement)

        // Also check if the tabbed window itself has children (AXTabGroup etc.)
        if let childAttrs = try? axElement.attributes([kAXChildrenAttribute]),
           let children = childAttrs.children, !children.isEmpty {
            entry.childCount = children.count
            // Check if any child is a tab group
            var tabGroups = [DebugTabGroup]()
            for child in children {
                if let cAttrs = try? child.attributes([kAXRoleAttribute]),
                   cAttrs.role == "AXTabGroup" {
                    var tg = DebugTabGroup()
                    tg.axAttributeNames = axAttributeNames(child)
                    if let tgChildren = try? child.attributes([kAXChildrenAttribute]),
                       let tabs = tgChildren.children {
                        tg.tabCount = tabs.count
                        tg.tabs = tabs.compactMap { tab in
                            var item = DebugTabItem()
                            if let a = try? tab.attributes([kAXRoleAttribute, kAXTitleAttribute]) {
                                item.title = a.title
                                item.role = a.role
                            }
                            item.value = axStringValue(tab, kAXValueAttribute)
                            return item
                        }
                    }
                    tabGroups.append(tg)
                }
            }
            if !tabGroups.isEmpty {
                entry.tabGroups = tabGroups
            }
        }

        return entry
    }

    // MARK: - AX helpers for debug-tabs

    /// Get all attribute names for an AX element.
    private static func axAttributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let arr = names as? [String] else { return [] }
        return arr
    }

    /// Get a string representation of an AX attribute value.
    private static func axStringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let v = value else { return nil }
        return "\(v)"
    }

    /// Get linked UI elements info.
    private static func axLinkedElements(_ element: AXUIElement) -> [DebugAXElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXLinkedUIElements" as CFString, &value) == .success,
              let arr = value as? [AXUIElement] else { return nil }
        return arr.map { linked in
            var info = DebugAXElement()
            if let a = try? linked.attributes([kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute]) {
                info.role = a.role
                info.subrole = a.subrole
                info.title = a.title
            }
            info.windowId = try? linked.cgWindowId()
            return info
        }
    }

    // MARK: - debug-tabs JSON types

    private struct DebugTabsResponse: Codable {
        var windows: [DebugTabEntry]
    }

    private struct DebugTabEntry: Codable {
        var id: CGWindowID
        var title: String
        var appName: String?
        var pid: Int32
        var isTabbed: Bool
        var axRole: String?
        var axSubrole: String?
        var childCount: Int?
        var tabGroups: [DebugTabGroup]?
        // tabbed-window-only fields
        var axAttributeNames: [String]?
        var axParentChain: [DebugAXElement]?
        var linkedElements: [DebugAXElement]?
    }

    private struct DebugTabGroup: Codable {
        var tabCount: Int?
        var tabs: [DebugTabItem]?
        var axAttributeNames: [String]?
    }

    private struct DebugTabItem: Codable {
        var title: String?
        var role: String?
        var subrole: String?
        var value: String?
        var axDescription: String?
        var identifier: String?
        var axAttributeNames: [String]?
    }

    private struct DebugAXElement: Codable {
        var role: String?
        var subrole: String?
        var title: String?
        var windowId: CGWindowID?
        var axAttributeNames: [String]?
    }
}

class CliClient {
    static func detectCommand() -> String? {
        let args = CommandLine.arguments
        if args.count == 2 && !args[1].starts(with: "--logs=") {
            if args[1] == "--list" || args[1] == "--detailed-list" || args[1] == "--debug-tabs" || args[1].hasPrefix("--focus=") || args[1].hasPrefix("--focusUsingLastFocusOrder=") || args[1].hasPrefix("--show=") {
                return args[1]
            }
        }
        return nil
    }

    static func sendCommandAndProcessResponse(_ command: String) {
        do {
            let serverPortClient = try CFMessagePortCreateRemote(nil, CliEvents.portName as CFString).unwrapOrThrow()
            let data = try command.data(using: .utf8).unwrapOrThrow()
            var returnData: Unmanaged<CFData>?
            let _ = CFMessagePortSendRequest(serverPortClient, 0, data as CFData, 2, 2, CFRunLoopMode.defaultMode.rawValue, &returnData)
            let responseData = try returnData.unwrapOrThrow().takeRetainedValue()
            if let response = String(data: responseData as Data, encoding: .utf8) {
                if response != "\"\(CliServer.error)\"" {
                    if response != "\"\(CliServer.noOutput)\"" {
                        print(response)
                    }
                    exit(0)
                }
            }
            print("Couldn't execute command. Is it correct?")
            exit(1)
        } catch {
            print("AltTab.app needs to be running for CLI commands to work")
            exit(1)
        }
    }
}
