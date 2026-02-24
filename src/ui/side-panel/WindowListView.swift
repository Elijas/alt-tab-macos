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

    init(separatorHeight: CGFloat = 7) {
        self.separatorHeight = separatorHeight
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

    /// Re-lays out rows using proportional heights when they fit, fixed 28pt + scrolling otherwise.
    func relayoutForBounds() {
        let width = max(bounds.width, SidePanelRow.panelWidth)
        let visibleRowCount = layoutOrder.filter { if case .row = $0 { return true }; return false }.count
        let visibleSepCount = layoutOrder.filter { if case .separator = $0 { return true }; return false }.count
        let separatorTotalHeight = separatorHeight + Self.separatorPadding * 2
        let separatorSpace = CGFloat(visibleSepCount) * separatorTotalHeight
        let availableForRows = bounds.height - separatorSpace

        let proportionalHeight = visibleRowCount > 0 ? availableForRows / CGFloat(visibleRowCount) : 0
        let useProportional = proportionalHeight >= SidePanelRow.rowHeight && visibleRowCount > 0
        let rowHeight = useProportional ? proportionalHeight : SidePanelRow.rowHeight

        let contentHeight = useProportional
            ? bounds.height
            : CGFloat(visibleRowCount) * SidePanelRow.rowHeight + separatorSpace

        var yPos = contentHeight
        for element in layoutOrder {
            switch element {
            case .row(let i):
                yPos -= rowHeight
                rowPool[i].frame = CGRect(x: 0, y: yPos, width: width, height: rowHeight)
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
            let row = SidePanelRow(frame: .zero)
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
        let contentHeight = CGFloat(totalRows) * SidePanelRow.rowHeight + CGFloat(separatorCount) * separatorTotalHeight
        var rowIndex = 0
        var separatorIndex = 0
        var yPos = contentHeight // start from top
        layoutOrder = []

        for (gi, group) in groups.enumerated() {
            if group.isEmpty {
                yPos -= SidePanelRow.rowHeight
                let row = rowPool[rowIndex]
                let width = max(bounds.width, SidePanelRow.panelWidth)
                row.frame = CGRect(x: 0, y: yPos, width: width, height: SidePanelRow.rowHeight)
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
                    yPos -= SidePanelRow.rowHeight
                    let row = rowPool[rowIndex]
                    let width = max(bounds.width, SidePanelRow.panelWidth)
                    row.frame = CGRect(x: 0, y: yPos, width: width, height: SidePanelRow.rowHeight)
                    let state: HighlightState
                    if let selectedId = selectedWindowId, window.cgWindowId == selectedId {
                        state = isActiveScreen ? .active : .selected
                    } else {
                        state = .none
                    }
                    row.update(window, highlightState: state)
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
                let sepWidth = max(bounds.width, SidePanelRow.panelWidth)
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
        contentStackView.frame = CGRect(x: 0, y: 0, width: max(bounds.width, SidePanelRow.panelWidth), height: contentHeight)

        return contentHeight
    }

    private func makeSeparator() -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.black.cgColor
        return sep
    }
}
