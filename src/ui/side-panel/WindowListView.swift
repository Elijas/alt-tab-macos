import Cocoa

private class SpaceHeaderLabel: NSView {
    private var spaceId: CGSSpaceID = 0
    private var displayIndex: SpaceIndex = 0
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.wraps = true
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func configure(spaceId: CGSSpaceID, displayIndex: SpaceIndex, fontSize: CGFloat) {
        self.spaceId = spaceId
        self.displayIndex = displayIndex
        titleLabel.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        titleLabel.stringValue = Preferences.spaceLabel(for: spaceId, displayIndex: displayIndex)
        let background = WindowListView.separatorColor()
        titleLabel.textColor = background.hsvAwareTextColor
        layer?.backgroundColor = background.cgColor
    }

    func desiredHeight(forWidth width: CGFloat, baseHeight: CGFloat) -> CGFloat {
        let textWidth = width - 16  // 8pt leading + 8pt trailing padding
        let size = titleLabel.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude))
        let singleLineHeight = ceil(titleLabel.font?.boundingRectForFont.height ?? 14)
        // If text needs more than ~1.3 lines, double the header height
        return size.height > singleLineHeight * 1.3 ? baseHeight * 2 : baseHeight
    }

    func setIconsOnly(_ iconsOnly: Bool) {
        titleLabel.isHidden = iconsOnly
    }

    override func mouseDown(with event: NSEvent) {
        let alert = NSAlert()
        alert.messageText = "Rename Space \(displayIndex)"
        alert.informativeText = "Enter a custom name, or leave empty to reset to default."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = Preferences.spaceLabels[String(spaceId)] ?? ""
        input.placeholderString = "Space \(displayIndex)"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
            if newName.isEmpty {
                Preferences.setSpaceLabel(spaceId, nil)
            } else {
                Preferences.setSpaceLabel(spaceId, newName)
            }
            titleLabel.stringValue = Preferences.spaceLabel(for: spaceId, displayIndex: displayIndex)
        }
    }
}

class WindowListView: NSView {
    private static let separatorPadding: CGFloat = 0

    private enum LayoutElement {
        case row(Int)
        case separator(Int)
        case spaceHeader(Int)
    }

    private let scrollView = NSScrollView()
    private let contentStackView = NSView()
    private var rowPool = [SidePanelRow]()
    private var separatorPool = [NSView]()
    private var spaceHeaderPool = [SpaceHeaderLabel]()
    private var layoutOrder = [LayoutElement]()
    private var headerHeights = [CGFloat]()
    private(set) var separatorHeight: CGFloat
    let rowHeight: CGFloat
    private let compactRowHeight: CGFloat
    private let headerHeight: CGFloat
    private let fontSize: CGFloat
    private let wrapping: Bool
    private var minWidth: CGFloat
    private var iconsOnly: Bool = false
    var showTabHierarchy: Bool = false
    var verticalFillEnabled: Bool = true

    func applyIconsOnly(_ iconsOnly: Bool) {
        self.iconsOnly = iconsOnly
        self.minWidth = iconsOnly ? SidePanelRow.compactPanelWidth : SidePanelRow.panelWidth
        for row in rowPool { row.setIconsOnly(iconsOnly) }
        for header in spaceHeaderPool { header.setIconsOnly(iconsOnly) }
        relayoutForBounds()
    }

