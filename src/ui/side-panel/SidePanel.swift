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
    private var buttonBarHeightConstraint: NSLayoutConstraint!
    private var isMouseInside = false
    private var appliedEffectiveHover = false
    private var lastContentHeight: CGFloat = 0
    private let screenUuidString: String?
    private var homeIsLeftAligned: Bool // persisted canonical side, set by the ◀/▶ button
    private var isLeftAligned: Bool // displayed side; hover-jump deviates this transiently
    private var isJumpPending = false
    private var isHiddenUntilMouseLeaves = false
    private var returnWorkItem: DispatchWorkItem?

    private static var yOffset: CGFloat = {
        let defaults = UserDefaults.standard
        return CGFloat(defaults.float(forKey: offsetDefaultsKey))
    }()

    init(for screen: NSScreen) {
        self.targetScreen = screen
        let uuid = screen.cachedUuid().map { $0 as String }
        let home = SidePanel.loadLeftAligned(for: uuid)
        self.screenUuidString = uuid
        self.homeIsLeftAligned = home
        self.isLeftAligned = home
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
        buttonBarHeightConstraint = buttonBar.heightAnchor.constraint(equalToConstant: Self.buttonBarHeight)
        NSLayoutConstraint.activate([
            panelBody.topAnchor.constraint(equalTo: panelRoot.topAnchor),
            panelBody.bottomAnchor.constraint(equalTo: panelRoot.bottomAnchor),
            panelBodyWidthConstraint,

            listView.topAnchor.constraint(equalTo: panelBody.topAnchor), // flush top (matches flush bottom)
            listView.bottomAnchor.constraint(equalTo: buttonBar.topAnchor),
            listView.leadingAnchor.constraint(equalTo: panelBody.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: panelBody.trailingAnchor),

            buttonBar.bottomAnchor.constraint(equalTo: panelBody.bottomAnchor),
            buttonBar.leadingAnchor.constraint(equalTo: panelBody.leadingAnchor),
            buttonBar.trailingAnchor.constraint(equalTo: panelBody.trailingAnchor),
            buttonBarHeightConstraint,
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

    // Unmodified hover avoids the panel: it jumps if the switch is on, hides if off.
    // Holding ⌘ means "I want this panel" and re-enables the full hover UI.
    private var isHoverBypassActive: Bool { NSEvent.modifierFlags.contains(.command) }

    private var hoverSuppressed: Bool { Preferences.sidePanelHoverJump && !isHoverBypassActive }

    // The single predicate every hover visual is gated on.
    private var effectiveHover: Bool {
        isMouseInside && !hoverSuppressed
    }

    private var usesCompactLayout: Bool {
        !effectiveHover
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
        // Re-align the body AND move the window to the target screen edge in one
        // transaction. Otherwise the body shifts within the window now and the window
        // frame only catches up on the throttled refresh ~200ms later — a two-step jump.
        caTransaction {
            applyBodyAlignment()
            applyCurrentWidth()
            repositionForAlignment()
        }
    }

    /// Snap only the window's x (width is constant) to the side `isLeftAligned` implies,
    /// keeping the current y/height. The next refresh recomputes height but won't move x.
    private func repositionForAlignment() {
        guard frame.height > 0 else { return } // not placed yet; updateContents() will do it
        let width = SidePanelRow.panelWidth
        let screenFrame = targetScreen.visibleFrame
        var newFrame = frame
        newFrame.size.width = width
        newFrame.origin.x = isLeftAligned ? screenFrame.minX : screenFrame.maxX - width
        setFrameIfNeeded(newFrame, display: true)
    }

    private func applyButtonOrder() {
        let buttons = isLeftAligned ? Array(buttonBarButtons.reversed()) : buttonBarButtons
        buttonBar.setViews(buttons, in: .leading)
    }

    private func applyHoverState() {
        let hovering = effectiveHover
        alphaValue = CGFloat(hovering ? Preferences.sidePanelHoverOpacity : Preferences.sidePanelOpacity) / 100
        buttonBar.isHidden = !hovering
    }

    /// Size and place the window. The TOP edge is anchored to where the full
    /// (button-bar-inclusive) panel's top would be, so it never moves; only the BOTTOM
    /// follows the actual height. When not hovering, the button bar collapses to 0 and
    /// the bottom rises by its height — no blank reserved strip.
    private func applyPanelGeometry() {
        guard lastContentHeight > 0 else { return } // no content yet; updateContents() will place it
        let hovering = effectiveHover
        caTransaction {
            buttonBarHeightConstraint.constant = hovering ? Self.buttonBarHeight : 0
            let screenFrame = targetScreen.visibleFrame
            // No top/bottom padding: content is flush to both edges; only the button bar
            // adds height (and only while hovering).
            let fullHeight = min(lastContentHeight + Self.buttonBarHeight, screenFrame.height * 0.8)
            let buffer: CGFloat = 100
            // slack = how far the center can move before an edge hits the buffer zone
            let slack = max((screenFrame.height - fullHeight) / 2 - buffer, 0)
            let clampedOffset = min(max(Self.yOffset, -slack), slack)
            let topY = screenFrame.midY + fullHeight / 2 + clampedOffset // stable across the bar toggle
            let height = hovering ? fullHeight : max(fullHeight - Self.buttonBarHeight, 0)
            let width = SidePanelRow.panelWidth
            let x = isLeftAligned ? screenFrame.minX : screenFrame.maxX - width
            setFrameIfNeeded(CGRect(x: x, y: topY - height, width: width, height: height), display: false)
            panelRoot.layoutSubtreeIfNeeded()
        }
    }

    func syncHover(at location: NSPoint) {
        guard !shouldStayHidden(at: location) else { return }
        let containsMouse = frame.contains(location)
        if containsMouse, !isMouseInside, !isHoverBypassActive, !isJumpPending {
            isMouseInside = true
            if Preferences.sidePanelHoverJump {
                scheduleHoverJump()
            } else {
                hideUntilMouseLeaves()
            }
            return
        }
        isMouseInside = containsMouse
        syncHoverVisuals(at: location)
    }

    private func shouldStayHidden(at location: NSPoint) -> Bool {
        guard isHiddenUntilMouseLeaves else { return false }
        guard frame.contains(location), !isHoverBypassActive else {
            isHiddenUntilMouseLeaves = false
            orderFront(nil)
            return false
        }
        return true
    }

    private func hideUntilMouseLeaves() {
        isMouseInside = false
        isHiddenUntilMouseLeaves = true
        syncHoverVisuals(at: NSEvent.mouseLocation)
        orderOut(nil)
    }

    private func syncHoverVisuals(at location: NSPoint) {
        // All hover visuals follow effectiveHover, so unmodified avoidance shows none.
        let hovering = effectiveHover
        if appliedEffectiveHover != hovering {
            appliedEffectiveHover = hovering
            applyHoverState()
            applyCurrentWidth()
            applyPanelGeometry() // grow/collapse the button-bar strip, top edge anchored
        }
        listView.syncHover(at: hovering ? location : nil)
    }

    private func scheduleHoverJump() {
        // Defer to the next runloop tick: syncHover() is driven from a loop over all
        // panels in SidePanelManager, and hoverJump() re-enters that path via
        // applyPlacementPreference()/refreshPanels(). Async breaks the re-entrancy.
        isJumpPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isJumpPending = false
            self.hoverJump()
        }
    }

    private func hoverJump() {
        // Transient, display-only flip away from home (NOT persisted). The panel
        // returns to its home side on its own after sidePanelReturnDelay seconds.
        isLeftAligned.toggle()
        SidePanelManager.shared.applyPlacementPreference()
        scheduleAutoReturn()
    }

    private func scheduleAutoReturn() {
        cancelAutoReturn()
        let delaySeconds = Preferences.sidePanelReturnDelay
        // 0 = feature off; also nothing to do if the display already matches home.
        guard delaySeconds > 0, isLeftAligned != homeIsLeftAligned else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.returnWorkItem = nil
            self.isLeftAligned = self.homeIsLeftAligned
            SidePanelManager.shared.applyPlacementPreference()
        }
        returnWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(delaySeconds), execute: work)
    }

    private func cancelAutoReturn() {
        returnWorkItem?.cancel()
        returnWorkItem = nil
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
        // The ◀/▶ button sets this monitor's HOME side (persisted, per-monitor).
        // Display follows immediately and any pending auto-return is cancelled, since
        // there is no longer a deviation to return from.
        homeIsLeftAligned.toggle()
        isLeftAligned = homeIsLeftAligned
        SidePanel.saveLeftAligned(homeIsLeftAligned, for: screenUuidString)
        cancelAutoReturn()
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
            lastContentHeight = listView.updateContents(groups, selectedWindowId: selectedWindowId, isActiveScreen: isActiveScreen, currentSpaceGroupIndex: currentSpaceGroupIndex)
            applyPanelGeometry()
            syncHover(at: NSEvent.mouseLocation)
        }
    }
}
