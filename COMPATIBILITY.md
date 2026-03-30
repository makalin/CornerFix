# Compatibility Matrix

Use this matrix when validating a new release or a new macOS build.

## Core Matrix

| Area | Example Targets | What To Check |
|---|---|---|
| Native apps | Safari, Finder, Terminal | windows sharpen, titlebars remain usable |
| Developer tools | Xcode, Console | no crashes, inspectors/panels are not corrupted |
| Chromium/Electron | Chrome, Slack, VS Code | custom window chrome still behaves |
| Utility apps | Activity Monitor, System Settings | sheets and secondary panels are not broken |
| Fullscreen | Safari fullscreen, QuickTime fullscreen | radius falls back cleanly, no artifacts |
| Multi-display | two monitors with mixed scaling | windows remain correct when moved across screens |
| Spaces | Mission Control, separate spaces | windows re-apply after space changes |
| Dialogs | save/open panels, alerts | transient windows stay filtered or render acceptably |

## Recommended Test Pass

1. Enable globally with `cornerfixctl --preset sharp`
2. Launch each app fresh under the loader
3. Create a standard window, resize it, and toggle fullscreen
4. Open a dialog, sheet, popover, or inspector where relevant
5. Move the window between displays if available
6. Disable globally, then re-enable with a softer radius
7. Apply one per-app override and confirm only that app changes

## Result Template

| App | macOS Version | Result | Notes |
|---|---|---|---|
| Safari | | pass/fail | |
| Finder | | pass/fail | |
| Terminal | | pass/fail | |
| Xcode | | pass/fail | |
| Chrome | | pass/fail | |
| Slack | | pass/fail | |
