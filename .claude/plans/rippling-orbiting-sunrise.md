# Integration: Group Sort into SidePanelManager + UI Toggle

## Context
Workers completed:
- W1 (67544-w6): Renamed windowPanel → mainPanel everywhere, build succeeded
- W2 (67544-w8): Added groupSortKeys(), effectiveCreationOrder(), groupTabsInSortOrder pref to Windows.swift

## Remaining Integration

### 1. SidePanelManager.swift — always track tabs + use group sort
- Always compute `tabParentMap` (remove `if showTabs` gate around `queryAXTabGroups`)
- Compute group creation keys via `Windows.groupSortKeys`
- Use group sort key in the sort: `$0.creationOrder > $1.creationOrder` → group-aware comparison
- Keep `showTabs` gate for: `parentWindowId` assignment, visibility correction, pulling in `spaces=[]` children, `orderWithTabHierarchy`

### 2. PanelTab.swift — add groupTabsInSortOrder toggle
- Add a switch for `groupTabsInSortOrder` in either the Side Panel section or a shared section
- Extra action: `refreshPanels()`

### 3. Build + deploy
- `xcodebuild` with `-derivedDataPath /tmp/alt-tab-build-main`
- Kill → reset TCC → reinstall → relaunch

## Verification
- Open Ghostty with 2+ tabs, enable tab hierarchy in side panel
- Switch tabs → window position should NOT jump in the side panel
- Disable tab hierarchy → switching tabs should still not jump (group sort is independent of display)
