import Quickshell
import QtQuick
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
  }

  // 2. Screen Frame Borders (Bottom, Left, Right bezel windows and dock margins)
  ScreenFrame {
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    islandColor: root.islandColor
    barHidden: root.barHidden
  }

  // 3. Right Control Window (Hover notch & panel for volume, brightness, power)
  RightControlWindow {
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    notchColor: root.islandColor
    barHidden: root.barHidden
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
  }
}
