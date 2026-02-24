import Cocoa

class SidePanel: NSPanel {
    private static let buttonBarHeight: CGFloat = 28
    private static let offsetStep: CGFloat = 100
    private static let offsetDefaultsKey = "sidePanelYOffset"
    private static let leftAlignedDefaultsKey = "sidePanelLeftAligned"

    private static var isLeftAligned: Bool = UserDefaults.standard.bool(forKey: leftAlignedDefaultsKey)

    private let listView = WindowListView(separatorHeight: CGFloat(Preferences.sidePanelSeparatorSize), fontSize: CGFloat(Preferences.sidePanelFontSize), minWidth: SidePanelRow.panelWidth)
    let targetScreen: NSScreen
    private let buttonBar = NSView()
    private var lrButton: NSButton!

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
        collectionBehavior = .canJoinAllSpaces
        level = .floating
        alphaValue = CGFloat(Preferences.sidePanelOpacity) / 100
        setAccessibilitySubrole(.unknown)

        let vibrancy = NSVisualEffectView()
        vibrancy.material = .sidebar  // KNOWN UNKNOWN: .sidebar vs .hudWindow - depends on final visual design
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 8
        contentView = vibrancy

        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        vibrancy.addTrackingArea(trackingArea)

        // button bar at bottom
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        vibrancy.addSubview(buttonBar)

        let hideButton = makeButton("hide 10s", #selector(hideTenSeconds))
        let downButton = makeButton("▼", #selector(shiftOffsetDown))
        let upButton = makeButton("▲", #selector(shiftOffsetUp))
        lrButton = makeButton(Self.isLeftAligned ? "▶" : "◀", #selector(toggleLeftRight))
        let offButton = makeButton("off", #selector(turnOff))
        buttonBar.addSubview(hideButton)
        buttonBar.addSubview(downButton)
        buttonBar.addSubview(upButton)
        buttonBar.addSubview(lrButton)
        buttonBar.addSubview(offButton)

        hideButton.translatesAutoresizingMaskIntoConstraints = false
        downButton.translatesAutoresizingMaskIntoConstraints = false
        upButton.translatesAutoresizingMaskIntoConstraints = false
        lrButton.translatesAutoresizingMaskIntoConstraints = false
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
            offButton.leadingAnchor.constraint(equalTo: lrButton.trailingAnchor, constant: 4),
            offButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
        ])

        // list view (shared row/separator layout)
        vibrancy.addSubview(listView)

        NSLayoutConstraint.activate([
            listView.topAnchor.constraint(equalTo: vibrancy.topAnchor, constant: 4),
            listView.bottomAnchor.constraint(equalTo: buttonBar.topAnchor),
            listView.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),

            buttonBar.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor),
            buttonBar.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            buttonBar.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),
            buttonBar.heightAnchor.constraint(equalToConstant: Self.buttonBarHeight),
        ])
    }

    override var canBecomeKey: Bool { false }

    override func mouseEntered(with event: NSEvent) {
        alphaValue = CGFloat(Preferences.sidePanelHoverOpacity) / 100
    }

    override func mouseExited(with event: NSEvent) {
        alphaValue = CGFloat(Preferences.sidePanelOpacity) / 100
    }

    func applyOpacity() {
        alphaValue = CGFloat(Preferences.sidePanelOpacity) / 100
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
        Preferences.set("sidePanelEnabled", "false")
        SidePanelManager.shared.tearDown()
    }

    @objc private func toggleLeftRight() {
        Self.isLeftAligned.toggle()
        UserDefaults.standard.set(Self.isLeftAligned, forKey: Self.leftAlignedDefaultsKey)
        lrButton.title = Self.isLeftAligned ? "▶" : "◀"
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
            listView.showTabHierarchy = showTabHierarchy
            let contentHeight = listView.updateContents(groups, selectedWindowId: selectedWindowId, isActiveScreen: isActiveScreen, currentSpaceGroupIndex: currentSpaceGroupIndex)

            // reposition panel (clamp offset so panel edges stay on screen with buffer)
            let screenFrame = targetScreen.visibleFrame
            let panelHeight = min(contentHeight + 8 + Self.buttonBarHeight, screenFrame.height * 0.8)
            let buffer: CGFloat = 100
            // slack = how far the center can move before an edge hits the buffer zone
            let slack = max((screenFrame.height - panelHeight) / 2 - buffer, 0)
            let clampedOffset = min(max(Self.yOffset, -slack), slack)
            let x = Self.isLeftAligned ? screenFrame.minX : screenFrame.maxX - SidePanelRow.panelWidth
            let y = screenFrame.midY - panelHeight / 2 + clampedOffset
            setFrame(CGRect(x: x, y: y, width: SidePanelRow.panelWidth, height: panelHeight), display: false)
        }
    }
}
