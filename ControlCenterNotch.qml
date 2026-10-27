import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

// ===========================================================================
// Bottom-Right Control Center Notch
// ---------------------------------------------------------------------------
// Native bottom-right gusset & start-menu bloom with horizontal bars layout.
//  • Resting: a "C" gusset melted into the RIGHT + BOTTOM borders.
//  • When apps are open (hasOpenApps): auto-retracts flush into the frame.
//    Moving cursor to bottom-right corner wakes it with iOS fluid spring.
//  • Clicking or hovering blooms the control menu upwards with iOS spring physics.
//  • Open layout (Left to Right):
//    - Row 1: Wi-Fi + Bluetooth circular buttons side by side
//    - Row 2: Horizontal Brightness slider capsule (left to right fill)
//    - Row 3: Horizontal Volume slider capsule (left to right fill)
//    - Row 4: Power profile circular buttons (Low power, Balanced, Performance)
// ===========================================================================
Item {
  id: root

  FrameConfig {
    id: frameConfig
  }

  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  property bool isOpen: false
  property bool hasOpenApps: false

  // Interaction state: hover blooms the menu, click pins it open
  property bool isHoverOpen: false
  property bool isPinned: false

  signal openRequested()
  signal closeRequested()

  readonly property bool isOpenEffective: root.isOpen || root.isHoverOpen || root.isPinned

  function open() {
    root.isPinned = true
    root.openRequested()
    root.refreshAll()
    root.refreshStatus()
  }

  function close() {
    root.isPinned = false
    root.isHoverOpen = false
    root.closeRequested()
  }

  function toggle() {
    if (root.isOpenEffective) root.close()
    else root.open()
  }

  // Grace period so the menu doesn't snap shut while the cursor crosses a gap
  Timer {
    id: hoverCloseTimer
    interval: 180
    repeat: false
    onTriggered: {
      if (!root.isPinned && !root.isOpen) root.isHoverOpen = false
    }
  }

  // Sizing bounds driven by FrameConfig
  readonly property real collapsedWidth: frameConfig.controlCollapsedWidth
  readonly property real expandedWidth: frameConfig.controlExpandedWidth
  readonly property real collapsedHeight: root.borderThickness
    + Math.max(frameConfig.controlCollapsedHeight, frameConfig.controlRightTabHeight)
  readonly property real expandedHeight: root.borderThickness + frameConfig.controlExpandedHeight

  // Flare & corner radii adapting dynamically with openProgress
  readonly property real currentFlareRadius: frameConfig.controlFlareRadius
    + (openProgress * (frameConfig.controlExpandedFlareRadius - frameConfig.controlFlareRadius))
  readonly property real currentCornerRadius: frameConfig.controlCornerRadius
    + (openProgress * (frameConfig.controlExpandedCornerRadius - frameConfig.controlCornerRadius))

  // Driver value: 0.0 (resting gusset) -> 1.0 (full control menu)
  readonly property real targetProgress: root.isOpenEffective ? 1.0 : 0.0
  property real openProgress: targetProgress

  Behavior on openProgress {
    NumberAnimation {
      duration: root.isOpenEffective ? frameConfig.controlOpenDuration
                                     : frameConfig.controlCloseDuration
      easing.type: root.isOpenEffective ? Easing.OutBack : Easing.OutCubic
      easing.overshoot: root.isOpenEffective ? frameConfig.controlOpenOvershoot : 1.0
    }
  }

  // iOS liquid stretch: sinusoidal volume pulse mid-transition
  readonly property real currentWidth: collapsedWidth
    + (openProgress * (expandedWidth - collapsedWidth))
    + (Math.sin(Math.min(1.0, Math.max(0.0, openProgress)) * Math.PI) * 10.0)

  readonly property real currentHeight: collapsedHeight
    + (openProgress * (expandedHeight - collapsedHeight))
    + (Math.sin(Math.min(1.0, Math.max(0.0, openProgress)) * Math.PI) * 6.0)

  // Exposed items for PanelWindow masking
  property alias maskItem: notchContainer
  property alias backdropItem: backdropOverlay

  readonly property string iconFont: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"

  // -------------------------------------------------------------------------
  // System State: Wi-Fi / Bluetooth (native Rust backend)
  // -------------------------------------------------------------------------
  readonly property string backendScript: "/home/rover/Projects/lumania shell/lumania-status"

  property var wifiData: ({
    enabled: true,
    connected: false,
    signal: 0
  })

  property var btData: ({
    enabled: false,
    connectedCount: 0
  })

  Process {
    id: statusProc
    command: [root.backendScript]
    stdout: StdioCollector {
      onStreamFinished: {
        var str = String(text || "").trim()
        if (str && str.startsWith("{")) {
          try {
            var data = JSON.parse(str)
            if (data.wifi) root.wifiData = data.wifi
            if (data.bluetooth) root.btData = data.bluetooth
          } catch (e) {}
        }
      }
    }
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  Process {
    id: statusActionProc
    onExited: root.refreshStatus()
  }

  function runStatusAction(args) {
    statusActionProc.command = [root.backendScript].concat(args)
    statusActionProc.running = true
  }

  function toggleWifi() {
    root.wifiData.enabled = !root.wifiData.enabled
    runStatusAction(["--toggle-wifi", root.wifiData.enabled ? "on" : "off"])
  }

  function toggleBluetooth() {
    root.btData.enabled = !root.btData.enabled
    runStatusAction(["--toggle-bt", root.btData.enabled ? "on" : "off"])
  }

  // -------------------------------------------------------------------------
  // System State: Volume / Brightness / Power Profiles
  // -------------------------------------------------------------------------
  property real volumeFraction: 0.5
  property real brightnessFraction: 0.5
  property string activePowerProfile: "balanced"
  property bool isDraggingSlider: false

  function refreshAll() {
    volProc.running = true
    brightProc.running = true
    powerProc.running = true
  }

  Component.onCompleted: root.refreshAll()

  Timer {
    interval: 3000
    running: root.isOpenEffective
    repeat: true
    onTriggered: {
      if (!root.isDraggingSlider) {
        root.refreshAll()
        root.refreshStatus()
      }
    }
  }

  onIsOpenChanged: {
    if (root.isOpenEffective) {
      root.refreshAll()
      root.refreshStatus()
    }
  }

  Process {
    id: volProc
    command: ["pamixer", "--get-volume"]
    stdout: SplitParser {
      onRead: function(line) {
        var val = parseInt(String(line || "").trim())
        if (!isNaN(val) && !root.isDraggingSlider) {
          root.volumeFraction = Math.max(0, Math.min(1.0, val / 100.0))
        }
      }
    }
  }

  Process {
    id: brightProc
    command: ["sh", "-c", "cat /sys/class/backlight/intel_backlight/brightness 2>/dev/null; cat /sys/class/backlight/intel_backlight/max_brightness 2>/dev/null"]
    property var lines: []
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line || "").trim()
        if (str) brightProc.lines.push(str)
      }
    }
    onExited: function(code) {
      if (brightProc.lines.length >= 2 && !root.isDraggingSlider) {
        var cur = parseInt(brightProc.lines[0])
        var max = parseInt(brightProc.lines[1])
        if (!isNaN(cur) && !isNaN(max) && max > 0) {
          root.brightnessFraction = Math.max(0.02, Math.min(1.0, cur / max))
        }
      }
      brightProc.lines = []
    }
  }

  Process {
    id: powerProc
    command: ["powerprofilesctl", "get"]
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line || "").trim()
        if (str === "power-saver" || str === "balanced" || str === "performance") {
          root.activePowerProfile = str
        }
      }
    }
  }

  Process { id: volSetter }

  function setVolume(pct) {
    root.volumeFraction = pct
    volSetter.command = ["pamixer", "--set-volume", String(Math.round(pct * 100))]
    volSetter.running = true
  }

  Process { id: brightSetter }

  function setBrightness(pct) {
    root.brightnessFraction = pct
    brightSetter.command = ["brightnessctl", "set", Math.max(5, Math.round(pct * 100)) + "%"]
    brightSetter.running = true
  }

  Process {
    id: powerSetter
    onExited: powerProc.running = true
  }

  function setPowerProfile(profile) {
    root.activePowerProfile = profile
    powerSetter.command = ["powerprofilesctl", "set", profile]
    powerSetter.running = true
  }

  function getVolumeIcon(fraction) {
    if (fraction <= 0.01) return ""
    if (fraction < 0.35) return ""
    if (fraction < 0.70) return ""
    return ""
  }

  function getWifiIcon() {
    if (!root.wifiData || !root.wifiData.enabled) return "󰤮"
    if (!root.wifiData.connected) return "󰤯"
    var sig = root.wifiData.signal || 50
    if (sig > 75) return "󰤨"
    if (sig > 50) return "󰤥"
    if (sig > 25) return "󰤢"
    return "󰤟"
  }

  function getBluetoothIcon() {
    if (!root.btData || !root.btData.enabled) return "󰂲"
    if (root.btData.connectedCount > 0) return "󰂱"
    return "󰂯"
  }

  // =========================================================================
  // Fixed Bottom-Right Corner Edge Trigger: stays pinned at corner to wake notch
  // =========================================================================
  Item {
    id: cornerTriggerItem
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    width: Math.max(64, root.collapsedWidth)
    height: Math.max(48, root.collapsedHeight)

    HoverHandler {
      id: cornerTriggerHover
    }
  }

  readonly property bool isCornerActive: cornerTriggerHover.hovered || (notchHover && notchHover.hovered) || root.isOpenEffective

  // Auto-retract inward into screen border when apps are opened;
  // Springs out immediately when cursor touches bottom-right corner or menu opens
  readonly property bool shouldRetract: root.hasOpenApps && !root.isCornerActive && root.openProgress < 0.05

  // =========================================================================
  // Full-Screen Click-Away Catcher (no backdrop dimming)
  // =========================================================================
  Item {
    id: backdropOverlay
    anchors.fill: root.isOpenEffective ? parent : undefined
    width: root.isOpenEffective ? parent.width : 0
    height: root.isOpenEffective ? parent.height : 0
    visible: root.isOpenEffective && root.openProgress > 0.01

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  // =========================================================================
  // Bottom-Right Anchored Notch Container
  // =========================================================================
  Item {
    id: notchContainer
    anchors.bottom: parent.bottom
    anchors.right: parent.right

    // iOS Fluid Retract Offsets:
    // Retracts down and right flush with the 12px screen frame
    readonly property real targetRetractY: root.shouldRetract ? -(root.collapsedHeight - root.borderThickness) : 0.0
    readonly property real targetRetractX: root.shouldRetract ? -(root.collapsedWidth - root.borderThickness) : 0.0
    property real currentRetractY: targetRetractY
    property real currentRetractX: targetRetractX

    Behavior on currentRetractY {
      NumberAnimation {
        duration: root.shouldRetract ? 280 : 380
        easing.type: root.shouldRetract ? Easing.OutCubic : Easing.OutBack
        easing.overshoot: 1.08
      }
    }

    Behavior on currentRetractX {
      NumberAnimation {
        duration: root.shouldRetract ? 280 : 380
        easing.type: root.shouldRetract ? Easing.OutCubic : Easing.OutBack
        easing.overshoot: 1.08
      }
    }

    anchors.bottomMargin: currentRetractY
    anchors.rightMargin: currentRetractX

    width: root.currentWidth
    height: root.currentHeight

    property color activeColor: root.notchColor

    HoverHandler {
      id: notchHover
      cursorShape: root.isOpenEffective ? Qt.ArrowCursor : Qt.PointingHandCursor
      onHoveredChanged: {
        if (hovered) {
          root.isHoverOpen = true
          root.refreshAll()
          root.refreshStatus()
        } else {
          if (!root.isPinned && !root.isOpen) {
            root.isHoverOpen = false
          }
        }
      }
    }

    // Tactile press feedback
    property bool isGussetPressed: restingTapHandler.pressed
    scale: (!root.isOpenEffective && isGussetPressed) ? 0.96 : 1.0
    transformOrigin: Item.BottomRight

    Behavior on scale {
      NumberAnimation {
        duration: notchContainer.isGussetPressed ? 120 : 280
        easing.type: notchContainer.isGussetPressed ? Easing.OutQuad : Easing.OutBack
        easing.overshoot: 1.15
      }
    }

    // -----------------------------------------------------------------------
    // Native Bottom-Right Geometry (Resting "C" Gusset)
    // -----------------------------------------------------------------------
    Shape {
      id: gussetShape
      anchors.fill: parent
      visible: root.openProgress < 0.05
      preferredRendererType: Shape.CurveRenderer

      readonly property real w: gussetShape.width
      readonly property real h: gussetShape.height
      readonly property real b: root.borderThickness
      readonly property real stripTop: h - b - frameConfig.controlCollapsedHeight
      readonly property real tabW: Math.max(2, Math.min(frameConfig.controlRightTabWidth, w * 0.25))
      readonly property real tabTop: Math.max(0, h - b - frameConfig.controlRightTabHeight)
      readonly property real rTab: Math.max(0, Math.min(frameConfig.controlTabCapRadius,
                                                        tabW * 0.5,
                                                        (stripTop - tabTop) * 0.45))
      readonly property real fillet: Math.max(0, Math.min(frameConfig.controlInnerRadius,
                                                          stripTop - tabTop))
      readonly property real rCorner: Math.max(0, Math.min(frameConfig.controlCornerRadius,
                                                           (h - stripTop) * 0.55))
      readonly property real stripEnd: Math.max(rCorner, w - tabW - fillet)

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: notchContainer.activeColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        startX: gussetShape.w + 2.0
        startY: gussetShape.h + 2.0

        PathLine {
          x: gussetShape.w - gussetShape.stripEnd
          y: gussetShape.h + 2.0
        }

        PathLine {
          x: gussetShape.w - gussetShape.stripEnd
          y: gussetShape.stripTop + gussetShape.rCorner
        }

        PathArc {
          x: gussetShape.w - gussetShape.stripEnd + gussetShape.rCorner
          y: gussetShape.stripTop
          radiusX: gussetShape.rCorner
          radiusY: gussetShape.rCorner
          direction: PathArc.Clockwise
        }

        PathLine {
          x: gussetShape.w - gussetShape.tabW - gussetShape.fillet
          y: gussetShape.stripTop
        }

        PathCubic {
          x: gussetShape.w - gussetShape.tabW
          y: gussetShape.stripTop - gussetShape.fillet
          control1X: gussetShape.w - gussetShape.tabW - (gussetShape.fillet * 0.5)
          control1Y: gussetShape.stripTop
          control2X: gussetShape.w - gussetShape.tabW
          control2Y: gussetShape.stripTop - (gussetShape.fillet * 0.5)
        }

        PathLine {
          x: gussetShape.w - gussetShape.tabW
          y: gussetShape.tabTop + gussetShape.rTab
        }

        PathCubic {
          x: gussetShape.w
          y: gussetShape.tabTop + gussetShape.rTab
          control1X: gussetShape.w - gussetShape.tabW
          control1Y: gussetShape.tabTop
          control2X: gussetShape.w
          control2Y: gussetShape.tabTop
        }

        PathLine {
          x: gussetShape.w + 2.0
          y: gussetShape.tabTop + gussetShape.rTab
        }

        PathLine {
          x: gussetShape.w + 2.0
          y: gussetShape.h + 2.0
        }
      }
    }

    // -----------------------------------------------------------------------
    // Native Bottom-Right Geometry (Expanded Start-Menu Card)
    // -----------------------------------------------------------------------
    Shape {
      id: notchShape
      anchors.fill: parent
      visible: root.openProgress >= 0.05
      preferredRendererType: Shape.CurveRenderer

      readonly property real w: notchShape.width
      readonly property real h: notchShape.height
      readonly property real rf: root.currentFlareRadius
      readonly property real rc: root.currentCornerRadius
      readonly property real b: root.borderThickness

      readonly property real effRfTop: Math.min(rf, Math.max(2, (w - b) * 0.15))
      readonly property real effRfBot: Math.min(rf, Math.max(2, (w - b) * 0.15))
      readonly property real effRc: Math.min(rc, Math.max(4, Math.min(w * 0.15, h * 0.15)))

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: notchContainer.activeColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        startX: notchShape.w + 2.0
        startY: notchShape.h + 2.0

        PathLine {
          x: notchShape.w + 2.0
          y: -notchShape.effRfTop
        }

        PathLine {
          x: notchShape.w
          y: -notchShape.effRfTop
        }

        PathCubic {
          x: notchShape.w - notchShape.effRfTop
          y: 0
          control1X: notchShape.w
          control1Y: -notchShape.effRfTop * 0.5
          control2X: notchShape.w - (notchShape.effRfTop * 0.5)
          control2Y: 0
        }

        PathLine {
          x: notchShape.effRfBot + notchShape.effRc
          y: 0
        }

        PathArc {
          x: notchShape.effRfBot
          y: notchShape.effRc
          radiusX: notchShape.effRc
          radiusY: notchShape.effRc
          direction: PathArc.Counterclockwise
        }

        PathLine {
          x: notchShape.effRfBot
          y: Math.max(notchShape.effRc, notchShape.h - notchShape.b - notchShape.effRfBot)
        }

        PathCubic {
          x: 0
          y: notchShape.h - notchShape.b
          control1X: notchShape.effRfBot
          control1Y: notchShape.h - notchShape.b - (notchShape.effRfBot * 0.5)
          control2X: notchShape.effRfBot * 0.5
          control2Y: notchShape.h - notchShape.b
        }

        PathLine {
          x: -2.0
          y: notchShape.h - notchShape.b
        }

        PathLine {
          x: -2.0
          y: notchShape.h + 2.0
        }

        PathLine {
          x: notchShape.w + 2.0
          y: notchShape.h + 2.0
        }
      }
    }

    // -----------------------------------------------------------------------
    // Resting state: whole gusset area is the tap target (start-menu trigger)
    // -----------------------------------------------------------------------
    Item {
      id: restingArea
      anchors.fill: parent
      visible: root.openProgress < 0.9
      opacity: Math.max(0.0, 1.0 - root.openProgress * 3.0)

      HoverHandler {
        cursorShape: Qt.PointingHandCursor
      }

      TapHandler {
        id: restingTapHandler
        onTapped: {
          if (root.isPinned) root.close()
          else root.open()
        }
      }
    }

    // -----------------------------------------------------------------------
    // Expanded control menu: horizontal bars layout with Apple HIG insets
    // -----------------------------------------------------------------------
    Item {
      id: expandedView
      anchors.fill: parent

      visible: opacity > 0.01 && root.openProgress > 0.20
      opacity: Math.max(0.0, Math.min(1.0, (root.openProgress - 0.20) * 1.25))
      scale: 0.92 + (0.08 * root.openProgress)
      transformOrigin: Item.BottomRight

      Column {
        id: controlsColumn
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.borderThickness + 14
        anchors.right: parent.right
        anchors.rightMargin: root.borderThickness + 14
        spacing: 12

        // Top section: Wi-Fi/BT on LEFT + Horizontal Sliders on RIGHT
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 14

          // LEFT: Wi-Fi (top) + Bluetooth (bottom) column
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            // Wi-Fi toggle
            Rectangle {
              id: btnWifi
              width: frameConfig.controlButtonSize
              height: frameConfig.controlButtonSize
              radius: width / 2

              readonly property bool isActive: Boolean(root.wifiData && root.wifiData.enabled)
              readonly property bool isPressed: wifiArea.pressed

              color: isActive
                ? frameConfig.powerButtonActiveBg
                : (wifiArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
              scale: isPressed ? 0.90 : (wifiArea.containsMouse ? 1.08 : 1.0)

              Behavior on color { ColorAnimation { duration: 180 } }
              Behavior on scale {
                NumberAnimation {
                  duration: btnWifi.isPressed ? 110 : 260
                  easing.type: btnWifi.isPressed ? Easing.OutQuad : Easing.OutBack
                  easing.overshoot: 1.15
                }
              }

              Text {
                anchors.centerIn: parent
                text: root.getWifiIcon()
                font.family: root.iconFont
                font.pixelSize: 22
                color: btnWifi.isActive
                  ? frameConfig.powerButtonActiveIcon
                  : frameConfig.powerButtonInactiveIcon
                renderType: Text.NativeRendering
              }

              MouseArea {
                id: wifiArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleWifi()
              }
            }

            // Bluetooth toggle
            Rectangle {
              id: btnBluetooth
              width: frameConfig.controlButtonSize
              height: frameConfig.controlButtonSize
              radius: width / 2

              readonly property bool isActive: Boolean(root.btData && root.btData.enabled)
              readonly property bool isPressed: btArea.pressed

              color: isActive
                ? frameConfig.powerButtonActiveBg
                : (btArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
              scale: isPressed ? 0.90 : (btArea.containsMouse ? 1.08 : 1.0)

              Behavior on color { ColorAnimation { duration: 180 } }
              Behavior on scale {
                NumberAnimation {
                  duration: btnBluetooth.isPressed ? 110 : 260
                  easing.type: btnBluetooth.isPressed ? Easing.OutQuad : Easing.OutBack
                  easing.overshoot: 1.15
                }
              }

              Text {
                anchors.centerIn: parent
                text: root.getBluetoothIcon()
                font.family: root.iconFont
                font.pixelSize: 22
                color: btnBluetooth.isActive
                  ? frameConfig.powerButtonActiveIcon
                  : frameConfig.powerButtonInactiveIcon
                renderType: Text.NativeRendering
              }

              MouseArea {
                id: btArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleBluetooth()
              }
            }
          }

          // RIGHT: Horizontal Brightness (top) + Volume (bottom) column
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            // Horizontal Brightness Slider (fills from LEFT to RIGHT)
            Item {
              id: brightItem
              width: frameConfig.controlSliderWidth
              height: frameConfig.controlSliderHeight
              scale: brightArea.pressed ? 0.98 : 1.0

              Behavior on scale {
                NumberAnimation {
                  duration: brightArea.pressed ? 100 : 220
                  easing.type: brightArea.pressed ? Easing.OutQuad : Easing.OutBack
                }
              }

              Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: frameConfig.sliderTrackColor
              }

              Item {
                id: brightFillContainer
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, parent.width * root.brightnessFraction)
                clip: true
                visible: (root.brightnessFraction > 0.005) && (width > 1)

                Behavior on width {
                  enabled: !brightArea.pressed
                  NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: brightItem.width
                  radius: height / 2
                  color: frameConfig.activeSliderFillColor
                }
              }

              Text {
                z: 5
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "󰃠"
                font.family: root.iconFont
                font.pixelSize: 20
                color: (brightFillContainer.visible && brightFillContainer.width >= 36)
                  ? frameConfig.activeSliderIconColorFilled
                  : frameConfig.sliderIconColorUnfilled
                renderType: Text.NativeRendering
              }

              MouseArea {
                id: brightArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function applyPosition(mouse) {
                  var rawFrac = mouse.x / width
                  var frac = (rawFrac <= 0.02) ? 0.0 : Math.max(0.0, Math.min(1.0, rawFrac))
                  root.setBrightness(frac)
                }

                onPressed: function(mouse) {
                  root.isDraggingSlider = true
                  applyPosition(mouse)
                }
                onPositionChanged: function(mouse) {
                  if (pressed) applyPosition(mouse)
                }
                onReleased: root.isDraggingSlider = false
              }
            }

            // Horizontal Volume Slider (fills from LEFT to RIGHT)
            Item {
              id: volItem
              width: frameConfig.controlSliderWidth
              height: frameConfig.controlSliderHeight
              scale: volArea.pressed ? 0.98 : 1.0

              Behavior on scale {
                NumberAnimation {
                  duration: volArea.pressed ? 100 : 220
                  easing.type: volArea.pressed ? Easing.OutQuad : Easing.OutBack
                }
              }

              Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: frameConfig.sliderTrackColor
              }

              Item {
                id: volFillContainer
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, parent.width * root.volumeFraction)
                clip: true
                visible: (root.volumeFraction > 0.005) && (width > 1)

                Behavior on width {
                  enabled: !volArea.pressed
                  NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: volItem.width
                  radius: height / 2
                  color: frameConfig.activeSliderFillColor
                }
              }

              Text {
                z: 5
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: root.getVolumeIcon(root.volumeFraction)
                font.family: root.iconFont
                font.pixelSize: 20
                color: (volFillContainer.visible && volFillContainer.width >= 36)
                  ? frameConfig.activeSliderIconColorFilled
                  : frameConfig.sliderIconColorUnfilled
                renderType: Text.NativeRendering
              }

              MouseArea {
                id: volArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function applyPosition(mouse) {
                  var rawFrac = mouse.x / width
                  var frac = (rawFrac <= 0.02) ? 0.0 : Math.max(0.0, Math.min(1.0, rawFrac))
                  root.setVolume(frac)
                }

                onPressed: function(mouse) {
                  root.isDraggingSlider = true
                  applyPosition(mouse)
                }
                onPositionChanged: function(mouse) {
                  if (pressed) applyPosition(mouse)
                }
                onReleased: root.isDraggingSlider = false
              }
            }
          }
        }

        // Row 4: 3 Power Profile Buttons
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 14

          // Low power
          Rectangle {
            id: btnLowPower
            width: frameConfig.controlPowerButtonSize
            height: frameConfig.controlPowerButtonSize
            radius: width / 2

            readonly property bool isActive: root.activePowerProfile === "power-saver"

            color: isActive
              ? frameConfig.powerButtonActiveBg
              : (lpArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
            scale: lpArea.pressed ? 0.90 : (lpArea.containsMouse ? 1.08 : 1.0)

            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on scale {
              NumberAnimation {
                duration: lpArea.pressed ? 110 : 260
                easing.type: lpArea.pressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: 1.15
              }
            }

            Text {
              anchors.centerIn: parent
              text: "󰌪"
              font.family: root.iconFont
              font.pixelSize: 22
              color: btnLowPower.isActive
                ? frameConfig.powerButtonActiveIcon
                : frameConfig.powerButtonInactiveIcon
              renderType: Text.NativeRendering
            }

            MouseArea {
              id: lpArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setPowerProfile("power-saver")
            }
          }

          // Balanced
          Rectangle {
            id: btnBalanced
            width: frameConfig.controlPowerButtonSize
            height: frameConfig.controlPowerButtonSize
            radius: width / 2

            readonly property bool isActive: root.activePowerProfile === "balanced"

            color: isActive
              ? frameConfig.powerButtonActiveBg
              : (balArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
            scale: balArea.pressed ? 0.90 : (balArea.containsMouse ? 1.08 : 1.0)

            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on scale {
              NumberAnimation {
                duration: balArea.pressed ? 110 : 260
                easing.type: balArea.pressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: 1.15
              }
            }

            Text {
              anchors.centerIn: parent
              text: "󰊚"
              font.family: root.iconFont
              font.pixelSize: 22
              color: btnBalanced.isActive
                ? frameConfig.powerButtonActiveIcon
                : frameConfig.powerButtonInactiveIcon
              renderType: Text.NativeRendering
            }

            MouseArea {
              id: balArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setPowerProfile("balanced")
            }
          }

          // Performance
          Rectangle {
            id: btnPerformance
            width: frameConfig.controlPowerButtonSize
            height: frameConfig.controlPowerButtonSize
            radius: width / 2

            readonly property bool isActive: root.activePowerProfile === "performance"

            color: isActive
              ? frameConfig.powerButtonActiveBg
              : (perfArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
            scale: perfArea.pressed ? 0.90 : (perfArea.containsMouse ? 1.08 : 1.0)

            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on scale {
              NumberAnimation {
                duration: perfArea.pressed ? 110 : 260
                easing.type: perfArea.pressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: 1.15
              }
            }

            Text {
              anchors.centerIn: parent
              text: "󰓅"
              font.family: root.iconFont
              font.pixelSize: 22
              color: btnPerformance.isActive
                ? frameConfig.powerButtonActiveIcon
                : frameConfig.powerButtonInactiveIcon
              renderType: Text.NativeRendering
            }

            MouseArea {
              id: perfArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setPowerProfile("performance")
            }
          }
        }
      }
    }
  }
}
