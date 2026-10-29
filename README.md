# Lumania Dynamic Island (`lumania.island`)

An iOS-style Dynamic Island notch bar for **Omarchy Shell** (Quickshell + Hyprland).

It replaces the stock top bar with a 5px OLED bezel and a centered floating notch that reads as real hardware: it retracts flush into the frame when apps are open, springs back on hover, and morphs into a media player, notification card, or call card.

```
┌─────────────────────────────── screen ───────────────────────────────┐
│ power   workspaces        ((( ● )))  눈   tray                      │
│                        dynamic island                                │
│                                                                      │
│                     your windows (docked to the bezel)               │
│                                                                      │
│                        search notch (bottom)                         │
│                 control center (bottom right)  wallpaper (bottom)   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 1. Requirements

| Dependency | Why | Check |
| --- | --- | --- |
| **Omarchy** (Arch-based) | ships Quickshell, the `qs.Ui` / `qs.Commons` modules and `omarchy-shell` IPC | `omarchy --version` |
| **Quickshell ≥ 0.3** | the QML shell runtime | `qs --version` |
| **Hyprland** | window/workspace probing, `hyprctl` | `hyprctl version` |
| **Rust (`rustc`)** | builds the three native helper binaries | `rustc --version` |
| **`jq`** | parses `hyprctl` JSON in the workspace probe | `jq --version` |
| **PipeWire (`pw-record`)** | audio spectrum for the media waveform | `which pw-record` |
| **python3** | optional call detection helper | `python3 --version` |

Optional, not in this repo (`~/.local/bin/`): `lumania-call-status` and `lumania-call-cut` power the live call card (Discord / WhatsApp / Telegram / WebRTC). Without them the call view simply never activates.

---

## 2. Install

```bash
# 1. Link the repo into the Omarchy plugin directory
ln -s "$HOME/Projects/lumania shell" ~/.config/omarchy/plugins/lumania.island

# 2. Build the native helpers (lumania-vis, lumania-colors, lumania-status)
cd "$HOME/Projects/lumania shell" && ./build.sh

# 3. Select it as the active bar
#    ~/.config/omarchy/shell.json  ->  { "activeBar": "lumania.island" }

# 4. Restart the shell
omarchy restart shell
```

The plugin manifest (`manifest.json`) declares a single `bar` entry point, `IslandBar.qml`. Everything else is loaded from there.

---

## 3. What each part does

| Region | Component | Behaviour |
| --- | --- | --- |
| Top center | `DynamicIsland.qml` | Clock, media (cover + waveform + controls), notifications, calls |
| Top left | `TopLeftNotch.qml` | Power menu: lock, logout, restart, hibernate, suspend |
| Left of center | `WorkspaceNotch.qml` | Workspace rail (numbers, active pill) + window previews |
| Top right | `TopRightNotch.qml` | System tray + Omarchy plugin widgets (Whimsy) |
| Bottom center | `BottomSearchNotch.qml` | Spotlight-style search / command runner |
| Bottom center rail | `WallpaperNotch.qml` | Wallpaper filmstrip |
| Bottom right | `ControlCenterNotch.qml` | Wi-Fi, Bluetooth, mic, volume, brightness, power profile |
| All edges | `ScreenFrame.qml` + `FrameCorner.qml` | The 5px bezel, G1 corner fillets, dock reservation |

Every notch follows the same interaction model: **retracted at rest when apps are open → wakes on hover → blooms with an iOS spring**. Calls and active playback are the exceptions: they stay pinned out so you never lose the controls.

---

## 4. Media, artwork and the sticky player

The island talks to players over **MPRIS** (Spotify, Chromium/YouTube, Firefox, mpv, VLC, …).

- **Cover art** — the compact notch shows a 24px circular cover left of the waveform; the opened notch shows prev / play-pause / next. Artwork comes from `mpris:artUrl` (https, `file://`, or `data:` URIs all render).
- **YouTube** — browsers publish artwork as a *temporary* PNG. The island retries a failed decode for ~2.5s and falls back to a YouTube thumbnail derived from the media URL when a browser exposes no artwork at all.
- **Sticky player** — the player you last started keeps the controls even while paused. Without this, a second background player (e.g. Spotify while a YouTube tab is paused) would steal the Play button and resume the wrong app.
- **Paused is not gone** — pausing keeps the track's art and controls available; only the waveform goes flat. The notch retracts once playback stops.

---

## 5. IPC and keybindings

