<div align="center">

# Lumania Shell

**A desktop shell for Omarchy / Hyprland, built with Quickshell.**

[![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?style=for-the-badge&logo=hyprland&logoColor=black)](https://hyprland.org)
[![Omarchy](https://img.shields.io/badge/Omarchy-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)](https://omarchy.org)
[![Quickshell](https://img.shields.io/badge/Quickshell-QML-41CD52?style=for-the-badge&logo=qt&logoColor=white)](https://quickshell.org)
[![Rust](https://img.shields.io/badge/Rust-helpers-CE422B?style=for-the-badge&logo=rust&logoColor=white)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](#license)

<img src="assets/showcase.gif" alt="Lumania Shell showcase" width="100%">

<a href="https://buymeacoffee.com/rover01"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black" alt="Buy me a coffee"></a>

[Features](#features) · [Getting started](#getting-started) · [Commands](#controlling-it-from-the-terminal) · [Configuration](#configuration)

</div>

---

## Features

Lumania replaces the Omarchy bar with a thin frame around your screen plus a set of pop-out panels ("notches") on its edges:

| Where | File | What it does |
| --- | --- | --- |
| Top center | `DynamicIsland.qml` | Clock, now-playing media (MPRIS) with album art, controls and an audio visualizer, notifications |
| Top left | `TopLeftNotch.qml` | Power menu: lock, logout, suspend, reboot, shutdown |
| Top right | `TopRightNotch.qml` | System tray |
| Workspaces | `WorkspaceNotch.qml` | Hyprland workspace switcher |
| Bottom center | `BottomSearchNotch.qml` | App launcher / search |
| Bottom left | `WallpaperNotch.qml` | Wallpaper picker; shell colors follow the wallpaper |
| Bottom right | `ControlCenterNotch.qml` | Wi-Fi, Bluetooth, volume, brightness, battery, power profile |

The wallpaper tone also drives the keyboard backlight where the hardware exposes writable RGB (see [Keyboard backlight sync](#keyboard-backlight-sync)).

Entry point is `IslandBar.qml` (registered as the Omarchy bar plugin `lumania.island` in `manifest.json`).

## Requirements

- Omarchy (Arch Linux) with Hyprland and `omarchy-shell` / Quickshell
- PipeWire (for the visualizer)
- `rustc` (only to rebuild the helpers)
- `python3` (for `lumania-focus` and `lumania-call-status`: focusing apps from notifications, detecting voice calls)
- Optional: `ydotool` and `jq` for the island's hang-up button (`lumania-call-cut`). It clicks Discord's Disconnect button, so it currently works only with Discord in its default layout.

## Getting started

**1. Install from the Omarchy plugin marketplace** (or straight from git):

```bash
omarchy plugin add https://github.com/rover-001/lumania-shell.git --enable
```

This clones the plugin into `~/.config/omarchy/plugins/lumania.island` and makes it the active bar. Plugins land disabled until you enable them, so you can drop `--enable` and read the code first, then run `omarchy plugin enable lumania.island`.

**2. Helpers.** Prebuilt x86_64 binaries ship in the repo:
- `lumania-vis` reads audio from PipeWire and drives the visualizer
- `lumania-colors` picks accent colors from the current wallpaper
- `lumania-status` reports Wi-Fi, Bluetooth and battery state to the control center
- `lumania-settings` native Rust + GPUI companion app for shell settings and updates

`lumania-keyboard` is a plain bash helper (no build step) that pushes the wallpaper tone onto the keyboard backlight.

The plugin calls them from its own folder, wherever it is installed. To rebuild them from source (another architecture, or after editing a `.rs` file):

```bash
cd ~/.config/omarchy/plugins/lumania.island && ./build.sh
```

**Updating:** `omarchy plugin update lumania.island` or open `lumania-settings` and click "Update Now". **Removing:** `omarchy plugin remove lumania.island`.

**3. (Optional) Put the launcher scripts on your PATH and bind keys.**

```bash
mkdir -p ~/.local/bin
for s in lumania-search lumania-wallpaper lumania-focus lumania-settings; do
  ln -sf ~/.config/omarchy/plugins/lumania.island/$s ~/.local/bin/$s
done
```

`~/.config/hypr/hyprland.conf`:

```ini
bind = SUPER, SPACE, exec, lumania-search
bind = SUPER CTRL, SPACE, exec, lumania-wallpaper
```

**4. Restart the shell.**

```bash
omarchy restart shell
```

## Controlling it from the terminal

```bash
omarchy-shell lumania.search toggle
omarchy-shell lumania.wallpaper toggle   # also: next, prev
omarchy-shell lumania.control toggle
omarchy-shell lumania.control status wifi   # or bluetooth, audio
```

## Configuration

Colors, frame thickness, corner radii and panel sizes live in `FrameConfig.qml`. Set `dynamicWallpaperColor: false` there to use the fixed `borderColor` / `textColor` instead of wallpaper-derived colors.

After editing, run `omarchy restart shell`. If you change a `.rs` file, re-run `./build.sh`.

## Keyboard backlight sync

`KeyboardColorSync.qml` pushes the same tone the frame and island use (`activeBorderColor`) onto the keyboard backlight. Turn it off with `syncKeyboardColor: false` in `FrameConfig.qml`.

Keyboards are not interchangeable, so all hardware knowledge lives in the `lumania-keyboard` helper. On start the shell asks it `--probe`, and if the answer is "nothing writable here" the backlight is never touched:

| Backend | Hardware | How |
| --- | --- | --- |
| `omen4zone` | HP OMEN 4-zone RGB (`omen-rgb-keyboard` driver) | writes `rgb_zones/all`; auto-detected, udev grants the `input` group |
| `multicolor` | LED-class `*kbd*` backlight with red/green/blue channels | writes `multi_intensity`; auto-detected |
| `openrgb` | Any board OpenRGB supports (external keyboards) | opt-in: `LUMANIA_KEYBOARD_BACKEND=openrgb` |
| `brightness` | Monochrome backlights with no color channel | opt-in: `LUMANIA_KEYBOARD_BACKEND=brightness`, brightness follows the tone's luminance |

OpenRGB and brightness are opt-in because the first drives every device OpenRGB manages and the second has no hue to drive, so the shell will not take them over unasked. Export the variable somewhere the shell sees it (`~/.config/uwsm/env`, `~/.config/hypr/hyprland.conf` `env =`, or `~/.config/environment.d/`):

```bash
LUMANIA_KEYBOARD_BACKEND=openrgb
LUMANIA_KEYBOARD_OPENRGB_DEVICE=0   # optional; default drives all OpenRGB devices
LUMANIA_KEYBOARD_TARGET=/sys/class/leds/rgb:kbd_backlight   # optional; force a node
```

Check what a machine reports:

```bash
~/.config/omarchy/plugins/lumania.island/lumania-keyboard --probe
```

Brightness is respected: the OMEN driver scales the tone by the keyboard's own brightness, so screen-following dimming keeps working. Wallpaper switches coalesce into one hardware write (~350 ms debounce), and an identical tone is never rewritten. A board that is not supported is polled every 15 s, so plugging in a supported keyboard lights it up without restarting the shell.

## Support

If you like Lumania Shell, you can support development here:

<a href="https://buymeacoffee.com/rover01"><img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=%E2%98%95&slug=rover01&button_colour=FFDD00&font_colour=000000&font_family=Inter&outline_colour=000000&coffee_colour=ffffff" alt="Buy me a coffee" height="45"></a>

## License

MIT, see [LICENSE](LICENSE).
