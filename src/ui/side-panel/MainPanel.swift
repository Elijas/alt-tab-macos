import Cocoa

struct ScreenColumnData {
    let screenName: String
    let groups: [[Window]]
    let selectedWindowId: CGWindowID?
    let isActiveScreen: Bool
    let currentSpaceGroupIndex: Int?
    let showTabHierarchy: Bool
}

class MainPanel: NSPanel {
    private static let columnPadding: CGFloat = 8
    private static let headerHeight: CGFloat = 24
    private static let separatorWidth: CGFloat = 1
    private static let collapsedColumnWidth: CGFloat = 20

    private var columns = [(header: NSTextField, listView: WindowListView)]()
    private var columnSeparators = [NSView]()
    private var columnHasWindows = [Bool]()
    private var needsInitialSizing = true

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 300, height: 400),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        title = "Main Panel"
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        if setFrameUsingName("MainPanel") {
            needsInitialSizing = false
        }
        setFrameAutosaveName("MainPanel")
        minSize = NSSize(width: 260, height: 200)
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    func update(_ screenData: [ScreenColumnData]) {
        guard let contentView else { return }

        // adjust column count to match screen count
        while columns.count < screenData.count {
            let header = NSTextField(labelWithString: "")
            header.font = NSFont.boldSystemFont(ofSize: CGFloat(Preferences.mainPanelFontSize))
            header.textColor = .labelColor
            header.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(header)

            let listView = WindowListView(separatorHeight: CGFloat(Preferences.mainPanelSeparatorSize), fontSize: CGFloat(Preferences.mainPanelFontSize), wrapping: Preferences.mainPanelTitleWrapping)
            contentView.addSubview(listView)

            columns.append((header: header, listView: listView))

            // add vertical separator before all columns except the first
            if columns.count > 1 {
                let sep = NSView()
                sep.wantsLayer = true
                sep.layer?.backgroundColor = WindowListView.separatorColor().cgColor
                contentView.addSubview(sep)
                columnSeparators.append(sep)
            }
        }

        // remove excess columns
        while columns.count > screenData.count {
            let col = columns.removeLast()
            col.header.removeFromSuperview()
            col.listView.removeFromSuperview()
            if !columnSeparators.isEmpty {
                columnSeparators.removeLast().removeFromSuperview()
            }
        }

        // update content, determine which columns are empty
        let canCollapse = screenData.count > 1
        var maxContentHeight: CGFloat = 0
        columnHasWindows = []
        for (i, data) in screenData.enumerated() {
            let hasWindows = data.groups.contains { !$0.isEmpty }
            columnHasWindows.append(hasWindows)

            columns[i].listView.showTabHierarchy = data.showTabHierarchy
            let contentHeight = columns[i].listView.updateContents(
                data.groups,
                selectedWindowId: data.selectedWindowId,
                isActiveScreen: data.isActiveScreen,
                currentSpaceGroupIndex: data.currentSpaceGroupIndex
            )
            maxContentHeight = max(maxContentHeight, contentHeight)

            // Collapsed empty columns: vertical text, smaller font
            let collapsed = !hasWindows && canCollapse
            if collapsed {
                columns[i].header.stringValue = data.screenName.map { String($0) }.joined(separator: "\n")
                columns[i].header.maximumNumberOfLines = 0
                columns[i].header.alignment = .center
                columns[i].header.font = NSFont.systemFont(ofSize: 9)
                columns[i].header.textColor = .secondaryLabelColor
            } else {
                columns[i].header.stringValue = data.screenName
                columns[i].header.maximumNumberOfLines = 1
                columns[i].header.alignment = .natural
                columns[i].header.font = NSFont.boldSystemFont(ofSize: CGFloat(Preferences.mainPanelFontSize))
                columns[i].header.textColor = .labelColor
            }
        }

        // initial sizing: account for collapsed columns being narrower
        if needsInitialSizing {
            needsInitialSizing = false

            let normalCount = canCollapse ? CGFloat(columnHasWindows.filter { $0 }.count) : CGFloat(screenData.count)
            let collapsedCount = canCollapse ? CGFloat(screenData.count) - normalCount : 0
            // If all columns are empty in multi-monitor, treat them all as normal
            let effectiveNormal = normalCount == 0 ? CGFloat(screenData.count) : normalCount
            let effectiveCollapsed = normalCount == 0 ? CGFloat(0) : collapsedCount
            let separatorCount = max(CGFloat(screenData.count) - 1, 0)
            let totalWidth = effectiveNormal * SidePanelRow.panelWidth
                + effectiveCollapsed * Self.collapsedColumnWidth
                + separatorCount * Self.separatorWidth
                + Self.columnPadding * 2

            let maxScreenHeight = (NSScreen.main?.visibleFrame.height ?? 800) * 0.8
            let titleBarHeight: CGFloat = 28
            let totalContentHeight = maxContentHeight + Self.headerHeight + Self.columnPadding
            let windowHeight = min(totalContentHeight + titleBarHeight, maxScreenHeight)

            let screenFrame = NSScreen.main?.frame ?? .zero
            let newSize = CGSize(width: totalWidth, height: windowHeight)
            let origin = NSPoint(
                x: screenFrame.midX - newSize.width / 2,
                y: screenFrame.midY - newSize.height / 2
            )
            setFrame(CGRect(origin: origin, size: newSize), display: true)
        }

        layoutColumns()
    }

    private func layoutColumns() {
        guard let contentView, !columns.isEmpty else { return }
        let bounds = contentView.bounds

        // Determine which columns collapse (empty monitors in multi-monitor setup)
        let canCollapse = columns.count > 1
        var isCollapsed = [Bool]()
        for i in 0..<columns.count {
            let empty = columnHasWindows.indices.contains(i) ? !columnHasWindows[i] : false
            isCollapsed.append(empty && canCollapse)
        }
        // If ALL columns would collapse, show them all normally instead
        if isCollapsed.allSatisfy({ $0 }) {
            isCollapsed = Array(repeating: false, count: columns.count)
        }

        let collapsedCount = CGFloat(isCollapsed.filter { $0 }.count)
        let normalCount = CGFloat(columns.count) - collapsedCount
        let separatorCount = max(CGFloat(columns.count) - 1, 0)
        let totalCollapsedWidth = collapsedCount * Self.collapsedColumnWidth
        let availableForNormal = bounds.width - Self.columnPadding * 2 - separatorCount * Self.separatorWidth - totalCollapsedWidth
        let normalColWidth = normalCount > 0 ? max(availableForNormal / normalCount, 100) : 100

        var x = Self.columnPadding
        for (i, col) in columns.enumerated() {
            col.header.translatesAutoresizingMaskIntoConstraints = true
            col.listView.translatesAutoresizingMaskIntoConstraints = true

            if isCollapsed[i] {
                // Collapsed: thin bar with vertical monitor name
                col.header.frame = CGRect(x: x, y: 0, width: Self.collapsedColumnWidth, height: bounds.height)
                col.listView.isHidden = true
                x += Self.collapsedColumnWidth
            } else {
                // Normal: header at top, listView fills remaining height
                col.header.frame = CGRect(x: x, y: bounds.height - Self.headerHeight,
                                          width: normalColWidth, height: Self.headerHeight)
                col.listView.isHidden = false
                col.listView.frame = CGRect(x: x, y: 0, width: normalColWidth,
                                            height: bounds.height - Self.headerHeight)
                col.listView.relayoutForBounds()
                x += normalColWidth
            }

            if i < columnSeparators.count {
                columnSeparators[i].frame = CGRect(x: x, y: 0,
                                                   width: Self.separatorWidth, height: bounds.height)
                x += Self.separatorWidth
            }
        }
    }
}

extension MainPanel: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        layoutColumns()
    }
}
