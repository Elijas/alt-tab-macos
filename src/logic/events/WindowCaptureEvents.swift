import Cocoa
import ScreenCaptureKit

fileprivate struct ScreenshotWindowSnapshot {
    let cgWindowId: CGWindowID
    let size: CGSize
    let scaleFactor: CGFloat
    let debugId: String
    let previewSelectedWindow: Bool
    let maxThumbnailSize: NSSize
}

@available(macOS 14.0, *)
class WindowCaptureScreenshots {
    // SCShareableContent.getExcludingDesktopWindows is expensive for the OS; we cache as much as possible
    static var cachedSCWindows = [SCWindow]()

    static func oneTimeScreenshots(_ windowsToScreenshot: [Window], _ source: RefreshCausedBy) {
        let (windows, snapshots) = windowSnapshots(windowsToScreenshot)
        guard !windows.isEmpty else { return }
        BackgroundWork.screenshotsQueue.addOperation {
            guard source != .refreshOnlyThumbnailsAfterShowUi || App.appIsBeingUsed else { return }
            let (cachedWindows, notCachedWindows) = sortCachedAndNotCached(windows)
            Logger.debug { "cached:\(cachedWindows.map { $0.windowID }) notCached:\(notCachedWindows)" }
            handleCachedWindows(cachedWindows, source, snapshots)
            handleNotCachedWindows(notCachedWindows, source, snapshots)
        }
    }

    private static func windowSnapshots(_ windowsToScreenshot: [Window]) -> ([CGWindowID], [CGWindowID: ScreenshotWindowSnapshot]) {
        if Thread.isMainThread {
            return makeWindowSnapshots(windowsToScreenshot)
        }
        return DispatchQueue.main.sync {
            makeWindowSnapshots(windowsToScreenshot)
        }
    }

    private static func makeWindowSnapshots(_ windowsToScreenshot: [Window]) -> ([CGWindowID], [CGWindowID: ScreenshotWindowSnapshot]) {
        var windows = [CGWindowID]()
        var snapshots = [CGWindowID: ScreenshotWindowSnapshot]()
        let previewSelectedWindow = Preferences.previewSelectedWindow
        let maxThumbnailSize = TilesPanel.maxPossibleThumbnailSize
        for window in windowsToScreenshot {
            guard let cgWindowId = window.cgWindowId, let size = window.size else { continue }
            windows.append(cgWindowId)
            snapshots[cgWindowId] = ScreenshotWindowSnapshot(cgWindowId: cgWindowId, size: size, scaleFactor: scaleFactor(for: window.screenId), debugId: window.debugId, previewSelectedWindow: previewSelectedWindow, maxThumbnailSize: maxThumbnailSize)
        }
        return (windows, snapshots)
    }

    private static func scaleFactor(for screenId: ScreenUuid?) -> CGFloat {
        if let screenId,
           let screen = Screens.all[screenId] {
            return screen.backingScaleFactor
        }
        return NSScreen.preferred.backingScaleFactor
    }

    private static func handleCachedWindows(_ cachedWindows: [SCWindow], _ source: RefreshCausedBy, _ snapshots: [CGWindowID: ScreenshotWindowSnapshot]) {
        guard !cachedWindows.isEmpty else { return }
        for cachedWindow in cachedWindows {
            oneTimeCapture(cachedWindow, source, snapshots[cachedWindow.windowID])
        }
    }

