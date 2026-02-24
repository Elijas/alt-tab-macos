import Cocoa

class WindowListView: NSView {
    private static let separatorPadding: CGFloat = 0

    private enum LayoutElement {
        case row(Int)
        case separator(Int)
    }

    private let scrollView = NSScrollView()
    private let contentStackView = NSView()
    private var rowPool = [SidePanelRow]()
    private var separatorPool = [NSView]()
    private var layoutOrder = [LayoutElement]()
    private(set) var separatorHeight: CGFloat
    let rowHeight: CGFloat
    private let compactRowHeight: CGFloat
    private let fontSize: CGFloat
    private let wrapping: Bool
    private let minWidth: CGFloat
    var showTabHierarchy: Bool = false

    init(separatorHeight: CGFloat = 7, fontSize: CGFloat = 12, wrapping: Bool = false, minWidth: CGFloat = 0) {
        self.separatorHeight = separatorHeight
        self.fontSize = fontSize
        self.wrapping = wrapping
        self.minWidth = minWidth
        self.rowHeight = SidePanelRow.rowHeight(fontSize: fontSize, wrapping: wrapping)
        self.compactRowHeight = SidePanelRow.rowHeight(fontSize: fontSize, wrapping: false)
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
        let width = max(bounds.width, minWidth)
        let visibleRowCount = layoutOrder.filter { if case .row = $0 { return true }; return false }.count
        let emptyRowCount = layoutOrder.filter { if case .row(let i) = $0 { return rowPool[i].isEmpty }; return false }.count
        let windowRowCount = visibleRowCount - emptyRowCount
        let visibleSepCount = layoutOrder.filter { if case .separator = $0 { return true }; return false }.count
        let separatorTotalHeight = separatorHeight + Self.separatorPadding * 2
        let separatorSpace = CGFloat(visibleSepCount) * separatorTotalHeight
        // empty rows get capped at compactRowHeight; subtract their budget before distributing to window rows
        let emptyRowSpace = CGFloat(emptyRowCount) * compactRowHeight
        let availableForRows = bounds.height - separatorSpace - emptyRowSpace

        let proportionalHeight = windowRowCount > 0 ? availableForRows / CGFloat(windowRowCount) : 0

        let effectiveRowHeight: CGFloat
        let useWrapping: Bool
        let contentHeight: CGFloat
        if proportionalHeight >= rowHeight && windowRowCount > 0 {
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
            contentHeight = CGFloat(visibleRowCount) * compactRowHeight + separatorSpace
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
            }
        }
        contentStackView.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
    }

    /// Lays out rows+separators for the given groups. Returns content height.
    func updateContents(_ groups: [[Window]], selectedWindowId: CGWindowID?, isActiveScreen: Bool, currentSpaceGroupIndex: Int? = nil) -> CGFloat {
        let totalRows = groups.reduce(0) { $0 + max($1.count, 1) }
        let separatorCount = max(groups.count - 1, 0)
        let separatorTotalHeight = separatorHeight + Self.separatorPadding * 2

        // grow row pool if needed
        while rowPool.count < totalRows {
            let row = SidePanelRow(fontSize: fontSize, wrapping: wrapping)
            rowPool.append(row)
            contentStackView.addSubview(row)
        }

        // grow separator pool if needed
        while separatorPool.count < separatorCount {
            let sep = makeSeparator()
            separatorPool.append(sep)
            contentStackView.addSubview(sep)
        }

        // layout: groups top-to-bottom, macOS Y goes bottom-up
        let contentHeight = CGFloat(totalRows) * rowHeight + CGFloat(separatorCount) * separatorTotalHeight
        var rowIndex = 0
        var separatorIndex = 0
        var yPos = contentHeight // start from top
        layoutOrder = []

        for (gi, group) in groups.enumerated() {
            if group.isEmpty {
                yPos -= rowHeight
                let row = rowPool[rowIndex]
                let width = max(bounds.width, minWidth)
                row.frame = CGRect(x: 0, y: yPos, width: width, height: rowHeight)
                let emptyState: HighlightState
                if gi == currentSpaceGroupIndex {
                    emptyState = isActiveScreen ? .active : .selected
                } else {
                    emptyState = .none
                }
                row.showEmpty(highlightState: emptyState)
                row.isHidden = false
                layoutOrder.append(.row(rowIndex))
                rowIndex += 1
            } else {
                for window in group {
                    yPos -= rowHeight
                    let row = rowPool[rowIndex]
                    let width = max(bounds.width, minWidth)
                    row.frame = CGRect(x: 0, y: yPos, width: width, height: rowHeight)
                    let state: HighlightState
                    if let selectedId = selectedWindowId, window.cgWindowId == selectedId {
                        state = isActiveScreen ? .active : .selected
                    } else {
                        state = .none
                    }
                    let indented = showTabHierarchy && window.isTabChild
                    row.update(window, highlightState: state, isIndented: indented)
                    row.isHidden = false
                    layoutOrder.append(.row(rowIndex))
                    rowIndex += 1
                }
            }
            // separator after each group except the last
            if gi < groups.count - 1 {
                yPos -= Self.separatorPadding
                yPos -= separatorHeight
                let sep = separatorPool[separatorIndex]
                let sepWidth = max(bounds.width, minWidth)
                sep.frame = CGRect(x: 0, y: yPos, width: sepWidth, height: separatorHeight)
                sep.isHidden = false
                layoutOrder.append(.separator(separatorIndex))
                separatorIndex += 1
                yPos -= Self.separatorPadding
            }
        }

        // hide surplus rows and separators
        for i in rowIndex..<rowPool.count { rowPool[i].isHidden = true }
        for i in separatorIndex..<separatorPool.count { separatorPool[i].isHidden = true }

        // size the document view
        contentStackView.frame = CGRect(x: 0, y: 0, width: max(bounds.width, minWidth), height: contentHeight)

        return contentHeight
    }

    private func makeSeparator() -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.black.cgColor
        return sep
    }
}
