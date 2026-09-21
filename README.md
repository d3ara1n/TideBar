<p align="center">
  <img src="assets/banner.png" alt="TideBar 汐 — a window taskbar for macOS that collapses to a thin line at the bottom of the screen and expands when approached.">
</p>

[![Release](https://img.shields.io/github/v/release/d3ara1n/TideBar)](https://github.com/d3ara1n/TideBar/releases/latest) [![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)](https://github.com/d3ara1n/TideBar) [![MIT License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[Download](https://github.com/d3ara1n/TideBar/releases) · [Website](https://tidebar.dearain.dev) · [Report an issue](https://github.com/d3ara1n/TideBar/issues)

English · [简体中文](README.zh-CN.md)

## Why TideBar

The macOS Dock costs permanent screen space, hides minimized windows behind an invisible edge, and tells you little beyond a running dot. TideBar keeps the useful parts — launching, switching, recovering minimized windows — and drops the permanent footprint.

| | macOS Dock | TideBar |
|---|---|---|
| Screen space | A permanent bar along the bottom | A 2–3 pt line when idle, expanding only when approached |
| Minimized windows | Easy to lose, hard to restore | State dots under each app icon; click to restore |
| Window awareness | A running dot only | Per-window state dots and a per-app window list |

TideBar does not try to recreate every Dock feature. It focuses on two things: zero on-screen presence, and window management.

## Features

### Tide Line & expansion

- Collapses to a subtle capsule line that adapts to light and dark mode. Move the pointer close to expand; move away to collapse.
- In fullscreen apps the line stays out of the way by default — click it to expand. Hover-to-expand or fully hidden are available in **Settings → Appearance & Interaction**.
- Works on multiple displays, one line per screen.
- Prefer the keyboard? **Option-Space** shows or hides the bar from anywhere.

### Window management

- Window dots under every running app: filled for on-screen windows, hollow for minimized, accent color for the focused one, dimmed for windows on another display. With more than five windows, the count replaces the dots.
- Click an app to launch it or cycle through its windows — minimized windows join the cycle and restore with a click.
- Hold or Option-click an app to open its **Surge**: the app's window list by title. Click any entry — minimized included — to focus or restore it.
- When the system Dock is hidden, minimized windows still have a home: the Surge list takes over where the Dock's minimized-window tray left off.

### Items & pinning

- Pin apps, files, and folders alongside running apps. Unpinning never deletes the file or quits the app.
- Drag within the bar to reorder, drag out to unpin, or drag in from Finder to pin. Dropping files **onto an app icon** opens them with that app; onto **a folder icon** moves them in (same volume only, never overwrites).
- Right-click an app to pin or unpin it, reveal it in Finder, show or hide its windows, or quit it.
- **App Collections** group launch shortcuts for quick starting; they don't mirror the running state of their apps.

### Notifications, quietly

- App badges are mirrored from the system Dock onto TideBar icons.
- A new badge sends one pulse along the Tide Line, then a calm ripple repeats until you expand the bar or the triggering apps' badges clear. Expanding acknowledges the reminder — it never marks messages as read in the original apps.

## Install

Requires **macOS 14 or later**.

1. Download the `TideBar-<version>.zip` asset from [Releases](https://github.com/d3ara1n/TideBar/releases).
2. Extract it and move `TideBar.app` to Applications.
3. Open TideBar. Current builds are not notarized by Apple. If macOS blocks the app, try launching it once, then open **System Settings → Privacy & Security** and use **Open Anyway**.
4. Follow the setup guide to grant Accessibility access and enable Dock takeover.

TideBar lives in the menu bar — use its menu to open Settings or quit.

## Dock takeover & recovery

TideBar shows its taskbar only while Dock takeover is enabled:

- Enabling it saves your current Dock settings, changes them to hide the Dock, adjusts the Dock icon size and the minimization animation, and restarts the Dock process.
- Your open apps keep running throughout.

**To bring back the system Dock:** open **Settings → Dock & Recovery** and disable takeover; TideBar reapplies the settings it saved. Quitting TideBar normally restores them automatically.

**If TideBar quits unexpectedly** (a crash or a force quit), the saved settings are not reapplied and the system Dock stays hidden. To restore it:

1. Reopen TideBar.
2. Go to **Settings → Dock & Recovery** and disable takeover to restore your saved Dock settings.

## Usage

| Action | Result |
|---|---|
| Move the pointer near the bottom line | Expand the bar; moving away collapses it |
| Click an app | Launch it or switch to its recent window; restore a minimized window if none are unminimized |
| Hold or Option-click an app | Open its Surge window list; click a title to focus or restore that window |
| Right-click an app | Pin or unpin it, show it in Finder, show or hide its windows, or quit it |
| Drag an app, file, or folder from Finder into a gap in the bar | Pin it |
| Drag a pinned item within the bar or out of it | Reorder it or unpin it; unpinning does not delete the resource or quit the app |
| Click a pinned file or folder | Open it with macOS |
| Hold or Option-click a folder | List its contents by modification time, newest first |

Dropping files **onto an app icon** opens them with that app if it supports them. Dropping them **onto a folder icon** moves the files into that folder. Folder drops support moves on the same volume and do not overwrite existing files.

### Keyboard

| Default shortcut | Action |
|---|---|
| Option-Space | Show or hide the bar for keyboard navigation |
| Option-Tab | Cycle through apps; the selection activates after a short idle delay |
| Left / Right | Select an app |
| Down | Open the selected app's Surge, then move down the list |
| Up | Move up the window list |
| Return | Activate the selection |
| Escape | Close the window list, or cancel navigation at the app level |

Fullscreen behavior and appearance options live in **Settings → Appearance & Interaction**; global shortcuts and the switching delay in **Settings → Shortcuts**.

## Permissions and privacy

- The **Accessibility** permission is used to read window titles and states, focus and restore windows, detect fullscreen apps, and mirror Dock badges. Without it, app launching still works, but window management is limited.
- TideBar shows no window thumbnails and never asks for **Screen Recording**.
- No account system, no analytics, no telemetry of any kind. The only network traffic is Sparkle checking GitHub Releases for updates (and downloading one, if you choose to); automatic checks can be disabled in **Settings → About**.
- File access follows standard macOS access controls.

## Known limitations

- No window previews or thumbnails — a deliberate trade-off to avoid the Screen Recording permission.
- No Trash item and no app-specific Dock menus.
- Some apps do not expose usable window information; for those, launching works but window management is unavailable.
- The expanded icon bar overlays your windows; it never resizes or rearranges them.
- Folder drops move files within the same volume only, and never overwrite existing files.

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