    private static func handleNotCachedWindows(_ notCachedWindows: [CGWindowID], _ source: RefreshCausedBy, _ snapshots: [CGWindowID: ScreenshotWindowSnapshot]) {
        guard !notCachedWindows.isEmpty else { return }
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
            guard let shareableContent, error == nil else { Logger.error { "\(shareableContent == nil) \(error)" }; return }
            guard source != .refreshOnlyThumbnailsAfterShowUi || App.appIsBeingUsed else { return }
            // this callback is executed on an undetermined queue; we move execution to main-thread
            BackgroundWork.screenshotsQueue.addOperation {
                cachedSCWindows = shareableContent.windows
                guard source != .refreshOnlyThumbnailsAfterShowUi || App.appIsBeingUsed else { return }
                for notCachedWindow in notCachedWindows {
                    if let cachedWindow = (cachedSCWindows.first { $0.windowID == notCachedWindow }) {
                        oneTimeCapture(cachedWindow, source, snapshots[notCachedWindow])
                    } else {
                        Logger.debug { "wid:\(notCachedWindow) was not found in SCShareableContent windows" }
                    }
                }
            }
        }
    }

    private static func sortCachedAndNotCached(_ windows: [CGWindowID]) -> ([SCWindow], [CGWindowID]) {
        var cachedWindows = [SCWindow]()
        var notCachedWindows = [CGWindowID]()
        for window in windows {
            if let cachedWindow = (cachedSCWindows.first { $0.windowID == window }) {
                cachedWindows.append(cachedWindow)
            } else {
                notCachedWindows.append(window)
            }
        }
        return (cachedWindows, notCachedWindows)
    }

    private static func oneTimeCapture(_ scWindow: SCWindow, _ source: RefreshCausedBy, _ snapshot: ScreenshotWindowSnapshot?) {
        guard !App.isTerminating, let snapshot else { return }
        let config = SCStreamConfiguration.forWindow(scWindow, snapshot, false)
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        ActiveWindowCaptures.increment()
        SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config) { sampleBuffer, error in
            ActiveWindowCaptures.decrement()
            guard let sampleBuffer, error == nil else { Logger.error { "\(snapshot.debugId) \(sampleBuffer == nil) \(error)" }; return }
            guard source != .refreshOnlyThumbnailsAfterShowUi || App.appIsBeingUsed else { return }
            let pixelBuffer: CVPixelBuffer? = sampleBuffer.pixelBuffer() ?? sampleBuffer.imageBuffer
            guard let pixelBuffer else { Logger.error { "\(snapshot.debugId) no pixelBuffer" }; return }
            DispatchQueue.main.async {
                guard source != .refreshOnlyThumbnailsAfterShowUi || App.appIsBeingUsed else { return }
                if let window = (Windows.list.first { $0.cgWindowId == snapshot.cgWindowId }) {
                    window.refreshThumbnail(.pixelBuffer(pixelBuffer))
                }
            }
        }
    }
}

class WindowCaptureScreenshotsPrivateApi {
    static func oneTimeScreenshots(_ eligibleWindows: [Window], _ source: RefreshCausedBy) {
        for window in eligibleWindows {
            BackgroundWork.screenshotsQueue.addOperation { [weak window] in
                guard source != .refreshOnlyThumbnailsAfterShowUi || App.appIsBeingUsed else { return }
                guard let wid = window?.cgWindowId, let cgImage = oneTimeCapture(wid) else { return }
                guard source != .refreshOnlyThumbnailsAfterShowUi || App.appIsBeingUsed else { return }
                DispatchQueue.main.async { [weak window] in
                    guard source != .refreshOnlyThumbnailsAfterShowUi || App.appIsBeingUsed else { return }
                    window?.refreshThumbnail(.cgImage(cgImage))
                }
            }
        }
    }

    private static func oneTimeCapture(_ wid: CGWindowID) -> CGImage? {
        guard !App.isTerminating else { return nil }
        // we use CGSHWCaptureWindowList because it can screenshot minimized windows, which CGWindowListCreateImage can't
        var windowId_ = wid
        ActiveWindowCaptures.increment()
        let list = CGSHWCaptureWindowList(CGS_CONNECTION, &windowId_, 1, [.ignoreGlobalClipShape, .bestResolution, .fullSize]).takeRetainedValue() as! [CGImage]
        ActiveWindowCaptures.decrement()
        return list.first
    }
}

