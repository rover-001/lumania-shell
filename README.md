# Lumania Shell

A desktop shell for [Omarchy](https://omarchy.org) / Hyprland, built with [Quickshell](https://quickshell.org) (QML) and a few small Rust helpers.

It replaces the Omarchy bar with a thin frame around your screen plus a set of pop-out panels ("notches") on its edges:

| Where | File | What it does |
| --- | --- | --- |
| Top center | `DynamicIsland.qml` | Clock, now-playing media (MPRIS) with album art, controls and an audio visualizer, notifications |
| Top left | `TopLeftNotch.qml` | Power menu: lock, logout, suspend, reboot, shutdown |
| Top right | `TopRightNotch.qml` | System tray |
| Workspaces | `WorkspaceNotch.qml` | Hyprland workspace switcher |
| Bottom center | `BottomSearchNotch.qml` | App launcher / search |
| Bottom left | `WallpaperNotch.qml` | Wallpaper picker; shell colors follow the wallpaper |
| Bottom right | `ControlCenterNotch.qml` | Wi-Fi, Bluetooth, volume, brightness, battery, power profile |

Entry point is `IslandBar.qml` (registered as the Omarchy bar plugin `lumania.island` in `manifest.json`).

## Requirements

- Omarchy (Arch Linux) with Hyprland and `omarchy-shell` / Quickshell
- PipeWire (for the visualizer)
- `rustc` to build the helpers
- `python3` (for `lumania-focus`, used to focus apps from notifications)

## Getting started

**1. Clone to `~/Projects/lumania shell`.**
Several QML files call the Rust helpers by this exact path, so keep it (including the space) unless you also edit those paths.

```bash
git clone https://github.com/rover-001/lumania-shell.git ~/Projects/"lumania shell"
cd ~/Projects/"lumania shell"
```

**2. Build the helpers.**

```bash
./build.sh
```

This compiles three binaries with `rustc`:
- `lumania-vis` – reads audio from PipeWire and feeds the visualizer
- `lumania-colors` – picks accent colors from the current wallpaper
- `lumania-status` – Wi-Fi / Bluetooth / battery info for the control center

**3. Register it as an Omarchy plugin.**

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s ~/Projects/"lumania shell" ~/.config/omarchy/plugins/lumania.island
```

**4. Make it the active bar** in `~/.config/omarchy/shell.json`:

```json
{
  "activeBar": "lumania.island"
}
```

**5. (Optional) Put the launcher scripts on your PATH and bind keys.**

```bash
mkdir -p ~/.local/bin
for s in lumania-search lumania-wallpaper lumania-focus; do
  ln -sf ~/Projects/"lumania shell"/$s ~/.local/bin/$s
done
```

`~/.config/hypr/hyprland.conf`:

```ini
bind = SUPER, SPACE, exec, lumania-search
bind = SUPER CTRL, SPACE, exec, lumania-wallpaper
```

**6. Restart the shell.**

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

## License

MIT
