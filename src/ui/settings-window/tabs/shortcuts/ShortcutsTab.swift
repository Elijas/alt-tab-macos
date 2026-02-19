import Cocoa
import ShortcutRecorder

// MARK: - Sidebar Row (duplicated from ControlsTab since it's private there)

private class ShortcutSidebarRow: ClickHoverStackView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let chevronLabel = NSTextField(labelWithString: "›")
    private let textColumn = NSStackView()
    private var isSelectedRow = false
    private var isHoveredRow = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = TableGroupView.cornerRadius
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 0
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        let spacer = NSView()
        titleLabel.alignment = .left
        summaryLabel.alignment = .left
        summaryLabel.font = NSFont.systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor
        chevronLabel.font = NSFont.systemFont(ofSize: 22)
        chevronLabel.textColor = .secondaryLabelColor
        textColumn.addArrangedSubview(titleLabel)
        textColumn.addArrangedSubview(summaryLabel)
        addArrangedSubview(textColumn)
        addArrangedSubview(spacer)
        addArrangedSubview(chevronLabel)
        textColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TableGroupView.padding).isActive = true
        textColumn.trailingAnchor.constraint(lessThanOrEqualTo: chevronLabel.leadingAnchor, constant: -8).isActive = true
        chevronLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TableGroupView.padding).isActive = true
        updateStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func setContent(_ title: String, _ summary: String) {
        titleLabel.stringValue = title
        summaryLabel.stringValue = summary
        updateStyle()
    }

    func setSelected(_ selected: Bool) {
        isSelectedRow = selected
        updateStyle()
    }

    func setHovered(_ hovered: Bool) {
        isHoveredRow = hovered
        updateStyle()
    }

    private func updateStyle() {
        let selectedColor = NSColor.systemAccentColor.withAlphaComponent(0.16)
        let backgroundColor = isSelectedRow ? selectedColor : (isHoveredRow ? NSColor.tableHoverColor : .clear)
        let titleFont = NSFont.systemFont(ofSize: 13, weight: isSelectedRow ? .semibold : .regular)
        titleLabel.attributedStringValue = NSAttributedString(string: titleLabel.stringValue,
            attributes: [.font: titleFont, .foregroundColor: NSColor.labelColor])
        layer?.backgroundColor = backgroundColor.cgColor
    }
}

// MARK: - Sidebar ScrollView (duplicated from ControlsTab since it's private there)

private class ShortcutsSidebarScrollView: NSScrollView {
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard shouldHandleVerticalScroll(event) else {
            return // Don't forward horizontal scrolls
        }
        if canScrollInEventDirection(event) {
            super.scrollWheel(with: event)
        }
        // At scroll boundary: absorb the event instead of forwarding to parent
    }

    private func shouldHandleVerticalScroll(_ event: NSEvent) -> Bool {
        abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) && abs(event.scrollingDeltaY) > 0.1
    }

    private func canScrollInEventDirection(_ event: NSEvent) -> Bool {
        let maxOffset = maxVerticalOffset()
        guard maxOffset > 0 else { return false }
        let y = contentView.bounds.origin.y
        let dy = normalizedVerticalDelta(event)
        if dy > 0 { return y > 0.5 }
        if dy < 0 { return y < maxOffset - 0.5 }
        return false
    }

    private func maxVerticalOffset() -> CGFloat {
        guard let content = documentView?.subviews.first else { return 0 }
        return max(0, content.fittingSize.height - contentView.bounds.height)
    }

    private func normalizedVerticalDelta(_ event: NSEvent) -> CGFloat {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        return event.isDirectionInvertedFromDevice ? -delta : delta
    }

    private func parentScrollView() -> NSScrollView? {
        var parent = superview
        while let view = parent {
            if let scrollView = view as? NSScrollView { return scrollView }
            parent = view.superview
        }
        return nil
    }
}

// MARK: - Window-filling content view

