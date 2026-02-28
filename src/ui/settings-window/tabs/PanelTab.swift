import Cocoa

class PanelTab {
    static func initTab() -> NSView {
        // "Common" group (shared settings for both panel types)
        let separatorAction: ActionClosure = { _ in
            SidePanelManager.shared.applySeparatorSizes()
        }

        let lightColorWell = NSColorWell()
        lightColorWell.color = NSColor(hex: Preferences.separatorColorLight)
        lightColorWell.onAction = { sender in
            let hex = (sender as! NSColorWell).color.hexString
            Preferences.set("separatorColorLight", hex)
            separatorAction(sender)
        }

        let darkColorWell = NSColorWell()
        darkColorWell.color = NSColor(hex: Preferences.separatorColorDark)
        darkColorWell.onAction = { sender in
            let hex = (sender as! NSColorWell).color.hexString
            Preferences.set("separatorColorDark", hex)
            separatorAction(sender)
        }

        let commonTable = TableGroupView(title: "Common", width: SettingsWindow.contentWidth)
        commonTable.addRow(leftText: "Separator color (light)", rightViews: [lightColorWell])
        commonTable.addRow(leftText: "Separator color (dark)", rightViews: [darkColorWell])

        // "Side Panel" group
        let enableSwitch = LabelAndControl.makeSwitch("sidePanelEnabled", extraAction: { _ in
            if Preferences.sidePanelEnabled {
                // clear per-screen disables so all panels come back
                Preferences.set("sidePanelDisabledScreens", Preferences.jsonEncode([String]()))
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
        let opacitySlider = LabelAndControl.makeLabelWithSlider("", "sidePanelOpacity", 0, 100, 0, false, "%", width: 140, extraAction: opacityAction)
        let hoverSlider = LabelAndControl.makeLabelWithSlider("", "sidePanelHoverOpacity", 0, 100, 0, false, "%", width: 140, extraAction: opacityAction)
        let sideSepSlider = LabelAndControl.makeLabelWithSlider("", "sidePanelSeparatorSize", 0, 20, 0, false, "px", width: 140, extraAction: separatorAction)
        let sideFontSlider = LabelAndControl.makeLabelWithSlider("", "sidePanelFontSize", 9, 30, 0, false, "pt", width: 140, extraAction: sidePanelRebuildAction)

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

        let groupSortSwitch = LabelAndControl.makeSwitch("groupTabsInSortOrder", extraAction: { _ in
            SidePanelManager.shared.refreshPanels()
        })
        sideTable.addRow(leftText: "Group tabs in sort order", rightViews: [groupSortSwitch])

        // "Main Panel" group
        let openButton = NSButton(title: "Open", target: nil, action: nil)
        openButton.bezelStyle = .rounded
        openButton.onAction = { _ in
            SidePanelManager.shared.openMainPanel()
        }

        let mainPanelRebuildAction: ActionClosure = { _ in
            SidePanelManager.shared.applySeparatorSizes()
        }
        let openOnStartupSwitch = LabelAndControl.makeSwitch("mainPanelOpenOnStartup")
        let winSepSlider = LabelAndControl.makeLabelWithSlider("", "mainPanelSeparatorSize", 0, 20, 0, false, "px", width: 140, extraAction: separatorAction)
        let winFontSlider = LabelAndControl.makeLabelWithSlider("", "mainPanelFontSize", 9, 30, 0, false, "pt", width: 140, extraAction: mainPanelRebuildAction)
        let wrappingSwitch = LabelAndControl.makeSwitch("mainPanelTitleWrapping", extraAction: mainPanelRebuildAction)

        let windowTable = TableGroupView(title: "Main Panel", width: SettingsWindow.contentWidth)
        windowTable.addRow(leftText: "All-screen overview", rightViews: [openButton])
        windowTable.addRow(leftText: "Open on startup", rightViews: [openOnStartupSwitch])
        windowTable.addRow(leftText: "Space separator", rightViews: [winSepSlider[1], winSepSlider[2]])
        windowTable.addRow(leftText: "Font size", rightViews: [winFontSlider[1], winFontSlider[2]])
        windowTable.addRow(leftText: "Wrap titles", rightViews: [wrappingSwitch])

        let verticalFillSwitch = LabelAndControl.makeSwitch("mainPanelVerticalFill", extraAction: mainPanelRebuildAction)
        windowTable.addRow(leftText: "Stretch rows to fill space", rightViews: [verticalFillSwitch])

        let windowTabSwitch = LabelAndControl.makeSwitch("showTabHierarchyInMainPanel", extraAction: { _ in
            SidePanelManager.shared.refreshPanels()
        })
        windowTable.addRow(leftText: "Show tabs as indented items", rightViews: [windowTabSwitch])

        return TableGroupSetView(originalViews: [commonTable, sideTable, windowTable], bottomPadding: 0)
    }
}
