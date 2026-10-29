# 🌌 Lumania Shell — Fluid Desktop Environment for Hyprland

[![Platform](https://img.shields.io/badge/platform-Wayland%20%7C%20Hyprland-blue.svg)](#)
[![Runtime](https://img.shields.io/badge/runtime-Quickshell%20%E2%89%A50.3-emerald.svg)](#)
[![Audio Engine](https://img.shields.io/badge/audio-PipeWire%20FFT%20(Rust)-orange.svg)](#)
[![OS](https://img.shields.io/badge/os-Arch%20Linux%20%7C%20Omarchy-purple.svg)](#)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**Lumania Shell** is a comprehensive, hardware-integrated desktop shell experience built for **Hyprland** and **Omarchy** using **Quickshell**.

Instead of treating desktop panels as detached rectangles or isolated status bars, Lumania treats the entire monitor as an organic, hardware-aware canvas. It wraps your screen in a continuous 5px OLED bezel with G1 curvature, housing an ecosystem of reactive notches that dynamically adapt to your workflow: retracting into the display frame when you focus on applications, emerging with damped spring physics on hover, and morphing to serve your system's real-time state.

```
┌──────────────────────────────── screen ────────────────────────────────┐
│  [Power]  [1][2][3][4]          ((( ● )))          [Tray] [Whimsy]     │
│                         adaptive central notch                         │
│                                                                        │
│                    your windows (docked to the bezel)                  │
│                                                                        │
│                           [Search Notch]                               │
│                   [Wallpaper]        [Control Center]                  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🏛️ Architecture & Core Components

Lumania is a cohesive desktop environment consisting of seven coordinated subsystem notches:

### 1. 🏝️ The Adaptive Central Notch (`DynamicIsland.qml`)
- **Real-Time Audio Spectrum**: Powered by `lumania-vis` (native Rust PipeWire FFT), driving an 18-band spring-modeled waveform visualizer.
- **Intelligent Pause Decay**: Audio pause initiates a calibrated 320ms spring settle window that fluidly collapses waveform bars down to rest and fades opacity into the clock view without static visual freezing.
- **Multi-Player MPRIS Coordination**: Sticky player persistence guarantees that background playback from Spotify, Chromium, Firefox, or YouTube never loses controls to secondary media.
- **Direct Album Art & Fallback Pipeline**: Circular cover masking with automated decode retry and fallback fetching for web media.
- **Active Call Monitoring**: Dedicated call heads and quick actions for WebRTC, Discord, WhatsApp, and Telegram.
- **Notification Daemon**: Integrated D-Bus notification receiver with avatar grouping and expandable history.

### 2. 🎛️ System Control Center (`ControlCenterNotch.qml`)
- Tucked into the bottom-right corner, blooming into a full system management hub on cursor proximity.
- **Wi-Fi & Networking**: Real-time network scanning and connection handling via `lumania-status`.
- **Bluetooth Management**: Rapid device discovery, pairing, and status indicators.
- **Audio & Media Routing**: Volume slider, sink/source switching, and mic gain controls.
- **Hardware Telemetry**: Screen brightness, battery percentage with health estimation, and system power profiles (Performance / Balanced / Power-saver).

### 3. 🔍 Spotlight Omni-Search Notch (`BottomSearchNotch.qml`)
- Centered at the bottom edge, providing instant fuzzy application launching, command running, and calculation.
- Features deep backdrop Gaussian blur and smooth expand/collapse transitions.

### 4. 🖼️ Dynamic Wallpaper Engine (`WallpaperNotch.qml`)
- Interactive bottom filmstrip providing visual preview and seamless switching between desktop wallpapers.
- **Real-Time Palette Extraction**: Backed by `lumania-colors` (Rust), which extracts dominant chromatic and tonal colors directly from wallpaper images to drive live QML accent themes across the entire shell.

### 5. 🗂️ Workspace & Window Indexer (`WorkspaceNotch.qml`)
- Spatial workspace navigator tracking Hyprland workspace state, active window titles, and workspace density pills.

### 6. ⚡ Quick Session Notch (`TopLeftNotch.qml`)
- Dedicated top-left power interface for quick lock, logout, reboot, shutdown, suspend, and hibernate routines.

### 7. 📥 System Tray & Plugin Notch (`TopRightNotch.qml`)
- High-compatibility status notifier host supporting Quickshell DBus menu delegation (`QsMenuEntry`), scratchpad window toggles, and seamless integration with desktop widget suites like Whimsy.

---

## 📋 System Requirements

| Component | Minimum Version | Function |
| :--- | :--- | :--- |
| **Omarchy** / **Arch Linux** | Latest | Base platform shipping Quickshell & `qs` core modules |
| **Quickshell** | `≥ 0.3` | Wayland QML reactive shell runtime |
| **Hyprland** | `≥ 0.40` | Wayland compositor and IPC socket dispatcher |
| **Rust (`rustc`)** | `≥ 1.70` | Compiles native visualizer and status engines |
| **PipeWire** | `latest` | High-fidelity audio backend (`pw-record`) |
| **`jq`** | `latest` | Fast JSON parsing for Hyprland workspace queries |

---

## 🚀 Installation & Setup

### 1. Clone the Repository

Clone Lumania Shell directly into your Omarchy plugins directory:

```bash
git clone https://github.com/rover-001/lumania-shell.git ~/.config/omarchy/plugins/lumania.island
```

*(Or clone to a workspace directory and symlink):*

```bash
ln -s "$HOME/Projects/lumania-shell" ~/.config/omarchy/plugins/lumania.island
```

### 2. Build the Native Rust Engines

Lumania relies on three high-performance Rust binaries for zero-latency execution:
- `lumania-vis`: Low-overhead PipeWire FFT spectrum processor.
- `lumania-colors`: Fast k-means color extraction engine for dynamic desktop theming.
- `lumania-status`: Asynchronous network, Bluetooth, and battery status telemetry.

Run the build script:

```bash
cd ~/.config/omarchy/plugins/lumania.island
chmod +x build.sh lumania-search lumania-wallpaper lumania-focus
./build.sh
```

### 3. Link CLI Wrappers

Install the command wrappers to your user path for instant keybinding integration:

```bash
mkdir -p ~/.local/bin
ln -sf ~/.config/omarchy/plugins/lumania.island/lumania-search ~/.local/bin/lumania-search
ln -sf ~/.config/omarchy/plugins/lumania.island/lumania-wallpaper ~/.local/bin/lumania-wallpaper
ln -sf ~/.config/omarchy/plugins/lumania.island/lumania-focus ~/.local/bin/lumania-focus
```

### 4. Enable Lumania in Omarchy Shell

Set `lumania.island` as your active bar in `~/.config/omarchy/shell.json`:

```json
{
  "activeBar": "lumania.island"
}
```

### 5. Bind Shortcuts in Hyprland

Add the following keybindings to your Hyprland configuration (`~/.config/hypr/hyprland.conf`):

```ini
# Lumania Shell Notches
bind = SUPER, SPACE, exec, lumania-search
bind = SUPER SHIFT, RETURN, exec, lumania-search
bind = SUPER CTRL, SPACE, exec, lumania-wallpaper
```

*Or for Omarchy Hyprland Lua setups (`~/.config/hypr/hyprland.lua`):*

```lua
o.bind("SUPER + SPACE", "Lumania Search", "lumania-search")
o.bind("SUPER + SHIFT + RETURN", "Lumania Search", "lumania-search")
o.bind("SUPER + CTRL + SPACE", "Lumania Wallpaper", "lumania-wallpaper")
```

### 6. Start / Restart Shell

Restart Omarchy Shell to initialize all notches:

```bash
omarchy restart shell
```

---

## ⌨️ Command-Line & IPC Control

Control any component directly via terminal scripts or custom binds:

```bash
# Toggle Search Notch
omarchy-shell lumania.search toggle

# Toggle System Control Center
omarchy-shell lumania.control toggle

# Open Control Center to a specific tab
omarchy-shell lumania.control status wifi
omarchy-shell lumania.control status bluetooth
omarchy-shell lumania.control status audio

# Toggle Wallpaper Filmstrip
omarchy-shell lumania.wallpaper toggle

# Step to Next/Previous Wallpaper
omarchy-shell lumania.wallpaper next
omarchy-shell lumania.wallpaper prev
```

---

## ⚙️ Customization & Geometry

All frame geometry, bezel parameters, color modes, and spring physics are configured in [`FrameConfig.qml`](FrameConfig.qml):

| Option | Default | Effect |
| :--- | :--- | :--- |
| `frameThickness` | `5` | OLED screen border bezel thickness (pixels) |
| `islandRadius` | `24` | Curvature radius for central adaptive notch |
| `springStiffness` | `280` | Spring acceleration constant across notch transitions |
| `springDamping` | `24` | Critical damping coefficient for zero-jitter settling |
| `dynamicWallpaperColor` | `true` | Real-time adaptive color palette extraction |

---

## 🛡️ Input Masking & Wayland Safety

Lumania operates strictly as a **Wayland layer-shell overlay**. Every notch exposes an exact geometric hitmask to the compositor (`mask: Region { item: ... }`). Pixels outside visible notch surfaces pass through directly to underlying application windows without click interception or mouse grab leakage.

---

## 📄 License

Released under the [MIT License](LICENSE). Designed and built with pride for the Linux desktop.
