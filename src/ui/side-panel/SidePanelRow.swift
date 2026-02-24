import Cocoa

enum HighlightState {
    case active   // globally focused window → accent color
    case selected // per-screen most-recent window → dark grey
    case none
}

class SidePanelRow: NSView {
    static let iconSize: CGFloat = 20
    static let panelWidth: CGFloat = 260

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
    private(set) var isIndented = false

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
        isHovered = false
        iconLayer.isHidden = false
        if let icon = window.icon {
            iconLayer.contents = icon
        } else {
            iconLayer.contents = nil
        }
        let appName = window.application.localizedName ?? ""
        let windowTitle = window.title ?? ""
        titleLabel.stringValue = windowTitle.isEmpty ? appName : windowTitle
        titleLabel.textColor = .labelColor
        self.highlightState = highlightState
        self.isIndented = isIndented
        applyIndent()
        updateBackground()
        onClick = { [weak window] in window?.focus() }
        onMiddleClick = { [weak window] in window?.close() }
    }

    func showEmpty(highlightState: HighlightState = .none) {
        isHovered = false
        iconLayer.isHidden = true
        iconLayer.contents = nil
        titleLabel.stringValue = "(empty)"
        titleLabel.textColor = .secondaryLabelColor
        self.highlightState = highlightState
        self.isIndented = false
        applyIndent()
        updateBackground()
        onClick = nil
        onMiddleClick = nil
    }

    private func applyIndent() {
        let offset = isIndented ? Self.indentOffset : 0
        iconLayer.frame.origin.x = 8 + offset
        titleLeadingConstraint.constant = 8 + Self.iconSize + 6 + offset
    }

    private func updateBackground() {
        if isHovered {
            let accent: NSColor = if #available(macOS 10.14, *) { .controlAccentColor } else { .alternateSelectedControlColor }
            layer?.backgroundColor = accent.cgColor
        } else {
            switch highlightState {
            case .active:
                let accent: NSColor = if #available(macOS 10.14, *) { .controlAccentColor } else { .alternateSelectedControlColor }
                layer?.backgroundColor = accent.withAlphaComponent(0.6).cgColor
            case .selected:
                // KNOWN UNKNOWN: grey value (white: 0.5, alpha: 0.3) needs visual tuning against vibrancy material
                layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.3).cgColor
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

    override func mouseEntered(with event: NSEvent) {
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
