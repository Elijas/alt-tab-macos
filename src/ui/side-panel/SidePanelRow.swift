import Cocoa

enum HighlightState {
    case active   // globally focused window → accent color
    case selected // per-screen most-recent window → dark grey
    case none
}

class SidePanelRow: NSView {
    static let iconSize: CGFloat = 20
    static let rowHeight: CGFloat = 28
    static let panelWidth: CGFloat = 260

    private let iconLayer = LightImageLayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private var onClick: (() -> Void)?
    private var onMiddleClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var highlightState = HighlightState.none
    private var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4

        iconLayer.frame = CGRect(x: 8, y: (Self.rowHeight - Self.iconSize) / 2, width: Self.iconSize, height: Self.iconSize)
        iconLayer.contentsGravity = .resizeAspect
        layer!.addSublayer(iconLayer)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8 + Self.iconSize + 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func update(_ window: Window, highlightState: HighlightState) {
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
        updateBackground()
        onClick = { [weak window] in window?.focus() }
        onMiddleClick = { [weak window] in window?.close() }
    }

    func showEmpty(highlightState: HighlightState = .none) {
        iconLayer.isHidden = true
        iconLayer.contents = nil
        titleLabel.stringValue = "(empty)"
        titleLabel.textColor = .secondaryLabelColor
        self.highlightState = highlightState
        updateBackground()
        onClick = nil
        onMiddleClick = nil
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
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
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
