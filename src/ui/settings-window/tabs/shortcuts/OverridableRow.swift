import Cocoa

/// Wraps any control with override/inherit semantics.
/// When inherited: control and label are dimmed (alpha 0.45).
/// When overridden: full contrast + reset button visible.
/// Interacting with a dimmed control activates the override automatically.
    enum Layout { case horizontal, vertical }

class OverridableRowView: NSStackView {
    private(set) var isOverridden = false
    private weak var wrappedControl: NSView?
    private weak var leftLabel: NSTextField?
    private var resetButton: NSButton!
    let settingName: String
    var onOverrideChanged: ((String, Bool) -> Void)?
    /// Called to re-read the current UserDefaults value into the control.
    var refreshControl: (() -> Void)?

    init(settingName: String, control: NSView, leftLabel: NSTextField? = nil, layout: Layout = .horizontal) {
        self.settingName = settingName
        self.wrappedControl = control
        self.leftLabel = leftLabel
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        resetButton = makeResetButton()
        resetButton.isHidden = true

        if layout == .vertical {
            orientation = .vertical
            alignment = .centerX
            spacing = 6
            addArrangedSubview(control)
            addArrangedSubview(resetButton)
        } else {
            orientation = .horizontal
            alignment = .centerY
            spacing = 4
            addArrangedSubview(control)
            addArrangedSubview(resetButton)
        }

        applyInheritedAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func makeResetButton() -> NSButton {
        let button: NSButton
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset to default") {
            button = NSButton(image: image, target: self, action: #selector(resetToInherited))
        } else {
            button = NSButton(title: "↺", target: self, action: #selector(resetToInherited))
        }
        button.bezelStyle = .inline
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.toolTip = NSLocalizedString("Reset to default", comment: "")
        if #available(macOS 10.14, *) {
            button.contentTintColor = .secondaryLabelColor
        }
        return button
    }

    func activateOverride() {
        guard !isOverridden else { return }
        isOverridden = true
        applyOverriddenAppearance()
        onOverrideChanged?(settingName, true)
    }

    @objc private func resetToInherited() {
        guard isOverridden else { return }
        isOverridden = false
        applyInheritedAppearance()
        onOverrideChanged?(settingName, false)
    }

    private func applyInheritedAppearance() {
        // Dim the entire OverridableRowView — composites through layer-backed children (e.g. ImageTextButtonView)
        alphaValue = 0.45
        leftLabel?.alphaValue = 0.45
        resetButton.isHidden = true
        refreshControl?()
    }

    private func applyOverriddenAppearance() {
        alphaValue = 1.0
        leftLabel?.alphaValue = 1.0
        resetButton.isHidden = false
    }

    func setOverridden(_ overridden: Bool) {
        if overridden {
            activateOverride()
        } else {
            resetToInherited()
        }
    }
}

/// Tracks which settings are overridden and updates a footer label.
class OverrideTracker {
    private static let inheritedAlpha = CGFloat(0.45)

    private var overriddenSettings = Set<String>()
    private weak var footerLabel: NSTextField?
    private weak var resetAllButton: NSButton?
    private var sectionMap = [String: String]()
    private var sectionTitleLabels = [String: NSTextField]()
    /// All overridable rows managed by this tracker, for batch reset.
    private var rows = [OverridableRowView]()

    init(footerLabel: NSTextField, resetAllButton: NSButton? = nil) {
        self.footerLabel = footerLabel
        self.resetAllButton = resetAllButton
        updateFooter()
    }

    func registerSetting(_ name: String, section: String) {
        sectionMap[name] = section
    }

    func registerSectionTitle(_ label: NSTextField, section: String) {
        sectionTitleLabels[section] = label
        label.alphaValue = Self.inheritedAlpha
    }

    func registerRow(_ row: OverridableRowView) {
        rows.append(row)
    }

    func resetAll() {
        for row in rows {
            row.setOverridden(false)
        }
    }

    func settingChanged(_ name: String, isOverridden: Bool) {
        if isOverridden {
            overriddenSettings.insert(name)
        } else {
            overriddenSettings.remove(name)
        }
        updateFooter()
    }

    private func updateFooter() {
        guard let label = footerLabel else { return }
        let hasOverrides = !overriddenSettings.isEmpty
        resetAllButton?.alphaValue = hasOverrides ? 1.0 : 0.0
        resetAllButton?.isEnabled = hasOverrides
        updateSectionTitles()
        if hasOverrides {
            let count = overriddenSettings.count
            let noun = count == 1 ? "setting" : "settings"
            label.stringValue = "⚡ \(count) \(noun) overridden"
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = NSLocalizedString("All settings inherited from Defaults", comment: "")
            label.textColor = .tertiaryLabelColor
        }
    }

    private func updateSectionTitles() {
        let sectionsWithOverrides = Set(overriddenSettings.compactMap { sectionMap[$0] })
        for (section, titleLabel) in sectionTitleLabels {
            titleLabel.alphaValue = sectionsWithOverrides.contains(section) ? 1.0 : Self.inheritedAlpha
        }
    }
}
