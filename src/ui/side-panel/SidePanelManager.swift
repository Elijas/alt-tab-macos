import Cocoa

class SidePanelManager {
    static let shared = SidePanelManager()
    private static let mainAltTabBundleId = "com.lwouis.alt-tab-macos"

    private var panels = [ScreenUuid: SidePanel]()
    private var lastRefreshTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var nextRefreshScheduled = false
    private var resolvedBlacklist: [BlacklistEntry]?

    private init() {}

    func setup() {
        guard Preferences.sidePanelEnabled else { return }
        // force-discover windows on all spaces that AX events may have missed
        Applications.addMissingWindows()
        rebuildPanelsForScreenChange()
        // delayed refresh to catch async AX discoveries
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshPanels()
        }
    }

    func tearDown() {
        for (_, panel) in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    func rebuildPanelsForScreenChange() {
        // remove all existing panels
        for (_, panel) in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()

        guard Preferences.sidePanelEnabled else { return }

        // create one panel per screen
        for screen in NSScreen.screens {
            guard let uuid = screen.cachedUuid() else { continue }
            let panel = SidePanel(for: screen)
            panels[uuid] = panel
            panel.orderFront(nil)
        }

        // populate immediately
        refreshPanelsNow()
    }

    func refreshPanels() {
        guard Preferences.sidePanelEnabled else { return }
        let throttleDelayInMs = 200
        let timeSinceLastRefreshInMs = Float(DispatchTime.now().uptimeNanoseconds - lastRefreshTimeInNanoseconds) / 1_000_000
        if timeSinceLastRefreshInMs >= Float(throttleDelayInMs) {
            lastRefreshTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
            refreshPanelsNow()
            return
        }
        guard !nextRefreshScheduled else { return }
        nextRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(throttleDelayInMs + 10)) {
            self.nextRefreshScheduled = false
            self.refreshPanels()
        }
    }

    private func refreshPanelsNow() {
        Spaces.refresh()

        let panelWindowNumbers = allWindowNumbers()

        // build cgWindowId → Window lookup for fast matching
        var windowByCgId = [CGWindowID: Window]()
        for window in Windows.list {
            if let wid = window.cgWindowId { windowByCgId[wid] = window }
        }

        for (_, panel) in panels {
            guard let screenUuid = panel.targetScreen.cachedUuid() else { continue }
            let screenSpaces = Spaces.screenSpacesMap[screenUuid] ?? []

            // sort spaces in fixed Mission Control order (space 1 on top)
            let sortedSpaces = screenSpaces.sorted { a, b in
                let ai = Spaces.idsAndIndexes.first { $0.0 == a }?.1 ?? Int.max
                let bi = Spaces.idsAndIndexes.first { $0.0 == b }?.1 ?? Int.max
                return ai < bi
            }

            // per-space grouping with per-space tab detection
            var groups = [[Window]]()
            var seen = Set<CGWindowID>()
            for spaceId in sortedSpaces {
                // all windows CGS knows about on this space
                let allOnSpace = Spaces.windowsInSpaces([spaceId])
                // only non-invisible (non-tabbed) windows on this space
                let visibleOnSpace = Set(Spaces.windowsInSpaces([spaceId], false))

                var group = [Window]()
                for wid in allOnSpace {
                    let isVisible = visibleOnSpace.contains(wid)
                    if let window = windowByCgId[wid] {
                        let dominated = seen.contains(wid)
                            || window.isWindowlessApp
                            || window.isMinimized
                            || window.isHidden
                            || !isVisible
                            || self.isBlacklisted(window)
                            || panelWindowNumbers.contains(Int(wid))
                        if !dominated {
                            group.append(window)
                        }
                    }
                }
                let sorted = group.sorted { $0.creationOrder > $1.creationOrder }
                for w in sorted { seen.insert(w.cgWindowId!) }
                groups.append(sorted)
            }
            panel.updateContents(groups)
        }
    }

    private func blacklist() -> [BlacklistEntry] {
        if let resolved = resolvedBlacklist { return resolved }
        // read from main AltTab's preferences domain (sidepanel has its own bundle id)
        var entries = Preferences.blacklist
        if let mainDefaults = UserDefaults(suiteName: Self.mainAltTabBundleId),
           let json = mainDefaults.string(forKey: "blacklist"),
           let data = json.data(using: .utf8),
           let mainEntries = try? JSONDecoder().decode([BlacklistEntry].self, from: data) {
            // merge: main AltTab entries take precedence, add any not already present
            let existingIds = Set(entries.map { $0.bundleIdentifier })
            for entry in mainEntries where !existingIds.contains(entry.bundleIdentifier) {
                entries.append(entry)
            }
        }
        resolvedBlacklist = entries
        return entries
    }

    private func isBlacklisted(_ window: Window) -> Bool {
        guard let bundleId = window.application.bundleIdentifier else { return false }
        return blacklist().contains { entry in
            guard entry.hide != .none else { return false }
            guard bundleId.hasPrefix(entry.bundleIdentifier) else { return false }
            switch entry.hide {
            case .none: return false
            case .always: return true
            case .whenNoOpenWindow: return window.isWindowlessApp
            case .windowTitleContains:
                guard let titleFilter = entry.windowTitleContains, !titleFilter.isEmpty else { return false }
                return window.title.contains(titleFilter)
            }
        }
    }

    func allWindowNumbers() -> Set<Int> {
        Set(panels.values.map { $0.windowNumber })
    }
}
