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

  // Fast reactive Hyprland probe tracking workspace window count and fullscreen state
  property bool fullscreenActive: false
  property bool hasOpenApps: false

  Process {
    id: workspaceStateProbe
    command: ["sh", "-c", "ws=$(hyprctl activeworkspace -j 2>/dev/null); win=$(hyprctl activewindow -j 2>/dev/null); mon=$(hyprctl monitors -j 2>/dev/null); echo \"$ws $win $mon\" | jq -r -s 'def has_special: (.[2] // []) | any(.specialWorkspace.name != null and .specialWorkspace.name != \"\" and .specialWorkspace.id != 0); def ws_windows: (.[0].windows // 0); def has_pinned: (.[1].pinned == true); def is_full: (.[0].hasfullscreen == true or (.[1].fullscreen != null and .[1].fullscreen > 0) or (.[1].fullscreenClient != null and .[1].fullscreenClient > 0)); (((ws_windows > 0 or has_special or has_pinned) | if . then \"1\" else \"0\" end) + \" \" + (is_full | if . then \"1\" else \"0\" end))' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        var raw = String(text || "").trim().split(/\s+/)
        if (raw.length >= 2) {
          var hasApps = (raw[0] === "1")
          var isFull = (raw[1] === "1")
          root.hasOpenApps = hasApps
          root.fullscreenActive = isFull
        }
      }
    }
    onExited: {
      if (root.workspaceSyncPending) root.syncWorkspaceState()
    }
  }

  // A request that arrives while the probe is in flight is replayed on exit, never dropped
  property bool workspaceSyncPending: false

  function syncWorkspaceState() {
    if (workspaceStateProbe.running) {
      root.workspaceSyncPending = true
      return
    }
    root.workspaceSyncPending = false
    workspaceStateProbe.running = true
  }

  // Coalesces Hyprland event bursts (title churn while streaming) into at most one probe per window
  Timer {
    id: workspaceSyncThrottle
    interval: 200
    repeat: false
    onTriggered: root.syncWorkspaceState()
  }

  function requestWorkspaceSync() {
    if (!workspaceSyncThrottle.running) workspaceSyncThrottle.start()
  }

  Component.onCompleted: {
    root.syncWorkspaceState()
  }

  // Slow safety-net poll; Hyprland events drive the fast path
  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.syncWorkspaceState()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      root.requestWorkspaceSync()
    }
    function onFocusedWorkspaceChanged() {
      root.requestWorkspaceSync()
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
    hasOpenApps: root.hasOpenApps
    shell: root.shell
    barWidgetRegistry: root.barWidgetRegistry
    pluginRegistry: root.pluginRegistry
    barConfig: root.barConfig
  }

  // 1b. Top-Right Tray and Omarchy Plugin Notch Window (Twin Dynamic Island)
  TopRightWindow {
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    notchColor: root.islandColor
    textColor: root.islandTextColor
    mutedColor: root.islandMutedColor
    fontFamily: root.fontFamily
    barHidden: root.barHidden
    fullscreen: root.fullscreenActive
    hasOpenApps: root.hasOpenApps
    shell: root.shell
    barWidgetRegistry: root.barWidgetRegistry
    pluginRegistry: root.pluginRegistry
    barConfig: root.barConfig
  }

  // 2. Screen Frame Borders (Bottom, Left, Right bezel windows and dock margins)
  ScreenFrame {
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    islandColor: root.islandColor
    barHidden: root.barHidden
    fullscreen: root.fullscreenActive
  }

  // 3. Bottom-Right Control Center (corner gusset blooming into Wi-Fi/Bluetooth,
  //    brightness/volume and power profiles — replaces the old right notch)
  ControlCenterWindow {
    id: controlCenterWindow
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    notchColor: root.islandColor
    barHidden: root.barHidden
    fullscreen: root.fullscreenActive
    hasOpenApps: root.hasOpenApps
  }

  // Forward control menu convenience methods
  property alias controlOpen: controlCenterWindow.controlOpen
  function toggleControl() { controlCenterWindow.toggleControl() }
  function openControl() { controlCenterWindow.openControl() }
  function closeControl() { controlCenterWindow.closeControl() }

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
    hasOpenApps: root.hasOpenApps
  }

  // 5. Left Workspace Window (Top-left workspace notch showing active workspace with iOS fluid animations)
  WorkspaceWindow {
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    notchColor: root.islandColor
    textColor: root.islandTextColor
    mutedColor: root.islandMutedColor
    fontFamily: root.fontFamily
    barHidden: root.barHidden
    fullscreen: root.fullscreenActive
    hasOpenApps: root.hasOpenApps
  }

  // 6. Bottom Center Wallpaper Window (filmstrip notch for switching wallpapers)
  WallpaperWindow {
    id: wallpaperWindow
    frameConfig: frameConfig
    borderThickness: root.borderThickness
    notchColor: root.islandColor
    textColor: root.islandTextColor
    mutedColor: root.islandMutedColor
    fontFamily: root.fontFamily
    barHidden: root.barHidden
    fullscreen: root.fullscreenActive
    hasOpenApps: root.hasOpenApps
  }

  // Forward wallpaper convenience methods
  property alias wallpaperOpen: wallpaperWindow.wallpaperOpen
  function toggleWallpapers() { wallpaperWindow.toggleWallpapers() }
  function openWallpapers() { wallpaperWindow.openWallpapers() }
  function closeWallpapers() { wallpaperWindow.closeWallpapers() }
}
