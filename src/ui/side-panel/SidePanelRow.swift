import Cocoa

class SidePanelRow: NSView {
    static let iconSize: CGFloat = 20
    static let rowHeight: CGFloat = 28
    static let panelWidth: CGFloat = 260

    private let iconLayer = LightImageLayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isFocused = false
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

    func update(_ window: Window) {
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
        isFocused = window.lastFocusOrder == 0
        updateBackground()
        onClick = { [weak window] in window?.focus() }
    }

    func showEmpty() {
        iconLayer.isHidden = true
        iconLayer.contents = nil
        titleLabel.stringValue = "(empty)"
        titleLabel.textColor = .secondaryLabelColor
        isFocused = false
        updateBackground()
        onClick = nil
    }

    private func updateBackground() {
        if isHovered {
            let accent: NSColor = if #available(macOS 10.14, *) { .controlAccentColor } else { .alternateSelectedControlColor }
            layer?.backgroundColor = accent.cgColor
        } else if isFocused {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        } else {
            layer?.backgroundColor = nil
        }
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
}
