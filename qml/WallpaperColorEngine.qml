import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // Reference to central FrameConfig instance
  required property var frameConfig

  // Keep one lightweight watcher alive instead of launching a short-lived
  // helper several times a second. The helper emits only when the wallpaper
  // changes, so idle wallpaper tracking no longer creates repeated processes.
  Process {
    id: rustColorProc
    command: [decodeURIComponent(Qt.resolvedUrl("../bin/lumania-colors").toString().replace(/^file:\/\//, "")), "--daemon"]
    running: root.frameConfig ? root.frameConfig.dynamicWallpaperColor : false
    // Daemon output is line based; parse each changed palette as it arrives.
    stdout: SplitParser {
      onRead: function(line) { root.applyColors(String(line || "").trim()) }
    }
  }

  function applyColors(str) {
    if (!str || !str.startsWith("{")) return
    try {
      var data = JSON.parse(str)
      if (data.accent) root.frameConfig.autoAccentColor = data.accent
      if (data.complementary) root.frameConfig.autoComplementaryColor = data.complementary
      if (data.muted) root.frameConfig.autoMutedColor = data.muted
      if (data.textColor) root.frameConfig.autoTextColor = data.textColor
      if (data.sliderFill) root.frameConfig.autoSliderFill = data.sliderFill
      if (data.sliderIconFilled) root.frameConfig.autoSliderIconFilled = data.sliderIconFilled
    } catch (e) {
      console.warn("Lumania rust color parse error:", e)
    }
  }
}
