<div align="center">

# TideBar 汐

**A hairline at rest, every window at hand.**

TideBar (汐) is a zero-footprint window taskbar for macOS. At rest, it is a hairline tucked against the bottom edge of the screen; move the cursor close and it tides up into an icon bar — every window's state visible as a dot, one click away. Click and hold (or ⌥-click) any icon and the Surge list lays out all of that app's windows, minimized ones included — one click brings any of them back. Turn on takeover and the system Dock steps aside, leaving nothing on screen but the line — a whole row of screen back on small MacBook displays. One permission (Accessibility), no screen recording, no tracking or account.

English · [简体中文](README.zh-CN.md)

[Download (GitHub Releases)](../../releases) · [Website](https://tidebar.dearain.dev) · [Feedback](../../issues)

</div>

<!-- Once demo assets are produced (plans/todo-2026-09-06-branding.md), remove the placeholder below and enable the image:
<img src="docs/images/demo.gif" alt="Tide line → icon bar → Surge" width="720"> -->

> 🎬 **Demo placeholder**: tide line → icon bar → Surge (animation and before/after screenshots to come)

## Features

### Tide Line · Zero footprint

At rest, a 2–3 pt hairline hugs the bottom edge, adapting to light and dark mode — nearly invisible. Approach and it rises like a tide; move away and it settles.

### Dots · Window state, visible

Small dots under each icon mirror your windows: filled for the active window, hollow for minimized. They answer not "which apps are running" but "where every window is".

### Surge · Reach any window

Click and hold (or ⌥-click) an icon to fan out its window list; jump straight to any window by title, minimized ones restore on a click. When the Dock hides, minimized windows finally have a home.

### Ripple · Considerate notifications

A new badge nudges the line once; unread, it keeps gently rippling; opening the bar settles it. It doesn't shout "you have unread things" — it quietly says "not yet seen".

## Permissions & Privacy

- **One permission only**: Accessibility — used to list and restore windows and detect fullscreen state.
- **No screen recording**: TideBar shows no window thumbnails and asks for no Screen Recording permission.
- **No telemetry**: no tracking, no account, no analytics.

## Install

Download the latest `TideBar.app` from [Releases](../../releases) and drag it into Applications. Requires **macOS 14** or later.

### Build from source

```bash
swift build    # compile
swift run      # run locally (occupies the terminal, Ctrl-C to quit)
```

Requires a Swift 6.2+ toolchain; macOS 14 minimum.

## Documentation

Project docs are written in Chinese:

- [Product positioning & core interactions](docs/product.md)
- [Architecture decisions & conventions](docs/decisions.md)
- [External copy source (bilingual)](docs/copy.md)

## License

[MIT](LICENSE)
