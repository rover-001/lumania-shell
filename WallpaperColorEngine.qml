import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // Reference to central FrameConfig instance
  required property var frameConfig

  // Native Rust Wallpaper Color Engine (sub-millisecond color extraction)
  Process {
    id: rustColorProc
    command: ["/home/rover/Projects/lumania shell/lumania-colors"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        var str = String(text || "").trim()
        if (str && str.startsWith("{")) {
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
    }
  }

  // Instant reactive inotify file watch on active wallpaper symlink
  FileView {
    id: wallpaperWatch
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
    watchChanges: true
    printErrors: false
    onLoaded: {
      if (!rustColorProc.running) rustColorProc.running = true
    }
    onFileChanged: {
      if (!rustColorProc.running) rustColorProc.running = true
    }
  }

  // Wallpaper switches replace the symlink (new inode), which the FileView inotify
  // watch does not see; this fast poll is the real trigger (cached run is ~2ms)
  Timer {
    interval: 250
    repeat: true
    running: root.frameConfig ? root.frameConfig.dynamicWallpaperColor : false
    onTriggered: {
      if (!rustColorProc.running) rustColorProc.running = true
    }
  }
}
