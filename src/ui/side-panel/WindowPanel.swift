import Cocoa

struct ScreenColumnData {
    let screenName: String
    let groups: [[Window]]
    let selectedWindowId: CGWindowID?
    let isActiveScreen: Bool
    let currentSpaceGroupIndex: Int?
}

class WindowPanel: NSPanel {
    private static let columnPadding: CGFloat = 8
    private static let headerHeight: CGFloat = 24
    private static let separatorWidth: CGFloat = 1

    private var columns = [(header: NSTextField, listView: WindowListView)]()
    private var columnSeparators = [NSView]()
    private var needsInitialSizing = true

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 300, height: 400),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        title = "Window Panel"
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        if setFrameUsingName("WindowPanel") {
            needsInitialSizing = false
        }
        setFrameAutosaveName("WindowPanel")
        minSize = NSSize(width: 260, height: 200)
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    func update(_ screenData: [ScreenColumnData]) {
        guard let contentView else { return }

        // adjust column count to match screen count
        while columns.count < screenData.count {
            let header = NSTextField(labelWithString: "")
            header.font = NSFont.boldSystemFont(ofSize: CGFloat(Preferences.windowPanelFontSize))
            header.textColor = .labelColor
            header.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(header)

            let listView = WindowListView(separatorHeight: CGFloat(Preferences.windowPanelSeparatorSize), fontSize: CGFloat(Preferences.windowPanelFontSize), wrapping: Preferences.windowPanelTitleWrapping)
            contentView.addSubview(listView)

            columns.append((header: header, listView: listView))

            // add vertical separator before all columns except the first
            if columns.count > 1 {
                let sep = NSView()
                sep.wantsLayer = true
                if #available(macOS 10.14, *) {
                    sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
                } else {
                    sep.layer?.backgroundColor = NSColor.gridColor.cgColor
                }
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

        // update content and compute sizes
        var maxContentHeight: CGFloat = 0
        for (i, data) in screenData.enumerated() {
            columns[i].header.stringValue = data.screenName
            let contentHeight = columns[i].listView.updateContents(
                data.groups,
                selectedWindowId: data.selectedWindowId,
                isActiveScreen: data.isActiveScreen,
                currentSpaceGroupIndex: data.currentSpaceGroupIndex
            )
            maxContentHeight = max(maxContentHeight, contentHeight)
        }

        // initial sizing: compute ideal window size and center on screen
        if needsInitialSizing {
            needsInitialSizing = false

            let columnCount = CGFloat(screenData.count)
            let separatorCount = max(columnCount - 1, 0)
            let totalWidth = columnCount * SidePanelRow.panelWidth
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
        let columnCount = CGFloat(columns.count)
        let separatorCount = max(columnCount - 1, 0)
        let availableWidth = bounds.width - Self.columnPadding * 2 - separatorCount * Self.separatorWidth
        let colWidth = max(availableWidth / columnCount, 100)

        var x = Self.columnPadding
        for (i, col) in columns.enumerated() {
            col.header.frame = CGRect(x: x, y: bounds.height - Self.headerHeight,
                                      width: colWidth, height: Self.headerHeight)
            col.listView.translatesAutoresizingMaskIntoConstraints = true
            col.listView.frame = CGRect(x: x, y: 0, width: colWidth,
                                        height: bounds.height - Self.headerHeight)
            col.listView.relayoutForBounds()
            x += colWidth
            if i < columnSeparators.count {
                columnSeparators[i].frame = CGRect(x: x, y: 0,
                                                   width: Self.separatorWidth, height: bounds.height)
                x += Self.separatorWidth
            }
        }
    }
}

extension WindowPanel: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        layoutColumns()
    }
}
