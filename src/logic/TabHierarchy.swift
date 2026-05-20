import Cocoa

/// Fork-only tab hierarchy and group sort logic.
/// Extracted from Windows.swift to minimize merge conflicts with upstream.
/// Upstream uses TabGroup.swift for event-driven tab detection (peer-based, tabbedSiblingWids).
/// This class provides parent→child hierarchy for the fork's side panel, main panel indentation,
/// group-aware sorting, and CLI --debug-tabs diagnostic.
class TabHierarchy {
    // Group-aware sort keys: tab group members share min(key) across group
    static var groupLastFocusKeys = [CGWindowID: Int]()
    static var groupCreationKeys = [CGWindowID: Int]()
    // Last computed parent map (child→parent), for access by Windows.updatesBeforeShowing
    static var lastParentMap = [CGWindowID: CGWindowID]()
    private static var cachedParentMap = [CGWindowID: CGWindowID]()
    private static var cachedParentMapTimes = [CGWindowID: UInt64]()
    private static let cachedParentMaxAgeNs: UInt64 = 30_000_000_000

    /// Main entry point: compute tab groups and group sort keys for the given window list.
    /// Called from Windows.updatesBeforeShowing() before sort().
    static func computeAndApply(_ windows: [Window]) {
        let visibleWindowIds = visibleWindowIds(for: windows)
        let freshParentMap = queryAXTabGroups(windows, visibleWindowIds: visibleWindowIds)
        let parentMap = stableParentMap(freshParentMap, windows: windows, visibleWindowIds: visibleWindowIds)
        lastParentMap = parentMap
        if Preferences.groupTabsInSortOrder {
            groupLastFocusKeys = groupSortKeys(windows, tabParentMap: parentMap, keyPath: \.lastFocusOrder)
            groupCreationKeys = groupSortKeys(windows, tabParentMap: parentMap, keyPath: \.creationOrder)
        } else {
            groupLastFocusKeys.removeAll()
            groupCreationKeys.removeAll()
        }
    }

    static func stableParentMap(
        _ parentMap: [CGWindowID: CGWindowID],
        windows: [Window],
        visibleWindowIds: Set<CGWindowID>
    ) -> [CGWindowID: CGWindowID] {
        var result = parentMap
        let fallbackParentMap = eventDrivenParentIds(windows, visibleWindowIds: visibleWindowIds)
        for (childWid, parentWid) in fallbackParentMap where result[childWid] == nil {
            result[childWid] = parentWid
        }
        result = mergeCachedParentMap(result, windows: windows, visibleWindowIds: visibleWindowIds)
        lastParentMap = result
        return result
    }

    static func applyParentMap(_ parentMap: [CGWindowID: CGWindowID], to windows: [Window]) {
        for window in windows {
            guard let wid = window.cgWindowId else { continue }
            window.parentWindowId = parentMap[wid] ?? 0
        }
    }

    /// Look up group-aware lastFocusOrder; falls back to window's own value.
    static func effectiveLastFocusOrder(_ window: Window) -> Int {
        if let wid = window.cgWindowId, let key = groupLastFocusKeys[wid] {
            return key
        }
        return window.lastFocusOrder
    }

    /// Look up group-aware creationOrder; falls back to window's own value.
    static func effectiveCreationOrder(_ window: Window) -> Int {
        if let wid = window.cgWindowId, let key = groupCreationKeys[wid] {
            return key
        }
        return window.creationOrder
    }

    // MARK: - Tab group queries

