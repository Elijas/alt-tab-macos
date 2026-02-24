import Cocoa

class SidePanelManager {
    static let shared = SidePanelManager()
    private static let mainAltTabBundleId = "com.lwouis.alt-tab-macos"

    private var panels = [ScreenUuid: SidePanel]()
    private var mainPanel: MainPanel?
    private var lastRefreshTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var lastSpaceChangeNanos: UInt64 = 0
    private var nextRefreshScheduled = false
    private var resolvedBlacklist: [BlacklistEntry]?
    private var discoveryTimer: Timer?
    private var separatorDebounce: DispatchWorkItem?

    private init() {}

    func notifySpaceChange() {
        lastSpaceChangeNanos = DispatchTime.now().uptimeNanoseconds
    }

    func setup() {
        guard Preferences.sidePanelEnabled else { return }
        // force-discover windows on all spaces that AX events may have missed
        Applications.addMissingWindows()
        rebuildPanelsForScreenChange()
        if Preferences.mainPanelOpenOnStartup {
            openMainPanel()
        }
        // staggered re-discovery passes: AX brute-force scan may miss windows on
        // other spaces if the AX subsystem hasn't registered them yet at launch.
        // Each pass re-scans and refreshes so progressively more windows appear.
        for delay in [1, 3, 5, 7, 10] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
                self?.discoverMissingWindows()
                self?.refreshPanels()
            }
        }
        // periodic re-discovery: AX events miss windows on other spaces
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.discoverMissingWindows()
            self?.refreshPanels()
        }
    }

    func applyOpacity() {
        for (_, panel) in panels {
            panel.applyOpacity()
        }
    }

    func applySeparatorSizes() {
        separatorDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.rebuildPanelsForScreenChange()
            if self.mainPanel?.isVisible ?? false {
                self.closeMainPanel()
                self.openMainPanel()
            }
            self.refreshPanelsNow()
        }
        separatorDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func tearDown() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
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

    // MARK: - Main Panel

    func openMainPanel() {
        if mainPanel == nil { mainPanel = MainPanel() }
        mainPanel!.orderFront(nil)
        refreshPanelsNow()
    }

    func closeMainPanel() {
        mainPanel?.orderOut(nil)
        mainPanel = nil
    }

    // MARK: - Refresh

    func refreshPanels() {
        guard Preferences.sidePanelEnabled || (mainPanel?.isVisible ?? false) else { return }
        let throttleDelayInMs = 200

        // During space transitions, CGS APIs return inconsistent window-space data.
        // Defer all refreshes until the transition animation settles.
        let spaceChangeCooldownMs: UInt64 = 400
        let msSinceSpaceChange = (DispatchTime.now().uptimeNanoseconds - lastSpaceChangeNanos) / 1_000_000
        let inSpaceCooldown = msSinceSpaceChange < spaceChangeCooldownMs

        let timeSinceLastRefreshInMs = Float(DispatchTime.now().uptimeNanoseconds - lastRefreshTimeInNanoseconds) / 1_000_000
        if !inSpaceCooldown && timeSinceLastRefreshInMs >= Float(throttleDelayInMs) {
            lastRefreshTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
            refreshPanelsNow()
            return
        }
        guard !nextRefreshScheduled else { return }
        nextRefreshScheduled = true
        let delayMs = inSpaceCooldown ? Int(spaceChangeCooldownMs - msSinceSpaceChange) + 10 : throttleDelayInMs + 10
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) {
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

        var allScreenData = [ScreenColumnData]()

        // sort screens left-to-right; ties broken top-to-bottom (higher Quartz Y = physically higher)
        let sortedScreens = NSScreen.screens.sorted { a, b in
            if a.frame.origin.x != b.frame.origin.x {
                return a.frame.origin.x < b.frame.origin.x
            }
            return a.frame.origin.y > b.frame.origin.y
        }

        for screen in sortedScreens {
            guard let screenUuid = screen.cachedUuid() else { continue }

            // feed matching side panel (uses side panel pref)
            if let panel = panels[screenUuid] {
                let result = buildScreenGroups(screenUuid: screenUuid, windowByCgId: windowByCgId, panelWindowNumbers: panelWindowNumbers, showTabHierarchy: Preferences.showTabHierarchyInSidePanel)
                panel.updateContents(result.groups, selectedWindowId: result.selectedWindowId, isActiveScreen: result.isActiveScreen, currentSpaceGroupIndex: result.currentSpaceGroupIndex, showTabHierarchy: Preferences.showTabHierarchyInSidePanel)
            }

            // collect for main panel (uses main panel pref)
            let screenName: String
            if #available(macOS 10.15, *) {
                screenName = screen.localizedName
            } else {
                let index = NSScreen.screens.firstIndex(of: screen).map { $0 + 1 } ?? 0
                screenName = "Screen \(index)"
            }
            let wpResult = buildScreenGroups(screenUuid: screenUuid, windowByCgId: windowByCgId, panelWindowNumbers: panelWindowNumbers, showTabHierarchy: Preferences.showTabHierarchyInMainPanel)
            allScreenData.append(ScreenColumnData(
                screenName: screenName,
                groups: wpResult.groups,
                selectedWindowId: wpResult.selectedWindowId,
                isActiveScreen: wpResult.isActiveScreen,
                currentSpaceGroupIndex: wpResult.currentSpaceGroupIndex,
                showTabHierarchy: Preferences.showTabHierarchyInMainPanel
            ))
        }

        if let wp = mainPanel, wp.isVisible {
            wp.update(allScreenData)
        }
    }

    private func buildScreenGroups(
        screenUuid: ScreenUuid,
        windowByCgId: [CGWindowID: Window],
        panelWindowNumbers: Set<Int>,
        showTabHierarchy: Bool
    ) -> (groups: [[Window]], selectedWindowId: CGWindowID?, isActiveScreen: Bool, currentSpaceGroupIndex: Int?) {
        let screenSpaces = Spaces.screenSpacesMap[screenUuid] ?? []

        // sort spaces in fixed Mission Control order (space 1 on top)
        let sortedSpaces = screenSpaces.sorted { a, b in
            let ai = Spaces.idsAndIndexes.first { $0.0 == a }?.1 ?? Int.max
            let bi = Spaces.idsAndIndexes.first { $0.0 == b }?.1 ?? Int.max
            return ai < bi
        }

        let currentSpaceId = Spaces.currentSpaceForScreen[screenUuid]

        // AX-based tab parent mapping (computed once, used per-space)
        let showTabs = showTabHierarchy
        var tabParentMap = [CGWindowID: CGWindowID]()
        if showTabs {
            tabParentMap = Windows.queryAXTabGroups(Array(windowByCgId.values))
            for (childWid, parentWid) in tabParentMap {
                windowByCgId[childWid]?.parentWindowId = parentWid
            }
        }

        // per-space grouping
        var groups = [[Window]]()
        var seen = Set<CGWindowID>()
        for spaceId in sortedSpaces {
            // all windows CGS knows about on this space
            let allOnSpace = Spaces.windowsInSpaces([spaceId])
            // only non-invisible (non-tabbed) windows on this space
            let visibleOnSpace = Set(Spaces.windowsInSpaces([spaceId], false))

            // A visible window can never be a tab child — in macOS native tabs only one
            // tab per group is on-screen at a time. This corrects stale parentWindowId
            // from queryAXTabGroups when the active tab switches (the newly visible
            // window may have nil axUiElement from when it was invisible, causing the
            // AX query to misclassify it as a child).
            if showTabs {
                for wid in visibleOnSpace {
                    windowByCgId[wid]?.parentWindowId = 0
                }
            }

            var group = [Window]()
            for wid in allOnSpace {
                let isVisible = visibleOnSpace.contains(wid)
                if let window = windowByCgId[wid] {
                    let isTab = showTabs && window.isTabChild
                    let dominated = seen.contains(wid)
                        || window.isWindowlessApp
                        || window.isMinimized
                        || window.isHidden
                        || (!isVisible && !isTab)
                        || self.isBlacklisted(window)
                        || panelWindowNumbers.contains(Int(wid))
                    if !dominated {
                        group.append(window)
                    }
                }
            }
            // pull in tabbed windows with spaces=[] whose parent is in this group
            if showTabs {
                let groupWids = Set(group.compactMap { $0.cgWindowId })
                for (childWid, parentWid) in tabParentMap {
                    if groupWids.contains(parentWid),
                       !seen.contains(childWid),
                       !visibleOnSpace.contains(childWid),
                       let window = windowByCgId[childWid],
                       !self.isBlacklisted(window),
                       !panelWindowNumbers.contains(Int(childWid)) {
                        group.append(window)
                    }
                }
            }
            var sorted = group.sorted { $0.creationOrder > $1.creationOrder }
            if showTabs {
                sorted = Windows.orderWithTabHierarchy(sorted)
            }
            for w in sorted { seen.insert(w.cgWindowId!) }
            groups.append(sorted)
        }

        let currentSpaceGroupIndex: Int? = currentSpaceId.flatMap { csId in
            sortedSpaces.firstIndex(of: csId)
        }

        // find per-screen "selected" window: lowest lastFocusOrder in the current space only
        var selectedWindowId: CGWindowID? = nil
        var lowestFocusOrder = Int.max
        if let csgi = currentSpaceGroupIndex, csgi < groups.count {
            for window in groups[csgi] {
                if window.lastFocusOrder < lowestFocusOrder {
                    lowestFocusOrder = window.lastFocusOrder
                    selectedWindowId = window.cgWindowId
                }
            }
        }
        let isActiveScreen = lowestFocusOrder == 0

        return (groups: groups, selectedWindowId: selectedWindowId, isActiveScreen: isActiveScreen, currentSpaceGroupIndex: currentSpaceGroupIndex)
    }

    // MARK: - Blacklist

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
        var numbers = Set(panels.values.map { $0.windowNumber })
        if let wp = mainPanel { numbers.insert(wp.windowNumber) }
        return numbers
    }

    // MARK: - CGWindowList Audit

    /// Uses CGWindowListCopyWindowInfo to find windows the Window Server knows about
    /// but AltTab's Windows.list doesn't. For apps with missing windows, triggers
    /// manuallyUpdateWindows() to re-scan via AX.
    private func discoverMissingWindows() {
        let windowInfoList = CGWindow.windows(.optionAll)

        // our own panel windows to exclude
        let panelWindowNumbers = allWindowNumbers()
        let tilesWindowNumber = App.app.tilesPanel.windowNumber

        // system processes that never produce user windows
        let systemProcessNames: Set<String> = [
            "Window Server", "Dock", "SystemUIServer",
            "Control Center", "Notification Center",
        ]

        // known CGWindowIDs from AltTab's window list
        let knownWids = Set(Windows.list.compactMap { $0.cgWindowId })

        // collect PIDs that have at least one window the Window Server sees but AltTab doesn't
        var pidsWithMissingWindows = Set<pid_t>()

        for info in windowInfoList {
            guard let wid = info.id(),
                  let pid = info.ownerPID(),
                  let layer = info.layer() else { continue }

            // only normal-layer windows
            guard layer == 0 else { continue }

            // only visible (non-transparent) windows
            if let alpha = info[kCGWindowAlpha] as? Double, alpha <= 0 { continue }

            // only reasonably-sized windows (skip tiny system chrome / popups)
            guard let bounds = info.bounds(),
                  bounds.width > 50, bounds.height > 50 else { continue }

            // skip system processes
            if let ownerName = info.ownerName(), systemProcessNames.contains(ownerName) { continue }

            // skip our own panels
            guard Int(wid) != tilesWindowNumber,
                  !panelWindowNumbers.contains(Int(wid)) else { continue }

            // if this window is missing from AltTab, mark the owning app for re-scan
            if !knownWids.contains(wid) {
                pidsWithMissingWindows.insert(pid)
            }
        }

        // trigger targeted AX re-discovery only for apps with missing windows
        for pid in pidsWithMissingWindows {
            if let app = Applications.list.first(where: { $0.pid == pid }) {
                app.manuallyUpdateWindows()
            }
        }
    }
}