// @available(macOS 12.3, *)
// class WindowCaptureVideos {
//     private static var streams = [CGWindowID: SCStream]()
//     private static var streamOutputs = [CGWindowID: StreamOutput]()
//     // SCStream.backgroundColor is [unowned], so we must keep own these variables
//     static let scStreamBackgroundColorDark = NSColor(white: 0.23, alpha: 1).cgColor
//     static let scStreamBackgroundColorLight = NSColor.white.cgColor
//
//     static func startCapturing(_ windowsWhichMayHaveChanged: [Window]) {
//         let windowsToShow = Set<CGWindowID>(Windows.list.filter { !$0.isWindowlessApp && $0.shouldShowTheUser }.compactMap { $0.cgWindowId })
//         let windowsAlreadyStreaming = Set<CGWindowID>(streams.keys)
//         let windowsToStop = windowsAlreadyStreaming.subtracting(windowsToShow)
//         stopCaptures(windowsToStop)
//         let windowsToStart = windowsToShow.subtracting(windowsAlreadyStreaming)
//         let windowsWhichMayHaveChanged_ = windowsWhichMayHaveChanged.compactMap { $0.cgWindowId }
//         if !windowsToStart.isEmpty || !windowsWhichMayHaveChanged_.isEmpty {
//             SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
//                 guard let shareableContent, error == nil else {
//                     Logger.error { "\(shareableContent == nil) \(error)" }
//                     return
//                 }
//                 // this callback is executed on an undetermined queue
//                 // we move execution to main-thread to avoid races with starting/stopping streams and the app being shown/hidden
//                 DispatchQueue.main.async {
//                     guard App.appIsBeingUsed else { return }
//                     startCaptures(windowsToStart, shareableContent)
//                     updateCaptures(windowsWhichMayHaveChanged_, shareableContent)
//                     Logger.debug { streams.keys }
//                 }
//             }
//         }
//     }
//
//     static func stopCapturing() {
//         Logger.debug { streams.keys }
//         for stream in streams.values {
//             stream.stopCapture()
//         }
//         streams.removeAll()
//         streamOutputs.removeAll()
//     }
//
//     private static func updateCaptures(_ windowsWhichMayHaveChanged: [CGWindowID], _ shareableContent: SCShareableContent) {
//         for wid in windowsWhichMayHaveChanged {
//             if let stream = streams[wid],
//                let scWindow = shareableContent.windows.first(where: { $0.windowID == wid }) {
//                 stream.updateConfiguration(SCStreamConfiguration.forWindow(scWindow, true)) { error in
//                     if let error { Logger.error { error } }
//                 }
//             }
//         }
//     }
//
//     private static func startCaptures(_ windowsToStart: Set<CGWindowID>, _ shareableContent: SCShareableContent) {
//         for wid in windowsToStart {
//             if let scWindow = shareableContent.windows.first(where: { $0.windowID == wid }) {
//                 startCapture(scWindow)
//             }
//         }
//     }
//
//
//     private static func startCapture(_ window: SCWindow) {
//         let wid = window.windowID
//         let output = StreamOutput(wid)
//         let config = SCStreamConfiguration.forWindow(window, true)
//         let filter = SCContentFilter(desktopIndependentWindow: window)
//         let stream = SCStream(filter: filter, configuration: config, delegate: output)
//         do {
//             try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: BackgroundWork.screenshotsQueue.strongUnderlyingQueue)
//             stream.startCapture { error in
//                 if let error { Logger.error { error } }
//             }
//             streams[wid] = stream
//             streamOutputs[wid] = output
//         } catch {
//             Logger.error { error }
//         }
//     }
//
//     private static func stopCaptures(_ windowsToStop: Set<CGWindowID>) {
//         for wid in windowsToStop {
//             stopCapture(wid)
//         }
//     }
//
//     private static func stopCapture(_ wid: CGWindowID) {
//         if let stream = streams[wid] {
//             stream.stopCapture()
//             streams.removeValue(forKey: wid)
//             streamOutputs.removeValue(forKey: wid)
//         }
//     }
//
//     class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
//         let wid: CGWindowID
//
//         init(_ wid: CGWindowID) {
//             self.wid = wid
//         }
//
//         // from SCStreamOutput; handle captured samples
//         func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
//             BackgroundWork.screenshotsQueue.trackCallbacks {
//                 if sampleBuffer.isValid,
//                    let pixelBuffer = sampleBuffer.pixelBuffer() {
//                     DispatchQueue.main.async {
//                         if let window = (Windows.list.first { $0.cgWindowId == self.wid }) {
//                             window.refreshThumbnail(.pixelBuffer(pixelBuffer))
//                         }
//                     }
//                 }
//             }
//         }
//
//         // from SCStreamDelegate; handle errors when opening a stream
//         func stream(_ stream: SCStream, didStopWithError error: any Error) {
//             BackgroundWork.screenshotsQueue.trackCallbacks {
//                 Logger.error { error }
//             }
//         }
//     }
// }

