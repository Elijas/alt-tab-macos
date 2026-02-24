# Make Window Panel space dividers bold and visible

## Context
The Window Panel (`WindowListView.swift`) shows windows grouped by space, separated by thin 1px lines using `NSColor.separatorColor`. These dividers are nearly invisible — the user wants them bold and super clear.

## Changes — `src/ui/side-panel/WindowListView.swift`

### 1. Increase separator thickness
`separatorHeight`: `1` → `2`

### 2. Add more breathing room around separators
`separatorPadding`: `6` → `8`

### 3. Make the line span full width (remove horizontal inset)
In `updateContents()` and `relayoutForBounds()`, change separator frame from:
```swift
sep.frame = CGRect(x: 12, y: yPos, width: width - 24, height: Self.separatorHeight)
```
to:
```swift
sep.frame = CGRect(x: 0, y: yPos, width: width, height: Self.separatorHeight)
```
(Two locations: `updateContents` line ~143 and `relayoutForBounds` line ~69)

### 4. Use a higher-contrast color
In `makeSeparator()`, replace `NSColor.separatorColor` with a more visible color:
```swift
sep.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.5).cgColor
```
This gives a solid mid-grey line that's clearly visible in both light and dark mode, without being distractingly harsh.

## Files modified
- `src/ui/side-panel/WindowListView.swift` — all changes in this one file

## Verification
Build → reinstall with TCC reset → open Window Panel → confirm space dividers are visually prominent between groups.
