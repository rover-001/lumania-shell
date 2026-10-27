import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

Item {
  id: root

  FrameConfig {
    id: frameConfig
  }

  // Sizing bounds for sleek vertical notch (subtle resting protrusion, tall height, luxurious expanded panel)
  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  readonly property real collapsedWidth: frameConfig.rightCollapsedWidth > root.borderThickness
    ? frameConfig.rightCollapsedWidth
    : (root.borderThickness + Math.max(2.0, frameConfig.rightCollapsedWidth))
  readonly property real expandedWidth: frameConfig.rightExpandedWidth
  readonly property real collapsedHeight: frameConfig.rightCollapsedHeight
  readonly property real expandedHeight: frameConfig.rightExpandedHeight

  // Flare & corner radii adapting dynamically with hoverProgress from FrameConfig
  readonly property real currentFlareRadius: frameConfig.rightFlareRadius
    + (hoverProgress * (frameConfig.rightExpandedFlareRadius - frameConfig.rightFlareRadius))
  readonly property real currentCornerRadius: frameConfig.rightCornerRadius
    + (hoverProgress * (frameConfig.rightExpandedCornerRadius - frameConfig.rightCornerRadius))

  // Interaction state
  property bool isDraggingSlider: false

  // Hover interaction state - instant reactive spring matching Dynamic Island exactly
  readonly property bool isHoveredOrActive: Boolean(edgeHover && edgeHover.hovered) || Boolean(cardHover && cardHover.hovered) || isDraggingSlider
  readonly property bool isOpen: isHoveredOrActive
  readonly property real targetHoverProgress: isHoveredOrActive ? 1.0 : 0.0
  property real hoverProgress: targetHoverProgress

  // iOS Fluid Spring Behavior matching IslandBar.qml:
  // Expanding (hover in): snappy energetic spring (400ms, OutBack overshoot 1.08)
  // Collapsing (hover out): critically damped graceful settle (280ms, OutCubic)
  Behavior on hoverProgress {
    NumberAnimation {
      duration: root.isHoveredOrActive ? 400 : 280
      easing.type: root.isHoveredOrActive ? Easing.OutBack : Easing.OutCubic
      easing.overshoot: root.isHoveredOrActive ? 1.08 : 1.0
    }
  }

  // Authentic iOS liquid stretch matching IslandBar.qml:
  // Width widens smoothly with liquid volume pulse during mid-transition (sin curve)
  readonly property real currentWidth: collapsedWidth
    + (hoverProgress * (expandedWidth - collapsedWidth))
    + (Math.sin(Math.min(1.0, Math.max(0.0, hoverProgress)) * Math.PI) * 6.0)

  readonly property real currentHeight: collapsedHeight
    + (hoverProgress * (expandedHeight - collapsedHeight))

  // Mask item exposed to PanelWindow
  property alias maskItem: activeRegionItem

  // System States
  property real volumeFraction: 0.5
  property real brightnessFraction: 0.5
  property string activePowerProfile: "balanced"

  readonly property string iconFont: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"

  // -------------------------------------------------------------
  // Data Fetching & Sync
  // -------------------------------------------------------------
  function refreshAll() {
    volProc.running = true
    brightProc.running = true
    powerProc.running = true
  }

  Component.onCompleted: {
    refreshAll()
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: {
      if (!root.isDraggingSlider) root.refreshAll()
    }
  }

  onIsOpenChanged: {
    if (isOpen) root.refreshAll()
  }

  Process {
    id: volProc
    command: ["pamixer", "--get-volume"]
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line || "").trim()
        var val = parseInt(str)
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

  function setVolume(pct) {
    var v = Math.round(pct * 100)
    root.volumeFraction = pct
    volSetter.command = ["pamixer", "--set-volume", String(v)]
    volSetter.running = true
  }

  Process { id: volSetter }

  function setBrightness(pct) {
    var b = Math.max(5, Math.round(pct * 100))
    root.brightnessFraction = pct
    brightSetter.command = ["brightnessctl", "set", b + "%"]
    brightSetter.running = true
  }

  Process { id: brightSetter }

  function setPowerProfile(profile) {
    root.activePowerProfile = profile
    powerSetter.command = ["powerprofilesctl", "set", profile]
    powerSetter.running = true
  }

  Process {
    id: powerSetter
    onExited: powerProc.running = true
  }

  function getVolumeIcon(fraction) {
    if (fraction <= 0.01) return ""
    if (fraction < 0.35) return ""
    if (fraction < 0.70) return ""
    return ""
  }

  // -------------------------------------------------------------
  // Dynamic Active Input Region
  // -------------------------------------------------------------
  Item {
    id: activeRegionItem
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: (root.hoverProgress > 0.05) ? (notchContainer.width + 16) : 32
    height: (root.hoverProgress > 0.05) ? (notchContainer.height + 16) : 164

    HoverHandler {
      id: edgeHover
      cursorShape: Qt.PointingHandCursor
    }
  }

  // -------------------------------------------------------------
  // Notch Container (Anchored flush to right edge)
  // -------------------------------------------------------------
  Item {
    id: notchContainer
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: root.currentWidth
    height: root.currentHeight

    HoverHandler {
      id: cardHover
      cursorShape: Qt.ArrowCursor
    }

    // Press feedback: instant scale-down to 0.97 on press, spring pop back
    property bool isPressed: false
    scale: isPressed ? 0.97 : 1.0
    transformOrigin: Item.Right

    Behavior on scale {
      NumberAnimation {
        duration: notchContainer.isPressed ? 140 : 320
        easing.type: notchContainer.isPressed ? Easing.OutQuad : Easing.OutBack
        easing.overshoot: 1.2
      }
    }

    // 1. Warm Terracotta / Dusty Rose Notch Shape
    Shape {
      id: notchShape
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      readonly property real w: notchContainer.width
      readonly property real h: notchContainer.height
      readonly property real b: root.borderThickness
      readonly property real rf: root.currentFlareRadius
      readonly property real rc: root.currentCornerRadius

      // Guaranteed G1 squircle continuity: flare and corner automatically partition available protrusion
      readonly property real effRf: Math.min(rf, Math.max(2, (w - b) * 0.38))
      readonly property real effRc: Math.min(rc, Math.max(2, (w - b) - effRf))

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: root.notchColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        // Start past screen edge at top of notch
        startX: notchShape.w + 2
        startY: 0

        // Line to vertical border line at y = 0
        PathLine {
          x: notchShape.w - notchShape.b
          y: 0
        }

        // Top concave flare curving out from border line towards top edge
        PathCubic {
          x: notchShape.w - notchShape.b - notchShape.effRf
          y: notchShape.effRf
          control1X: notchShape.w - notchShape.b
          control1Y: notchShape.effRf * 0.5
          control2X: notchShape.w - notchShape.b - (notchShape.effRf * 0.5)
          control2Y: notchShape.effRf
        }

        // Top horizontal line to top-left corner
        PathLine {
          x: notchShape.effRc
          y: notchShape.effRf
        }

        // Top-left convex corner arc
        PathArc {
          x: 0
          y: notchShape.effRf + notchShape.effRc
          radiusX: Math.max(1, notchShape.effRc)
          radiusY: Math.max(1, notchShape.effRc)
          direction: PathArc.Counterclockwise
        }

        // Left vertical edge
        PathLine {
          x: 0
          y: Math.max(notchShape.effRf + notchShape.effRc, notchShape.h - notchShape.effRf - notchShape.effRc)
        }

        // Bottom-left convex corner arc
        PathArc {
          x: notchShape.effRc
          y: notchShape.h - notchShape.effRf
          radiusX: Math.max(1, notchShape.effRc)
          radiusY: Math.max(1, notchShape.effRc)
          direction: PathArc.Counterclockwise
        }

        // Bottom horizontal line to bottom-right flare
        PathLine {
          x: notchShape.w - notchShape.b - notchShape.effRf
          y: notchShape.h - notchShape.effRf
        }

        // Bottom concave flare curving back into the vertical border line
        PathCubic {
          x: notchShape.w - notchShape.b
          y: notchShape.h
          control1X: notchShape.w - notchShape.b - (notchShape.effRf * 0.5)
          control1Y: notchShape.h - notchShape.effRf
          control2X: notchShape.w - notchShape.b
          control2Y: notchShape.h - (notchShape.effRf * 0.5)
        }

        // Line past right screen edge
        PathLine {
          x: notchShape.w + 2
          y: notchShape.h
        }

        // Close along screen right edge
        PathLine {
          x: notchShape.w + 2
          y: 0
        }
      }
    }

    // 2. Notch Content: EVERYTHING IN 1 SINGLE VERTICAL COLUMN
    Column {
      id: mainColumn
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 12

      // Reveal smoothly with liquid fade & scale
      opacity: Math.max(0.0, (root.hoverProgress - 0.20) / 0.80)
      scale: 0.88 + (0.12 * root.hoverProgress)
      visible: opacity > 0.01

      // ---------------------------------------------------------
      // BAR 1 (TOP): Voice / Volume Vertical Bar (Fills from BOTTOM UP)
      // Icon placed at the BOTTOM of the bar (shifted down)
      // ---------------------------------------------------------
      Item {
        id: volItem
        width: parent.width
        height: 140

        // Base capsule track (tinted dark from FrameConfig)
        Rectangle {
          id: volTrack
          anchors.fill: parent
          radius: width / 2
          color: frameConfig.sliderTrackColor
        }

        // Fill Container: anchored to bottom, clips children cleanly without corner bleeding
        Item {
          id: volFillContainer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Math.max(0, parent.height * root.volumeFraction)
          clip: true
          visible: (root.volumeFraction > 0.005) && (height > 1)

          Behavior on height {
            enabled: !volArea.pressed
            NumberAnimation {
              duration: 120
              easing.type: Easing.OutCubic
            }
          }

          // Full-height capsule: shares the exact curvature of the track
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: volItem.height
            radius: width / 2
            color: frameConfig.activeSliderFillColor
          }
        }

        // Volume Icon in the BOTTOM of the bar (positioned low)
        Text {
          id: volIcon
          z: 5
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 8
          text: root.getVolumeIcon(root.volumeFraction)
          font.family: root.iconFont
          font.pixelSize: 22
          // Contrast: dynamically switches between filled and unfilled slider colors
          color: (volFillContainer.visible && volFillContainer.height >= 16)
            ? frameConfig.activeSliderIconColorFilled
            : frameConfig.sliderIconColorUnfilled
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: volArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor

          // Dragging UP increases volume (bottom-up progress)
          function applyPosition(mouse) {
            var rawFrac = (height - mouse.y) / height
            var frac = (rawFrac <= 0.02) ? 0.0 : Math.max(0.0, Math.min(1.0, rawFrac))
            root.setVolume(frac)
          }

          onPressed: function(mouse) {
            notchContainer.isPressed = true
            root.isDraggingSlider = true
            applyPosition(mouse)
          }
          onPositionChanged: function(mouse) {
            if (pressed) applyPosition(mouse)
          }
          onReleased: {
            notchContainer.isPressed = false
            root.isDraggingSlider = false
          }
        }
      }

      // ---------------------------------------------------------
      // CENTER BUTTON 1: Low Power Mode (Fully Rounded Circle)
      // ---------------------------------------------------------
      Rectangle {
        id: btnLowPower
        width: 52
        height: 52
        radius: 26
        anchors.horizontalCenter: parent.horizontalCenter

        readonly property bool isActive: root.activePowerProfile === "power-saver"
        readonly property bool isPressed: lpArea.pressed

        color: isActive ? frameConfig.powerButtonActiveBg : (lpArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
        scale: isPressed ? 0.92 : 1.0

        Behavior on scale {
          NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
        }
        Behavior on color {
          ColorAnimation { duration: 180 }
        }

        Text {
          anchors.centerIn: parent
          text: "󰌪" // Leaf icon
          font.family: root.iconFont
          font.pixelSize: 21
          color: btnLowPower.isActive ? frameConfig.powerButtonActiveIcon : frameConfig.powerButtonInactiveIcon
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

      // ---------------------------------------------------------
      // CENTER BUTTON 2: Balanced Mode (Fully Rounded Circle)
      // ---------------------------------------------------------
      Rectangle {
        id: btnBalanced
        width: 52
        height: 52
        radius: 26
        anchors.horizontalCenter: parent.horizontalCenter

        readonly property bool isActive: root.activePowerProfile === "balanced"
        readonly property bool isPressed: balArea.pressed

        color: isActive ? frameConfig.powerButtonActiveBg : (balArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
        scale: isPressed ? 0.92 : 1.0

        Behavior on scale {
          NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
        }
        Behavior on color {
          ColorAnimation { duration: 180 }
        }

        Text {
          anchors.centerIn: parent
          text: "󰊚" // Balance / Gauge icon
          font.family: root.iconFont
          font.pixelSize: 21
          color: btnBalanced.isActive ? frameConfig.powerButtonActiveIcon : frameConfig.powerButtonInactiveIcon
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

      // ---------------------------------------------------------
      // CENTER BUTTON 3: Performance Mode (Fully Rounded Circle)
      // ---------------------------------------------------------
      Rectangle {
        id: btnPerformance
        width: 52
        height: 52
        radius: 26
        anchors.horizontalCenter: parent.horizontalCenter

        readonly property bool isActive: root.activePowerProfile === "performance"
        readonly property bool isPressed: perfArea.pressed

        color: isActive ? frameConfig.powerButtonActiveBg : (perfArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
        scale: isPressed ? 0.92 : 1.0

        Behavior on scale {
          NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
        }
        Behavior on color {
          ColorAnimation { duration: 180 }
        }

        Text {
          anchors.centerIn: parent
          text: "󰓅" // Speedometer / Rocket icon
          font.family: root.iconFont
          font.pixelSize: 21
          color: btnPerformance.isActive ? frameConfig.powerButtonActiveIcon : frameConfig.powerButtonInactiveIcon
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

      // ---------------------------------------------------------
      // BAR 2 (BOTTOM): Brightness Vertical Bar (Fills from TOP DOWN)
      // Icon placed at the TOP of the bar (shifted down)
      // ---------------------------------------------------------
      Item {
        id: brightItem
        width: parent.width
        height: 140

        // Base capsule track (tinted dark from FrameConfig)
        Rectangle {
          id: brightTrack
          anchors.fill: parent
          radius: width / 2
          color: frameConfig.sliderTrackColor
        }

        // Fill Container: anchored to top, clips children cleanly without corner bleeding
        Item {
          id: brightFillContainer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Math.max(0, parent.height * root.brightnessFraction)
          clip: true
          visible: (root.brightnessFraction > 0.005) && (height > 1)

          Behavior on height {
            enabled: !brightArea.pressed
            NumberAnimation {
              duration: 120
              easing.type: Easing.OutCubic
            }
          }

          // Full-height capsule: shares the exact curvature of the track
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: brightItem.height
            radius: width / 2
            color: frameConfig.activeSliderFillColor
          }
        }

        // Brightness Sun Icon in the TOP of the bar (shifted down)
        Text {
          id: brightIcon
          z: 5
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: 10
          text: "󰃠" // Sun icon
          font.family: root.iconFont
          font.pixelSize: 22
          // Contrast: dynamically switches between filled and unfilled slider colors
          color: (brightFillContainer.visible && brightFillContainer.height >= 16)
            ? frameConfig.activeSliderIconColorFilled
            : frameConfig.sliderIconColorUnfilled
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: brightArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor

          // Dragging DOWN increases brightness (top-down progress)
          function applyPosition(mouse) {
            var rawFrac = mouse.y / height
            var frac = (rawFrac <= 0.02) ? 0.0 : Math.max(0.0, Math.min(1.0, rawFrac))
            root.setBrightness(frac)
          }

          onPressed: function(mouse) {
            notchContainer.isPressed = true
            root.isDraggingSlider = true
            applyPosition(mouse)
          }
          onPositionChanged: function(mouse) {
            if (pressed) applyPosition(mouse)
          }
          onReleased: {
            notchContainer.isPressed = false
            root.isDraggingSlider = false
          }
        }
      }
    }
  }
}