    /// Old heuristic tab detection using CGS visible-window lists.
    /// Kept for --debug-tabs diagnostic (comparing heuristic vs event-driven TabGroup).
    /// NOT used in the main UI path — upstream's event-driven TabGroup.updateState() is better.
    static func heuristicIsTabbed(_ window: Window, _ cgsWindowIds: [CGWindowID], _ visibleCgsWindowIds: [CGWindowID]) -> Bool {
        guard let cgWindowId = window.cgWindowId else { return false }
        if window.isMinimized || window.isHidden {
            if #available(macOS 13.0, *) {
                // not exact after window merging
                return !cgsWindowIds.contains(cgWindowId)
            }
            // not known
            return false
        }
        return !visibleCgsWindowIds.contains(cgWindowId)
    }

    /// Infers tab parent-child relationships from the isTabbed flag.
    /// Groups windows by PID: tabbed (invisible) windows are children of
    /// the non-tabbed (visible) window with the lowest lastFocusOrder in the same app.
    static func inferTabParentIds(_ windows: [Window]) -> [CGWindowID: CGWindowID] {
        var result = [CGWindowID: CGWindowID]()
        var byPid = [pid_t: [Window]]()
        for window in windows {
            guard let _ = window.cgWindowId else { continue }
            byPid[window.application.pid, default: []].append(window)
        }
        for (_, appWindows) in byPid {
            let visible = appWindows.filter { !$0.isTabbed && !$0.isWindowlessApp }
            let tabbed = appWindows.filter { $0.isTabbed }
            guard !tabbed.isEmpty else { continue }
            guard let parent = visible.min(by: { $0.lastFocusOrder < $1.lastFocusOrder }),
                  let parentWid = parent.cgWindowId else { continue }
            for child in tabbed {
                if let childWid = child.cgWindowId {
                    result[childWid] = parentWid
                }
            }
        }
        return result
    }

    /// Query AX tab groups on visible windows to build child→parent mapping.
    /// Walks each visible window's AXChildren for AXTabGroup, reads tab titles,
    /// then matches any window by (PID, title). Does NOT depend on isTabbed flag
    /// since that requires the CGS heuristic which the side panel path doesn't call.
    /// On title collision across tab groups, skip the ambiguous title rather than assigning it to the wrong parent.
    static func queryAXTabGroups(_ windows: [Window], visibleWindowIds providedVisibleWindowIds: Set<CGWindowID>? = nil) -> [CGWindowID: CGWindowID] {
        var result = [CGWindowID: CGWindowID]()
        let visibleWindowIds = providedVisibleWindowIds ?? visibleWindowIds(for: windows)
        // forward map: "pid:title" → parentWids (from visible windows' AX tab groups)
        var titleToParents = [String: Set<CGWindowID>]()
        // collect which wids are "parent" windows (have an AXTabGroup)
        var parentWids = Set<CGWindowID>()
        for window in windows {
            guard let axElement = window.axUiElement,
                  let wid = window.cgWindowId,
                  visibleWindowIds.contains(wid),
                  let childrenAttrs = try? axElement.attributes([kAXChildrenAttribute]),
                  let children = childrenAttrs.children else { continue }
            for child in children {
                guard let childRole = try? child.attributes([kAXRoleAttribute]),
                      childRole.role == "AXTabGroup",
                      let tgChildren = try? child.attributes([kAXChildrenAttribute]),
                      let tabs = tgChildren.children else { continue }
                parentWids.insert(wid)
                for tab in tabs {
                    let keys = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute]
                    guard let tabAttrs = try? tab.attributes(keys),
                          tabAttrs.role == "AXRadioButton" || tabAttrs.subrole == "AXTabButton",
                          let title = tabAttrs.title, !title.isEmpty else { continue }
                    let key = "\(window.application.pid):\(title)"
                    titleToParents[key, default: []].insert(wid)
                }
            }
        }
        // match windows by (pid, title) — a window is a tab child if its title
        // appears in a parent's AXTabGroup and it's not the parent itself
        for window in windows {
            guard let wid = window.cgWindowId,
                  !parentWids.contains(wid),
                  !visibleWindowIds.contains(wid) else { continue }
            let title = window.title ?? ""
            guard !title.isEmpty else { continue }
            let key = "\(window.application.pid):\(title)"
            if let parentWids = titleToParents[key],
               parentWids.count == 1,
               let parentWid = parentWids.first {
                result[wid] = parentWid
            }
        }

        // Fullscreen fallback: when a fullscreen window has no AXTabGroup (AX hierarchy
        // restructures in native fullscreen), find same-PID "orphan" windows with no space
        // assignment — these are inactive tabs that CGS doesn't place on any space.
        let alreadyMapped = Set(result.keys).union(parentWids)
        // Index: PID → fullscreen visible windows (candidate parents)
        var fullscreenParentsByPid = [pid_t: [Window]]()
        for window in windows {
            guard let wid = window.cgWindowId,
                  !alreadyMapped.contains(wid),
                  !parentWids.contains(wid),
                  visibleWindowIds.contains(wid),
                  window.spaceIds.contains(where: { Spaces.isFullscreenSpace($0) }) else { continue }
            fullscreenParentsByPid[window.application.pid, default: []].append(window)
        }
        if !fullscreenParentsByPid.isEmpty {
            for window in windows {
                guard let wid = window.cgWindowId,
                      !alreadyMapped.contains(wid),
                      !parentWids.contains(wid),
                      !visibleWindowIds.contains(wid),
                      result[wid] == nil,
                      window.spaceIds.allSatisfy({ $0 == CGSSpaceID.max }),
                      let candidates = fullscreenParentsByPid[window.application.pid],
                      !candidates.isEmpty else { continue }
                let boundsMatched: [Window]
                if let pos = window.position, let sz = window.size {
                    boundsMatched = candidates.filter { candidate in
                        guard let cPos = candidate.position, let cSz = candidate.size else { return false }
                        return abs(pos.x - cPos.x) < 10
                            && abs(sz.width - cSz.width) < 10
                            && abs(pos.y - cPos.y) < 80
                            && abs(sz.height - cSz.height) < 80
                    }
                } else {
                    boundsMatched = []
                }
                guard !boundsMatched.isEmpty else { continue }
                let parent = boundsMatched.min(by: {
                    abs(Int($0.cgWindowId ?? 0) - Int(wid)) < abs(Int($1.cgWindowId ?? 0) - Int(wid))
                })
                if let parentWid = parent?.cgWindowId {
                    result[wid] = parentWid
                }
            }
        }

        return result
    }

    private static func eventDrivenParentIds(
        _ windows: [Window],
        visibleWindowIds: Set<CGWindowID>
    ) -> [CGWindowID: CGWindowID] {
        var windowByWid = [CGWindowID: Window]()
        var result = [CGWindowID: CGWindowID]()
        for window in windows {
            guard let wid = window.cgWindowId else { continue }
            windowByWid[wid] = window
        }
        for window in windows {
            guard let childWid = window.cgWindowId,
                  let siblingWids = window.tabbedSiblingWids,
                  !visibleWindowIds.contains(childWid) else { continue }
            let siblings = siblingWids.compactMap { windowByWid[$0] }
                .filter { $0.application.pid == window.application.pid }
            let parent = siblings.first { sibling in
                guard let siblingWid = sibling.cgWindowId else { return false }
                return siblingWid != childWid && visibleWindowIds.contains(siblingWid) && !sibling.isTabbed
            } ?? siblings.first { sibling in
                guard let siblingWid = sibling.cgWindowId else { return false }
                return siblingWid != childWid && !sibling.isTabbed
            }
            if let parentWid = parent?.cgWindowId {
                result[childWid] = parentWid
            }
        }
        return result
    }

    private static func mergeCachedParentMap(
        _ parentMap: [CGWindowID: CGWindowID],
        windows: [Window],
        visibleWindowIds: Set<CGWindowID>
    ) -> [CGWindowID: CGWindowID] {
        let now = DispatchTime.now().uptimeNanoseconds
        var windowByWid = [CGWindowID: Window]()
        for window in windows {
            guard let wid = window.cgWindowId else { continue }
            windowByWid[wid] = window
        }
        for (childWid, parentWid) in parentMap {
            cachedParentMap[childWid] = parentWid
            cachedParentMapTimes[childWid] = now
        }
        cachedParentMap = cachedParentMap.filter { entry in
            let childWid = entry.key
            let parentWid = entry.value
            guard let childWindow = windowByWid[childWid],
                  let parentWindow = windowByWid[parentWid],
                  let cachedAt = cachedParentMapTimes[childWid],
                  now >= cachedAt,
                  now - cachedAt <= cachedParentMaxAgeNs else { return false }
            return canReuseCachedParent(childWindow, parentWindow, childWid, parentWid, visibleWindowIds)
        }
        cachedParentMapTimes = cachedParentMapTimes.filter { entry in cachedParentMap[entry.key] != nil }
        var result = parentMap
        for (childWid, parentWid) in cachedParentMap where result[childWid] == nil {
            result[childWid] = parentWid
        }
        return result
    }

    private static func canReuseCachedParent(
        _ childWindow: Window,
        _ parentWindow: Window,
        _ childWid: CGWindowID,
        _ parentWid: CGWindowID,
        _ visibleWindowIds: Set<CGWindowID>
    ) -> Bool {
        guard childWindow.application.pid == parentWindow.application.pid,
              childWid != parentWid,
              !visibleWindowIds.contains(childWid) else { return false }
        return true
    }

    static func visibleWindowIds(in spaceIds: [CGSSpaceID]) -> Set<CGWindowID> {
        let spaceIds = Array(Set(spaceIds))
        guard !spaceIds.isEmpty else { return [] }
        return Set(Spaces.windowsInSpaces(spaceIds, false))
    }

    private static func visibleWindowIds(for windows: [Window]) -> Set<CGWindowID> {
        let spaceIds = windows.flatMap { window in
            window.spaceIds.filter { $0 != CGSSpaceID.max }
        }
        return visibleWindowIds(in: spaceIds)
    }

    // MARK: - Group sort keys

    /// Compute group-aware sort keys for tab groups.
    /// Windows in a tab group all get min(keyPath) across group members.
    /// Windows not in any group keep their own value.
    static func groupSortKeys(_ windows: [Window], tabParentMap: [CGWindowID: CGWindowID], keyPath: KeyPath<Window, Int>) -> [CGWindowID: Int] {
        var windowByWid = [CGWindowID: Window]()
        for window in windows {
            guard let wid = window.cgWindowId else { continue }
            windowByWid[wid] = window
        }
        var childrenByParent = [CGWindowID: [Window]]()
        for (childWid, parentWid) in tabParentMap {
            if let childWindow = windowByWid[childWid] {
                childrenByParent[parentWid, default: []].append(childWindow)
            }
        }
        var result = [CGWindowID: Int]()
        for (parentWid, children) in childrenByParent {
            var groupValues = children.map { $0[keyPath: keyPath] }
            if let parentWindow = windowByWid[parentWid] {
                groupValues.append(parentWindow[keyPath: keyPath])
            }
            guard let minVal = groupValues.min() else { continue }
            if windowByWid[parentWid] != nil {
                result[parentWid] = minVal
            }
            for child in children {
                if let wid = child.cgWindowId {
                    result[wid] = minVal
                }
            }
        }
        for window in windows {
            guard let wid = window.cgWindowId else { continue }
            if result[wid] == nil {
                result[wid] = window[keyPath: keyPath]
            }
        }
        return result
    }

    // MARK: - Hierarchy reordering

    /// Returns windows reordered so tab children immediately follow their parent.
    /// Preserves original ordering for root windows and among siblings.
    static func orderWithTabHierarchy(_ windows: [Window]) -> [Window] {
        var childrenByParent = [CGWindowID: [Window]]()
        var rootWindows = [Window]()
        for window in windows {
            if window.isTabChild {
                childrenByParent[window.parentWindowId, default: []].append(window)
            } else {
                rootWindows.append(window)
            }
        }
        var result = [Window]()
        result.reserveCapacity(windows.count)
        for window in rootWindows {
            result.append(window)
            if let wid = window.cgWindowId, let children = childrenByParent.removeValue(forKey: wid) {
                result.append(contentsOf: children)
            }
        }
        // orphans: children whose parent isn't in the list
        for (_, orphans) in childrenByParent {
            result.append(contentsOf: orphans)
        }
        return result
    }
}