    init(separatorHeight: CGFloat = 7, fontSize: CGFloat = 12, wrapping: Bool = false, minWidth: CGFloat = 0) {
        self.separatorHeight = separatorHeight
        self.fontSize = fontSize
        self.wrapping = wrapping
        self.minWidth = minWidth
        self.rowHeight = SidePanelRow.rowHeight(fontSize: fontSize, wrapping: wrapping)
        self.compactRowHeight = SidePanelRow.rowHeight(fontSize: fontSize, wrapping: false)
        self.headerHeight = max(22, round(fontSize * 1.8))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        addSubview(scrollView)

        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentStackView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    /// Re-lays out rows using proportional heights when they fit, fixed height + scrolling otherwise.
    /// When wrapping is enabled, rows shrink proportionally down to `rowHeight` (wrapping min), then
    /// auto-switch to compact single-line mode down to `compactRowHeight`, then scroll.
    func relayoutForBounds() {
        let _perfStart = DispatchTime.now()
        let _perfSpan = PerfDebug.start("ui.windowList.relayoutForBounds", fields: ["order": layoutOrder.count, "icons_only": iconsOnly])
        defer {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - _perfStart.uptimeNanoseconds) / 1_000_000
            if ms > 10 { Logger.info { "[perf] WindowListView.relayoutForBounds \(String(format: "%.1f", ms))ms order=\(self.layoutOrder.count)" } }
            _perfSpan?.finish(["order": self.layoutOrder.count])
        }
        let width = max(bounds.width, minWidth)
        // Recompute header heights for current width (wrapping depends on available width)
        for case .spaceHeader(let i) in layoutOrder {
            headerHeights[i] = spaceHeaderPool[i].desiredHeight(forWidth: width, baseHeight: headerHeight)
        }
        let visibleRowCount = layoutOrder.filter { if case .row = $0 { return true }; return false }.count
        let emptyRowCount = layoutOrder.filter { if case .row(let i) = $0 { return rowPool[i].isEmpty }; return false }.count
        let windowRowCount = visibleRowCount - emptyRowCount
        let visibleSepCount = layoutOrder.filter { if case .separator = $0 { return true }; return false }.count
        let separatorTotalHeight = separatorHeight + Self.separatorPadding * 2
        let separatorSpace = CGFloat(visibleSepCount) * separatorTotalHeight
        let headerSpace = layoutOrder.reduce(CGFloat(0)) { acc, element in
            if case .spaceHeader(let i) = element { return acc + headerHeights[i] }
            return acc
        }
        // empty rows get capped at compactRowHeight; subtract their budget before distributing to window rows
        let emptyRowSpace = CGFloat(emptyRowCount) * compactRowHeight
        let availableForRows = bounds.height - separatorSpace - emptyRowSpace - headerSpace

        let proportionalHeight = windowRowCount > 0 ? availableForRows / CGFloat(windowRowCount) : 0

        let effectiveRowHeight: CGFloat
        let useWrapping: Bool
        let contentHeight: CGFloat
        if !verticalFillEnabled {
            // fixed row heights, no vertical stretching; scrollbar when content overflows
            // max() ensures content view fills the clip view so rows anchor to the top
            effectiveRowHeight = rowHeight
            useWrapping = wrapping
            let naturalHeight = CGFloat(windowRowCount) * rowHeight + CGFloat(emptyRowCount) * compactRowHeight + separatorSpace + headerSpace
            contentHeight = max(naturalHeight, bounds.height)
        } else if proportionalHeight >= rowHeight && windowRowCount > 0 {
            // tier 1: proportional, rows fit at wrapping height
            effectiveRowHeight = proportionalHeight
            useWrapping = wrapping
            contentHeight = bounds.height
        } else if wrapping && proportionalHeight >= compactRowHeight && windowRowCount > 0 {
            // tier 2: too tight for wrapping — switch to single-line, still proportional
            effectiveRowHeight = proportionalHeight
            useWrapping = false
            contentHeight = bounds.height
        } else {
            // tier 3: fixed compact height, scrolling
            effectiveRowHeight = compactRowHeight
            useWrapping = false
            contentHeight = CGFloat(visibleRowCount) * compactRowHeight + separatorSpace + headerSpace
        }

        // update row wrapping if needed
        if wrapping {
            for element in layoutOrder {
                if case .row(let i) = element { rowPool[i].setWrapping(useWrapping) }
            }
        }

        var yPos = contentHeight
        for element in layoutOrder {
            switch element {
            case .row(let i):
                let h = rowPool[i].isEmpty ? compactRowHeight : effectiveRowHeight
                yPos -= h
                rowPool[i].frame = CGRect(x: 0, y: yPos, width: width, height: h)
            case .separator(let i):
                yPos -= Self.separatorPadding
                yPos -= separatorHeight
                separatorPool[i].frame = CGRect(x: 0, y: yPos, width: width, height: separatorHeight)
                yPos -= Self.separatorPadding
            case .spaceHeader(let i):
                let hHeight = headerHeights[i]
                yPos -= hHeight
                spaceHeaderPool[i].frame = CGRect(x: 0, y: yPos, width: width, height: hHeight)
            }
        }
        contentStackView.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
    }

