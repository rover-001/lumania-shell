import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.Commons as Commons
import qs.Ui

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
            if (data.accent) frameConfig.autoAccentColor = data.accent
            if (data.complementary) frameConfig.autoComplementaryColor = data.complementary
            if (data.muted) frameConfig.autoMutedColor = data.muted
            if (data.textColor) frameConfig.autoTextColor = data.textColor
            if (data.sliderFill) frameConfig.autoSliderFill = data.sliderFill
            if (data.sliderIconFilled) frameConfig.autoSliderIconFilled = data.sliderIconFilled
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

  // Periodic watch fallback for wallpaper switches (fast 800ms heartbeat)
  Timer {
    interval: 800
    repeat: true
    running: frameConfig.dynamicWallpaperColor
    onTriggered: {
      if (!rustColorProc.running) rustColorProc.running = true
    }
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

  // Dynamic Island Geometry
  readonly property int bodyWidth: frameConfig.islandBodyWidth
  readonly property int topCurveRadius: frameConfig.islandTopCurveRadius
  readonly property int islandWidth: bodyWidth + (topCurveRadius * 2)
  readonly property int islandHeight: borderThickness + 32
  readonly property int bottomCornerRadius: frameConfig.islandBottomCornerRadius
  readonly property int topBarLineHeight: borderThickness

  // Expanded / Hover geometry deltas
  readonly property int hoverWidthDelta: 220
  readonly property int hoverHeightDelta: 14
  readonly property int islandWindowHeight: 520
  readonly property string iconFont: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"

  // Clock state
  property string currentTimeString: ""
  property string currentDateString: ""
  property bool use24Hour: true

  function updateClock() {
    var now = new Date()
    currentTimeString = Qt.formatDateTime(now, use24Hour ? "HH:mm" : "h:mm AP")
    currentDateString = Qt.formatDateTime(now, "ddd, MMM d")
  }

  Component.onCompleted: {
    updateClock()
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.updateClock()
  }

  // Shell protocol stubs
  function summonBarWidget(id) { return false }
  function hideBarWidget(id) { return false }
  function isBarWidgetOpen(id) { return false }
  function toggleTransparency() {}
  function debugBarGeometry() { return [] }
  function panelWidgetIdAt(section, index) { return null }

  // Bottom Search Notch State & IPC Controller
  property bool searchOpen: false

  function toggleSearch() {
    searchOpen = !searchOpen
  }

  function openSearch() {
    searchOpen = true
  }

  function closeSearch() {
    searchOpen = false
  }

  IpcHandler {
    target: "lumania.search"

    function toggle(): void {
      root.toggleSearch()
    }

    function open(): void {
      root.openSearch()
    }

    function close(): void {
      root.closeSearch()
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: islandWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !remapGuard.remapping

        ScreenMoveRemap {
          id: remapGuard
          window: islandWindow
        }

        // Full width anchors for the subtle top hairline bar
        anchors {
          top: true
          left: true
          right: true
        }

        implicitHeight: root.islandWindowHeight

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-island"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: root.borderThickness

        mask: Region {
          Region {
            item: topBarLine
          }
          Region {
            item: islandContainer
          }
          Region {
            item: topLeftCorner
          }
          Region {
            item: topRightCorner
          }
          Region {
            item: (statusSubpanel.isOpen || statusSubpanel.openProgress > 0.01) ? statusSubpanel.maskItem : null
          }
          Region {
            item: statusSubpanel.isPinned ? dismissArea : null
          }
        }

        // Full-width top border bar
        Rectangle {
          id: topBarLine
          visible: true
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.borderThickness
          color: root.islandColor

          // Left slot container for future widgets
          Row {
            id: topLeftSlot
            anchors.left: parent.left
            anchors.leftMargin: root.borderThickness + root.config.topLeftRadius + 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
          }

          // Right slot container for future widgets
          Row {
            id: topRightSlot
            anchors.right: parent.right
            anchors.rightMargin: root.borderThickness + root.config.topRightRadius + 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
          }
        }

        // Top-Left corner fillet merging left border into top border
        FrameCorner {
          id: topLeftCorner
          anchors.top: parent.top
          anchors.left: parent.left
          corner: "topLeft"
          thickness: root.borderThickness
          radius: root.config.topLeftRadius
          color: root.islandColor
          style: root.config.cornerStyle
          squircleFactor: root.config.squircleFactor
        }

        // Top-Right corner fillet merging right border into top border
        FrameCorner {
          id: topRightCorner
          anchors.top: parent.top
          anchors.right: parent.right
          corner: "topRight"
          thickness: root.borderThickness
          radius: root.config.topRightRadius
          color: root.islandColor
          style: root.config.cornerStyle
          squircleFactor: root.config.squircleFactor
        }

        // Centered Dynamic Island Notch with Smooth Animated Sizing
        Item {
          id: islandContainer
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter

          // Hover interaction state (stays active when subpanel is open, hovered, or pinned)
          readonly property bool isHovered: hoverHandler.hovered || (statusSubpanel && (statusSubpanel.isOpen || statusSubpanel.isHovered || statusSubpanel.isPinned))
          readonly property real targetHoverProgress: isHovered ? 1.0 : 0.0
          property real hoverProgress: targetHoverProgress

          // iOS Fluid Spring Behavior for hover
          // Expanding (hover in): snappy energetic spring (400ms, OutBack overshoot 1.08)
          // Collapsing (hover out): critically damped graceful settle (280ms, OutCubic)
          Behavior on hoverProgress {
            NumberAnimation {
              duration: islandContainer.isHovered ? 400 : 280
              easing.type: islandContainer.isHovered ? Easing.OutBack : Easing.OutCubic
              easing.overshoot: islandContainer.isHovered ? 1.08 : 1.0
            }
          }

          // iOS Fluid Motion driver value: 0.0 (Clock View) -> 1.0 (Audio Waveform)
          readonly property real targetProgress: dynamicView.showVisualizer ? 1.0 : 0.0
          property real transitionProgress: targetProgress

          Behavior on transitionProgress {
            NumberAnimation {
              duration: dynamicView.showVisualizer ? 340 : 180
              easing.type: dynamicView.showVisualizer ? Easing.OutBack : Easing.OutCubic
              easing.overshoot: dynamicView.showVisualizer ? 1.15 : 1.0
            }
          }

          // Dynamic Radii adapting with hover expansion for organic squircle continuity
          readonly property real currentTopRadius: root.topCurveRadius
            + (hoverProgress * (root.config.islandExpandedTopCurveRadius - root.topCurveRadius))
          readonly property real currentBottomRadius: root.bottomCornerRadius
            + (hoverProgress * (root.config.islandExpandedBottomCornerRadius - root.bottomCornerRadius))

          // Authentic iOS liquid stretch:
          // 1. Pill widens symmetrically (+350px) on hover (left and right)
          // 2. Liquid volume pulse during mid-transition (sin curve)
          width: root.islandWidth
            + (hoverProgress * root.hoverWidthDelta)
            + (Math.sin(Math.min(1.0, Math.max(0.0, transitionProgress)) * Math.PI) * 8.0)
            + (Math.sin(Math.min(1.0, Math.max(0.0, hoverProgress)) * Math.PI) * 6.0)

          // Height expands downwards (+54px) on hover
          height: root.islandHeight + (hoverProgress * root.hoverHeightDelta)

          // Press feedback: instant scale-down to 0.96 on press, spring pop back on release
          property bool isPressed: tapHandler.pressed
          scale: isPressed ? 0.96 : 1.0
          transformOrigin: Item.Top

          Behavior on scale {
            NumberAnimation {
              duration: islandContainer.isPressed ? 140 : 320
              easing.type: islandContainer.isPressed ? Easing.OutQuad : Easing.OutBack
              easing.overshoot: 1.2
            }
          }

          HoverHandler {
            id: hoverHandler
            cursorShape: Qt.PointingHandCursor
          }

          TapHandler {
            id: tapHandler
            onTapped: {
              root.use24Hour = !root.use24Hour
              root.updateClock()
            }
          }

          // Main OLED Island Shape (Curved top flare flush with 10px border + rounded bottom)
          Shape {
            id: islandShape
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            readonly property real w: islandContainer.width
            readonly property real h: islandContainer.height
            readonly property real rTop: islandContainer.currentTopRadius
            readonly property real rBot: islandContainer.currentBottomRadius
            readonly property real b: root.borderThickness

            ShapePath {
              strokeWidth: 0
              strokeColor: "transparent"
              fillColor: root.islandColor
              capStyle: ShapePath.RoundCap
              joinStyle: ShapePath.RoundJoin

              // Start at top-left flare edge flush against screen top edge
              startX: 0
              startY: -2.0

              // Top horizontal line
              PathLine {
                x: islandShape.w
                y: -2.0
              }

              // Down to top border bottom edge
              PathLine {
                x: islandShape.w
                y: islandShape.b
              }

              // Top-right flare curving into pill side
              PathCubic {
                x: islandShape.w - islandShape.rTop
                y: islandShape.b + islandShape.rTop
                control1X: islandShape.w - (islandShape.rTop * 0.5)
                control1Y: islandShape.b
                control2X: islandShape.w - islandShape.rTop
                control2Y: islandShape.b + (islandShape.rTop * 0.5)
              }

              // Right vertical side down to bottom arc
              PathLine {
                x: islandShape.w - islandShape.rTop
                y: islandShape.h - islandShape.rBot
              }

              // Bottom-right inward curve (full 15px pill arc)
              PathArc {
                x: islandShape.w - islandShape.rTop - islandShape.rBot
                y: islandShape.h
                radiusX: islandShape.rBot
                radiusY: islandShape.rBot
                direction: PathArc.Clockwise
              }

              // Bottom edge
              PathLine {
                x: islandShape.rTop + islandShape.rBot
                y: islandShape.h
              }

              // Bottom-left inward curve (full 15px pill arc)
              PathArc {
                x: islandShape.rTop
                y: islandShape.h - islandShape.rBot
                radiusX: islandShape.rBot
                radiusY: islandShape.rBot
                direction: PathArc.Clockwise
              }

              // Left vertical side up to left flare
              PathLine {
                x: islandShape.rTop
                y: islandShape.b + islandShape.rTop
              }

              // Top-left flare curving out to border line
              PathCubic {
                x: 0
                y: islandShape.b
                control1X: islandShape.rTop
                control1Y: islandShape.b + (islandShape.rTop * 0.5)
                control2X: islandShape.rTop * 0.5
                control2Y: islandShape.b
              }

              // Close path back up to top edge
              PathLine {
                x: 0
                y: -2.0
              }
            }
          }

          // Content Layer 1: Resting View (ONLY TIME DISPLAYED AT REST)
          Row {
            id: clockContentRow
            anchors.centerIn: parent
            anchors.verticalCenterOffset: (islandContainer.hoverProgress * 4.0) + (-5.0 * islandContainer.transitionProgress)

            // Crossfades cleanly; transitions into expanded controls as hover begins
            opacity: Math.max(0.0, (1.0 - islandContainer.transitionProgress) * (1.0 - islandContainer.hoverProgress * 3.0))
            scale: Math.max(0.80, (1.0 - islandContainer.transitionProgress * 0.16) * (1.0 - islandContainer.hoverProgress * 0.2))
            visible: opacity > 0.01
            transformOrigin: Item.Center

            Text {
              id: timeLabel
              anchors.verticalCenter: parent.verticalCenter
              text: root.currentTimeString
              color: root.islandTextColor
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              renderType: Text.NativeRendering
              verticalAlignment: Text.AlignVCenter
            }
          }

          // Content Layer 2: Adaptive Workspace View (Multi-Color Gradient Audio Waveform)
          DynamicWorkspaceView {
            id: dynamicView
            anchors.fill: parent

            opacity: islandContainer.transitionProgress * Math.max(0.0, 1.0 - islandContainer.hoverProgress * 3.0)
            scale: 0.82 + (0.18 * islandContainer.transitionProgress)
            visible: opacity > 0.01
            transformOrigin: Item.Center
          }

          // Content Layer 3: Expanded Interactive Notch Controls (Revealed on Hover)
          Item {
            id: expandedControlsRow
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            opacity: Math.min(1.0, islandContainer.hoverProgress * 2.0)
            scale: 0.90 + (0.10 * islandContainer.hoverProgress)
            visible: opacity > 0.01
            transformOrigin: Item.Center

            RowLayout {
              anchors.fill: parent
              spacing: 10

              // Left: Time & Date in Opened Notch
              Row {
                spacing: 6
                Layout.alignment: Qt.AlignVCenter

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.currentTimeString
                  color: root.islandTextColor
                  font.family: root.fontFamily
                  font.pixelSize: 13
                  font.weight: Font.DemiBold
                  renderType: Text.NativeRendering
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "• " + root.currentDateString
                  color: root.islandMutedColor
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  font.weight: Font.Medium
                  renderType: Text.NativeRendering
                  visible: islandContainer.width > 310
                }
              }

              Item {
                Layout.fillWidth: true
              }

              // Right: WiFi, Bluetooth, and DNS in Circular Buttons
              Row {
                spacing: 8
                Layout.alignment: Qt.AlignVCenter

                // 1. Wi-Fi Circular Button
                Rectangle {
                  id: wifiCircle
                  width: 30
                  height: 30
                  radius: 15
                  anchors.verticalCenter: parent.verticalCenter
                  readonly property bool isActiveTab: statusSubpanel.isOpen && statusSubpanel.activeTab === "wifi"
                  color: isActiveTab
                    ? frameConfig.activeBorderColor
                    : (wifiHover.hovered ? Qt.rgba(255, 255, 255, 0.22) : Qt.rgba(255, 255, 255, 0.10))

                  property bool isPressed: wifiTap.pressed
                  scale: isPressed ? 0.90 : (wifiHover.hovered ? 1.08 : 1.0)

                  Behavior on scale {
                    NumberAnimation {
                      duration: wifiCircle.isPressed ? 120 : 240
                      easing.type: wifiCircle.isPressed ? Easing.OutQuad : Easing.OutBack
                      easing.overshoot: 1.15
                    }
                  }

                  Behavior on color {
                    ColorAnimation { duration: 180 }
                  }

                  Text {
                    anchors.centerIn: parent
                    text: {
                      if (!statusSubpanel.wifiData.enabled) return "󰤮"
                      if (!statusSubpanel.wifiData.connected) return "󰤯"
                      var sig = statusSubpanel.wifiData.signal || 50
                      if (sig > 75) return "󰤨"
                      if (sig > 50) return "󰤥"
                      if (sig > 25) return "󰤢"
                      return "󰤟"
                    }
                    font.family: root.iconFont
                    font.pixelSize: 15
                    color: wifiCircle.isActiveTab ? root.islandColor : root.islandTextColor
                    renderType: Text.NativeRendering
                  }

                  HoverHandler {
                    id: wifiHover
                    onHoveredChanged: {
                      if (hovered) {
                        statusSubpanel.activeTab = "wifi"
                        statusSubpanel.isOpen = true
                      }
                    }
                  }

                  TapHandler {
                    id: wifiTap
                    onTapped: {
                      statusSubpanel.activeTab = "wifi"
                      statusSubpanel.isPinned = !statusSubpanel.isPinned
                      if (statusSubpanel.isPinned) statusSubpanel.isOpen = true
                    }
                  }
                }

                // 2. Bluetooth Circular Button
                Rectangle {
                  id: btCircle
                  width: 30
                  height: 30
                  radius: 15
                  anchors.verticalCenter: parent.verticalCenter
                  readonly property bool isActiveTab: statusSubpanel.isOpen && statusSubpanel.activeTab === "bluetooth"
                  color: isActiveTab
                    ? frameConfig.activeBorderColor
                    : (btHover.hovered ? Qt.rgba(255, 255, 255, 0.22) : Qt.rgba(255, 255, 255, 0.10))

                  property bool isPressed: btTap.pressed
                  scale: isPressed ? 0.90 : (btHover.hovered ? 1.08 : 1.0)

                  Behavior on scale {
                    NumberAnimation {
                      duration: btCircle.isPressed ? 120 : 240
                      easing.type: btCircle.isPressed ? Easing.OutQuad : Easing.OutBack
                      easing.overshoot: 1.15
                    }
                  }

                  Behavior on color {
                    ColorAnimation { duration: 180 }
                  }

                  Text {
                    anchors.centerIn: parent
                    text: statusSubpanel.btData.enabled ? (statusSubpanel.btData.connectedCount > 0 ? "󰂱" : "󰂯") : "󰂲"
                    font.family: root.iconFont
                    font.pixelSize: 15
                    color: btCircle.isActiveTab ? root.islandColor : root.islandTextColor
                    renderType: Text.NativeRendering
                  }

                  HoverHandler {
                    id: btHover
                    onHoveredChanged: {
                      if (hovered) {
                        statusSubpanel.activeTab = "bluetooth"
                        statusSubpanel.isOpen = true
                      }
                    }
                  }

                  TapHandler {
                    id: btTap
                    onTapped: {
                      statusSubpanel.activeTab = "bluetooth"
                      statusSubpanel.isPinned = !statusSubpanel.isPinned
                      if (statusSubpanel.isPinned) statusSubpanel.isOpen = true
                    }
                  }
                }

                // 3. DNS Circular Button
                Rectangle {
                  id: dnsCircle
                  width: 30
                  height: 30
                  radius: 15
                  anchors.verticalCenter: parent.verticalCenter
                  readonly property bool isActiveTab: statusSubpanel.isOpen && statusSubpanel.activeTab === "dns"
                  color: isActiveTab
                    ? frameConfig.activeBorderColor
                    : (dnsHover.hovered ? Qt.rgba(255, 255, 255, 0.22) : Qt.rgba(255, 255, 255, 0.10))

                  property bool isPressed: dnsTap.pressed
                  scale: isPressed ? 0.90 : (dnsHover.hovered ? 1.08 : 1.0)

                  Behavior on scale {
                    NumberAnimation {
                      duration: dnsCircle.isPressed ? 120 : 240
                      easing.type: dnsCircle.isPressed ? Easing.OutQuad : Easing.OutBack
                      easing.overshoot: 1.15
                    }
                  }

                  Behavior on color {
                    ColorAnimation { duration: 180 }
                  }

                  Text {
                    anchors.centerIn: parent
                    text: "󰒃"
                    font.family: root.iconFont
                    font.pixelSize: 15
                    color: dnsCircle.isActiveTab ? root.islandColor : root.islandTextColor
                    renderType: Text.NativeRendering
                  }

                  HoverHandler {
                    id: dnsHover
                    onHoveredChanged: {
                      if (hovered) {
                        statusSubpanel.activeTab = "dns"
                        statusSubpanel.isOpen = true
                      }
                    }
                  }

                  TapHandler {
                    id: dnsTap
                    onTapped: {
                      statusSubpanel.activeTab = "dns"
                      statusSubpanel.isPinned = !statusSubpanel.isPinned
                      if (statusSubpanel.isPinned) statusSubpanel.isOpen = true
                    }
                  }
                }
              }
            }
          }
        }

        // Invisible Hover Bridge between Top Notch and Subpanel
        Item {
          id: hoverBridge
          anchors.top: islandContainer.bottom
          anchors.bottom: statusSubpanel.top
          anchors.horizontalCenter: islandContainer.horizontalCenter
          width: statusSubpanel.width

          HoverHandler {
            id: bridgeHover
          }
        }

        // Dropdown Subpanel below Top Notch (Fluid iOS Spring Motion)
        TopNotchSubpanel {
          id: statusSubpanel
          anchors.top: islandContainer.bottom
          anchors.topMargin: 8
          anchors.horizontalCenter: islandContainer.horizontalCenter
          fontFamily: root.fontFamily
        }

        // Outside Click Dismiss Handler when Subpanel is Pinned
        MouseArea {
          id: dismissArea
          anchors.fill: parent
          enabled: statusSubpanel.isPinned
          z: -1
          onClicked: {
            statusSubpanel.isPinned = false
            statusSubpanel.isOpen = false
          }
        }

        // Graceful Hover Close Timer
        Timer {
          id: subpanelCloseTimer
          interval: 220
          repeat: false
          onTriggered: {
            if (!statusSubpanel.isPinned && !hoverHandler.hovered && !bridgeHover.hovered && !statusSubpanel.isHovered) {
              statusSubpanel.isOpen = false
            }
          }
        }

        readonly property bool isSubpanelAreaHovered: hoverHandler.hovered || bridgeHover.hovered || statusSubpanel.isHovered

        onIsSubpanelAreaHoveredChanged: {
          if (isSubpanelAreaHovered) {
            subpanelCloseTimer.stop()
          } else {
            if (!statusSubpanel.isPinned) {
              subpanelCloseTimer.restart()
            }
          }
        }
      }
    }
  }

  // Bottom Frame Window (32px solid border with dock reserved space)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: bottomWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !remapGuardBottom.remapping

        ScreenMoveRemap {
          id: remapGuardBottom
          window: bottomWindow
        }

        anchors {
          bottom: true
          left: true
          right: true
        }

        implicitHeight: root.borderThickness + root.maxBottomRadius

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-frame-bottom"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: root.borderThickness

        mask: Region {
          Region {
            item: bottomBarLine
          }
          Region {
            item: bottomLeftCorner
          }
          Region {
            item: bottomRightCorner
          }
        }

        Rectangle {
          id: bottomBarLine
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.borderThickness
          color: root.islandColor
        }

        // Bottom-Left corner fillet merging left border into bottom border
        FrameCorner {
          id: bottomLeftCorner
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          corner: "bottomLeft"
          thickness: root.borderThickness
          radius: root.config.bottomLeftRadius
          color: root.islandColor
          style: root.config.cornerStyle
          squircleFactor: root.config.squircleFactor
        }

        // Bottom-Right corner fillet merging right border into bottom border
        FrameCorner {
          id: bottomRightCorner
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          corner: "bottomRight"
          thickness: root.borderThickness
          radius: root.config.bottomRightRadius
          color: root.islandColor
          style: root.config.cornerStyle
          squircleFactor: root.config.squircleFactor
        }

        // Slot container ready for bottom widgets / dock items
        Row {
          id: bottomCenterSlot
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          height: root.borderThickness
          spacing: 8
        }
      }
    }
  }

  // Left Frame Window (10px solid border with dock reserved space)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: leftWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !remapGuardLeft.remapping

        ScreenMoveRemap {
          id: remapGuardLeft
          window: leftWindow
        }

        anchors {
          left: true
          top: true
          bottom: true
        }

        implicitWidth: root.borderThickness

        color: root.islandColor
        surfaceFormat.opaque: true
        WlrLayershell.namespace: "lumania-frame-left"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: root.borderThickness

        // Slot container ready for vertical left items
        Column {
          id: leftCenterSlot
          anchors.centerIn: parent
          spacing: 8
        }
      }
    }
  }

  // Right Frame Window (10px solid border with dock reserved space)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: rightWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !remapGuardRight.remapping

        ScreenMoveRemap {
          id: remapGuardRight
          window: rightWindow
        }

        anchors {
          right: true
          top: true
          bottom: true
        }

        implicitWidth: root.borderThickness

        color: root.islandColor
        surfaceFormat.opaque: true
        WlrLayershell.namespace: "lumania-frame-right"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: root.borderThickness

        // Slot container ready for vertical right items
        Column {
          id: rightCenterSlot
          anchors.centerIn: parent
          spacing: 8
        }
      }
    }
  }

  // Right Center Hover Control Notch (iOS-fluid notch blooming from right border)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: rightControlWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !remapGuardPanel.remapping

        ScreenMoveRemap {
          id: remapGuardPanel
          window: rightControlWindow
        }

        anchors {
          right: true
        }

        implicitWidth: Math.max(124, frameConfig.rightExpandedWidth + 30)
        implicitHeight: Math.max(680, frameConfig.rightExpandedHeight + 100)

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-right-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
          Region {
            item: controlPanel.maskItem
          }
        }

        RightControlPanel {
          id: controlPanel
          anchors.fill: parent
          borderThickness: root.borderThickness
          notchColor: root.islandColor
        }
      }
    }
  }

  // Bottom Center Search Notch Window (iOS-fluid search notch blooming upwards from bottom border)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: bottomSearchWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !remapGuardSearch.remapping

        ScreenMoveRemap {
          id: remapGuardSearch
          window: bottomSearchWindow
        }

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-search-notch"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        readonly property bool isCurrentScreen: !Hyprland.focusedMonitor || (modelData && modelData.name === Hyprland.focusedMonitor.name)
        WlrLayershell.keyboardFocus: (searchNotch.isOpenEffective && isCurrentScreen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        mask: Region {
          Region {
            item: searchNotch.maskItem
          }
          Region {
            item: searchNotch.backdropItem
          }
        }

        BottomSearchNotch {
          id: searchNotch
          anchors.fill: parent
          borderThickness: root.borderThickness
          notchColor: root.islandColor
          fontFamily: root.fontFamily
          shell: root.shell
          isOpen: root.searchOpen

          onOpenRequested: root.openSearch()
          onCloseRequested: root.closeSearch()
        }
      }
    }
  }
}
