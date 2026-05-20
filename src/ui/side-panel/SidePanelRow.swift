import Cocoa

enum HighlightState {
    case active   // globally focused window → accent color
    case selected // per-screen most-recent window → dark grey
    case none
}

class SidePanelRow: NSView {
    static let iconSize: CGFloat = 20
    static let panelWidth: CGFloat = 260
    static var compactPanelWidth: CGFloat { CGFloat(Preferences.sidePanelCompactWidth) }

    static func rowHeight(fontSize: CGFloat, wrapping: Bool) -> CGFloat {
        if wrapping {
            return max(42, round(fontSize * 3.5))
        } else {
            return max(28, round(fontSize * 2.2))
        }
    }

    private static let indentOffset: CGFloat = 20

    private let iconLayer = LightImageLayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private var titleLeadingConstraint: NSLayoutConstraint!
    private var onClick: (() -> Void)?
    private var onMiddleClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var highlightState = HighlightState.none
    private var isHovered = false
    private var fullTitle: String = ""
    private(set) var isIndented = false
    private(set) var isEmpty = false

    init(fontSize: CGFloat = 12, wrapping: Bool = false) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4

        iconLayer.frame = CGRect(x: 8, y: 0, width: Self.iconSize, height: Self.iconSize)
        iconLayer.contentsGravity = .resizeAspect
        layer!.addSublayer(iconLayer)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = wrapping ? .byWordWrapping : .byTruncatingTail
        titleLabel.maximumNumberOfLines = wrapping ? 2 : 1
        titleLabel.cell?.wraps = wrapping
        titleLabel.font = NSFont.systemFont(ofSize: fontSize)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8 + Self.iconSize + 6)
        NSLayoutConstraint.activate([
            titleLeadingConstraint,
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func update(_ window: Window, highlightState: HighlightState, isIndented: Bool = false) {
        isEmpty = false
        isHovered = false
        iconLayer.isHidden = false
        if let icon = window.icon {
            iconLayer.contents = icon
        } else {
            iconLayer.contents = nil
        }
        let appName = window.application.localizedName ?? ""
        let windowTitle = window.title ?? ""
        fullTitle = windowTitle.isEmpty ? appName : windowTitle
        titleLabel.stringValue = fullTitle
        titleLabel.textColor = .labelColor
        self.highlightState = highlightState
        self.isIndented = isIndented
        applyIndent()
        updateBackground()
        onClick = { [weak window] in
            guard let window else { return }
            window.focus()
            if Windows.updateLastFocusOrder(window) != nil {
                SidePanelManager.shared.refreshPanels()
            }
        }
        onMiddleClick = { [weak window] in window?.close() }
    }

    func showEmpty(highlightState: HighlightState = .none) {
        isEmpty = true
        isHovered = false
        iconLayer.isHidden = true
        iconLayer.contents = nil
        fullTitle = "(empty)"
        titleLabel.stringValue = fullTitle
        titleLabel.textColor = .secondaryLabelColor
        self.highlightState = highlightState
        self.isIndented = false
        applyIndent()
        updateBackground()
        onClick = nil
        onMiddleClick = nil
    }

    func setWrapping(_ wrapping: Bool) {
        titleLabel.lineBreakMode = wrapping ? .byWordWrapping : .byTruncatingTail
        titleLabel.maximumNumberOfLines = wrapping ? 2 : 1
        titleLabel.cell?.wraps = wrapping
    }

    func setIconsOnly(_ iconsOnly: Bool) {
        if iconsOnly {
            let n = isIndented ? Preferences.sidePanelCompactLettersIndented : Preferences.sidePanelCompactLetters
            if isEmpty || n == 0 {
                titleLabel.isHidden = true
            } else {
                titleLabel.stringValue = fullTitle.count > n ? String(fullTitle.prefix(n)) + "…" : fullTitle
                titleLabel.isHidden = false
            }
        } else {
            titleLabel.stringValue = fullTitle
            titleLabel.isHidden = false
        }
    }

    private func applyIndent() {
        let offset = isIndented ? Self.indentOffset : 0
        iconLayer.frame.origin.x = 8 + offset
        titleLeadingConstraint.constant = 8 + Self.iconSize + 6 + offset
    }

    private func updateBackground() {
        let isDark = NSAppearance.current.getThemeName() == .dark
        if isHovered {
            let hex = isDark ? Preferences.hoverColorDark : Preferences.hoverColorLight
            layer?.backgroundColor = NSColor(hex: hex).cgColor
        } else {
            switch highlightState {
            case .active:
                let hex = isDark ? Preferences.activeColorDark : Preferences.activeColorLight
                layer?.backgroundColor = NSColor(hex: hex).withAlphaComponent(0.6).cgColor
            case .selected:
                let hex = isDark ? Preferences.selectedColorDark : Preferences.selectedColorLight
                layer?.backgroundColor = NSColor(hex: hex).withAlphaComponent(0.6).cgColor
            case .none:
                layer?.backgroundColor = nil
            }
        }
    }

    override func layout() {
        super.layout()
        iconLayer.frame.origin.y = (bounds.height - Self.iconSize) / 2
        titleLabel.preferredMaxLayoutWidth = bounds.width - (8 + Self.iconSize + 6) - 8
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func unhover() {
        guard isHovered else { return }
        isHovered = false
        updateBackground()
    }

    func syncHover(isMouseInside: Bool) {
        guard isHovered != isMouseInside else { return }
        isHovered = isMouseInside
        updateBackground()
    }

    override func mouseEntered(with event: NSEvent) {
        // Clear hover on sibling rows — NSTrackingArea doesn't reliably fire
        // mouseExited during scroll, so multiple rows can get stuck highlighted.
        if let container = superview {
            for case let sibling as SidePanelRow in container.subviews where sibling !== self {
                sibling.unhover()
            }
        }
        isHovered = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackground()
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onMiddleClick?() }
    }
}
