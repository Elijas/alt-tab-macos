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
        let sidePanelRebuildAction: ActionClosure = { _ in
            SidePanelManager.shared.rebuildPanelsForScreenChange()
        }
        let separatorAction: ActionClosure = { _ in
            SidePanelManager.shared.applySeparatorSizes()
        }
        let opacitySlider = LabelAndControl.makeLabelWithSlider("", "sidePanelOpacity", 0, 100, 0, false, "%", width: 140, extraAction: opacityAction)
        let hoverSlider = LabelAndControl.makeLabelWithSlider("", "sidePanelHoverOpacity", 0, 100, 0, false, "%", width: 140, extraAction: opacityAction)
        let sideSepSlider = LabelAndControl.makeLabelWithSlider("", "sidePanelSeparatorSize", 0, 20, 0, false, "px", width: 140, extraAction: separatorAction)
        let sideFontSlider = LabelAndControl.makeLabelWithSlider("", "sidePanelFontSize", 9, 20, 0, false, "pt", width: 140, extraAction: sidePanelRebuildAction)

        let sideTable = TableGroupView(title: "Side Panel", width: SettingsWindow.contentWidth)
        sideTable.addRow(enable)
        sideTable.addRow(leftText: NSLocalizedString("Opacity", comment: ""), rightViews: [opacitySlider[1], opacitySlider[2]])
        sideTable.addRow(leftText: NSLocalizedString("Hover opacity", comment: ""), rightViews: [hoverSlider[1], hoverSlider[2]])
        sideTable.addRow(leftText: "Space separator", rightViews: [sideSepSlider[1], sideSepSlider[2]])
        sideTable.addRow(leftText: "Font size", rightViews: [sideFontSlider[1], sideFontSlider[2]])

        let tabHierarchySwitch = LabelAndControl.makeSwitch("showTabHierarchyInSidePanel", extraAction: { _ in
            SidePanelManager.shared.refreshPanels()
        })
        sideTable.addRow(leftText: "Show tabs as indented items", rightViews: [tabHierarchySwitch])

        // "Window Panel" group
        let openButton = NSButton(title: "Open", target: nil, action: nil)
        openButton.bezelStyle = .rounded
        openButton.onAction = { _ in
            SidePanelManager.shared.openWindowPanel()
        }

        let windowPanelRebuildAction: ActionClosure = { _ in
            SidePanelManager.shared.applySeparatorSizes()
        }
        let openOnStartupSwitch = LabelAndControl.makeSwitch("windowPanelOpenOnStartup")
        let winSepSlider = LabelAndControl.makeLabelWithSlider("", "windowPanelSeparatorSize", 0, 20, 0, false, "px", width: 140, extraAction: separatorAction)
        let winFontSlider = LabelAndControl.makeLabelWithSlider("", "windowPanelFontSize", 9, 20, 0, false, "pt", width: 140, extraAction: windowPanelRebuildAction)
        let wrappingSwitch = LabelAndControl.makeSwitch("windowPanelTitleWrapping", extraAction: windowPanelRebuildAction)

        let windowTable = TableGroupView(title: "Window Panel", width: SettingsWindow.contentWidth)
        windowTable.addRow(leftText: "All-screen overview", rightViews: [openButton])
        windowTable.addRow(leftText: "Open on startup", rightViews: [openOnStartupSwitch])
        windowTable.addRow(leftText: "Space separator", rightViews: [winSepSlider[1], winSepSlider[2]])
        windowTable.addRow(leftText: "Font size", rightViews: [winFontSlider[1], winFontSlider[2]])
        windowTable.addRow(leftText: "Wrap titles", rightViews: [wrappingSwitch])

        return TableGroupSetView(originalViews: [sideTable, windowTable], bottomPadding: 0)
    }
}
