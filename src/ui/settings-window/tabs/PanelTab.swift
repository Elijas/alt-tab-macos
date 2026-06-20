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

        let rowColorAction: ActionClosure = { _ in SidePanelManager.shared.refreshPanels() }

        let activeLightWell = NSColorWell()
        activeLightWell.color = NSColor(hex: Preferences.activeColorLight)
        activeLightWell.onAction = { sender in
            Preferences.set("activeColorLight", (sender as! NSColorWell).color.hexString)
            rowColorAction(sender)
        }

        let activeDarkWell = NSColorWell()
        activeDarkWell.color = NSColor(hex: Preferences.activeColorDark)
        activeDarkWell.onAction = { sender in
            Preferences.set("activeColorDark", (sender as! NSColorWell).color.hexString)
            rowColorAction(sender)
        }

        let selectedLightWell = NSColorWell()
        selectedLightWell.color = NSColor(hex: Preferences.selectedColorLight)
        selectedLightWell.onAction = { sender in
            Preferences.set("selectedColorLight", (sender as! NSColorWell).color.hexString)
            rowColorAction(sender)
        }

        let selectedDarkWell = NSColorWell()
        selectedDarkWell.color = NSColor(hex: Preferences.selectedColorDark)
        selectedDarkWell.onAction = { sender in
            Preferences.set("selectedColorDark", (sender as! NSColorWell).color.hexString)
            rowColorAction(sender)
        }

        let hoverLightWell = NSColorWell()
        hoverLightWell.color = NSColor(hex: Preferences.hoverColorLight)
        hoverLightWell.onAction = { sender in
            Preferences.set("hoverColorLight", (sender as! NSColorWell).color.hexString)
            rowColorAction(sender)
        }

        let hoverDarkWell = NSColorWell()
        hoverDarkWell.color = NSColor(hex: Preferences.hoverColorDark)
        hoverDarkWell.onAction = { sender in
            Preferences.set("hoverColorDark", (sender as! NSColorWell).color.hexString)
            rowColorAction(sender)
        }

        let commonTable = TableGroupView(title: "Common", width: SettingsWindow.contentWidth)
        commonTable.addRow(leftText: "Separator color (light)", rightViews: [lightColorWell])
        commonTable.addRow(leftText: "Separator color (dark)", rightViews: [darkColorWell])
        commonTable.addRow(leftText: "Active row color (light)", rightViews: [activeLightWell])
        commonTable.addRow(leftText: "Active row color (dark)", rightViews: [activeDarkWell])
        commonTable.addRow(leftText: "Selected row color (light)", rightViews: [selectedLightWell])
        commonTable.addRow(leftText: "Selected row color (dark)", rightViews: [selectedDarkWell])
        commonTable.addRow(leftText: "Hover row color (light)", rightViews: [hoverLightWell])
        commonTable.addRow(leftText: "Hover row color (dark)", rightViews: [hoverDarkWell])

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
        let compactWidthSlider = LabelAndControl.makeLabelWithSlider("", "sidePanelCompactWidth", 30, 260, 0, false, "px", width: 140, extraAction: rowColorAction)
        let letterStep: (Double) -> Double = { $0 < 30 ? 1 : 5 }
        let compactLettersSlider = makeLogSlider("sidePanelCompactLetters", min: 1, max: 100, zeroLabel: "0", step: letterStep, extraAction: rowColorAction)
        let compactLettersIndentedSlider = makeLogSlider("sidePanelCompactLettersIndented", min: 1, max: 100, zeroLabel: "0", step: letterStep, extraAction: rowColorAction)

        let sideTable = TableGroupView(title: "Side Panel", width: SettingsWindow.contentWidth)
        sideTable.addRow(enable)
        sideTable.addRow(leftText: NSLocalizedString("Opacity", comment: ""), rightViews: [opacitySlider[1], opacitySlider[2]])
        sideTable.addRow(leftText: NSLocalizedString("Hover opacity", comment: ""), rightViews: [hoverSlider[1], hoverSlider[2]])
        sideTable.addRow(leftText: "Space separator", rightViews: [sideSepSlider[1], sideSepSlider[2]])
        sideTable.addRow(leftText: "Font size", rightViews: [sideFontSlider[1], sideFontSlider[2]])
        sideTable.addRow(leftText: "Compact width", rightViews: [compactWidthSlider[1], compactWidthSlider[2]])
        sideTable.addRow(leftText: "Compact letters", rightViews: compactLettersSlider)
        sideTable.addRow(leftText: "Compact letters (indented items)", rightViews: compactLettersIndentedSlider)

        let tabHierarchySwitch = LabelAndControl.makeSwitch("showTabHierarchyInSidePanel", extraAction: { _ in
            SidePanelManager.shared.refreshPanels()
        })
        sideTable.addRow(leftText: "Show tabs as indented items", rightViews: [tabHierarchySwitch])

        let groupSortSwitch = LabelAndControl.makeSwitch("groupTabsInSortOrder", extraAction: { _ in
            SidePanelManager.shared.refreshPanels()
        })
        sideTable.addRow(leftText: "Group tabs in sort order", rightViews: [groupSortSwitch])

        // Read live by SidePanel.syncHover on every hover, so no extraAction is needed.
        let hoverJumpSwitch = LabelAndControl.makeSwitch("sidePanelHoverJump")
        sideTable.addRow(leftText: "Hover jumps to other side (hold ⇧ to click)", rightViews: [hoverJumpSwitch])

        // Logarithmic: fine control at the low end (5→10s matters), coarse at the high
        // end (250→255s doesn't). Far-left = off. Stores plain seconds, read live when a
        // hover-jump schedules its return timer, so no extraAction is needed.
        sideTable.addRow(leftText: "Return to home side after",
            rightViews: makeLogSlider("sidePanelReturnDelay", min: 5, max: 300, zeroLabel: "off", unit: "s",
                step: { $0 < 30 ? 1 : ($0 < 120 ? 5 : 15) }))

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

        let collapseEmptySwitch = LabelAndControl.makeSwitch("mainPanelCollapseEmptyScreens", extraAction: { _ in
            SidePanelManager.shared.refreshPanels()
        })
        windowTable.addRow(leftText: "Collapse empty screens", rightViews: [collapseEmptySwitch])

        let windowTabSwitch = LabelAndControl.makeSwitch("showTabHierarchyInMainPanel", extraAction: { _ in
            SidePanelManager.shared.refreshPanels()
        })
        windowTable.addRow(leftText: "Show tabs as indented items", rightViews: [windowTabSwitch])

        return TableGroupSetView(originalViews: [commonTable, sideTable, windowTable], bottomPadding: 0)
    }

    // MARK: - Logarithmic slider

    /// A slider whose thumb position is normalized 0…1 but maps exponentially to the
    /// value range [min, max] — so equal pixels are equal ratios (fine control at the
    /// low end, coarse at the high end). The leftmost band is reserved for 0 (shown as
    /// `zeroLabel`). The stored pref stays plain integers; `step` snaps to tidy values.
    /// Returns [slider, suffixLabel] ready for TableGroupView.addRow(rightViews:).
    private static func makeLogSlider(_ key: String, min minValue: Double, max maxValue: Double,
                                      zeroLabel: String, unit: String = "", offZone: Double = 0.04,
                                      step: @escaping (Double) -> Double,
                                      extraAction: ActionClosure? = nil) -> [NSView] {
        func value(forPosition p: Double) -> Int {
            guard p >= offZone else { return 0 } // inclusive so the minimum is reachable
            let t = (p - offZone) / (1 - offZone)
            let raw = minValue * pow(maxValue / minValue, t)
            let s = step(raw)
            return Int((raw / s).rounded()) * Int(s)
        }
        func position(forValue v: Int) -> Double {
            guard v > 0 else { return 0 }
            let clamped = Swift.min(Swift.max(Double(v), minValue), maxValue)
            let t = log(clamped / minValue) / log(maxValue / minValue)
            return offZone + t * (1 - offZone)
        }
        func suffixText(_ v: Int) -> String { v <= 0 ? zeroLabel : "\(v)\(unit)" }

        let current = CachedUserDefaults.int(key)
        let suffix = NSTextField(labelWithString: suffixText(current))
        suffix.textColor = .gray
        let slider = NSSlider()
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = position(forValue: current)
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addOrUpdateConstraint(slider.widthAnchor, 140)
        slider.onAction = { control in
            let v = value(forPosition: (control as! NSSlider).doubleValue)
            Preferences.set(key, String(v))
            suffix.stringValue = suffixText(v)
            extraAction?(control)
        }
        return [slider, suffix]
    }
}
