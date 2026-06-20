import Cocoa

class SidePanel: NSPanel {
    private static let buttonBarHeight: CGFloat = 28
    private static let offsetStep: CGFloat = 100
    private static let offsetDefaultsKey = "sidePanelYOffset"
    private static let leftAlignedDefaultsKey = "sidePanelLeftAligned" // legacy global default (pre per-screen)
    private static let leftAlignedScreensKey = "sidePanelLeftAlignedScreens" // JSON [screenUuid: Bool], per-monitor

    // Per-screen left/right alignment, persisted as a JSON map keyed by screen UUID.
    // Falls back to the legacy global default so existing installs keep their current side.
    private static func leftAlignedMap() -> [String: Bool] {
        guard let raw = UserDefaults.standard.string(forKey: leftAlignedScreensKey),
              let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return map
    }

    private static func loadLeftAligned(for uuid: String?) -> Bool {
        let legacyDefault = UserDefaults.standard.bool(forKey: leftAlignedDefaultsKey)
        guard let uuid else { return legacyDefault }
        return leftAlignedMap()[uuid] ?? legacyDefault
    }

    private static func saveLeftAligned(_ value: Bool, for uuid: String?) {
        guard let uuid else { return }
        var map = leftAlignedMap()
        map[uuid] = value
        if let data = try? JSONEncoder().encode(map), let str = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(str, forKey: leftAlignedScreensKey)
        }
    }

    private let listView = WindowListView(separatorHeight: CGFloat(Preferences.sidePanelSeparatorSize), fontSize: CGFloat(Preferences.sidePanelFontSize), minWidth: SidePanelRow.panelWidth)
    let targetScreen: NSScreen
    private let panelRoot = NSView()
    private let panelBody = NSVisualEffectView()
    private let buttonBar = NSStackView()
    private var hideFifteenButton: NSButton!
    private var hideTwoMinutesButton: NSButton!
    private var hideThirtyMinutesButton: NSButton!
    private var lrButton: NSButton!
    private var offButton: NSButton!
    private var buttonBarButtons: [NSButton] = []
    private var panelBodyWidthConstraint: NSLayoutConstraint!
    private var panelBodyLeadingConstraint: NSLayoutConstraint!
    private var panelBodyTrailingConstraint: NSLayoutConstraint!
    private var isMouseInside = false
    private let screenUuidString: String?
    private var isLeftAligned: Bool
    private var isJumpPending = false

    private static var yOffset: CGFloat = {
        let defaults = UserDefaults.standard
        return CGFloat(defaults.float(forKey: offsetDefaultsKey))
    }()

    init(for screen: NSScreen) {
        self.targetScreen = screen
        let uuid = screen.cachedUuid().map { $0 as String }
        self.screenUuidString = uuid
        self.isLeftAligned = SidePanel.loadLeftAligned(for: uuid)
        super.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        backgroundColor = .clear
        isOpaque = false
        collectionBehavior = .canJoinAllSpaces
        level = .floating
        alphaValue = CGFloat(Preferences.sidePanelOpacity) / 100
        setAccessibilitySubrole(.unknown)

        panelRoot.wantsLayer = true
        panelRoot.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = panelRoot

        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        panelRoot.addTrackingArea(trackingArea)

        panelBody.translatesAutoresizingMaskIntoConstraints = false
        panelBody.material = .sidebar  // KNOWN UNKNOWN: .sidebar vs .hudWindow - depends on final visual design
        panelBody.blendingMode = .behindWindow
        panelBody.state = .active
        panelBody.wantsLayer = true
        panelBody.layer?.cornerRadius = 8
        panelRoot.addSubview(panelBody)

        // button bar at bottom
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.orientation = .horizontal
        buttonBar.alignment = .centerY
        buttonBar.distribution = .gravityAreas
        buttonBar.spacing = 4
        buttonBar.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        panelBody.addSubview(buttonBar)

        hideFifteenButton = makeButton(hideButtonTitle("15s"), #selector(hideFifteenSeconds))
        hideTwoMinutesButton = makeButton(hideButtonTitle("2m"), #selector(hideTwoMinutes))
        hideThirtyMinutesButton = makeButton(hideButtonTitle("30m"), #selector(hideThirtyMinutes))
        let downButton = makeButton("▼", #selector(shiftOffsetDown))
        let upButton = makeButton("▲", #selector(shiftOffsetUp))
        lrButton = makeButton(isLeftAligned ? "▶" : "◀", #selector(toggleLeftRight))
        offButton = makeButton(hideButtonTitle("∞"), #selector(turnOff))
        buttonBarButtons = [downButton, upButton, lrButton, hideFifteenButton, hideTwoMinutesButton, hideThirtyMinutesButton, offButton]

        // list view (shared row/separator layout)
        panelBody.addSubview(listView)

        panelBodyWidthConstraint = panelBody.widthAnchor.constraint(equalToConstant: currentWidth)
        panelBodyLeadingConstraint = panelBody.leadingAnchor.constraint(equalTo: panelRoot.leadingAnchor)
        panelBodyTrailingConstraint = panelBody.trailingAnchor.constraint(equalTo: panelRoot.trailingAnchor)
        NSLayoutConstraint.activate([
            panelBody.topAnchor.constraint(equalTo: panelRoot.topAnchor),
            panelBody.bottomAnchor.constraint(equalTo: panelRoot.bottomAnchor),
            panelBodyWidthConstraint,

            listView.topAnchor.constraint(equalTo: panelBody.topAnchor, constant: 4),
            listView.bottomAnchor.constraint(equalTo: buttonBar.topAnchor),
            listView.leadingAnchor.constraint(equalTo: panelBody.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: panelBody.trailingAnchor),

            buttonBar.bottomAnchor.constraint(equalTo: panelBody.bottomAnchor),
            buttonBar.leadingAnchor.constraint(equalTo: panelBody.leadingAnchor),
            buttonBar.trailingAnchor.constraint(equalTo: panelBody.trailingAnchor),
            buttonBar.heightAnchor.constraint(equalToConstant: Self.buttonBarHeight),
        ])
        applyBodyAlignment()

        buttonBar.isHidden = true
    }

    override var canBecomeKey: Bool { false }

    override func mouseEntered(with event: NSEvent) {
        syncHover(at: NSEvent.mouseLocation)
    }

    override func mouseExited(with event: NSEvent) {
        syncHover(at: NSEvent.mouseLocation)
    }

    private var usesCompactLayout: Bool {
        !isMouseInside
    }

    private var currentWidth: CGFloat {
        usesCompactLayout ? SidePanelRow.compactPanelWidth : SidePanelRow.panelWidth
    }

    private func applyCurrentWidth() {
        panelBodyWidthConstraint.constant = currentWidth
        panelRoot.layoutSubtreeIfNeeded()
        listView.applyIconsOnly(usesCompactLayout)
    }

    private func applyBodyAlignment() {
        panelBodyLeadingConstraint.isActive = isLeftAligned
        panelBodyTrailingConstraint.isActive = !isLeftAligned
        applyButtonOrder()
    }

    func applyPlacementPreference() {
        hideFifteenButton.title = hideButtonTitle("15s")
        hideTwoMinutesButton.title = hideButtonTitle("2m")
        hideThirtyMinutesButton.title = hideButtonTitle("30m")
        offButton.title = hideButtonTitle("∞")
        lrButton.title = isLeftAligned ? "▶" : "◀"
        applyBodyAlignment()
        applyCurrentWidth()
    }

    private func applyButtonOrder() {
        let buttons = isLeftAligned ? Array(buttonBarButtons.reversed()) : buttonBarButtons
        buttonBar.setViews(buttons, in: .leading)
    }

    private func applyHoverState() {
        alphaValue = CGFloat(isMouseInside ? Preferences.sidePanelHoverOpacity : Preferences.sidePanelOpacity) / 100
        buttonBar.isHidden = !isMouseInside
    }

    func syncHover(at location: NSPoint) {
        let containsMouse = frame.contains(location)
        if isMouseInside != containsMouse {
            isMouseInside = containsMouse
            // "Hover jump": entering the panel without holding ⇧ flips it to the
            // other side, so the cursor is left behind and you can't click — unless
            // you hold ⇧, which suppresses the jump and lets the click land.
            if containsMouse, Preferences.sidePanelHoverJump,
               !NSEvent.modifierFlags.contains(.shift), !isJumpPending {
                scheduleHoverJump()
                return
            }
            applyHoverState()
            applyCurrentWidth()
        }
        listView.syncHover(at: containsMouse ? location : nil)
    }

    private func scheduleHoverJump() {
        // Defer to the next runloop tick: syncHover() is driven from a loop over all
        // panels in SidePanelManager, and flipAlignment() re-enters that path via
        // applyPlacementPreference()/refreshPanels(). Async breaks the re-entrancy.
        isJumpPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isJumpPending = false
            self.flipAlignment()
        }
    }

    private func setFrameIfNeeded(_ newFrame: NSRect, display: Bool) {
        guard abs(frame.origin.x - newFrame.origin.x) > 0.5
            || abs(frame.origin.y - newFrame.origin.y) > 0.5
            || abs(frame.width - newFrame.width) > 0.5
            || abs(frame.height - newFrame.height) > 0.5 else { return }
        setFrame(newFrame, display: display)
    }

    func applyOpacity() {
        syncHover(at: NSEvent.mouseLocation)
        applyHoverState()
    }

    private func makeButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 10)
        return button
    }

    private func hideButtonTitle(_ duration: String) -> String {
        isLeftAligned ? "◀ \(duration)" : "\(duration) ▶"
    }

    @objc private func hideFifteenSeconds() {
        hide(for: 15)
    }

    @objc private func hideTwoMinutes() {
        hide(for: 120)
    }

    @objc private func hideThirtyMinutes() {
        hide(for: 1800)
    }

    private func hide(for seconds: TimeInterval) {
        orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.orderFront(nil)
        }
    }

    @objc private func shiftOffsetUp() {
        adjustOffset(by: Self.offsetStep)
    }

    @objc private func shiftOffsetDown() {
        adjustOffset(by: -Self.offsetStep)
    }

    @objc private func turnOff() {
        guard let uuid = targetScreen.cachedUuid() else { return }
        SidePanelManager.shared.disableScreen(uuid)
    }

    @objc private func toggleLeftRight() {
        flipAlignment()
    }

    /// Flip this panel's side only (per-monitor). Persists to the per-screen map and
    /// re-lays-out all panels; only this panel's stored state changed, so only it moves.
    private func flipAlignment() {
        isLeftAligned.toggle()
        SidePanel.saveLeftAligned(isLeftAligned, for: screenUuidString)
        SidePanelManager.shared.applyPlacementPreference()
    }

    private func adjustOffset(by delta: CGFloat) {
        let screenHeight = targetScreen.visibleFrame.height
        let buffer: CGFloat = 100 // keep panel at least this far from screen edges
        let maxOffset = screenHeight / 2 - buffer
        let minOffset = -(screenHeight / 2 - buffer)
        Self.yOffset += delta
        // wrap around with buffer
        if Self.yOffset > maxOffset {
            Self.yOffset = minOffset
        } else if Self.yOffset < minOffset {
            Self.yOffset = maxOffset
        }
        UserDefaults.standard.set(Float(Self.yOffset), forKey: Self.offsetDefaultsKey)
        SidePanelManager.shared.refreshPanels()
    }

    func updateContents(_ groups: [[Window]], selectedWindowId: CGWindowID?, isActiveScreen: Bool, currentSpaceGroupIndex: Int? = nil, showTabHierarchy: Bool = false) {
        caTransaction {
            syncHover(at: NSEvent.mouseLocation)
            applyHoverState()
            listView.showTabHierarchy = showTabHierarchy
            listView.applyIconsOnly(usesCompactLayout)
            let contentHeight = listView.updateContents(groups, selectedWindowId: selectedWindowId, isActiveScreen: isActiveScreen, currentSpaceGroupIndex: currentSpaceGroupIndex)

            // reposition panel (clamp offset so panel edges stay on screen with buffer)
            let screenFrame = targetScreen.visibleFrame
            let panelHeight = min(contentHeight + 8 + Self.buttonBarHeight, screenFrame.height * 0.8)
            let buffer: CGFloat = 100
            // slack = how far the center can move before an edge hits the buffer zone
            let slack = max((screenFrame.height - panelHeight) / 2 - buffer, 0)
            let clampedOffset = min(max(Self.yOffset, -slack), slack)
            let width = SidePanelRow.panelWidth
            let x = isLeftAligned ? screenFrame.minX : screenFrame.maxX - width
            let y = screenFrame.midY - panelHeight / 2 + clampedOffset
            setFrameIfNeeded(CGRect(x: x, y: y, width: width, height: panelHeight), display: false)
            syncHover(at: NSEvent.mouseLocation)
        }
    }
}
