import Quickshell
import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons as Commons

Item {
  id: root

  // Properties injected by Omarchy Shell host
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var barConfig: ({})

  // Central frame, border curvature, and geometry configuration
  FrameConfig {
    id: frameConfig
  }
  readonly property var config: frameConfig
  readonly property real maxBottomRadius: Math.max(frameConfig.bottomLeftRadius, frameConfig.bottomRightRadius)

  // Sub-millisecond Native Rust Wallpaper Color Engine
  WallpaperColorEngine {
    frameConfig: frameConfig
  }

  // State consumed by host shell and overlays
  property bool barHidden: false

  // True while the focused window is fullscreen: every lumania surface steps aside
  property bool fullscreenActive: false

  // HyprlandToplevel exposes no fullscreen flag in this Quickshell build, so ask
  // Hyprland directly and refresh on every event that can change the answer.
  Process {
    id: fullscreenProbe
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        var fullscreen = 0
        var fullscreenClient = 0
        var raw = String(text || "").trim()
        if (raw.charAt(0) === "{") {
          try {
            var win = JSON.parse(raw)
            fullscreen = Number(win.fullscreen || 0)
            fullscreenClient = Number(win.fullscreenClient || 0)
          } catch (err) {
            console.warn("Lumania fullscreen probe failed:", err)
          }
        }
        root.fullscreenActive = (fullscreen >= 2 || fullscreenClient >= 2)
      }
    }
  }

  function refreshFullscreen() {
    if (!fullscreenProbe.running) fullscreenProbe.running = true
  }

  // Safety net: also catches state changes no Hyprland event announces
  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.refreshFullscreen()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name || "") : ""
      if (name === "activewindow" || name === "activewindowv2" || name === "fullscreen"
          || name === "workspace" || name === "focusedmon"
          || name === "openwindow" || name === "closewindow" || name === "movewindow") {
        root.refreshFullscreen()
      }
    }
  }
  property int borderThickness: frameConfig.borderThickness
  property int barSize: borderThickness
  property int islandTopMargin: 8
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  property string position: "top"

  // Unified theme tone driven by FrameConfig (dynamic wallpaper or manual)
  property color islandColor: frameConfig.activeBorderColor
  property color islandTextColor: frameConfig.activeTextColor
  property color islandMutedColor: frameConfig.mutedColor

  Behavior on islandColor { ColorAnimation { duration: 500 } }
  Behavior on islandTextColor { ColorAnimation { duration: 500 } }
  Behavior on islandMutedColor { ColorAnimation { duration: 500 } }

  // Standard bar theme colors
  property color themeForeground: islandTextColor
  property color foreground: islandTextColor
  property color barForeground: islandTextColor
  property color background: islandColor
  property color urgent: Commons.Color ? Commons.Color.urgent : "#ff5555"

  // Shell protocol stubs
  function summonBarWidget(id) { return false }
  function hideBarWidget(id) { return false }
  function isBarWidgetOpen(id) { return false }
  function toggleTransparency() {}
  function debugBarGeometry() { return [] }
  function panelWidgetIdAt(section, index) { return null }

  // Forward search convenience methods
  property alias searchOpen: searchWindow.searchOpen
  function toggleSearch() { searchWindow.toggleSearch() }
  function openSearch() { searchWindow.openSearch() }
  function closeSearch() { searchWindow.closeSearch() }

  // 1. Top Bar Window (Top border line, corners, Dynamic Island notch & subpanel)
  TopBarWindow {
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    islandColor: root.islandColor
    islandTextColor: root.islandTextColor
    islandMutedColor: root.islandMutedColor
    fontFamily: root.fontFamily
    barHidden: root.barHidden
    fullscreen: root.fullscreenActive
  }

  // 2. Screen Frame Borders (Bottom, Left, Right bezel windows and dock margins)
  ScreenFrame {
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    islandColor: root.islandColor
    barHidden: root.barHidden
    fullscreen: root.fullscreenActive
  }

  // 3. Right Control Window (Hover notch & panel for volume, brightness, power)
  RightControlWindow {
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    notchColor: root.islandColor
    barHidden: root.barHidden
    fullscreen: root.fullscreenActive
  }

  // 4. Bottom Search Window (Search notch, command runner, and IPC handler)
  BottomSearchWindow {
    id: searchWindow
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    notchColor: root.islandColor
    fontFamily: root.fontFamily
    shell: root.shell
    barHidden: root.barHidden
    fullscreen: root.fullscreenActive
  }
}
