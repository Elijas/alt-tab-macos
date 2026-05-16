import Cocoa

class SidePanelManager {
    static let shared = SidePanelManager()
    private static let mainAltTabBundleId = "com.lwouis.alt-tab-macos"

    private var panels = [ScreenUuid: SidePanel]()
    private var mainPanel: MainPanel?
    private var lastRefreshTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var lastSpaceChangeNanos: UInt64 = 0
    private var nextRefreshScheduled = false
    private var resolvedExceptions: [ExceptionEntry]?
    private var discoveryTimer: Timer?
    private var separatorDebounce: DispatchWorkItem?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    private init() {}

    func notifySpaceChange() {
        lastSpaceChangeNanos = DispatchTime.now().uptimeNanoseconds
    }

    func setup() {
        guard Preferences.sidePanelEnabled else { return }
        // force-discover windows on all spaces that AX events may have missed
        Applications.addMissingWindows()
        rebuildPanelsForScreenChange()
        // Prune stale space labels keyed by CGSSpaceIDs from previous sessions
        let currentSpaceIds = Set(Spaces.idsAndIndexes.map { $0.0 })
        Preferences.pruneSpaceLabels(currentSpaceIds: currentSpaceIds)
        if Preferences.mainPanelOpenOnStartup {
            openMainPanel()
        }
        // staggered re-discovery passes: AX brute-force scan may miss windows on
        // other spaces if the AX subsystem hasn't registered them yet at launch.
        // Each pass re-scans and refreshes so progressively more windows appear.
        for delay in [1, 3, 5, 7, 10] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
                Applications.removeZombieWindows()
                self?.discoverMissingWindows()
                self?.refreshPanels()
            }
        }
        // periodic re-discovery: AX events miss windows on other spaces
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Applications.removeZombieWindows()
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
        stopMouseTracking()
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        for (_, panel) in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    func disableScreen(_ uuid: ScreenUuid) {
        var disabled = Preferences.sidePanelDisabledScreens
        let key = uuid as String
        if !disabled.contains(key) { disabled.append(key) }
        Preferences.set("sidePanelDisabledScreens", Preferences.jsonEncode(disabled))
        panels[uuid]?.orderOut(nil)
        panels.removeValue(forKey: uuid)
    }

    func enableScreen(_ uuid: ScreenUuid) {
        var disabled = Preferences.sidePanelDisabledScreens
        disabled.removeAll { $0 == uuid as String }
        Preferences.set("sidePanelDisabledScreens", Preferences.jsonEncode(disabled))
        rebuildPanelsForScreenChange()
    }

    func rebuildPanelsForScreenChange() {
        // remove all existing panels
        for (_, panel) in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()

        guard Preferences.sidePanelEnabled else {
            stopMouseTracking()
            return
        }
        startMouseTracking()

        // create one panel per screen, skipping per-screen disabled screens
        let disabledScreens = Set(Preferences.sidePanelDisabledScreens)
        for screen in NSScreen.screens {
            guard let uuid = screen.cachedUuid() else { continue }
            guard !disabledScreens.contains(uuid as String) else { continue }
            let panel = SidePanel(for: screen)
            panels[uuid] = panel
            panel.orderFront(nil)
        }

        // populate immediately
        refreshPanelsNow()
    }

    private func startMouseTracking() {
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                self?.syncHover()
                return event
            }
        }
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                self?.syncHover()
            }
        }
    }

    private func stopMouseTracking() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func syncHover() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.syncHover()
            }
            return
        }
        guard !panels.isEmpty else { return }
        let location = NSEvent.mouseLocation
        for panel in panels.values {
            panel.syncHover(at: location)
        }
    }

    // MARK: - Main Panel

    func openMainPanel() {
        if mainPanel == nil { mainPanel = MainPanel() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainPanel!.makeKeyAndOrderFront(nil)
        refreshPanelsNow()
    }

    func closeMainPanel() {
        mainPanel?.orderOut(nil)
        mainPanel = nil
        NSApp.setActivationPolicy(.accessory)
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
        let (allScreenData, sidePanelResults) = computeAllScreenData()

        // Update side panels
        for (screenUuid, result) in sidePanelResults {
            if let panel = panels[screenUuid] {
                panel.updateContents(result.groups, selectedWindowId: result.selectedWindowId, isActiveScreen: result.isActiveScreen, currentSpaceGroupIndex: result.currentSpaceGroupIndex, showTabHierarchy: Preferences.showTabHierarchyInSidePanel)
            }
        }

        // Update main panel
        if let wp = mainPanel, wp.isVisible {
            wp.update(allScreenData)
        }
    }

    /// Shared pipeline: compute grouped window data for all screens.
    /// Used by both refreshPanelsNow() (to update views) and snapshotPanelContents() (for CLI).
    private func computeAllScreenData() -> (
        mainPanelData: [ScreenColumnData],
        sidePanelResults: [(ScreenUuid, (groups: [[Window]], selectedWindowId: CGWindowID?, isActiveScreen: Bool, currentSpaceGroupIndex: Int?, spaceIndexes: [SpaceIndex], spaceIds: [CGSSpaceID]))]
    ) {
        Spaces.refresh()

        // Only exclude side panel overlays from the window list.
        // MainPanel is a full-citizen window and should appear as a row.
        let panelWindowNumbers = Set(panels.values.map { $0.windowNumber })

        // build cgWindowId → Window lookup for fast matching
        var windowByCgId = [CGWindowID: Window]()
        for window in Windows.list {
            if let wid = window.cgWindowId { windowByCgId[wid] = window }
        }
        let windows = Array(windowByCgId.values)

        // Compute tab parent map when any tab-aware feature needs it (AX IPC is expensive)
        let needsTabInfo = Preferences.showTabHierarchyInSidePanel || Preferences.showTabHierarchyInMainPanel || Preferences.groupTabsInSortOrder
        let visibleWindowIds = needsTabInfo ? TabHierarchy.visibleWindowIds(in: Spaces.screenSpacesMap.values.flatMap { $0 }) : Set<CGWindowID>()
        let tabParentMap: [CGWindowID: CGWindowID] = needsTabInfo ? TabHierarchy.queryAXTabGroups(windows, visibleWindowIds: visibleWindowIds) : [:]
        if needsTabInfo {
            TabHierarchy.applyParentMap(tabParentMap, to: windows)
        }
        let groupCreationKeys: [CGWindowID: Int]
        if Preferences.groupTabsInSortOrder {
            groupCreationKeys = TabHierarchy.groupSortKeys(windows, tabParentMap: tabParentMap, keyPath: \.creationOrder)
        } else {
            groupCreationKeys = [:]
        }

        var allScreenData = [ScreenColumnData]()
        var sidePanelResults = [(ScreenUuid, (groups: [[Window]], selectedWindowId: CGWindowID?, isActiveScreen: Bool, currentSpaceGroupIndex: Int?, spaceIndexes: [SpaceIndex], spaceIds: [CGSSpaceID]))]()

        // sort screens left-to-right; ties broken top-to-bottom (higher Quartz Y = physically higher)
        let sortedScreens = NSScreen.screens.sorted { a, b in
            if a.frame.origin.x != b.frame.origin.x {
                return a.frame.origin.x < b.frame.origin.x
            }
            return a.frame.origin.y > b.frame.origin.y
        }

        for screen in sortedScreens {
            guard let screenUuid = screen.cachedUuid() else { continue }

            // side panel data (uses side panel pref)
            let sidePanelResult = buildScreenGroups(screenUuid: screenUuid, windowByCgId: windowByCgId, panelWindowNumbers: panelWindowNumbers, showTabHierarchy: Preferences.showTabHierarchyInSidePanel, tabParentMap: tabParentMap, visibleWindowIds: visibleWindowIds, groupCreationKeys: groupCreationKeys)
            sidePanelResults.append((screenUuid, sidePanelResult))

            // main panel data (uses main panel pref)
            let screenName: String
            if #available(macOS 10.15, *) {
                screenName = screen.localizedName
            } else {
                let index = NSScreen.screens.firstIndex(of: screen).map { $0 + 1 } ?? 0
                screenName = "Screen \(index)"
            }
            let wpResult = buildScreenGroups(screenUuid: screenUuid, windowByCgId: windowByCgId, panelWindowNumbers: panelWindowNumbers, showTabHierarchy: Preferences.showTabHierarchyInMainPanel, tabParentMap: tabParentMap, visibleWindowIds: visibleWindowIds, groupCreationKeys: groupCreationKeys)
            allScreenData.append(ScreenColumnData(
                screenName: screenName,
                screenId: screenUuid as String,
                groups: wpResult.groups,
                selectedWindowId: wpResult.selectedWindowId,
                isActiveScreen: wpResult.isActiveScreen,
                currentSpaceGroupIndex: wpResult.currentSpaceGroupIndex,
                showTabHierarchy: Preferences.showTabHierarchyInMainPanel,
                spaceIndexes: wpResult.spaceIndexes,
                spaceIds: wpResult.spaceIds
            ))
        }

        return (allScreenData, sidePanelResults)
    }

    private func buildScreenGroups(
        screenUuid: ScreenUuid,
        windowByCgId: [CGWindowID: Window],
        panelWindowNumbers: Set<Int>,
        showTabHierarchy: Bool,
        tabParentMap: [CGWindowID: CGWindowID],
        visibleWindowIds: Set<CGWindowID>,
        groupCreationKeys: [CGWindowID: Int]
    ) -> (groups: [[Window]], selectedWindowId: CGWindowID?, isActiveScreen: Bool, currentSpaceGroupIndex: Int?, spaceIndexes: [SpaceIndex], spaceIds: [CGSSpaceID]) {
        let screenSpaces = Spaces.screenSpacesMap[screenUuid] ?? []

        // sort spaces in fixed Mission Control order (space 1 on top)
        let sortedSpaces = screenSpaces.sorted { a, b in
            let ai = Spaces.idsAndIndexes.first { $0.0 == a }?.1 ?? Int.max
            let bi = Spaces.idsAndIndexes.first { $0.0 == b }?.1 ?? Int.max
            return ai < bi
        }

        let currentSpaceId = Spaces.currentSpaceForScreen[screenUuid]

        let showTabs = showTabHierarchy

        // per-space grouping
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
                    let isTab = showTabs && tabParentMap[wid] != nil && !visibleWindowIds.contains(wid)
                    let dominated = seen.contains(wid)
                        || window.isWindowlessApp
                        || window.isMinimized
                        || window.isHidden
                        || (!isVisible && !isTab)
                        || self.isExcluded(window)
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
                       !visibleWindowIds.contains(childWid),
                       let window = windowByCgId[childWid],
                       !self.isExcluded(window),
                       !panelWindowNumbers.contains(Int(childWid)) {
                        group.append(window)
                    }
                }
            }
            var sorted = group.sorted { w0, w1 in
                let k0 = w0.cgWindowId.flatMap { groupCreationKeys[$0] } ?? w0.creationOrder
                let k1 = w1.cgWindowId.flatMap { groupCreationKeys[$0] } ?? w1.creationOrder
                if k0 != k1 { return k0 > k1 }
                return w0.creationOrder > w1.creationOrder
            }
            if showTabs {
                sorted = TabHierarchy.orderWithTabHierarchy(sorted)
            }
            for w in sorted { seen.insert(w.cgWindowId!) }
            groups.append(sorted)
        }

        // Remove fullscreen spaces with no visible windows — they render as
        // unnecessary "(empty)" rows in the panels.
        var filteredGroups = [[Window]]()
        var filteredSpaceIds = [CGSSpaceID]()
        for (i, spaceId) in sortedSpaces.enumerated() {
            if groups[i].isEmpty && Spaces.isFullscreenSpace(spaceId) {
                continue
            }
            filteredGroups.append(groups[i])
            filteredSpaceIds.append(spaceId)
        }

        let currentSpaceGroupIndex: Int? = currentSpaceId.flatMap { csId in
            filteredSpaceIds.firstIndex(of: csId)
        }

        // find per-screen "selected" window: lowest lastFocusOrder in the current space only
        var selectedWindowId: CGWindowID? = nil
        var lowestFocusOrder = Int.max
        if let csgi = currentSpaceGroupIndex, csgi < filteredGroups.count {
            for window in filteredGroups[csgi] {
                if window.lastFocusOrder < lowestFocusOrder {
                    lowestFocusOrder = window.lastFocusOrder
                    selectedWindowId = window.cgWindowId
                }
            }
        }
        let isActiveScreen = lowestFocusOrder == 0

        let spaceIndexes = filteredSpaceIds.map { spaceId in
            Spaces.idsAndIndexes.first { $0.0 == spaceId }?.1 ?? 0
        }

        return (groups: filteredGroups, selectedWindowId: selectedWindowId, isActiveScreen: isActiveScreen, currentSpaceGroupIndex: currentSpaceGroupIndex, spaceIndexes: spaceIndexes, spaceIds: filteredSpaceIds)
    }

    // MARK: - CLI: panel contents snapshot

    /// Serialize the same grouped window data that both panels display, for CLI diagnostic output.
    /// Calls computeAllScreenData() — the same pipeline as refreshPanelsNow().
    func snapshotPanelContents() -> [PanelScreenSnapshot] {
        let (allScreenData, _) = computeAllScreenData()
        return allScreenData.map { data in
            let spaceGroups = data.groups.enumerated().map { (groupIdx, windows) -> PanelSpaceGroup in
                let spaceIndex = groupIdx < data.spaceIndexes.count ? data.spaceIndexes[groupIdx] : 0
                let spaceId = groupIdx < data.spaceIds.count ? data.spaceIds[groupIdx] : 0
                let windowEntries = windows.map { w -> PanelWindowEntry in
                    PanelWindowEntry(
                        windowId: w.cgWindowId,
                        title: w.title,
                        appName: w.application.localizedName,
                        pid: w.application.pid,
                        parentWindowId: w.parentWindowId == 0 ? nil : w.parentWindowId,
                        isFullscreen: w.isFullscreen,
                        lastFocusOrder: w.lastFocusOrder,
                        creationOrder: w.creationOrder,
                        isSelected: w.cgWindowId == data.selectedWindowId
                    )
                }
                return PanelSpaceGroup(
                    spaceIndex: spaceIndex,
                    spaceId: spaceId,
                    isFullscreenSpace: Spaces.isFullscreenSpace(spaceId),
                    isCurrentSpace: data.currentSpaceGroupIndex == groupIdx,
                    windows: windowEntries
                )
            }
            return PanelScreenSnapshot(
                screenName: data.screenName,
                screenId: data.screenId,
                isActiveScreen: data.isActiveScreen,
                spaces: spaceGroups
            )
        }
    }

    struct PanelScreenSnapshot: Codable {
        var screenName: String
        var screenId: String
        var isActiveScreen: Bool
        var spaces: [PanelSpaceGroup]
    }

    struct PanelSpaceGroup: Codable {
        var spaceIndex: SpaceIndex
        var spaceId: CGSSpaceID
        var isFullscreenSpace: Bool
        var isCurrentSpace: Bool
        var windows: [PanelWindowEntry]
    }

    struct PanelWindowEntry: Codable {
        var windowId: CGWindowID?
        var title: String
        var appName: String?
        var pid: Int32
        var parentWindowId: CGWindowID?
        var isFullscreen: Bool
        var lastFocusOrder: Int
        var creationOrder: Int
        var isSelected: Bool
    }

    // MARK: - Exceptions

    private func exceptions() -> [ExceptionEntry] {
        if let resolved = resolvedExceptions { return resolved }
        // read from main AltTab's preferences domain (sidepanel has its own bundle id)
        var entries = Preferences.exceptions
        if let mainDefaults = UserDefaults(suiteName: Self.mainAltTabBundleId),
           let json = mainDefaults.string(forKey: "exceptions"),
           let data = json.data(using: .utf8),
           let mainEntries = try? JSONDecoder().decode([ExceptionEntry].self, from: data) {
            // merge: main AltTab entries take precedence, add any not already present
            let existingIds = Set(entries.map { $0.bundleIdentifier })
            for entry in mainEntries where !existingIds.contains(entry.bundleIdentifier) {
                entries.append(entry)
            }
        }
        resolvedExceptions = entries
        return entries
    }

    private func isExcluded(_ window: Window) -> Bool {
        guard let bundleId = window.application.bundleIdentifier else { return false }
        return exceptions().contains { entry in
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

    /// Window numbers for overlay panels only (SidePanels).
    /// MainPanel is a full-citizen window and participates in Windows.list.
    func allWindowNumbers() -> Set<Int> {
        Set(panels.values.map { $0.windowNumber })
    }

    // MARK: - CGWindowList Audit

    /// Uses CGWindowListCopyWindowInfo to find windows the Window Server knows about
    /// but AltTab's Windows.list doesn't. For apps with missing windows, triggers
    /// manuallyUpdateWindows() to re-scan via AX.
    private func discoverMissingWindows() {
        let windowInfoList = CGWindow.windows(.optionAll)

        // our own panel windows to exclude
        let panelWindowNumbers = allWindowNumbers()
        let tilesWindowNumber = TilesPanel.shared.windowNumber

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
                Applications.manuallyUpdateWindows(app)
            }
        }
    }
}