@available(macOS 12.3, *)
extension SCStreamConfiguration {
    fileprivate static func forWindow(_ scWindow: SCWindow, _ snapshot: ScreenshotWindowSnapshot, _ video: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.setWindowSize(scWindow, snapshot)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        // if video {
        //     config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(60))
        //     config.queueDepth = 8
        //     // ~60% memory reduction compared to kCVPixelFormatType_32BGRA
        //     config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        //     // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange doesn't have transparency, so we end up with an opaque background color around the window corners
        //     // we use a background color that try and hide these corners as much as possible
        //     config.backgroundColor = Appearance.currentTheme == .dark ? WindowCaptureVideos.scStreamBackgroundColorDark : WindowCaptureVideos.scStreamBackgroundColorLight
        // }
        // config.scalesToFit = true
        return config
    }

    private func setWindowSize(_ scWindow: SCWindow, _ snapshot: ScreenshotWindowSnapshot) {
        let size = snapshot.size
        // window.size shows logical size. It doesn't change when the scaleFactor changes. We need to correct for this as we need to capture more and less pixels depending on DPI
        let originalSize = NSSize(width: size.width * snapshot.scaleFactor, height: size.height * snapshot.scaleFactor)
        guard originalSize.width > 0, originalSize.height > 0 else { return }
        if snapshot.previewSelectedWindow {
            width = Int(originalSize.width)
            height = Int(originalSize.height)
        } else {
            // capture screenshots as small as needed for the thumbnails
            let maxSize = snapshot.maxThumbnailSize
            guard maxSize.width > 0, maxSize.height > 0 else { return }
            let scale = min(1.0, maxSize.width / originalSize.width, maxSize.height / originalSize.height)
            width = Int((originalSize.width * scale).rounded())
            height = Int((originalSize.height * scale).rounded())
        }
    }
}

extension CMSampleBuffer {
    @available(macOS 12.3, *)
    func pixelBuffer() -> CVPixelBuffer? {
        if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let attachments = attachmentsArray.first,
           let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRawValue),
           status == .complete || status == .started { // new frame was generated
            return imageBuffer
        }
        return nil
    }

    @available(macOS 12.3, *)
    func metalTexture(_ device: MTLDevice) -> MTLTexture? {
        guard let pixelBuffer = pixelBuffer(),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            mipmapped: false
        )
        return device.makeTexture(descriptor: desc, iosurface: surface, plane: 0)
    }
}

class ActiveWindowCaptures {
    private static var _count: Int32 = 0

    static func increment() { OSAtomicIncrement32(&_count) }
    static func decrement() { OSAtomicDecrement32(&_count) }
    static func value() -> Int { Int(OSAtomicAdd32(0, &_count)) }
}
