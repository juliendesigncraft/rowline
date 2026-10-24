# Rowline

Every Mac window in one horizontal row.

Rowline is a small menu bar app for macOS. Your open windows sit side by side in a single row instead of piling up. The row scrolls. The focused window is always fully visible. A thin slider at the bottom of the screen shows where you are in the row.

This is the version shown in my reel of 18 October 2026.

## What it does

- One row per screen. Each place in the row is a column with one window, or several stacked windows.
- A thin slider at the bottom: one single line as long as the row, brighter where the screen is, light blue on the focused window. Click a point to jump to the window under it, or drag to scroll the row.
- Workspaces: save the apps, their order and their widths, then restore them with one click or a shortcut.
- Three-finger swipe on the trackpad to move along the row. Four fingers, or ⌥ with two fingers, also work.
- A shortcuts sheet: hold ⌃⌥⌘ for almost a second and every shortcut appears. Let go and it disappears.
- Width per app, window previews in the slider, and on-screen keys for screen recordings.

## Requirements

- macOS 14 or later.
- The Accessibility permission. Nothing else is needed for the core app.
- Window previews in the slider are optional and ask for Screen Recording only if you turn them on.
- No network, no account.

## Build

You need the Xcode Command Line Tools (`xcode-select --install`).

```
./build.sh
open build/Rowline.app
```

The app is signed ad-hoc, so macOS asks for the Accessibility permission again after each rebuild. To keep the permission, sign with your own certificate:

```
SIGN_IDENTITY="Your Certificate Name" ./build.sh
```

## Remove

1. Quit Rowline from the menu bar icon. Parked windows come back into view.
2. Delete `Rowline.app`.
3. Optional: `defaults delete com.juliendesigncraft.rowline` removes the saved settings and workspaces.
4. Optional: remove Rowline from System Settings, Privacy and Security, Accessibility.

## Shortcuts

All of them can be changed in the panel. Open the panel with ⌃⌥⌘F or by clicking the menu bar icon.

| Shortcut | Action |
| --- | --- |
| ⌃⌥⌘ ← | Window on the left |
| ⌃⌥⌘ → | Window on the right |
| ⌃⌥⌘ ↑ | Up in the stack |
| ⌃⌥⌘ ↓ | Down in the stack |
| ⌃⌥⌘⇧ ← | Move left |
| ⌃⌥⌘⇧ → | Move right |
| ⌃⌥⌘ 1 | Half screen |
| ⌃⌥⌘ 2 | Two thirds |
| ⌃⌥⌘ 3 | Full width |
| ⌃⌥⌘ R | Change width |
| ⌃⌥⌘ = | Wider |
| ⌃⌥⌘ - | Narrower |
| ⌃⌥⌘ C | Centre |
| ⌃⌥⌘ [ | Stack left |
| ⌃⌥⌘ ] | Stack right |
| ⌃⌥⌘⇧ [ | Pop out left |
| ⌃⌥⌘⇧ ] | Pop out right |
| ⌃⌥⌘ T | Float or put back |
| ⌃⌥⌘ N | To the other display |
| ⌃⌥⌘ 4, 5, 6 | Workspaces 1, 2, 3 |
| ⌃⌥⌘ F | Open Rowline |
| ⌃⌥⌘ P | Turn on or off |

## License

PolyForm Noncommercial License 1.0.0. See `LICENSE`.

## Credit

Made by @juliendesigncraft with Claude.

Want it ready to use, signed and updated? Rowline is part of Pulsar: juliendesigncraft.gumroad.com
