# Group Sort — Tab-Aware Sort Stability

**Context**: AltTab fork — prevents tab group members from jumping position in the side panel, main popup, and CLI cycling scripts when switching tabs.
**Last updated**: 2026-02-24
**Prerequisite**: [`tab-hierarchy-guide.md`](tab-hierarchy-guide.md) — how tab parent→child relationships are detected.

## The Problem

When you switch tabs in a native-tabbed app (Ghostty, Finder, Safari), the newly active tab gets a fresh `lastFocusOrder` and the previously active tab becomes inactive with `spaces = []`. In any recency-based or creation-based sort, the tab group members scatter — the active tab jumps to the top, inactive tabs drift down or disappear.

This is jarring in the side panel where window positions should be stable.

## The Solution: Group Sort Keys

Instead of sorting each window by its own `creationOrder` or `lastFocusOrder`, tab group members share a **single sort key**: `min(value)` across all windows in the group.

```
Tab group: [Ghostty tab1 (creation=5), Ghostty tab2 (creation=12), Ghostty tab3 (creation=8)]
Group key: min(5, 12, 8) = 5
All three sort as if creationOrder=5 → they stay together, position stable
```

### Why min()?

The oldest window in a tab group is typically the one that established the group's "slot" in the list. Using `min()` preserves that slot regardless of which tab is active.

## Architecture

### Two Independent Axes

| Preference | Controls | Default |
|------------|----------|---------|
| `groupTabsInSortOrder` | Sort stability (min-key clustering) | `true` |
| `showTabHierarchyInSidePanel` | Display (indented child rows) | per-user |
| `showTabHierarchyInMainPanel` | Display (indented child rows) | per-user |

**These are fully independent.** You can have group sort without tab display (windows stay in stable positions but aren't visually indented), or tab display without group sort (indented but positions jump on tab switch).

### Code Paths

#### Main popup + CLI scripts (`Windows.swift`)

```
updatesBeforeShowing()
  ├─ queryAXTabGroups(list)              // always runs — NOT gated on showTabHierarchy
  ├─ groupSortKeys(list, ..., \.lastFocusOrder)  → groupLastFocusKeys   ┐
  ├─ groupSortKeys(list, ..., \.creationOrder)   → groupCreationKeys    ┤ gated on groupTabsInSortOrder
  └─ sort()
       ├─ recentlyFocused: effectiveLastFocusOrder()  // looks up groupLastFocusKeys[wid]
       ├─ recentlyCreated: effectiveCreationOrder()   // looks up groupCreationKeys[wid]
       ├─ space:           tiebreaker uses effectiveLastFocusOrder()
       └─ alphabetical:    tiebreaker uses effectiveLastFocusOrder()
```

#### Side panel (`SidePanelManager.swift`)

```
refreshPanelsNow()
  ├─ needsTabInfo = showTabHierarchyInSidePanel || showTabHierarchyInMainPanel || groupTabsInSortOrder
  ├─ queryAXTabGroups(windowByCgId.values)        // runs when needsTabInfo (AX IPC is expensive)
  ├─ groupSortKeys(..., \.creationOrder)           // gated on groupTabsInSortOrder
  └─ buildScreenGroups(..., tabParentMap, groupCreationKeys)
       ├─ if showTabs: apply parentWindowId         // display only
       ├─ sort: groupCreationKeys[wid] ?? creationOrder  // always uses group keys if available
       └─ if showTabs: orderWithTabHierarchy()      // display only
```

**Key design decision**: `queryAXTabGroups` runs whenever any tab-aware feature needs it (`showTabHierarchyInSidePanel || showTabHierarchyInMainPanel || groupTabsInSortOrder`). It was originally gated behind `if showTabs` only — the integration decoupled it so group sort works even with tab display off. When all three prefs are off, the AX query is skipped entirely (AX IPC is expensive).

### Aligning All Three Views

With "Order windows by" set to **Recently Created First**, all three views sort by the same key:

| View | Sort key source | Group-aware wrapper |
|------|----------------|---------------------|
| Side panel | `creationOrder` | `groupCreationKeys[wid]` (local to `refreshPanelsNow`) |
| Main popup | `creationOrder` | `effectiveCreationOrder()` → `Windows.groupCreationKeys[wid]` |
| CLI / ⌃⌥9/0 scripts | `Windows.list` order | Same as main popup (sorted in `updatesBeforeShowing`) |

The side panel and main popup compute group keys independently (different call sites) but use the same algorithm (`groupSortKeys`) on the same data (`queryAXTabGroups` output), so results are identical.

## Key Functions

| Function | File | Purpose |
|----------|------|---------|
| `groupSortKeys(_:tabParentMap:keyPath:)` | `Windows.swift` | Builds `[CGWindowID: Int]` mapping — every group member gets `min(keyPath)` |
| `effectiveCreationOrder(_:)` | `Windows.swift` | Lookup wrapper for popup sort — falls back to `window.creationOrder` |
| `effectiveLastFocusOrder(_:)` | `Windows.swift` | Lookup wrapper for popup sort — falls back to `window.lastFocusOrder` |
| `queryAXTabGroups(_:)` | `Windows.swift` | AX forward-lookup — returns `[childWid: parentWid]` map |

## Settings UI

The "Group tabs in sort order" toggle is in **Settings → Panel → Side Panel** section (`PanelTab.swift`). Its `extraAction` calls `refreshPanels()` to apply immediately.

Despite living in the Side Panel section, this is a **global preference** — it affects the main popup sort (`updatesBeforeShowing`) and CLI output too.

## Debugging

### Verify group keys are computed

Add a temporary print in `Windows.groupSortKeys`:
```swift
print("[groupSort] group parent=\(parentWid): children=\(children.map { $0.cgWindowId! }), key=\(minValue)")
```

### Verify sort alignment

Compare side panel order vs CLI output:
```bash
# CLI window list (sorted by updatesBeforeShowing)
curl -s 'http://localhost:PORT/windows?detailed=true' | jq '.[] | {title, creationOrder}'

# Side panel uses same creationOrder with same group keys
```

### Common issues

| Symptom | Likely cause |
|---------|-------------|
| Tab groups still jump in side panel | `groupTabsInSortOrder` is off — check Preferences |
| Group sort works in popup but not side panel | `queryAXTabGroups` re-gated behind `showTabs` (regression) |
| Windows not grouping despite being tabbed | AX query missed them — check `queryAXTabGroups` return; tab may not have `AXTabGroup` child |
| Different order in side panel vs popup | Sort type mismatch — side panel always uses `creationOrder`; popup uses whatever "Order windows by" is set to |

## Known Unknowns

### queryAXTabGroups performance in popup path

`Windows.updatesBeforeShowing()` calls `queryAXTabGroups` unconditionally (`Windows.swift:263`). The side panel path has a 3-pref guard (`needsTabInfo`), but the popup path doesn't — it runs on every alt-tab trigger. AX IPC iterates visible windows' children. For users with many windows/apps, this could add latency to the trigger. May need profiling.

### Group key staleness during search

Group sort keys (`groupLastFocusKeys`, `groupCreationKeys`) are computed once in `updatesBeforeShowing()` and stored as static vars. `updateSearchQuery()` calls `sort()` which reads these stale keys. During a search session the keys are frozen from the last popup trigger. Likely fine — tab structure doesn't change while typing a search query — but the staleness is real.
