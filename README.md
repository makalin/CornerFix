# CornerFix (macOS)

Visually square the rounded **display** corners in macOS 26 (Tahoe) and newer by drawing unobtrusive, click‑through overlay caps.

> Note: This does **not** change the rounded corners of individual app windows. It only restores the straight silhouette at the *edges of your display*.

---

## Why CornerFix?

Apple made corners more aggressively rounded in macOS 26, and many users find the effect distracting. There’s no system setting to disable it. CornerFix provides a safe, non-invasive way to visually bring back sharp edges without hacking system files.

Read the full story on Medium: [Reclaiming the Screen: A Developer’s Fix for macOS 26’s Corners](https://medium.com/@makalin/reclaiming-the-screen-a-developers-fix-for-macos-26-s-corners-a28844a0974d)

---

## Features

* Always‑on‑top, click‑through overlay windows per display
* Adjustable cap size (pixels)
* Auto color mode (matches dark/light appearance)
* Custom color selection for tricky wallpapers
* Multi‑monitor support, Spaces/fullscreen friendly
* Menu‑bar interface, no entitlements, SIP‑safe

---

## Quick Start (Xcode)

1. **File → New → Project… → App (macOS)**

   * Interface: *SwiftUI*, Language: *Swift*
2. Save as `CornerFix`.
3. Add the Swift files from `/Sources` into your target.
4. Build & run. A menu bar item named **CornerFix** appears.

---

## Requirements

* macOS 13+ (tested on macOS 14–26)
* Xcode 15+

---

## Notes

* For patterned wallpapers, try custom color mode to match the background edges.
* Overlay uses `.screenSaver` window level. If another app draws above that, you may see overlap.

---

## License

MIT Ⓒ 2025 Mehmet T. AKALIN