```bash
omarchy-shell lumania.search toggle      # search notch
omarchy-shell lumania.control toggle     # control center
omarchy-shell lumania.wallpaper toggle   # wallpaper filmstrip
omarchy-shell lumania.wallpaper next     # step wallpaper without opening
omarchy-shell lumania.wallpaper prev
```

`lumania.control status <tab>` opens the panel straight onto a tab. `open` / `close` exist on all three targets.

Suggested binds (`~/.config/hypr/`) — this repo ships the small wrappers `lumania-search` and `lumania-wallpaper` for them:

```lua
o.bind("SUPER + SPACE", "Lumania Search", "lumania-search")
o.bind("SUPER + SHIFT + RETURN", "Lumania Search", "lumania-search")
o.bind("SUPER + CTRL + SPACE", "Lumania Wallpaper", "lumania-wallpaper")
```

The control center has no keybind by design: hover the bottom-right corner.

---

## 6. File map

```
IslandBar.qml            root coordinator: builds FrameConfig + every window
FrameConfig.qml          ALL geometry, motion, colour and notch constants
DynamicIsland.qml        notch body: clock, MPRIS media, notifications, calls
DynamicWorkspaceView.qml MPRIS detection + circular cover + waveform
MediaWaveform.qml        spring-driven bar visualiser (fed by lumania-vis)
FluidSpring.qml          analytic damped-spring primitive for every motion
NotificationManager.qml  D-Bus notification daemon + history + avatars
TopBarWindow.qml         top bezel, corners, island host window
TopLeft/Right*Notch.qml  power notch, tray notch
WorkspaceNotch.qml       workspace rail
ControlCenterNotch.qml   bottom-right control panel
BottomSearchNotch.qml    search notch
WallpaperNotch.qml       wallpaper filmstrip
ScreenFrame.qml          bottom/left/right bezels + dock margins
FrameCorner.qml          G1-continuous corner fillets

visualizer.rs   -> lumania-vis      PipeWire spectrum (FFT) on stdout
wallpaper_colors.rs -> lumania-colors   palette extraction (JSON, cached)
status_backend.rs   -> lumania-status   Wi-Fi/BT/battery/power/mic state
```

Working on geometry or motion? Change constants in `FrameConfig.qml`, not in the components — every notch reads from it.

---

## 7. Development loop

```bash
# QML only: edit and save, Quickshell hot-reloads the plugin
# Structural changes / native helper rebuilds:
./build.sh && omarchy restart shell

# Static check
qmllint DynamicIsland.qml DynamicWorkspaceView.qml

# Live logs (the shell logs per instance)
tail -f /run/user/$UID/quickshell/by-id/*/log.log
```

Useful probes:

```bash
hyprctl activeworkspace -j        # what the retract logic sees
busctl --user list | grep mpris   # which players are talking to the island
busctl --user get-property org.mpris.MediaPlayer2.spotify \
  /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata
```

---

## 8. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| No bar at all | not selected in `shell.json`, or the plugin symlink is broken: `omarchy restart shell` and read the log |
| Notch is invisible while working | by design: it retracts when the active workspace has windows. Touch the top edge to wake it. Calls and playing media keep it out |
| Nothing shows in fullscreen | the island window hides in fullscreen (notch stays quiet for gaming/video) |
| No artwork for a browser tab | the browser exposes no `mpris:artUrl`; YouTube URLs are mapped to `i.ytimg.com` thumbnails, other sites fall back to a music glyph |
| Play resumes the wrong app | two players were active — the last one you started owns the controls (sticky player) |
| Waveform is flat | `lumania-vis` missing or not rebuilt: `./build.sh` |
| Colours don't match the wallpaper | `wallpaper_colors.rs` cache is stale: `rm /tmp/lumania_wallpaper_cache.json` and switch wallpaper once |
| Wi-Fi / Bluetooth list hangs | rebuild `lumania-status` — it uses `nmcli --rescan no` and cached Bluetooth sets |

---

## 9. Notes

- The shell is a **layer-shell overlay**: clicks outside a notch's mask pass through to your windows.
- Motion is spring-based by contract (`FluidSpring.qml`); avoid adding `duration + easing` to anything that tracks a finger or pointer.
- Reduced motion is honoured: Hyprland's `animations:enabled = false` shortens every transition without removing feedback.
- Theme colours come from the wallpaper engine by default; set `dynamicWallpaperColor: false` in `FrameConfig.qml` to pin the manual palette.