/// NSView subclass that dynamically sizes its height to fill the enclosing scroll view's visible area.
private class ShortcutsContentView: NSView {
    var heightConstraint: NSLayoutConstraint?
    /// Overhead above/below this view in the scroll view (section title, tools row, padding).
    var overhead: CGFloat = 70
    private var observing = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !observing else { return }
        if let clipView = enclosingScrollView?.contentView {
            clipView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(clipViewFrameChanged(_:)),
                name: NSView.frameDidChangeNotification, object: clipView)
            observing = true
            updateHeight(clipView.bounds.height)
        }
    }

    @objc private func clipViewFrameChanged(_ notification: Notification) {
        if let clipView = notification.object as? NSClipView {
            updateHeight(clipView.bounds.height)
        }
    }

    /// Consume scroll events so the parent settings scroll view doesn't scroll
    /// when the cursor is over the shortcuts section. The inner scroll views
    /// (sidebar rows, editor pane) handle their own scrolling independently.
    override func scrollWheel(with event: NSEvent) {
        // Don't call super — this prevents propagation to rightScrollView
    }

    private func updateHeight(_ visibleHeight: CGFloat) {
        let target = max(400, visibleHeight - overhead)
        heightConstraint?.constant = target
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - ShortcutsTab

class ShortcutsTab: NSObject {
    static var additionalControlsSheet: AdditionalControlsSheet!

    private static let shortcutSidebarWidth = CGFloat(200)
    private static let sidebarRowHeight = CGFloat(52)
    private static var shortcutEditorWidth: CGFloat { SettingsWindow.contentWidth - shortcutSidebarWidth - 1 }
    private static let defaultsSelectionIndex = -2
    private static let gestureSelectionIndex = -1

    private static var selectedIndex = defaultsSelectionIndex
    private static var shortcutRowsStackView: NSStackView?
    private static var shortcutRows = [ShortcutSidebarRow]()
    private static var defaultsSidebarRow: ShortcutSidebarRow?
    private static var gestureSidebarRow: ShortcutSidebarRow?
    private static var shortcutCountButtons: NSSegmentedControl?
    private static var multipleShortcutsCheckbox: NSButton?
    private static var shortcutsContentView: ShortcutsContentView?
    private static var sidebarView: NSView?
    private static var sidebarSeparator: NSView?
    private static var sidebarWidthConstraint: NSLayoutConstraint?
    private static var separatorWidthConstraint: NSLayoutConstraint?

    private static var simpleModeEditorView: NSView?
    private static var defaultsEditorView: NSView?
    private static var shortcutEditorViews = [NSView]()
    private static var gestureEditorView: NSView?
    /// All overridable rows across all editors, for refreshing inherited values on selection change.
    private static var allOverridableRows = [OverridableRowView]()
    /// Snapshot of the Defaults editor's current values, keyed by setting name.
    /// Per-shortcut inherited controls read from here instead of UserDefaults,
    /// because overriding a control writes to the same UserDefaults key (polluting Defaults).
    private static var defaultsSnapshot = [String: Int]()

    // MARK: - Public Entry Point

    static func initTab() -> NSView {
        simpleModeEditorView = makeSimpleModeEditor()
        defaultsEditorView = makeDefaultsEditor()
        shortcutEditorViews = (0..<Preferences.maxShortcutCount).map { makeShortcutEditor(index: $0) }
        gestureEditorView = makeGestureEditor()
        let shortcutsView = makeShortcutsView()
        let checkbox = NSButton(checkboxWithTitle: NSLocalizedString("Enable Multiple Shortcuts and Gestures", comment: ""),
            target: self, action: #selector(multipleShortcutsToggled(_:)))
        let isMultiEnabled = CachedUserDefaults.bool("multipleShortcutsEnabled")
        checkbox.state = isMultiEnabled ? .on : .off
        multipleShortcutsCheckbox = checkbox
        setSidebarVisible(isMultiEnabled)
        // Account for checkbox height below the panel in the dynamic height calculation
        shortcutsContentView?.overhead = 120
        // Vertical container: panel fills available space, checkbox pinned at bottom
        // (TableGroupSetView lays consecutive non-TableGroupView items horizontally)
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10
        container.addArrangedSubview(shortcutsView)
        container.addArrangedSubview(checkbox)
        let view = TableGroupSetView(originalViews: [container],
            bottomPadding: 0, othersAlignment: .leading)
        additionalControlsSheet = AdditionalControlsSheet()
        refreshUi()
        // Observe UserDefaults changes so sidebar subtitles update when shortcut recorders change
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            refreshSidebarRowTexts()
        }
        return view
    }

    // MARK: - Layout: Main View

    private static func makeShortcutsView() -> NSView {
        let sidebar = makeShortcutSidebar()
        let editorPane = makeEditorPane()
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        let content = ShortcutsContentView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.tableBackgroundColor.cgColor
        content.layer?.cornerRadius = TableGroupView.cornerRadius
        content.layer?.borderColor = NSColor.tableBorderColor.cgColor
        content.layer?.borderWidth = TableGroupView.borderWidth
        content.layer?.masksToBounds = true
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        editorPane.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)
        content.addSubview(separator)
        content.addSubview(editorPane)
        // Store refs for sidebar and styling toggle
        shortcutsContentView = content
        sidebarView = sidebar
        sidebarSeparator = separator
        let sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: shortcutSidebarWidth)
        sidebarWidthConstraint = sidebarWidth
        let sepWidth = separator.widthAnchor.constraint(equalToConstant: 1)
        separatorWidthConstraint = sepWidth
        // Dynamic height: fills the window's visible area, resizes with the window
        let heightConstraint = content.heightAnchor.constraint(equalToConstant: 520)
        content.heightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: SettingsWindow.contentWidth),
            heightConstraint,
            // Sidebar: left, full height
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebarWidth,
            // Separator
            separator.topAnchor.constraint(equalTo: content.topAnchor),
            separator.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sepWidth,
            // Editor pane: right, full height
            editorPane.topAnchor.constraint(equalTo: content.topAnchor),
            editorPane.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            editorPane.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            editorPane.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        return content
    }

    // MARK: - Layout: Editor Pane

    private static func makeEditorPane() -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        // No fixed width — editor pane sizes from leading/trailing constraints in makeShortcutsView()
        let documentView = FlippedView(frame: .zero)
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        var views: [NSView] = []
        if let simpleModeEditorView { views.append(simpleModeEditorView) }
        if let defaultsEditorView { views.append(defaultsEditorView) }
        views.append(contentsOf: shortcutEditorViews)
        if let gestureEditorView { views.append(gestureEditorView) }
        let editorsStack = NSStackView(views: views)
        editorsStack.orientation = .vertical
        editorsStack.alignment = .leading
        editorsStack.spacing = 0
        editorsStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(editorsStack)
        NSLayoutConstraint.activate([
            editorsStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 10),
            editorsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 10),
            editorsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -10),
            editorsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -10),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        return scrollView
    }

    // MARK: - Layout: Sidebar

    private static func makeShortcutSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: shortcutSidebarWidth).isActive = true
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.25).cgColor

        let listContainer = NSView()
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        listContainer.wantsLayer = true
        listContainer.layer?.backgroundColor = NSColor.tableBackgroundColor.cgColor
        listContainer.layer?.cornerRadius = TableGroupView.cornerRadius
        listContainer.layer?.borderColor = NSColor.tableBorderColor.cgColor
        listContainer.layer?.borderWidth = TableGroupView.borderWidth

        // Defaults row (fixed at top)
        let defaultsRow = ShortcutSidebarRow()
        defaultsRow.setContent(NSLocalizedString("Defaults", comment: ""), NSLocalizedString("Applied to all", comment: ""))
        defaultsRow.onClick = { _, _ in selectDefaults() }
        defaultsRow.onMouseEntered = { _, _ in defaultsRow.setHovered(true) }
        defaultsRow.onMouseExited = { _, _ in defaultsRow.setHovered(false) }
        defaultsSidebarRow = defaultsRow

        let defaultsSeparator = NSView()
        defaultsSeparator.translatesAutoresizingMaskIntoConstraints = false
        defaultsSeparator.wantsLayer = true
        defaultsSeparator.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor

        // Scrollable shortcut rows
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        shortcutRowsStackView = rows

        let rowsScrollView = ShortcutsSidebarScrollView()
        rowsScrollView.translatesAutoresizingMaskIntoConstraints = false
        rowsScrollView.drawsBackground = false
        rowsScrollView.hasVerticalScroller = true
        rowsScrollView.hasHorizontalScroller = false
        rowsScrollView.scrollerStyle = .overlay
        rowsScrollView.verticalScrollElasticity = .none
        rowsScrollView.usesPredominantAxisScrolling = true
        let documentView = FlippedView(frame: .zero)
        documentView.translatesAutoresizingMaskIntoConstraints = false
        rowsScrollView.documentView = documentView
        documentView.addSubview(rows)

        // Gesture separator & row (fixed at bottom)
        let gestureSeparator = NSView()
        gestureSeparator.translatesAutoresizingMaskIntoConstraints = false
        gestureSeparator.wantsLayer = true
        gestureSeparator.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor

        let gestureRow = ShortcutSidebarRow()
        gestureRow.onClick = { _, _ in selectGesture() }
        gestureRow.onMouseEntered = { _, _ in gestureRow.setHovered(true) }
        gestureRow.onMouseExited = { _, _ in gestureRow.setHovered(false) }
        gestureSidebarRow = gestureRow

        listContainer.addSubview(defaultsRow)
        listContainer.addSubview(defaultsSeparator)
        listContainer.addSubview(rowsScrollView)
        listContainer.addSubview(gestureSeparator)
        listContainer.addSubview(gestureRow)

        // +/- buttons
        let countButtons = NSSegmentedControl(labels: ["+", "-"], trackingMode: .momentary,
            target: self, action: #selector(updateShortcutCount(_:)))
        countButtons.translatesAutoresizingMaskIntoConstraints = false
        countButtons.segmentStyle = .rounded
        countButtons.setWidth(28, forSegment: 0)
        countButtons.setWidth(28, forSegment: 1)
        shortcutCountButtons = countButtons

        let buttonsRow = NSStackView(views: [countButtons])
        buttonsRow.orientation = .horizontal
        buttonsRow.alignment = .leading
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(listContainer)
        sidebar.addSubview(buttonsRow)

        NSLayoutConstraint.activate([
            // List container
            listContainer.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 10),
            listContainer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            listContainer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            listContainer.bottomAnchor.constraint(equalTo: buttonsRow.topAnchor, constant: -10),
            // Defaults row at top
            defaultsRow.topAnchor.constraint(equalTo: listContainer.topAnchor),
            defaultsRow.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            defaultsRow.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            defaultsRow.heightAnchor.constraint(equalToConstant: sidebarRowHeight),
            // Defaults separator
            defaultsSeparator.topAnchor.constraint(equalTo: defaultsRow.bottomAnchor),
            defaultsSeparator.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            defaultsSeparator.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            defaultsSeparator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth),
            // Scroll view for shortcut rows
            rowsScrollView.topAnchor.constraint(equalTo: defaultsSeparator.bottomAnchor),
            rowsScrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            rowsScrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            rowsScrollView.bottomAnchor.constraint(equalTo: gestureSeparator.topAnchor),
            documentView.widthAnchor.constraint(equalTo: rowsScrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: rowsScrollView.contentView.heightAnchor),
            rows.topAnchor.constraint(equalTo: documentView.topAnchor),
            rows.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            rows.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            // Gesture separator
            gestureSeparator.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            gestureSeparator.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            gestureSeparator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth),
            gestureSeparator.bottomAnchor.constraint(equalTo: gestureRow.topAnchor),
            // Gesture row
            gestureRow.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            gestureRow.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            gestureRow.heightAnchor.constraint(equalToConstant: sidebarRowHeight),
            gestureRow.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            // Buttons
            buttonsRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            buttonsRow.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -10),
        ])

        refreshGestureRow()
        return sidebar
    }

    // MARK: - Simple Mode Editor (full-width, no overrides, includes trigger)

    private static func makeSimpleModeEditor() -> NSView {
        let width = SettingsWindow.contentWidth

        let syncInherited: ActionClosure = { _ in
            snapshotAllDefaults()
            refreshInheritedControlValues()
        }

        let table = TableGroupView(width: width)

        // TRIGGER section
        table.addNewTable()
        let holdName = Preferences.indexToName("holdShortcut", 0)
        let holdValue = UserDefaults.standard.string(forKey: holdName) ?? ""
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(
            NSLocalizedString("Hold", comment: ""), holdName, holdValue, false,
            labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press", comment: "")))
        let nextName = Preferences.indexToName("nextWindowShortcut", 0)
        let nextValue = UserDefaults.standard.string(forKey: nextName) ?? ""
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(
            NSLocalizedString("Select next window", comment: ""), nextName, nextValue,
            labelPosition: .right)
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Trigger", comment: ""),
            rightViews: holdShortcut + [nextWindowShortcut[0]]))

        // APPEARANCE section
        table.addNewTable()
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Appearance", comment: ""), bold: true)], rightViews: nil)
        table.addRow(secondaryViews: [LabelAndControl.makeImageRadioButtons("appearanceStyle",
            AppearanceStylePreference.allCases, extraAction: syncInherited, buttonSpacing: 10)], secondaryViewsAlignment: .centerX)
        table.addRow(leftText: NSLocalizedString("Size", comment: ""),
            rightViews: [LabelAndControl.makeSegmentedControl("appearanceSize",
                AppearanceSizePreference.allCases, segmentWidth: 100, extraAction: syncInherited)])
        table.addRow(leftText: NSLocalizedString("Theme", comment: ""),
            rightViews: [LabelAndControl.makeSegmentedControl("appearanceTheme",
                AppearanceThemePreference.allCases, segmentWidth: 100, extraAction: syncInherited)])

        // FILTERING section
        table.addNewTable()
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Filtering", comment: ""), bold: true)], rightViews: nil)
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from applications", comment: ""))],
            rightViews: [LabelAndControl.makeDropdown("appsToShow", AppsToShowPreference.allCases, extraAction: syncInherited)])
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from Spaces", comment: ""))],
            rightViews: [LabelAndControl.makeDropdown("spacesToShow", SpacesToShowPreference.allCases, extraAction: syncInherited)])
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from screens", comment: ""))],
            rightViews: [LabelAndControl.makeDropdown("screensToShow", ScreensToShowPreference.allCases, extraAction: syncInherited)])
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show minimized windows", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("showMinimizedWindows", ShowHowPreference.allCases, extraAction: syncInherited)]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show hidden windows", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("showHiddenWindows", ShowHowPreference.allCases, extraAction: syncInherited)]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show fullscreen windows", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("showFullscreenWindows",
                ShowHowPreference.allCases.filter { $0 != .showAtTheEnd }, extraAction: syncInherited)]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show apps with no open window", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("showWindowlessApps", ShowHowPreference.allCases, extraAction: syncInherited)]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Order windows by", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("windowOrder", WindowOrderPreference.allCases, extraAction: syncInherited)]))

        // BEHAVIOR section
        table.addNewTable()
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Behavior", comment: ""), bold: true)], rightViews: nil)
        table.addRow(leftText: NSLocalizedString("After keys are released", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("shortcutStyle", ShortcutStylePreference.allCases, extraAction: syncInherited)])

        // MULTIPLE SCREENS section
        table.addNewTable()
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Multiple screens", comment: ""), bold: true)], rightViews: nil)
        table.addRow(leftText: NSLocalizedString("Show on", comment: ""),
            rightViews: LabelAndControl.makeDropdown("showOnScreen", ShowOnScreenPreference.allCases, extraAction: syncInherited))

        return table
    }

    // MARK: - Defaults Editor (no overrides)

    private static func makeDefaultsEditor() -> NSView {
        let width = shortcutEditorWidth
        let table = TableGroupView(width: width)

        // Explanatory hint
        let hint = NSTextField(labelWithString: NSLocalizedString(
            "These settings apply to all shortcuts. Individual shortcuts can override any setting below.", comment: ""))
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = width - 20
        hint.translatesAutoresizingMaskIntoConstraints = false
        let hintWrapper = NSStackView(views: [hint])
        hintWrapper.orientation = .vertical
        hintWrapper.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 2, right: 0)
        table.addRow(leftViews: [hintWrapper], rightViews: nil)

        // Snapshot all initial Defaults values so inherited controls can read the "true" defaults
        // even after a per-shortcut override writes to the same UserDefaults key.
        snapshotAllDefaults()

        // Callback to propagate Defaults changes to all inherited (greyed-out) controls in real time
        let syncInherited: ActionClosure = { _ in
            snapshotAllDefaults()
            refreshInheritedControlValues()
        }

        // APPEARANCE section
        table.addNewTable()
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Appearance", comment: ""), bold: true)], rightViews: nil)
        table.addRow(secondaryViews: [LabelAndControl.makeImageRadioButtons("appearanceStyle",
            AppearanceStylePreference.allCases, extraAction: syncInherited, buttonSpacing: 10)], secondaryViewsAlignment: .centerX)
        table.addRow(leftText: NSLocalizedString("Size", comment: ""),
            rightViews: [LabelAndControl.makeSegmentedControl("appearanceSize",
                AppearanceSizePreference.allCases, segmentWidth: 100, extraAction: syncInherited)])
        table.addRow(leftText: NSLocalizedString("Theme", comment: ""),
            rightViews: [LabelAndControl.makeSegmentedControl("appearanceTheme",
                AppearanceThemePreference.allCases, segmentWidth: 100, extraAction: syncInherited)])

        // FILTERING section
        table.addNewTable()
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Filtering", comment: ""), bold: true)], rightViews: nil)
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from applications", comment: ""))],
            rightViews: [LabelAndControl.makeDropdown("appsToShow", AppsToShowPreference.allCases, extraAction: syncInherited)])
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from Spaces", comment: ""))],
            rightViews: [LabelAndControl.makeDropdown("spacesToShow", SpacesToShowPreference.allCases, extraAction: syncInherited)])
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from screens", comment: ""))],
            rightViews: [LabelAndControl.makeDropdown("screensToShow", ScreensToShowPreference.allCases, extraAction: syncInherited)])
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show minimized windows", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("showMinimizedWindows", ShowHowPreference.allCases, extraAction: syncInherited)]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show hidden windows", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("showHiddenWindows", ShowHowPreference.allCases, extraAction: syncInherited)]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show fullscreen windows", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("showFullscreenWindows",
                ShowHowPreference.allCases.filter { $0 != .showAtTheEnd }, extraAction: syncInherited)]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show apps with no open window", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("showWindowlessApps", ShowHowPreference.allCases, extraAction: syncInherited)]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Order windows by", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("windowOrder", WindowOrderPreference.allCases, extraAction: syncInherited)]))

        // BEHAVIOR section
        table.addNewTable()
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Behavior", comment: ""), bold: true)], rightViews: nil)
        table.addRow(leftText: NSLocalizedString("After keys are released", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("shortcutStyle", ShortcutStylePreference.allCases, extraAction: syncInherited)])

        // MULTIPLE SCREENS section
        table.addNewTable()
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Multiple screens", comment: ""), bold: true)], rightViews: nil)
        table.addRow(leftText: NSLocalizedString("Show on", comment: ""),
            rightViews: LabelAndControl.makeDropdown("showOnScreen", ShowOnScreenPreference.allCases, extraAction: syncInherited))

        return table
    }

    // MARK: - Shortcut Editor (with overrides)

    private static func makeShortcutEditor(index: Int) -> NSView {
        let width = shortcutEditorWidth

        // Override tracking
        let footerLabel = NSTextField(labelWithString: "")
        footerLabel.font = NSFont.systemFont(ofSize: 11)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        let resetAllButton = makeResetAllButton()
        let tracker = OverrideTracker(footerLabel: footerLabel, resetAllButton: resetAllButton)
        resetAllButton.onAction = { [weak tracker] _ in tracker?.resetAll() }

        let table = TableGroupView(width: width)

        // Inheritance hint
        let hint = NSTextField(labelWithString: NSLocalizedString(
            "Greyed-out settings are inherited from Defaults. Click any to customize it for this shortcut, or ↺ to reset.", comment: ""))
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = width - 20
        hint.translatesAutoresizingMaskIntoConstraints = false
        let hintWrapper = NSStackView(views: [hint])
        hintWrapper.orientation = .vertical
        hintWrapper.alignment = .leading
        hintWrapper.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 2, right: 0)
        table.addRow(leftViews: [hintWrapper], rightViews: nil)

        // TRIGGER section (not overridable — always per-shortcut)
        table.addNewTable()
        let holdName = Preferences.indexToName("holdShortcut", index)
        let holdValue = UserDefaults.standard.string(forKey: holdName) ?? ""
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(
            NSLocalizedString("Hold", comment: ""), holdName, holdValue, false,
            labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press", comment: "")))
        let nextName = Preferences.indexToName("nextWindowShortcut", index)
        let nextValue = UserDefaults.standard.string(forKey: nextName) ?? ""
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(
            NSLocalizedString("Select next window", comment: ""), nextName, nextValue,
            labelPosition: .right)
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Trigger", comment: ""),
            rightViews: holdShortcut + [nextWindowShortcut[0]]))

        // APPEARANCE section (overridable)
        table.addNewTable()
        let appearanceTitle = TableGroupView.makeText(NSLocalizedString("Appearance", comment: ""), bold: true)
        tracker.registerSectionTitle(appearanceTitle, section: "Appearance")
        table.addRow(leftViews: [appearanceTitle], rightViews: nil)
        addOverridableImageRadioRow(table, tracker: tracker, settingName: "appearanceStyle",
            preferences: AppearanceStylePreference.allCases, section: "Appearance", index: index)
        addOverridableSegmentRow(table, tracker: tracker, settingName: "appearanceSize",
            label: NSLocalizedString("Size", comment: ""),
            preferences: AppearanceSizePreference.allCases, segmentWidth: 100, section: "Appearance", index: index)
        addOverridableSegmentRow(table, tracker: tracker, settingName: "appearanceTheme",
            label: NSLocalizedString("Theme", comment: ""),
            preferences: AppearanceThemePreference.allCases, segmentWidth: 100, section: "Appearance", index: index)

        // FILTERING section (overridable)
        table.addNewTable()
        let filteringTitle = TableGroupView.makeText(NSLocalizedString("Filtering", comment: ""), bold: true)
        tracker.registerSectionTitle(filteringTitle, section: "Filtering")
        table.addRow(leftViews: [filteringTitle], rightViews: nil)
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("appsToShow", index), defaultsSettingName: "appsToShow",
            label: NSLocalizedString("Show windows from applications", comment: ""),
            preferences: AppsToShowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("spacesToShow", index), defaultsSettingName: "spacesToShow",
            label: NSLocalizedString("Show windows from Spaces", comment: ""),
            preferences: SpacesToShowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("screensToShow", index), defaultsSettingName: "screensToShow",
            label: NSLocalizedString("Show windows from screens", comment: ""),
            preferences: ScreensToShowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("showMinimizedWindows", index), defaultsSettingName: "showMinimizedWindows",
            label: NSLocalizedString("Show minimized windows", comment: ""),
            preferences: ShowHowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("showHiddenWindows", index), defaultsSettingName: "showHiddenWindows",
            label: NSLocalizedString("Show hidden windows", comment: ""),
            preferences: ShowHowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("showFullscreenWindows", index), defaultsSettingName: "showFullscreenWindows",
            label: NSLocalizedString("Show fullscreen windows", comment: ""),
            preferences: ShowHowPreference.allCases.filter { $0 != .showAtTheEnd }, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("showWindowlessApps", index), defaultsSettingName: "showWindowlessApps",
            label: NSLocalizedString("Show apps with no open window", comment: ""),
            preferences: ShowHowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("windowOrder", index), defaultsSettingName: "windowOrder",
            label: NSLocalizedString("Order windows by", comment: ""),
            preferences: WindowOrderPreference.allCases, section: "Filtering")

        // BEHAVIOR section (overridable)
        table.addNewTable()
        let behaviorTitle = TableGroupView.makeText(NSLocalizedString("Behavior", comment: ""), bold: true)
        tracker.registerSectionTitle(behaviorTitle, section: "Behavior")
        table.addRow(leftViews: [behaviorTitle], rightViews: nil)
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("shortcutStyle", index), defaultsSettingName: "shortcutStyle",
            label: NSLocalizedString("After keys are released", comment: ""),
            preferences: ShortcutStylePreference.allCases, section: "Behavior")

        // MULTIPLE SCREENS section (overridable)
        table.addNewTable()
        let screensTitle = TableGroupView.makeText(NSLocalizedString("Multiple screens", comment: ""), bold: true)
        tracker.registerSectionTitle(screensTitle, section: "Multiple screens")
        table.addRow(leftViews: [screensTitle], rightViews: nil)
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: "showOnScreen",
            label: NSLocalizedString("Show on", comment: ""),
            preferences: ShowOnScreenPreference.allCases, section: "Multiple screens")

        // Footer
        table.addNewTable()
        table.addRow(leftViews: [footerLabel], rightViews: [resetAllButton])

        // Pre-activate demo overrides for Shortcut 1
        if index == 0 {
            preActivateDemoOverrides(in: table, tracker: tracker)
        }

        return table
    }

    // MARK: - Gesture Editor

    private static func makeGestureEditor() -> NSView {
        let width = shortcutEditorWidth
        let index = Preferences.gestureIndex

        let footerLabel = NSTextField(labelWithString: "")
        footerLabel.font = NSFont.systemFont(ofSize: 11)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        let gestureResetAllButton = makeResetAllButton()
        let tracker = OverrideTracker(footerLabel: footerLabel, resetAllButton: gestureResetAllButton)
        gestureResetAllButton.onAction = { [weak tracker] _ in tracker?.resetAll() }

        let table = TableGroupView(width: width)

        // TRIGGER section (gesture-specific, not overridable)
        let message = NSLocalizedString("You may need to disable some conflicting system gestures", comment: "")
        let button = NSButton(title: NSLocalizedString("Open Trackpad Settings…", comment: ""),
            target: self, action: #selector(openSystemGestures(_:)))
        let infoBtn = LabelAndControl.makeInfoButton(searchableTooltipTexts: [message], onMouseEntered: { event, view in
            Popover.shared.show(event: event, positioningView: view, message: message, extraView: button)
        })
        let gesture = LabelAndControl.makeDropdown("nextWindowGesture", GesturePreference.allCases)
        let gestureWithTooltip = NSStackView()
        gestureWithTooltip.orientation = .horizontal
        gestureWithTooltip.alignment = .centerY
        gestureWithTooltip.setViews([gesture], in: .trailing)
        gestureWithTooltip.setViews([infoBtn], in: .leading)
        // Inheritance hint
        let gestureHint = NSTextField(labelWithString: NSLocalizedString(
            "Greyed-out settings are inherited from Defaults. Click any to customize it for this gesture, or ↺ to reset.", comment: ""))
        gestureHint.font = NSFont.systemFont(ofSize: 11)
        gestureHint.textColor = .tertiaryLabelColor
        gestureHint.lineBreakMode = .byWordWrapping
        gestureHint.preferredMaxLayoutWidth = width - 20
        gestureHint.translatesAutoresizingMaskIntoConstraints = false
        let gestureHintWrapper = NSStackView(views: [gestureHint])
        gestureHintWrapper.orientation = .vertical
        gestureHintWrapper.alignment = .leading
        gestureHintWrapper.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 2, right: 0)
        table.addRow(leftViews: [gestureHintWrapper], rightViews: nil)

        // TRIGGER section (gesture-specific, not overridable)
        table.addNewTable()
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Trigger", comment: ""),
            rightViews: [gestureWithTooltip]))

        // FILTERING section (overridable)
        table.addNewTable()
        let gestureFilteringTitle = TableGroupView.makeText(NSLocalizedString("Filtering", comment: ""), bold: true)
        tracker.registerSectionTitle(gestureFilteringTitle, section: "Filtering")
        table.addRow(leftViews: [gestureFilteringTitle], rightViews: nil)
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("appsToShow", index), defaultsSettingName: "appsToShow",
            label: NSLocalizedString("Show windows from applications", comment: ""),
            preferences: AppsToShowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("spacesToShow", index), defaultsSettingName: "spacesToShow",
            label: NSLocalizedString("Show windows from Spaces", comment: ""),
            preferences: SpacesToShowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("screensToShow", index), defaultsSettingName: "screensToShow",
            label: NSLocalizedString("Show windows from screens", comment: ""),
            preferences: ScreensToShowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("showMinimizedWindows", index), defaultsSettingName: "showMinimizedWindows",
            label: NSLocalizedString("Show minimized windows", comment: ""),
            preferences: ShowHowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("showHiddenWindows", index), defaultsSettingName: "showHiddenWindows",
            label: NSLocalizedString("Show hidden windows", comment: ""),
            preferences: ShowHowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("showFullscreenWindows", index), defaultsSettingName: "showFullscreenWindows",
            label: NSLocalizedString("Show fullscreen windows", comment: ""),
            preferences: ShowHowPreference.allCases.filter { $0 != .showAtTheEnd }, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("showWindowlessApps", index), defaultsSettingName: "showWindowlessApps",
            label: NSLocalizedString("Show apps with no open window", comment: ""),
            preferences: ShowHowPreference.allCases, section: "Filtering")
        addOverridableDropdownRow(table, tracker: tracker,
            settingName: Preferences.indexToName("windowOrder", index), defaultsSettingName: "windowOrder",
            label: NSLocalizedString("Order windows by", comment: ""),
            preferences: WindowOrderPreference.allCases, section: "Filtering")

        // Footer
        table.addNewTable()
        table.addRow(leftViews: [footerLabel], rightViews: [gestureResetAllButton])

        return table
    }

    // MARK: - Override Helpers

    private static func makeResetAllButton() -> NSButton {
        let button: NSButton
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset All") {
            button = NSButton(title: NSLocalizedString("Reset All", comment: ""), image: image, target: nil, action: nil)
            button.imagePosition = .imageTrailing
        } else {
            button = NSButton(title: NSLocalizedString("Reset All ↺", comment: ""), target: nil, action: nil)
        }
        button.bezelStyle = .inline
        button.font = NSFont.systemFont(ofSize: 11)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.alphaValue = 0.0
        return button
    }

    private static func addOverridableDropdownRow(_ table: TableGroupView,
                                                   tracker: OverrideTracker,
                                                   settingName: String,
                                                   defaultsSettingName: String? = nil,
                                                   label: String,
                                                   preferences: [MacroPreference],
                                                   section: String) {
        var overridableRef: OverridableRowView?
        let inheritedKey = defaultsSettingName ?? settingName
        let dropdown = LabelAndControl.makeDropdown(inheritedKey, preferences)
        // Chain override activation into the control's own action so direct clicks also activate
        dropdown.onAction = {
            LabelAndControl.controlWasChanged($0, nil)
            overridableRef?.activateOverride()
        }
        let leftLabel = TableGroupView.makeText(label)
        let overridable = OverridableRowView(settingName: settingName, control: dropdown, leftLabel: leftLabel)
        overridableRef = overridable
        overridable.refreshControl = { [weak dropdown] in
            guard let dropdown else { return }
            let index = defaultsSnapshot[inheritedKey] ?? CachedUserDefaults.intFromMacroPref(inheritedKey, preferences)
            if index >= 0, index < dropdown.numberOfItems { dropdown.selectItem(at: index) }
        }
        tracker.registerSetting(settingName, section: section)
        tracker.registerRow(overridable)
        overridable.onOverrideChanged = { name, isOverridden in
            tracker.settingChanged(name, isOverridden: isOverridden)
        }
        allOverridableRows.append(overridable)
        table.addRow(leftViews: [leftLabel], rightViews: [overridable])
    }

    private static func addOverridableSegmentRow(_ table: TableGroupView,
                                                  tracker: OverrideTracker,
                                                  settingName: String,
                                                  defaultsSettingName: String? = nil,
                                                  label: String,
                                                  preferences: [MacroPreference],
                                                  segmentWidth: CGFloat,
                                                  section: String,
                                                  index: Int) {
        var overridableRef: OverridableRowView?
        let inheritedKey = defaultsSettingName ?? settingName
        let control = LabelAndControl.makeSegmentedControl(inheritedKey, preferences, segmentWidth: segmentWidth)
        // Chain override activation into the control's own action so direct clicks also activate
        control.onAction = {
            LabelAndControl.controlWasChanged($0, nil)
            overridableRef?.activateOverride()
        }
        let leftLabel = TableGroupView.makeText(label)
        let overridable = OverridableRowView(settingName: settingName, control: control, leftLabel: leftLabel)
        overridableRef = overridable
        overridable.refreshControl = { [weak control] in
            guard let control else { return }
            let selected = defaultsSnapshot[inheritedKey] ?? CachedUserDefaults.intFromMacroPref(inheritedKey, preferences)
            if selected >= 0, selected < control.segmentCount { control.selectedSegment = selected }
        }
        tracker.registerSetting(settingName, section: section)
        tracker.registerRow(overridable)
        overridable.onOverrideChanged = { name, isOverridden in
            tracker.settingChanged(name, isOverridden: isOverridden)
        }
        allOverridableRows.append(overridable)
        table.addRow(leftViews: [leftLabel], rightViews: [overridable])
    }

    private static func addOverridableImageRadioRow(_ table: TableGroupView,
                                                     tracker: OverrideTracker,
                                                     settingName: String,
                                                     defaultsSettingName: String? = nil,
                                                     preferences: [ImageMacroPreference],
                                                     section: String,
                                                     index: Int) {
        // Use a weak ref so the extraAction closure can trigger override activation
        var overridableRef: OverridableRowView?
        let inheritedKey = defaultsSettingName ?? settingName
        let control = LabelAndControl.makeImageRadioButtons(inheritedKey, preferences, extraAction: { _ in
            overridableRef?.activateOverride()
        }, buttonSpacing: 10)
        let overridable = OverridableRowView(settingName: settingName, control: control, layout: .horizontal)
        overridableRef = overridable
        overridable.refreshControl = { [weak control] in
            guard let control else { return }
            let selected = defaultsSnapshot[inheritedKey] ?? CachedUserDefaults.intFromMacroPref(inheritedKey, preferences)
            for (i, subview) in control.arrangedSubviews.enumerated() {
                if let btn = subview as? ImageTextButtonView {
                    btn.state = i == selected ? .on : .off
                }
            }
        }
        tracker.registerSetting(settingName, section: section)
        tracker.registerRow(overridable)
        overridable.onOverrideChanged = { name, isOverridden in
            tracker.settingChanged(name, isOverridden: isOverridden)
        }
        allOverridableRows.append(overridable)
        table.addRow(secondaryViews: [overridable], secondaryViewsAlignment: .centerX)
    }

    /// Pre-activates a few overrides on Shortcut 1 for demo purposes.
    private static func preActivateDemoOverrides(in table: TableGroupView, tracker: OverrideTracker) {
        // Find OverridableRowViews in the table hierarchy and activate some
        var overridables = [OverridableRowView]()
        findOverridableRows(in: table, result: &overridables)
        // Activate overrides for style and showMinimizedWindows (first two we find that match)
        for row in overridables {
            if row.settingName == "appearanceStyle" || row.settingName.hasPrefix("showMinimizedWindows") {
                row.setOverridden(true)
            }
        }
    }

    private static func findOverridableRows(in view: NSView, result: inout [OverridableRowView]) {
        if let overridable = view as? OverridableRowView {
            result.append(overridable)
        }
        for subview in view.subviews {
            findOverridableRows(in: subview, result: &result)
        }
    }

    // MARK: - Selection Logic

    private static func selectDefaults() {
        selectedIndex = defaultsSelectionIndex
        refreshSelection()
        refreshShortcutCountButtons()
    }

    private static func selectShortcut(_ index: Int) {
        guard (0..<Preferences.shortcutCount).contains(index) else { return }
        selectedIndex = index
        refreshSelection()
        refreshShortcutCountButtons()
    }

    private static func selectGesture() {
        selectedIndex = gestureSelectionIndex
        refreshSelection()
        refreshShortcutCountButtons()
    }

    private static func refreshUi() {
        if selectedIndex != gestureSelectionIndex && selectedIndex != defaultsSelectionIndex {
            selectedIndex = max(0, min(selectedIndex, Preferences.shortcutCount - 1))
        }
        refreshShortcutRows()
        refreshGestureRow()
        refreshSelection()
        refreshShortcutCountButtons()
    }

    private static func refreshShortcutRows() {
        guard let rows = shortcutRowsStackView else { return }
        clearArrangedSubviews(rows)
        shortcutRows.removeAll(keepingCapacity: true)
        for index in 0..<Preferences.shortcutCount {
            let row = ShortcutSidebarRow()
            row.setContent(shortcutTitle(index), shortcutSummary(index))
            row.setSelected(index == selectedIndex)
            row.onClick = { _, _ in selectShortcut(index) }
            row.onMouseEntered = { _, _ in row.setHovered(true) }
            row.onMouseExited = { _, _ in row.setHovered(false) }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: sidebarRowHeight).isActive = true
            shortcutRows.append(row)
            if index < Preferences.shortcutCount - 1 {
                let separator = NSView()
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.wantsLayer = true
                separator.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
                rows.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
                separator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth).isActive = true
            }
        }
    }

    /// Updates only the text of existing sidebar rows without rebuilding them.
    private static func refreshSidebarRowTexts() {
        for (i, row) in shortcutRows.enumerated() where i < Preferences.shortcutCount {
            row.setContent(shortcutTitle(i), shortcutSummary(i))
        }
        refreshGestureRow()
    }

    private static func refreshSelection() {
        let isSimpleMode = !CachedUserDefaults.bool("multipleShortcutsEnabled")

        // Simple mode: show only the simple editor, hide everything else
        simpleModeEditorView?.isHidden = !isSimpleMode
        if isSimpleMode {
            defaultsEditorView?.isHidden = true
            shortcutEditorViews.forEach { $0.isHidden = true }
            gestureEditorView?.isHidden = true
            return
        }

        // Multi mode: selection-based editor visibility
        defaultsSidebarRow?.setSelected(selectedIndex == defaultsSelectionIndex)
        defaultsEditorView?.isHidden = selectedIndex != defaultsSelectionIndex

        // Shortcuts
        shortcutRows.enumerated().forEach { $1.setSelected($0 == selectedIndex) }
        shortcutEditorViews.enumerated().forEach { index, view in
            view.isHidden = index != selectedIndex || index >= Preferences.shortcutCount
        }

        // Gesture
        gestureSidebarRow?.setSelected(selectedIndex == gestureSelectionIndex)
        gestureEditorView?.isHidden = selectedIndex != gestureSelectionIndex

        // Sync inherited controls to current UserDefaults values
        refreshInheritedControlValues()
    }

    /// Re-reads UserDefaults values into all non-overridden (inherited) controls.
    private static func refreshInheritedControlValues() {
        for row in allOverridableRows where !row.isOverridden {
            row.refreshControl?()
        }
    }

    /// Captures the current UserDefaults value for every Defaults editor setting.
    /// Called once at init and again each time the Defaults editor changes a control.
    private static func snapshotAllDefaults() {
        func snap(_ key: String, _ prefs: [MacroPreference]) {
            defaultsSnapshot[key] = CachedUserDefaults.intFromMacroPref(key, prefs)
        }
        snap("appearanceStyle", AppearanceStylePreference.allCases)
        snap("appearanceSize", AppearanceSizePreference.allCases)
        snap("appearanceTheme", AppearanceThemePreference.allCases)
        snap("appsToShow", AppsToShowPreference.allCases)
        snap("spacesToShow", SpacesToShowPreference.allCases)
        snap("screensToShow", ScreensToShowPreference.allCases)
        snap("showMinimizedWindows", ShowHowPreference.allCases)
        snap("showHiddenWindows", ShowHowPreference.allCases)
        snap("showFullscreenWindows", ShowHowPreference.allCases)
        snap("showWindowlessApps", ShowHowPreference.allCases)
        snap("windowOrder", WindowOrderPreference.allCases)
        snap("shortcutStyle", ShortcutStylePreference.allCases)
        snap("showOnScreen", ShowOnScreenPreference.allCases)
    }

    private static func refreshShortcutCountButtons() {
        shortcutCountButtons?.setEnabled(Preferences.shortcutCount < Preferences.maxShortcutCount, forSegment: 0)
        shortcutCountButtons?.setEnabled(
            Preferences.shortcutCount > Preferences.minShortcutCount
            && selectedIndex >= 0 && selectedIndex < Preferences.shortcutCount,
            forSegment: 1)
    }

    private static func refreshGestureRow() {
        guard let gestureSidebarRow else { return }
        let gestureIndex = Int(UserDefaults.standard.string(forKey: "nextWindowGesture") ?? "0") ?? 0
        let gesture = GesturePreference.allCases[safe: gestureIndex] ?? .disabled
        gestureSidebarRow.setContent(
            NSLocalizedString("Gesture", comment: ""),
            gesture.localizedString)
        gestureSidebarRow.setSelected(selectedIndex == gestureSelectionIndex)
    }

    // MARK: - Sidebar Helpers

    private static func shortcutTitle(_ index: Int) -> String {
        NSLocalizedString("Shortcut", comment: "") + " " + String(index + 1)
    }

    private static func shortcutSummary(_ index: Int) -> String {
        let holdShortcut = UserDefaults.standard.string(forKey: Preferences.indexToName("holdShortcut", index)) ?? ""
        let nextWindowShortcut = UserDefaults.standard.string(forKey: Preferences.indexToName("nextWindowShortcut", index)) ?? ""
        if nextWindowShortcut.isEmpty { return NSLocalizedString("Not configured", comment: "") }
        return holdShortcut + " + " + nextWindowShortcut
    }

    private static func clearArrangedSubviews(_ stackView: NSStackView) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    // MARK: - Actions

    @objc private static func updateShortcutCount(_ sender: NSSegmentedControl) {
        let segment = sender.selectedSegment
        sender.selectedSegment = -1
        if segment == 0 {
            addShortcutSlot()
        } else if segment == 1 && selectedIndex >= 0 {
            removeShortcutSlot()
        }
    }

    private static func addShortcutSlot() {
        let currentCount = Preferences.shortcutCount
        guard currentCount < Preferences.maxShortcutCount else { return }
        // Set minimal defaults for the new shortcut
        Preferences.set(Preferences.indexToName("holdShortcut", currentCount), "⌥", false)
        Preferences.set(Preferences.indexToName("nextWindowShortcut", currentCount), "", false)
        Preferences.set(Preferences.indexToName("appsToShow", currentCount), AppsToShowPreference.all.indexAsString, false)
        selectedIndex = currentCount
        Preferences.set("shortcutCount", String(currentCount + 1))
        refreshUi()
    }

    /// Per-shortcut preference keys that need shifting/clearing on removal.
    private static let perShortcutPreferences = [
        "holdShortcut", "nextWindowShortcut",
        "appsToShow", "spacesToShow", "screensToShow",
        "showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows", "showWindowlessApps",
        "windowOrder", "shortcutStyle",
    ]

    private static func removeShortcutSlot() {
        let currentCount = Preferences.shortcutCount
        guard currentCount > Preferences.minShortcutCount, selectedIndex >= 0, selectedIndex < currentCount else { return }
        let removedIndex = selectedIndex
        // Shift preferences from shortcuts after the removed one down by one
        if removedIndex < currentCount - 1 {
            for index in removedIndex..<(currentCount - 1) {
                copyShortcutPreferences(from: index + 1, to: index)
            }
        }
        // Clear the last slot (now a duplicate of second-to-last)
        resetShortcutPreferences(currentCount - 1)
        selectedIndex = min(removedIndex, currentCount - 2)
        Preferences.set("shortcutCount", String(currentCount - 1))
        refreshUi()
    }

    private static func copyShortcutPreferences(from fromIndex: Int, to toIndex: Int) {
        perShortcutPreferences.forEach { baseName in
            let fromKey = Preferences.indexToName(baseName, fromIndex)
            let toKey = Preferences.indexToName(baseName, toIndex)
            if let value = UserDefaults.standard.string(forKey: fromKey) {
                Preferences.set(toKey, value, false)
            } else {
                Preferences.remove(toKey, false)
            }
        }
    }

    private static func resetShortcutPreferences(_ index: Int) {
        perShortcutPreferences.forEach {
            Preferences.remove(Preferences.indexToName($0, index), false)
        }
    }

    @objc static func showAdditionalControlsSettings() {
        App.app.settingsWindow.beginSheetWithSearchHighlight(additionalControlsSheet)
    }

    @objc private static func openSystemGestures(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
    }

    // MARK: - Multiple Shortcuts Toggle

    @objc private static func multipleShortcutsToggled(_ sender: NSButton) {
        if sender.state == .on {
            enableMultipleShortcuts()
        } else {
            disableMultipleShortcuts(sender)
        }
    }

    private static func enableMultipleShortcuts() {
        Preferences.set("multipleShortcutsEnabled", "true")
        setSidebarVisible(true)
        refreshUi()
    }

    private static func disableMultipleShortcuts(_ checkbox: NSButton) {
        let gestureValue = UserDefaults.standard.string(forKey: "nextWindowGesture") ?? GesturePreference.disabled.indexAsString
        let gestureEnabled = gestureValue != GesturePreference.disabled.indexAsString
        let hasMultipleShortcuts = Preferences.shortcutCount > 1
        let hasOverrides = shortcut1HasAnyOverrides()

        if !gestureEnabled && !hasMultipleShortcuts && !hasOverrides {
            performDisableMultipleShortcuts()
            return
        }

        // Build warning listing what will be lost
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Disable Multiple Shortcuts?", comment: "")
        var warnings = [String]()
        if hasMultipleShortcuts {
            let extra = Preferences.shortcutCount - 1
            warnings.append("• " + String(format: NSLocalizedString("%d extra shortcut(s) will be removed", comment: ""), extra))
        }
        if gestureEnabled {
            warnings.append("• " + NSLocalizedString("Gesture trigger will be disabled", comment: ""))
        }
        if hasOverrides {
            warnings.append("• " + NSLocalizedString("Custom overrides on Shortcut 1 will be reset", comment: ""))
        }
        alert.informativeText = warnings.joined(separator: "\n")
        alert.addButton(withTitle: NSLocalizedString("Disable", comment: "")).setAccessibilityFocused(true)
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"

        if alert.runModal() == .alertFirstButtonReturn {
            performDisableMultipleShortcuts()
        } else {
            checkbox.state = .on
        }
    }

    private static func performDisableMultipleShortcuts() {
        // Disable gesture
        Preferences.set("nextWindowGesture", GesturePreference.disabled.indexAsString)
        // Remove extra shortcuts
        let currentCount = Preferences.shortcutCount
        for index in 1..<currentCount {
            resetShortcutPreferences(index)
        }
        Preferences.set("shortcutCount", "1")
        // Reset Shortcut 1 overrides (UI state)
        if let editor = shortcutEditorViews.first {
            var rows = [OverridableRowView]()
            findOverridableRows(in: editor, result: &rows)
            for row in rows {
                row.setOverridden(false)
            }
        }
        Preferences.set("multipleShortcutsEnabled", "false")
        setSidebarVisible(false)
        selectedIndex = defaultsSelectionIndex
        refreshUi()
    }

    private static func shortcut1HasAnyOverrides() -> Bool {
        guard let editor = shortcutEditorViews.first else { return false }
        var rows = [OverridableRowView]()
        findOverridableRows(in: editor, result: &rows)
        return rows.contains { $0.isOverridden }
    }

    private static func setSidebarVisible(_ visible: Bool) {
        sidebarView?.isHidden = !visible
        sidebarSeparator?.isHidden = !visible
        sidebarWidthConstraint?.constant = visible ? shortcutSidebarWidth : 0
        separatorWidthConstraint?.constant = visible ? 1 : 0
        // Toggle grey box styling: bordered in multi mode, transparent in simple mode
        shortcutsContentView?.layer?.borderWidth = visible ? TableGroupView.borderWidth : 0
        shortcutsContentView?.layer?.backgroundColor = visible ? NSColor.tableBackgroundColor.cgColor : NSColor.clear.cgColor
    }
}
