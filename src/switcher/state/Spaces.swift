import Cocoa

class Spaces {
    static var currentSpaceId = CGSSpaceID(1)
    static var currentSpaceIndex = SpaceIndex(1)
    static var visibleSpaces = [CGSSpaceID]()
    static var currentSpaceForScreen = [ScreenUuid: CGSSpaceID]()
    static var screenSpacesMap = [ScreenUuid: [CGSSpaceID]]()
    static var idsAndIndexes = [(CGSSpaceID, SpaceIndex)]()
    static var fullscreenSpaces = Set<CGSSpaceID>()

    static func isSingleSpace() -> Bool {
        return idsAndIndexes.count == 1
    }

    static func isFullscreenSpace(_ spaceId: CGSSpaceID) -> Bool {
        return fullscreenSpaces.contains(spaceId)
    }

    static func windowsInSpaces(_ spaceIds: [CGSSpaceID], _ includeInvisible: Bool = true) -> [CGWindowID] {
        var setTags = ([] as CGSCopyWindowsTags).rawValue
        var clearTags = ([] as CGSCopyWindowsTags).rawValue
        var options = [.screenSaverLevel1000] as CGSCopyWindowsOptions
        if includeInvisible {
            options = [options, .invisible1, .invisible2]
        }
        return CGSCopyWindowsWithOptionsAndTags(CGS_CONNECTION, 0, spaceIds as CFArray, options.rawValue, &setTags, &clearTags) as! [CGWindowID]
    }

    /// A point-in-time read of the Space layout + (optionally) per-window membership, gathered entirely
    /// from SkyLight. `query` does all the blocking CGS IPC and touches no main-only state, so it can run
    /// OFF the main thread; `applyTopology` writes the statics on the main thread. `mainScreenUuid` is
    /// captured on main first (`NSScreen.main` is main-only) and threaded through. See #5721: this is what
    /// lets the expensive Space refresh run off the switcher's render path.
    struct Snapshot {
        let managedDisplaySpaces: [NSDictionary]
        let currentSpaceId: CGSSpaceID?
        let windowToSpacesMap: [CGWindowID: [CGSSpaceID]]
        let mainScreenUuid: ScreenUuid?
    }

    static func mainScreenUuid() -> ScreenUuid? {
        return NSScreen.main?.uuid()
    }

    /// OFF-MAIN safe: only CGS calls + pure parsing of their results. `includeWindowMap` adds the per-Space
    /// `windowsInSpaces` fan-out (only the per-window membership refresh needs it).
    static func query(_ mainScreenUuid: ScreenUuid?, includeWindowMap: Bool) -> Snapshot {
        let raw = CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as! [NSDictionary]
        // rare scenario: NSScreen.main is nil → no uuid → keep the previous current Space (nil here)
        let current = mainScreenUuid.map { CGSManagedDisplayGetCurrentSpace(CGS_CONNECTION, $0) }
        var map = [CGWindowID: [CGSSpaceID]]()
        if includeWindowMap {
            // one query per Space, inverted, so N per-window CGSCopySpacesForWindows calls become M per-Space calls
            let allSpaceIds = raw.flatMap { ($0["Spaces"] as! [NSDictionary]).map { $0["id64"] as! CGSSpaceID } }
            for spaceId in allSpaceIds {
                for wid in CGSCallScheduler.windowsInSpaces([spaceId]) {
                    map[wid, default: []].append(spaceId)
                }
            }
        }
        return Snapshot(managedDisplaySpaces: raw, currentSpaceId: current, windowToSpacesMap: map, mainScreenUuid: mainScreenUuid)
    }

    /// MAIN-thread: write the statics from a snapshot. Returns whether topology / visible Spaces / current
    /// Space changed, so callers can skip a re-render when nothing moved.
    @discardableResult
    static func applyTopology(_ s: Snapshot) -> Bool {
        let beforeIds = idsAndIndexes.map { $0.0 }
        let beforeVisible = visibleSpaces
        let beforeCurrent = currentSpaceId
        idsAndIndexes.removeAll()
        screenSpacesMap.removeAll()
        visibleSpaces.removeAll()
        currentSpaceForScreen.removeAll()
        fullscreenSpaces.removeAll()
        var spaceIndex = SpaceIndex(1)
        s.managedDisplaySpaces.forEach { (screen: NSDictionary) in
            var display = screen["Display Identifier"] as! ScreenUuid
            if display as String == "Main", let mainUuid = s.mainScreenUuid {
                display = mainUuid
            }
            (screen["Spaces"] as! [NSDictionary]).forEach { (space: NSDictionary) in
                let spaceId = space["id64"] as! CGSSpaceID
                let spaceType = space["type"] as? Int ?? 0
                if spaceType == 4 {
                    fullscreenSpaces.insert(spaceId)
                }
                idsAndIndexes.append((spaceId, spaceIndex))
                screenSpacesMap[display, default: []].append(spaceId)
                spaceIndex += 1
            }
            let currentSpaceId = (screen["Current Space"] as! NSDictionary)["id64"] as! CGSSpaceID
            visibleSpaces.append(currentSpaceId)
            currentSpaceForScreen[display] = currentSpaceId
        }
        if let current = s.currentSpaceId {
            currentSpaceId = current
        }
        currentSpaceIndex = idsAndIndexes.first { $0.0 == currentSpaceId }?.1 ?? SpaceIndex(1)
        return beforeIds != idsAndIndexes.map { $0.0 } || beforeVisible != visibleSpaces || beforeCurrent != currentSpaceId
    }

    /// MAIN-thread synchronous refresh for the rare reactive callers (Space switch, screen change, launch).
    /// Topology only — the per-window map is refreshed off-main in `Applications.syncSpacesState`.
    static func refresh() {
        applyTopology(query(mainScreenUuid(), includeWindowMap: false))
    }
}

typealias SpaceIndex = Int
