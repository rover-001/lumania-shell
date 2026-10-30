import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // Reference to central FrameConfig instance
  required property var frameConfig

  readonly property string settingsPath: Quickshell.env("HOME") + "/.config/omarchy/lumania.json"

  FileView {
    id: settingsWatch
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applySettings()
    onFileChanged: settingsWatch.reload()
  }

  // Backup active poll timer so settings update immediately with zero latency (<300ms)
  Timer {
    interval: 300
    repeat: true
    running: true
    onTriggered: settingsWatch.reload()
  }

  property string lastRawSettings: ""

  function applySettings() {
    var raw = String(settingsWatch.text() || "").trim()
    if (!raw || !raw.startsWith("{") || raw === root.lastRawSettings) return
    root.lastRawSettings = raw

    try {
      var d = JSON.parse(raw)
      console.log("[Lumania SettingsBridge] Applying:", JSON.stringify(d))
      if (d.borderThickness !== undefined && d.borderThickness >= 0) {
        root.frameConfig.borderThickness = d.borderThickness
      }
      if (d.borderColor && typeof d.borderColor === "string") {
        root.frameConfig.borderColor = d.borderColor
      }
      if (d.dynamicWallpaperColor !== undefined) {
        root.frameConfig.dynamicWallpaperColor = Boolean(d.dynamicWallpaperColor)
      }
      if (d.wallpaperColorMode && (d.wallpaperColorMode === "accent" || d.wallpaperColorMode === "complementary")) {
        root.frameConfig.wallpaperColorMode = d.wallpaperColorMode
      }
      if (d.cornerStyle && (d.cornerStyle === "squircle" || d.cornerStyle === "arc")) {
        root.frameConfig.cornerStyle = d.cornerStyle
      }
      if (d.cornerRadius !== undefined && d.cornerRadius > 0) {
        root.frameConfig.topLeftRadius = d.cornerRadius
        root.frameConfig.topRightRadius = d.cornerRadius
        root.frameConfig.bottomLeftRadius = d.cornerRadius
        root.frameConfig.bottomRightRadius = d.cornerRadius
      }
      if (d.islandBodyWidth !== undefined && d.islandBodyWidth >= 160) {
        root.frameConfig.islandBodyWidth = d.islandBodyWidth
      }
      if (d.wallpaperInstantSwitch !== undefined) {
        root.frameConfig.wallpaperInstantSwitch = Boolean(d.wallpaperInstantSwitch)
      }
      if (d.wallpaperMaxVisibleThumbs !== undefined && d.wallpaperMaxVisibleThumbs > 0) {
        root.frameConfig.wallpaperMaxVisibleThumbs = d.wallpaperMaxVisibleThumbs
      }
    } catch (e) {
      console.warn("Lumania settings parse error:", e)
    }
  }

  Component.onCompleted: applySettings()
}
