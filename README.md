# 🏝️ Lumania Shell — iOS Dynamic Island & Fluid Bezel for Hyprland

[![Platform](https://img.shields.io/badge/platform-Wayland%20%7C%20Hyprland-blue.svg)](#)
[![Runtime](https://img.shields.io/badge/runtime-Quickshell%20%E2%89%A50.3-emerald.svg)](#)
[![Audio](https://img.shields.io/badge/audio-PipeWire%20FFT-orange.svg)](#)
[![OS](https://img.shields.io/badge/os-Arch%20Linux%20%7C%20Omarchy-purple.svg)](#)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

An ultra-sleek, hardware-native **Dynamic Island notch bar and OLED bezel suite** for **Hyprland** and **Omarchy Shell** powered by **Quickshell**.

Lumania replaces conventional desktop taskbars with an organic 5px screen bezel and interactive floating notches designed with fluid iOS-style spring mechanics: retracting flush into the display frame when windows are active, springing into view on cursor hover, and morphing seamlessly into media players, system monitors, notification banners, and spotlight launchers.

```
┌──────────────────────────────── screen ────────────────────────────────┐
│  [Power]  [1][2][3][4]          ((( ● )))          [Tray] [Whimsy]     │
│                              dynamic island                            │
│                                                                        │
│                    your windows (docked to the bezel)                  │
│                                                                        │
│                           [Search Notch]                               │
│                   [Wallpaper]        [Control Center]                  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## ✨ Features

- 🏝️ **Adaptive Dynamic Island**:
  - **Clock & Date**: Minimalist digital clock with date view.
  - **Live MPRIS Media Player**: Real-time fluid PipeWire audio visualizer (`lumania-vis`), circular cover art with fallback thumbnailing for Spotify and YouTube, persistent sticky player, and playback controls.
  - **Intelligent Audio Decay**: Waveforms collapse fluidly into the clock pill the moment audio pauses instead of freezing mid-frame.
  - **Call Heads**: Real-time active call badges for Discord, WhatsApp, Telegram, and WebRTC.
  - **Interactive Popups**: Expands into high-density media and notification cards on hover.
- 🎛️ **Quick Control Center**:
  - Bottom-right corner trigger with quick toggles for Wi-Fi, Bluetooth, Audio Volume, Microphone, Screen Brightness, Battery status, and Power profiles.
- 🔍 **Spotlight Search Notch**:
  - Centered bottom command runner, application launcher, and quick calculations with live backdrop blur.
- 🖼️ **Wallpaper Filmstrip**:
  - Bottom edge notch displaying wallpapers with real-time hardware-accelerated dominant color extraction (`lumania-colors`) synced directly to your UI palette.
- 📐 **G1 Bezel & Layer-Shell Precision**:
  - Surrounds the display with a 5px OLED bezel and G1-continuous fillets with zero click-through interference via surgical Wayland input masking.

---

## 📋 Requirements

| Dependency | Purpose | Verification |
| :--- | :--- | :--- |
| **Omarchy** / **Arch Linux** | Quickshell platform, `qs.Ui`, and `qs.Commons` | `omarchy --version` |
| **Quickshell ≥ 0.3** | Wayland QML shell runtime | `qs --version` |
| **Hyprland** | Wayland compositor and IPC | `hyprctl version` |
| **Rust (`rustc`)** | Compiles native visualizer and status engines | `rustc --version` |
| **PipeWire (`pw-record`)** | Captures audio spectrum for the live waveform | `which pw-record` |
| **`jq`** | JSON parser for Hyprland workspace queries | `jq --version` |
| **Python 3** | Optional call detection backend | `python3 --version` |

---

## 🚀 Installation Guide

### Step 1: Clone the Repository

Clone Lumania Shell directly into your Omarchy plugins directory:

```bash
# Clone repository
git clone https://github.com/rover-001/lumania-shell.git ~/.config/omarchy/plugins/lumania.island
```

*(Alternatively, if cloned to a custom location such as `~/Projects/lumania-shell`, create a symlink):*

```bash
ln -s "$HOME/Projects/lumania-shell" ~/.config/omarchy/plugins/lumania.island
```

### Step 2: Build Native Helper Binaries

Lumania Shell includes three performance-critical native engines written in Rust:
- `lumania-vis`: Low-latency PipeWire FFT spectrum visualizer.
- `lumania-colors`: Image color extraction engine for dynamic UI theming.
- `lumania-status`: Asynchronous Wi-Fi, Bluetooth, and battery telemetry backend.

Run the build script:

```bash
cd ~/.config/omarchy/plugins/lumania.island
chmod +x build.sh lumania-search lumania-wallpaper lumania-focus
./build.sh
```

### Step 3: Install Command-Line Wrappers

Link the wrapper scripts to your local user binary path so keybindings can trigger notches:

```bash
mkdir -p ~/.local/bin
ln -sf ~/.config/omarchy/plugins/lumania.island/lumania-search ~/.local/bin/lumania-search
ln -sf ~/.config/omarchy/plugins/lumania.island/lumania-wallpaper ~/.local/bin/lumania-wallpaper
ln -sf ~/.config/omarchy/plugins/lumania.island/lumania-focus ~/.local/bin/lumania-focus
```

Make sure `~/.local/bin` is in your `$PATH`.

### Step 4: Configure Omarchy Shell

Set `lumania.island` as your active bar in `~/.config/omarchy/shell.json`:

```json
{
  "activeBar": "lumania.island"
}
```

### Step 5: Configure Hyprland Keybindings

Add the recommended keybindings to your Hyprland configuration (`~/.config/hypr/hyprland.conf` or `~/.config/hypr/bindings.conf`):

```ini
# Lumania Shell Notches
bind = SUPER, SPACE, exec, lumania-search
bind = SUPER SHIFT, RETURN, exec, lumania-search
bind = SUPER CTRL, SPACE, exec, lumania-wallpaper
```

*For Omarchy Lua configurations (`~/.config/hypr/hyprland.lua`):*

```lua
o.bind("SUPER + SPACE", "Lumania Search", "lumania-search")
o.bind("SUPER + SHIFT + RETURN", "Lumania Search", "lumania-search")
o.bind("SUPER + CTRL + SPACE", "Lumania Wallpaper", "lumania-wallpaper")
```

### Step 6: Restart the Shell

Restart Omarchy Shell to initialize Lumania Island:

```bash
omarchy restart shell
```

---

## ⌨️ CLI & IPC Control

You can trigger and toggle any notch programmatically using `omarchy-shell`:

```bash
# Toggle Search Notch
omarchy-shell lumania.search toggle

# Toggle Control Center
omarchy-shell lumania.control toggle

# Open Control Center to a specific tab (e.g. wifi, bluetooth, audio)
omarchy-shell lumania.control status wifi

# Toggle Wallpaper Filmstrip
omarchy-shell lumania.wallpaper toggle

# Cycle Wallpaper directly
omarchy-shell lumania.wallpaper next
omarchy-shell lumania.wallpaper prev
```

---

## 🎨 Configuration & Tuning

All motion curves, geometry dimensions, bezels, and spring physics are centralized in [`FrameConfig.qml`](FrameConfig.qml):

| Property | Default | Description |
| :--- | :--- | :--- |
| `frameThickness` | `5` | OLED screen edge bezel width in pixels |
| `islandRadius` | `24` | Corner rounding for the top dynamic notch |
| `springStiffness` | `280` | Spring force constant for notch animations |
| `springDamping` | `24` | Damping factor for overshoot and settling |
| `dynamicWallpaperColor` | `true` | Extract dominant accent palette from wallpaper |

---

## 🛠️ Troubleshooting

| Issue | Resolution |
| :--- | :--- |
| **No bar visible after restart** | Verify the plugin folder is at `~/.config/omarchy/plugins/lumania.island` and `shell.json` has `"activeBar": "lumania.island"`. Check logs with `quickshell -p /usr/share/omarchy/shell log`. |
| **Waveform visualizer is static or flat** | Ensure PipeWire is active (`systemctl --user status pipewire`) and compile the helper via `./build.sh`. |
| **Notch retracts and doesn't wake** | The notch retracts when windows occupy the active workspace to maximize screen estate. Touch the top center screen edge to wake it. |
| **Clicks pass through or get swallowed** | Wayland layer-shell masks restrict click regions to visible notch surfaces. Ensure no floating transparent windows conflict. |

---

## 📄 License

Distributed under the [MIT License](LICENSE). Built for the Omarchy Linux and Hyprland communities.
