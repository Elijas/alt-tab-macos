import Cocoa

class SidePanel: NSPanel {
    private static let buttonBarHeight: CGFloat = 28
    private static let offsetStep: CGFloat = 100
    private static let offsetDefaultsKey = "sidePanelYOffset"
    private static let leftAlignedDefaultsKey = "sidePanelLeftAligned"
    private static let iconsOnlyDefaultsKey = "sidePanelIconsOnly"

    private static var isLeftAligned: Bool = UserDefaults.standard.bool(forKey: leftAlignedDefaultsKey)
    private static var isIconsOnly: Bool = UserDefaults.standard.bool(forKey: iconsOnlyDefaultsKey)

    private let listView = WindowListView(separatorHeight: CGFloat(Preferences.sidePanelSeparatorSize), fontSize: CGFloat(Preferences.sidePanelFontSize), minWidth: SidePanelRow.panelWidth)
    let targetScreen: NSScreen
    private let panelRoot = NSView()
    private let panelBody = NSVisualEffectView()
    private let buttonBar = NSView()
    private var lrButton: NSButton!
    private var iconsOnlyButton: NSButton!
    private var panelBodyWidthConstraint: NSLayoutConstraint!
    private var panelBodyLeadingConstraint: NSLayoutConstraint!
    private var panelBodyTrailingConstraint: NSLayoutConstraint!
    private var isMouseInside = false

    private static var yOffset: CGFloat = {
        let defaults = UserDefaults.standard
        return CGFloat(defaults.float(forKey: offsetDefaultsKey))
    }()

    init(for screen: NSScreen) {
        self.targetScreen = screen
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
        panelBody.addSubview(buttonBar)

        let hideButton = makeButton("hide 10s", #selector(hideTenSeconds))
        let downButton = makeButton("▼", #selector(shiftOffsetDown))
        let upButton = makeButton("▲", #selector(shiftOffsetUp))
        lrButton = makeButton(Self.isLeftAligned ? "▶" : "◀", #selector(toggleLeftRight))
        iconsOnlyButton = makeButton(Self.isLeftAligned ? "◀" : "▶", #selector(toggleIconsOnly))
        let offButton = makeButton("off", #selector(turnOff))
        buttonBar.addSubview(hideButton)
        buttonBar.addSubview(downButton)
        buttonBar.addSubview(upButton)
        buttonBar.addSubview(lrButton)
        buttonBar.addSubview(iconsOnlyButton)
        buttonBar.addSubview(offButton)

        hideButton.translatesAutoresizingMaskIntoConstraints = false
        downButton.translatesAutoresizingMaskIntoConstraints = false
        upButton.translatesAutoresizingMaskIntoConstraints = false
        lrButton.translatesAutoresizingMaskIntoConstraints = false
        iconsOnlyButton.translatesAutoresizingMaskIntoConstraints = false
        offButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hideButton.leadingAnchor.constraint(equalTo: buttonBar.leadingAnchor, constant: 4),
            hideButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
            downButton.leadingAnchor.constraint(equalTo: hideButton.trailingAnchor, constant: 4),
            downButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
            upButton.leadingAnchor.constraint(equalTo: downButton.trailingAnchor, constant: 4),
            upButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
            lrButton.leadingAnchor.constraint(equalTo: upButton.trailingAnchor, constant: 4),
            lrButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
            iconsOnlyButton.leadingAnchor.constraint(equalTo: lrButton.trailingAnchor, constant: 4),
            iconsOnlyButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
            offButton.leadingAnchor.constraint(equalTo: iconsOnlyButton.trailingAnchor, constant: 4),
            offButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
        ])

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
        isMouseInside = true
        applyHoverState()
        if Self.isIconsOnly { applyCurrentWidth() }
    }

    override func mouseExited(with event: NSEvent) {
        guard !frame.contains(NSEvent.mouseLocation) else { return }
        isMouseInside = false
        applyHoverState()
        if Self.isIconsOnly { applyCurrentWidth() }
    }

    private var usesCompactLayout: Bool {
        Self.isIconsOnly && !isMouseInside
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
        panelBodyLeadingConstraint.isActive = Self.isLeftAligned
        panelBodyTrailingConstraint.isActive = !Self.isLeftAligned
    }

    private func applyHoverState() {
        alphaValue = CGFloat(isMouseInside ? Preferences.sidePanelHoverOpacity : Preferences.sidePanelOpacity) / 100
        buttonBar.isHidden = !isMouseInside
    }

    private func syncMouseInside() {
        let containsMouse = frame.contains(NSEvent.mouseLocation)
        guard isMouseInside != containsMouse else { return }
        isMouseInside = containsMouse
    }

    private func setFrameIfNeeded(_ newFrame: NSRect, display: Bool) {
        guard abs(frame.origin.x - newFrame.origin.x) > 0.5
            || abs(frame.origin.y - newFrame.origin.y) > 0.5
            || abs(frame.width - newFrame.width) > 0.5
            || abs(frame.height - newFrame.height) > 0.5 else { return }
        setFrame(newFrame, display: display)
    }

    func applyOpacity() {
        syncMouseInside()
        applyHoverState()
    }

    private func makeButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 10)
        return button
    }

    @objc private func hideTenSeconds() {
        orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
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
        Self.isLeftAligned.toggle()
        UserDefaults.standard.set(Self.isLeftAligned, forKey: Self.leftAlignedDefaultsKey)
        lrButton.title = Self.isLeftAligned ? "▶" : "◀"
        iconsOnlyButton.title = Self.isLeftAligned ? "◀" : "▶"
        applyBodyAlignment()
        applyCurrentWidth()
        SidePanelManager.shared.refreshPanels()
    }

    @objc private func toggleIconsOnly() {
        Self.isIconsOnly.toggle()
        UserDefaults.standard.set(Self.isIconsOnly, forKey: Self.iconsOnlyDefaultsKey)
        applyCurrentWidth()
        SidePanelManager.shared.refreshPanels()
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
            syncMouseInside()
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
            let x = Self.isLeftAligned ? screenFrame.minX : screenFrame.maxX - width
            let y = screenFrame.midY - panelHeight / 2 + clampedOffset
            setFrameIfNeeded(CGRect(x: x, y: y, width: width, height: panelHeight), display: false)
        }
    }
}
