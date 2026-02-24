import Cocoa

class PanelTab {
    static func initTab() -> NSView {
        // "Side Panel" group
        let enableSwitch = LabelAndControl.makeSwitch("sidePanelEnabled", extraAction: { _ in
            if Preferences.sidePanelEnabled {
                SidePanelManager.shared.setup()
            } else {
                SidePanelManager.shared.tearDown()
            }
        })
        let enable = TableGroupView.Row(leftTitle: NSLocalizedString("Enable", comment: ""),
            rightViews: [enableSwitch])

        let opacityAction: ActionClosure = { _ in
            SidePanelManager.shared.applyOpacity()
        }
        let separatorAction: ActionClosure = { _ in
            SidePanelManager.shared.applySeparatorSizes()
        }
        let opacitySlider = LabelAndControl.makeLabelWithSlider("", "sidePanelOpacity", 0, 100, 0, false, "%", width: 140, extraAction: opacityAction)
        let hoverSlider = LabelAndControl.makeLabelWithSlider("", "sidePanelHoverOpacity", 0, 100, 0, false, "%", width: 140, extraAction: opacityAction)
        let sideSepSlider = LabelAndControl.makeLabelWithSlider("", "sidePanelSeparatorSize", 0, 20, 0, false, "px", width: 140, extraAction: separatorAction)

        let sideTable = TableGroupView(title: "Side Panel", width: SettingsWindow.contentWidth)
        sideTable.addRow(enable)
        sideTable.addRow(leftText: NSLocalizedString("Opacity", comment: ""), rightViews: [opacitySlider[1], opacitySlider[2]])
        sideTable.addRow(leftText: NSLocalizedString("Hover opacity", comment: ""), rightViews: [hoverSlider[1], hoverSlider[2]])
        sideTable.addRow(leftText: "Space separator", rightViews: [sideSepSlider[1], sideSepSlider[2]])

        // "Window Panel" group
        let openButton = NSButton(title: "Open", target: nil, action: nil)
        openButton.bezelStyle = .rounded
        openButton.onAction = { _ in
            SidePanelManager.shared.openWindowPanel()
        }

        let openOnStartupSwitch = LabelAndControl.makeSwitch("windowPanelOpenOnStartup")
        let winSepSlider = LabelAndControl.makeLabelWithSlider("", "windowPanelSeparatorSize", 0, 20, 0, false, "px", width: 140, extraAction: separatorAction)

        let windowTable = TableGroupView(title: "Window Panel", width: SettingsWindow.contentWidth)
        windowTable.addRow(leftText: "All-screen overview", rightViews: [openButton])
        windowTable.addRow(leftText: "Open on startup", rightViews: [openOnStartupSwitch])
        windowTable.addRow(leftText: "Space separator", rightViews: [winSepSlider[1], winSepSlider[2]])

        return TableGroupSetView(originalViews: [sideTable, windowTable], bottomPadding: 0)
    }
}
