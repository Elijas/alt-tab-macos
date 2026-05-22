import Cocoa

class Spaces {
    static var currentSpaceId = CGSSpaceID(1)
    static var currentSpaceIndex = SpaceIndex(1)
    static var visibleSpaces = [CGSSpaceID]()
    static var currentSpaceForScreen = [ScreenUuid: CGSSpaceID]()
    static var screenSpacesMap = [ScreenUuid: [CGSSpaceID]]()
    static var idsAndIndexes = [(CGSSpaceID, SpaceIndex)]()
    static var fullscreenSpaces = Set<CGSSpaceID>()
    private static var lastPerfFingerprint = 0

    static func isSingleSpace() -> Bool {
        return idsAndIndexes.count == 1
    }

    static func isFullscreenSpace(_ spaceId: CGSSpaceID) -> Bool {
        return fullscreenSpaces.contains(spaceId)
    }

    static func windowsInSpaces(_ spaceIds: [CGSSpaceID], _ includeInvisible: Bool = true) -> [CGWindowID] {
        let span = PerfDebug.start("spaces.windowsInSpaces", fields: ["spaces": spaceIds.count, "include_invisible": includeInvisible])
        var set_tags = ([] as CGSCopyWindowsTags).rawValue
        var clear_tags = ([] as CGSCopyWindowsTags).rawValue
        var options = [.screenSaverLevel1000] as CGSCopyWindowsOptions
        if includeInvisible {
            options = [options, .invisible1, .invisible2]
        }
        let result = CGSCopyWindowsWithOptionsAndTags(CGS_CONNECTION, 0, spaceIds as CFArray, options.rawValue, &set_tags, &clear_tags) as! [CGWindowID]
        span?.finish(["windows": result.count])
        return result
    }

    static func refresh() {
        let oldFingerprint = lastPerfFingerprint
        let span = PerfDebug.start("spaces.refresh", fields: ["old_spaces": idsAndIndexes.count, "old_visible": visibleSpaces.count])
        refreshAllIdsAndIndexes()
        updateCurrentSpace()
        lastPerfFingerprint = perfFingerprint()
        span?.finish(["spaces": idsAndIndexes.count, "screens": screenSpacesMap.count, "visible": visibleSpaces.count, "fullscreen": fullscreenSpaces.count, "changed": oldFingerprint != lastPerfFingerprint])
    }

    private static func updateCurrentSpace() {
        // it seems that in some rare scenarios, some of these values are nil; we wrap to avoid crashing
        if let mainScreen = NSScreen.main,
           let uuid = mainScreen.uuid() {
            currentSpaceId = CGSManagedDisplayGetCurrentSpace(CGS_CONNECTION, uuid)
        }
        currentSpaceIndex = idsAndIndexes.first { (spaceId: CGSSpaceID, _) -> Bool in
            spaceId == currentSpaceId
        }?.1 ?? SpaceIndex(1)
    }

    private static func refreshAllIdsAndIndexes() -> Void {
        idsAndIndexes.removeAll()
        screenSpacesMap.removeAll()
        visibleSpaces.removeAll()
        currentSpaceForScreen.removeAll()
        fullscreenSpaces.removeAll()
        var spaceIndex = SpaceIndex(1)
        (CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as! [NSDictionary]).forEach { (screen: NSDictionary) in
            var display = screen["Display Identifier"] as! ScreenUuid
            if display as String == "Main", let mainUuid = NSScreen.main?.uuid() {
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
    }

    private static func perfFingerprint() -> Int {
        var hash = Int(currentSpaceId)
        for (spaceId, index) in idsAndIndexes {
            hash = hash &* 31 &+ Int(spaceId)
            hash = hash &* 31 &+ index
        }
        for spaceId in visibleSpaces {
            hash = hash &* 31 &+ Int(spaceId)
        }
        return hash
    }
}

typealias SpaceIndex = Int
