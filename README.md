# TideBar 汐

An open-source window taskbar for macOS. TideBar collapses to a thin line at the bottom of the screen and expands when you move the pointer near it. Use it to launch apps, switch windows, and restore minimized windows.

English · [简体中文](README.zh-CN.md)

[Download](https://github.com/d3ara1n/TideBar/releases) · [Website](https://tidebar.dearain.dev) · [Report an issue](https://github.com/d3ara1n/TideBar/issues)

## Features

- Launch apps and switch to individual windows from a list of window titles, including minimized windows.
- See window states below each app icon: filled dots for non-minimized windows, hollow dots for minimized windows, and an accent color for the focused window.
- Pin apps, files, and folders. Drag to reorder them, or open a folder's recently modified items from its popup list.
- Create app collections to group launch shortcuts.
- Show app notification badges from the system Dock. New badges trigger a line animation that stops when you expand the bar.
- Use keyboard shortcuts, display the bar on multiple monitors, and adjust its appearance and fullscreen behavior.

## Install

Requires **macOS 14 or later**.

1. Download the `TideBar-<version>.zip` asset from [Releases](https://github.com/d3ara1n/TideBar/releases).
2. Extract it and move `TideBar.app` to Applications.
3. Open TideBar. Current builds are not notarized by Apple. If macOS blocks the app, open **System Settings → Privacy & Security** and use **Open Anyway** after attempting to launch it.
4. Follow the setup guide to grant Accessibility access and enable Dock takeover.

TideBar appears in the menu bar. Use that menu to open Settings or quit.

### System Dock settings

Enabling Dock takeover saves your existing Dock settings, changes them to hide the Dock, and restarts the Dock process. It also changes Dock icon size and the minimization animation. Your open apps stay running.

The TideBar taskbar appears only while takeover is enabled. To disable it and restore your saved Dock settings, use **Settings → Dock & Recovery**. Quitting TideBar normally also restores those settings; a crash or forced termination may leave them changed. Reopen TideBar and use the same settings page to restore them.

## Use TideBar

| Action | Result |
|---|---|
| Move the pointer near the bottom line | Expand the bar; moving away collapses it |
| Click an app | Launch it or switch to its recent window; restore a minimized window if none are unminimized |
| Hold or Option-click an app | Open its window list; click a title to focus or restore that window |
| Right-click an app | Pin or unpin it, show it in Finder, show or hide its windows, or quit it |
| Drag an app, file, or folder from Finder into a gap in the bar | Pin it |
| Drag a pinned item within the bar or out of it | Reorder it or unpin it; unpinning does not delete the resource or quit the app |
| Click a pinned file or folder | Open it with macOS |
| Hold or Option-click a folder | List its contents by modification time, newest first |

Dropping files from Finder **onto an app icon** opens them with that app if it supports them. Dropping them **onto a folder icon** moves the files into that folder. Folder drops support moves on the same volume and do not overwrite existing files.

### Keyboard shortcuts

| Default shortcut | Action |
|---|---|
| Option-Space | Show or hide the bar for keyboard navigation |
| Option-Tab | Cycle through apps; the selection activates after a short idle delay |
| Left / Right | Select an app |
| Down | Open the selected app's window list, then move down the list |
| Up | Move up the window list |
| Return | Activate the selection |
| Escape | Close the window list, or cancel navigation at the app level |

Change the global shortcuts and switching delay in **Settings → Shortcuts**. Keyboard navigation covers apps and their windows.

In fullscreen apps, click the bottom line to expand it by default. You can choose hover-to-expand or hide it entirely in **Settings → Appearance & Interaction**.

## Permissions and limitations

- **Accessibility** is used to read window titles and states, focus and restore windows, detect fullscreen apps, and read Dock badges. Without it, app launching remains available but window management is limited. Some apps do not expose usable window information.
- TideBar does not show window thumbnails or request Screen Recording permission. File access follows macOS access controls.
- TideBar has no account system or usage analytics. Packaged builds use Sparkle to check GitHub Releases for updates; automatic checks can be disabled in **Settings → About**.
- TideBar does not include a Trash item or app-specific Dock menus. Expanding the bar overlays your windows without resizing them.

## Build from source

Requires a Swift 6.2 or later toolchain on macOS. Clone the repository, build, and run:

```bash
git clone https://github.com/d3ara1n/TideBar.git
cd TideBar
swift build
swift run
```

Keep the terminal open while running, and quit through TideBar's menu bar menu to restore the Dock settings. The development executable and the packaged app need separate Accessibility grants. Update checks and launch at login are available only in `TideBar.app`.

## Feedback and contributions

Report bugs or suggest changes in [Issues](https://github.com/d3ara1n/TideBar/issues). For bugs, include your macOS version, TideBar version, and steps to reproduce. Pull requests are welcome; describe the behavior you changed and how you checked it.

## License

[MIT](LICENSE)
