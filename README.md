# Lumania Dynamic Island (`lumania.island`)

An iOS-inspired Dynamic Island notch bar plugin for **Omarchy Shell** (built on Quickshell & Hyprland).

Replaces the default desktop top bar with a centered, floating Dynamic Island notch that seamlessly integrates into the screen bezel and dynamically adapts to workspace activity and media playback.

---

## Features

- **Dynamic Island Squircle Geometry**: Authentic 7:1 pill proportions with inward 15px circular arcs and 10px concave top flares flush against the screen bezel.
- **Top Hairline Bar**: Full-width 2px top bar providing a grounded desktop bar feel without pushing content down.
- **Floating Overlay Mode**: Configured with `exclusionMode: Ignore` and native Wayland shape masking (`mask: Region { item: islandContainer }`) so clicks outside the notch pass through to windows.
- **Dynamic Theme Adaptation**: Seamlessly inherits active Omarchy themes (`Commons.Color.background`, `Commons.Color.foreground`, `Commons.Color.muted`) with animated color transitions.
- **Adaptive Workspace & Media Detection**:
  - **Idle / Media Paused**: Displays clean centered Day, Date, and Time (`Tue, Oct 27 • 14:38`).
  - **Media Playing**: When video/audio (YouTube, Spotify, etc.) is actively playing on the current workspace, the notch morphs into an audio visualizer.
  - **Auto-Hide on Pause**: Immediately transitions back to the clock view when media is paused.
- **iOS Fluid Motion**:
  - Implements Apple HIG & WWDC spring physics (`response: 0.35s`, `zeta: 0.80`, `bounce: 0.20`).
  - Single continuous driver value (`transitionProgress` 0.0 -> 1.0) governing scale, Y-translation, and opacity.
  - **Liquid Horizontal Stretch**: Island pill expands (+8px) mid-transition during state changes.
  - **Tactile Press Feedback**: Instant scale squish (0.96) on touch-down with spring pop on release.
  - Tapping toggles 12-hour and 24-hour time formatting.
- **High-Performance Native Audio Visualizer**:
  - Compiled Rust binary (`lumania-vis`) capturing the PipeWire default sink monitor stream via `pw-record` with zero socket latency.
  - Radix-2 Cooley-Tukey FFT with logarithmic frequency bands (60 Hz to 8000 Hz) and perceptual loudness expansion.
  - 22 bars rendered with an Electric Cyan (`#00f0ff`) to Neon Violet (`#b026ff`) gradient.
  - Hardware-interpolated 144 Hz rendering in Qt Quick scenegraph with ultra-low resource usage (<0.1% CPU, 3 MB RAM).

---

## Building Native Visualizer

To compile or re-build the native PipeWire visualizer:

```bash
./build.sh
```

---

## Installation & Activation

Symlinked into Omarchy plugins directory:
```bash
ln -s "/home/rover/Projects/lumania shell" ~/.config/omarchy/plugins/lumania.island
```

Activate in `~/.config/omarchy/shell.json`:
```json
{
  "activeBar": "lumania.island"
}
```

Reload shell:
```bash
omarchy restart shell
```