    func syncHover(at screenLocation: NSPoint?) {
        guard let screenLocation, let window else {
            for row in rowPool { row.unhover() }
            return
        }
        let windowLocation = window.convertPoint(fromScreen: screenLocation)
        let location = contentStackView.convert(windowLocation, from: nil)
        let hoveredRowIndex = firstVisibleRowIndex(containing: location)
        for (i, row) in rowPool.enumerated() {
            row.syncHover(isMouseInside: i == hoveredRowIndex)
        }
    }

    private func firstVisibleRowIndex(containing location: NSPoint) -> Int? {
        for case .row(let i) in layoutOrder {
            let row = rowPool[i]
            guard !row.isHidden, row.frame.contains(location) else { continue }
            return i
        }
        return nil
    }

    /// Lays out rows+separators+headers for the given groups. Returns content height.
    func updateContents(_ groups: [[Window]], selectedWindowId: CGWindowID?, isActiveScreen: Bool, currentSpaceGroupIndex: Int? = nil, spaceIndexes: [SpaceIndex] = [], spaceIds: [CGSSpaceID] = []) -> CGFloat {
        let _perfStart = DispatchTime.now()
        let totalRows = groups.reduce(0) { $0 + max($1.count, 1) }
        let _perfSpan = PerfDebug.start("ui.windowList.updateContents", fields: ["groups": groups.count, "rows": totalRows, "icons_only": iconsOnly, "show_tab_hierarchy": showTabHierarchy])
        defer {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - _perfStart.uptimeNanoseconds) / 1_000_000
            if ms > 15 { Logger.info { "[perf] WindowListView.updateContents \(String(format: "%.1f", ms))ms rows=\(totalRows) iconsOnly=\(self.iconsOnly)" } }
            _perfSpan?.finish(["row_pool": self.rowPool.count, "separator_pool": self.separatorPool.count])
        }
        let separatorCount = max(groups.count - 1, 0)
        let headerCount = spaceIndexes.isEmpty ? 0 : groups.count
        let separatorTotalHeight = separatorHeight + Self.separatorPadding * 2

        // grow row pool if needed
        while rowPool.count < totalRows {
            let row = SidePanelRow(fontSize: fontSize, wrapping: wrapping)
            row.setIconsOnly(iconsOnly)
            rowPool.append(row)
            contentStackView.addSubview(row)
        }

        // grow separator pool if needed
        while separatorPool.count < separatorCount {
            let sep = makeSeparator()
            separatorPool.append(sep)
            contentStackView.addSubview(sep)
        }

        // grow space header pool if needed
        while spaceHeaderPool.count < headerCount {
            let header = SpaceHeaderLabel()
            header.setIconsOnly(iconsOnly)
            spaceHeaderPool.append(header)
            contentStackView.addSubview(header)
        }

        // layout: groups top-to-bottom, macOS Y goes bottom-up
        layoutOrder = []
        let width = max(bounds.width, minWidth)

        // Pre-pass: configure headers and measure heights
        headerHeights = Array(repeating: headerHeight, count: headerCount)
        if !spaceIndexes.isEmpty {
            var measuredHeaderIndex = 0
            for (gi, _) in groups.enumerated() {
                let spId: CGSSpaceID = spaceIds.indices.contains(gi) ? spaceIds[gi] : 0
                if Spaces.isFullscreenSpace(spId) || groups[gi].isEmpty {
                    headerHeights[measuredHeaderIndex] = 0
                } else {
                    let spIdx = spaceIndexes.indices.contains(gi) ? spaceIndexes[gi] : gi + 1
                    let header = spaceHeaderPool[measuredHeaderIndex]
                    header.configure(spaceId: spId, displayIndex: spIdx, fontSize: fontSize)
                    headerHeights[measuredHeaderIndex] = header.desiredHeight(forWidth: width, baseHeight: headerHeight)
                }
                measuredHeaderIndex += 1
            }
        }
        let headerSpace = headerHeights.prefix(headerCount).reduce(0, +)

        // Skip separator when the following group has a visible header
        var visibleSeparatorCount = 0
        for gi in 0..<max(groups.count - 1, 0) {
            let nextHasHeader = (gi + 1) < headerHeights.count && headerHeights[gi + 1] > 0
            if !nextHasHeader {
                visibleSeparatorCount += 1
            }
        }

