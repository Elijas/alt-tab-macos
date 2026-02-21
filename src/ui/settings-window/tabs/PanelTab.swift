import Cocoa

class PanelTab {
    static func initTab() -> NSView {
        let enableSwitch = LabelAndControl.makeSwitch("sidePanelEnabled", extraAction: { _ in
            if Preferences.sidePanelEnabled {
                SidePanelManager.shared.setup()
            } else {
                SidePanelManager.shared.tearDown()
            }
        })
        let enable = TableGroupView.Row(leftTitle: NSLocalizedString("Enable", comment: ""),
            rightViews: [enableSwitch])
        let table = TableGroupView(width: SettingsWindow.contentWidth)
        table.addRow(enable)
        let view = TableGroupSetView(originalViews: [table], bottomPadding: 0)
        return view
    }
}
