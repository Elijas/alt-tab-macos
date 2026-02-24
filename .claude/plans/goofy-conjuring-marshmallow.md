# Fix: `isTabbed` false positive skipping windows in cycle-next/cycle-prev jq scripts

## Context

The skhd shortcuts `Ctrl+Opt+9` / `Ctrl+Opt+0` cycle windows on the current screen using jq scripts that query AltTab's CLI (`--detailed-list`). The scripts filter out windows where `isTabbed == true` (line 19 of both `cycle-next.jq` and `cycle-prev.jq`).

AltTab's `isTabbed` detection is **self-described as "flaky"** (`Windows.swift:91`). It relies on a private macOS API (`CGSCopyWindowsWithOptionsAndTags`) and produces false positives — a visible, non-tabbed window can be reported as `isTabbed = true` if it's not in the API's visible-windows list at the instant of the snapshot. AltTab's own UI compensates with delayed refreshes, but the one-shot CLI read has no retry.

Result: the "caffeinate -dims" Ghostty window is falsely flagged `isTabbed = true` and filtered out by the jq scripts, even though AltTab's panel correctly shows it.

## Fix

**Remove `select(.isTabbed == false)` from both jq scripts.**

### Files to modify

1. **`/Users/user/Development/personal-workbench/w260126_alttab_workaround/src/cycle-next.jq`** — delete line 19 (`select(.isTabbed == false) |`)
2. **`/Users/user/Development/personal-workbench/w260126_alttab_workaround/src/cycle-prev.jq`** — delete line 19 (`select(.isTabbed == false) |`)

### Trade-off

Removing the filter means that if you have actual macOS native tabs (e.g., multiple Finder tabs merged into one window), the inactive tabs would appear in the cycle. In practice this is unlikely to matter — Ghostty and most terminal apps don't use macOS native tab grouping, and the false-positive cost (skipping real windows) outweighs the false-negative cost (occasionally cycling to a tab sub-window).

## Verification

1. Run `at004 --detailed-list | jq '[.windows[] | select(.appName == "Ghostty") | {title, isTabbed}]'` to confirm the caffeinate window has `isTabbed: true` (proving the hypothesis)
2. After the fix, press `Ctrl+Opt+0` / `Ctrl+Opt+9` and confirm all 4 windows on the screen are cycled through, including the caffeinate Ghostty window