        let contentHeight = CGFloat(totalRows) * rowHeight
            + CGFloat(visibleSeparatorCount) * separatorTotalHeight
            + headerSpace
        var rowIndex = 0
        var separatorIndex = 0
        var headerIndex = 0
        var yPos = contentHeight // start from top

        for (gi, group) in groups.enumerated() {
            // space header label (before each group's rows)
            if !spaceIndexes.isEmpty {
                let spId: CGSSpaceID = spaceIds.indices.contains(gi) ? spaceIds[gi] : 0
                if Spaces.isFullscreenSpace(spId) || group.isEmpty {
                    // fullscreen/empty spaces: hide header, don't add to layout
                    spaceHeaderPool[headerIndex].isHidden = true
                } else {
                    let header = spaceHeaderPool[headerIndex]
                    let hHeight = headerHeights[headerIndex]
                    yPos -= hHeight
                    header.frame = CGRect(x: 0, y: yPos, width: width, height: hHeight)
                    header.isHidden = false
                    layoutOrder.append(.spaceHeader(headerIndex))
                }
                headerIndex += 1
            }

            if group.isEmpty {
                yPos -= rowHeight
                let row = rowPool[rowIndex]
                row.frame = CGRect(x: 0, y: yPos, width: width, height: rowHeight)
                let emptyState: HighlightState
                if gi == currentSpaceGroupIndex {
                    emptyState = isActiveScreen ? .active : .selected
                } else {
                    emptyState = .none
                }
                row.showEmpty(highlightState: emptyState)
                row.setIconsOnly(iconsOnly)
                row.isHidden = false
                layoutOrder.append(.row(rowIndex))
                rowIndex += 1
            } else {
                for window in group {
                    yPos -= rowHeight
                    let row = rowPool[rowIndex]
                    row.frame = CGRect(x: 0, y: yPos, width: width, height: rowHeight)
                    let state: HighlightState
                    if let selectedId = selectedWindowId, window.cgWindowId == selectedId {
                        state = isActiveScreen ? .active : .selected
                    } else {
                        state = .none
                    }
                    let indented = showTabHierarchy && window.isTabChild
                    row.update(window, highlightState: state, isIndented: indented)
                    row.setIconsOnly(iconsOnly)
                    row.isHidden = false
                    layoutOrder.append(.row(rowIndex))
                    rowIndex += 1
                }
            }
            // separator after each group except the last; skip when next group has a visible header
            if gi < groups.count - 1 {
                let nextHasHeader = (gi + 1) < headerHeights.count && headerHeights[gi + 1] > 0
                if !nextHasHeader {
                    yPos -= Self.separatorPadding
                    yPos -= separatorHeight
                    let sep = separatorPool[separatorIndex]
                    sep.frame = CGRect(x: 0, y: yPos, width: width, height: separatorHeight)
                    sep.isHidden = false
                    layoutOrder.append(.separator(separatorIndex))
                    separatorIndex += 1
                    yPos -= Self.separatorPadding
                }
            }
        }

        // hide surplus rows, separators, and headers
        for i in rowIndex..<rowPool.count { rowPool[i].isHidden = true }
        for i in separatorIndex..<separatorPool.count { separatorPool[i].isHidden = true }
        for i in headerIndex..<spaceHeaderPool.count { spaceHeaderPool[i].isHidden = true }

        // size the document view
        contentStackView.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)

        return contentHeight
    }

    static func separatorColor() -> NSColor {
        let hex = NSAppearance.current.getThemeName() == .dark
            ? Preferences.separatorColorDark
            : Preferences.separatorColorLight
        return NSColor(hex: hex)
    }

    private func makeSeparator() -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = WindowListView.separatorColor().cgColor
        return sep
    }
}

private extension NSColor {
    var hsvAwareTextColor: NSColor {
        guard let rgb = usingColorSpace(.sRGB) else { return .labelColor }
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        rgb.getHue(nil, saturation: &saturation, brightness: &brightness, alpha: nil)
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return brightness < 0.55 || luminance < 0.5 || (saturation > 0.45 && luminance < 0.62) ? .white : .black
    }
}
