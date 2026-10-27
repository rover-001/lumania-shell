import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  // Injected configuration & styling
  required property var frameConfig
  property int borderThickness: frameConfig.borderThickness
  property color islandColor: frameConfig.activeBorderColor
  property color islandTextColor: frameConfig.activeTextColor
  property color islandMutedColor: frameConfig.mutedColor
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  property string iconFont: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"
  property bool hasOpenApps: false

  // Dynamic Island Geometry
  readonly property int bodyWidth: frameConfig.islandBodyWidth
  readonly property int topCurveRadius: frameConfig.islandTopCurveRadius
  readonly property int islandWidth: bodyWidth + (topCurveRadius * 2)
  readonly property int islandHeight: borderThickness + 32
  readonly property int bottomCornerRadius: frameConfig.islandBottomCornerRadius

  // Mask items exposed to PanelWindow
  readonly property Item islandMaskItem: islandContainer
  readonly property Item subpanelMaskItem: (statusSubpanel && (statusSubpanel.isOpen || statusSubpanel.openProgress > 0.01)) ? statusSubpanel.maskItem : null
  readonly property Item dismissMaskItem: (statusSubpanel && statusSubpanel.isPinned) ? dismissArea : null

  // Clock state & formatting
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

  // -------------------------------------------------------------
  // MPRIS Media Detection & Track Capability Evaluation
  // Excludes voice calls (Discord, WhatsApp, Zoom, Teams, WebRTC)
  // -------------------------------------------------------------
  function isCallOrComm(p) {
    if (!p) return false
    var id = String(p.identity || "").toLowerCase()
    var title = String(p.trackTitle || "").toLowerCase()
    var artist = String(p.trackArtist || "").toLowerCase()
    if (id.indexOf("discord") !== -1 || id.indexOf("whatsapp") !== -1 ||
        id.indexOf("telegram") !== -1 || id.indexOf("slack") !== -1 ||
        id.indexOf("zoom") !== -1 || id.indexOf("teams") !== -1 ||
        id.indexOf("skype") !== -1 || id.indexOf("webrtc") !== -1) {
      return true
    }
    return false
  }

  function getActivePlayer() {
    var players = Mpris.players ? Mpris.players.values : []
    // 1. Any player actively playing with track metadata or skip capabilities (non-call)
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (p && p.isPlaying && !root.isCallOrComm(p) && (p.trackTitle || p.trackArtist || p.canGoNext || p.canGoPrevious)) {
        return p
      }
    }
    // 2. Any player actively playing (non-call)
    for (var j = 0; j < players.length; j++) {
      var q = players[j]
      if (q && q.isPlaying && !root.isCallOrComm(q)) return q
    }
    // 3. Any player with metadata (non-call)
    for (var k = 0; k < players.length; k++) {
      var r = players[k]
      if (r && !root.isCallOrComm(r) && (r.trackTitle || r.trackArtist)) return r
    }
    return null
  }

  readonly property var activePlayer: getActivePlayer()

  // Actual media is active only when an authentic music/video player is playing or has track data
  readonly property bool hasActualMedia: Boolean(
    activePlayer && !root.isCallOrComm(activePlayer) && (
      (activePlayer.isPlaying && (activePlayer.trackTitle || activePlayer.trackArtist || activePlayer.canGoNext || activePlayer.canGoPrevious)) ||
      (activePlayer.trackTitle && activePlayer.trackTitle.length > 0)
    )
  )

  // Video or song (has track metadata or skip capabilities), not a call or general audio
  readonly property bool isSkippable: Boolean(
    activePlayer && !root.isCallOrComm(activePlayer) && (
      activePlayer.canGoNext ||
      activePlayer.canGoPrevious ||
      (activePlayer.trackTitle && activePlayer.trackTitle.length > 0)
    )
  )

  Instantiator {
    model: Mpris.players ? Mpris.players.values : []
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { root.activePlayerChanged() }
      function onTrackTitleChanged() { root.activePlayerChanged() }
      function onCanGoNextChanged() { root.activePlayerChanged() }
      function onCanGoPreviousChanged() { root.activePlayerChanged() }
    }
  }

  Connections {
    target: Mpris.players
    function onValuesChanged() { root.activePlayerChanged() }
  }

  // Fixed Top Edge Trigger Strip: stays at y=0 so cursor touching top border wakes retracted notch immediately
  Item {
    id: edgeTriggerItem
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.islandWidth
    height: root.borderThickness + 14

    HoverHandler {
      id: edgeTriggerHover
    }
  }

  // -------------------------------------------------------------
  // Centered Dynamic Island Notch with Smooth Animated Sizing
  // -------------------------------------------------------------
  Item {
    id: islandContainer
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter

    // Hover interaction state (stays active while subpanel is open, hovered, or pinned)
    readonly property bool isHovered: islandHover.hovered || edgeTriggerHover.hovered || (statusSubpanel && (statusSubpanel.isOpen || statusSubpanel.isHovered || statusSubpanel.isPinned))
    readonly property real targetHoverProgress: isHovered ? 1.0 : 0.0
    property real hoverProgress: targetHoverProgress

    // Auto-retract inward when apps are opened; springs down immediately when cursor touches top edge
    readonly property bool shouldRetract: root.hasOpenApps && !islandContainer.isHovered && islandContainer.hoverProgress < 0.05
    readonly property real targetRetractY: shouldRetract ? -(root.islandHeight - root.borderThickness) : 0.0
    property real currentRetractY: targetRetractY

    Behavior on currentRetractY {
      NumberAnimation {
        duration: islandContainer.shouldRetract ? 280 : 380
        easing.type: islandContainer.shouldRetract ? Easing.OutCubic : Easing.OutBack
        easing.overshoot: 1.08
      }
    }

    y: currentRetractY

    // iOS Fluid Spring Behavior for hover
    // Expanding: snappy energetic spring (400ms, OutBack overshoot 1.08)
    // Collapsing: critically damped graceful settle (280ms, OutCubic)
    Behavior on hoverProgress {
      NumberAnimation {
        duration: islandContainer.isHovered ? 400 : 280
        easing.type: islandContainer.isHovered ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: islandContainer.isHovered ? 1.08 : 1.0
      }
    }

    // iOS Fluid Motion driver value: 0.0 (Clock View) -> 1.0 (Audio Waveform)
    readonly property real targetProgress: (dynamicView.showVisualizer && root.hasActualMedia) ? 1.0 : 0.0
    property real transitionProgress: targetProgress

    Behavior on transitionProgress {
      NumberAnimation {
        duration: (dynamicView.showVisualizer && root.hasActualMedia) ? 380 : 220
        easing.type: (dynamicView.showVisualizer && root.hasActualMedia) ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: (dynamicView.showVisualizer && root.hasActualMedia) ? 1.15 : 1.0
      }
    }

    // Dynamic Radii adapting with hover expansion for organic squircle continuity
    readonly property real currentTopRadius: root.topCurveRadius
      + (hoverProgress * (root.frameConfig.islandExpandedTopCurveRadius - root.topCurveRadius))
    readonly property real currentBottomRadius: root.bottomCornerRadius
      + (hoverProgress * (root.frameConfig.islandExpandedBottomCornerRadius - root.bottomCornerRadius))

    // Height expansion delta: taller when idle (+42px down to 79px) to fit 48px circles,
    // and sleek when media is playing (+24px down to 61px) to fit 44px media controls
    readonly property real activeHoverHeightDelta: (dynamicView.showVisualizer && root.hasActualMedia)
      ? root.frameConfig.islandHoverHeightDeltaMedia
      : root.frameConfig.islandHoverHeightDeltaIdle

    // Authentic iOS liquid stretch:
    // Pill widens symmetrically (+140px) on hover with liquid volume pulse during transitions
    width: root.islandWidth
      + (hoverProgress * root.frameConfig.islandHoverWidthDelta)
      + (Math.sin(Math.min(1.0, Math.max(0.0, transitionProgress)) * Math.PI) * 8.0)
      + (Math.sin(Math.min(1.0, Math.max(0.0, hoverProgress)) * Math.PI) * 6.0)

    // Height expands downwards on hover (+42px idle, +24px media)
    height: root.islandHeight + (hoverProgress * activeHoverHeightDelta)

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
      id: islandHover
      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      id: tapHandler
      enabled: !islandContainer.isHovered && !dynamicView.showVisualizer
      onTapped: {
        root.use24Hour = !root.use24Hour
        root.updateClock()
      }
    }

    // Main OLED Island Shape (Curved top flare flush with border + rounded bottom)
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

        // Bottom-right inward curve (full pill arc)
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

        // Bottom-left inward curve (full pill arc)
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

    // =========================================================================
    // Content Layer 1: Standard Outside View (Day, Date, Time)
    // Matches commit 149d0b0. Zero bleed: instantly hidden on hover.
    // =========================================================================
    Row {
      id: clockContentRow
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -5.0 * islandContainer.transitionProgress
      spacing: 8

      // Transitions out when audio starts or when hovered/opened
      opacity: (!islandContainer.isHovered && islandContainer.hoverProgress < 0.02)
        ? Math.max(0.0, 1.0 - islandContainer.transitionProgress * 2.2)
        : 0.0
      scale: Math.max(0.82, 1.0 - islandContainer.transitionProgress * 0.16)
      visible: opacity > 0.01 && !islandContainer.isHovered && islandContainer.hoverProgress < 0.02
      transformOrigin: Item.Center

      Behavior on opacity {
        NumberAnimation { duration: 140 }
      }

      Text {
        id: dateLabel
        anchors.verticalCenter: parent.verticalCenter
        text: root.currentDateString
        color: root.islandMutedColor
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
        renderType: Text.NativeRendering
        verticalAlignment: Text.AlignVCenter
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: 3
        radius: 1.5
        color: Qt.rgba(root.islandTextColor.r, root.islandTextColor.g, root.islandTextColor.b, 0.35)
      }

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

    // =========================================================================
    // Content Layer 2: Adaptive Audio Visualizer (Multi-Color Gradient Waveform)
    // Active when video/song or audio stream is playing. Hidden when opened.
    // =========================================================================
    DynamicWorkspaceView {
      id: dynamicView
      anchors.fill: parent

      opacity: (!islandContainer.isHovered && islandContainer.hoverProgress < 0.02)
        ? Math.min(1.0, Math.max(0.0, (islandContainer.transitionProgress - 0.25) * 1.33))
        : 0.0
      scale: 0.82 + (0.18 * islandContainer.transitionProgress)
      y: 4.0 * (1.0 - islandContainer.transitionProgress)
      visible: opacity > 0.01 && !islandContainer.isHovered && islandContainer.hoverProgress < 0.02
      transformOrigin: Item.Center

      Behavior on opacity {
        NumberAnimation { duration: 140 }
      }
    }

    // =========================================================================
    // Content Layer 3A: Opened During Media Playback (Skip / Play / Pause Controls)
    // When watching videos or songs: shows Skip Left, Play/Pause, Skip Right
    // When on calls or general streams: shows only Play/Pause (no skip buttons)
    // =========================================================================
    Row {
      id: mediaControlsRow
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.borderThickness * 0.5
      spacing: 18
      opacity: (islandContainer.hoverProgress > 0.15 && dynamicView.showVisualizer && root.hasActualMedia)
        ? Math.min(1.0, (islandContainer.hoverProgress - 0.15) * 1.35)
        : 0.0
      scale: 0.88 + (0.12 * islandContainer.hoverProgress)
      visible: opacity > 0.01 && dynamicView.showVisualizer && root.hasActualMedia
      transformOrigin: Item.Center

      // 1. Skip Previous Track (Shown only for videos/songs, hidden on calls)
      Rectangle {
        id: btnPrev
        visible: root.isSkippable
        width: 38
        height: 38
        radius: 19
        anchors.verticalCenter: parent.verticalCenter

        readonly property bool isPressed: prevArea.pressed
        scale: isPressed ? 0.90 : (prevArea.containsMouse ? 1.08 : 1.0)
        color: prevArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : root.frameConfig.powerButtonInactiveBg

        Behavior on scale {
          NumberAnimation {
            duration: btnPrev.isPressed ? 120 : 240
            easing.type: btnPrev.isPressed ? Easing.OutQuad : Easing.OutBack
            easing.overshoot: 1.15
          }
        }
        Behavior on color {
          ColorAnimation { duration: 180 }
        }

        Text {
          anchors.centerIn: parent
          text: "󰒮" // Material Skip Previous
          font.family: root.iconFont
          font.pixelSize: 18
          color: root.frameConfig.powerButtonInactiveIcon
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: prevArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.activePlayer && root.activePlayer.canGoPrevious) {
              root.activePlayer.previous()
            }
          }
        }
      }

      // 2. Play / Pause Hero Button
      Rectangle {
        id: btnPlayPause
        width: 44
        height: 44
        radius: 22
        anchors.verticalCenter: parent.verticalCenter

        readonly property bool isPlaying: Boolean(root.activePlayer && root.activePlayer.isPlaying)
        readonly property bool isPressed: playPauseArea.pressed
        scale: isPressed ? 0.90 : (playPauseArea.containsMouse ? 1.08 : 1.0)

        color: isPlaying
          ? root.frameConfig.powerButtonActiveBg
          : (playPauseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : root.frameConfig.powerButtonInactiveBg)

        Behavior on scale {
          NumberAnimation {
            duration: btnPlayPause.isPressed ? 120 : 240
            easing.type: btnPlayPause.isPressed ? Easing.OutQuad : Easing.OutBack
            easing.overshoot: 1.15
          }
        }
        Behavior on color {
          ColorAnimation { duration: 180 }
        }

        Text {
          anchors.centerIn: parent
          text: btnPlayPause.isPlaying ? "󰏤" : "󰐊" // Pause vs Play
          font.family: root.iconFont
          font.pixelSize: 22
          color: btnPlayPause.isPlaying ? root.frameConfig.powerButtonActiveIcon : root.frameConfig.powerButtonInactiveIcon
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: playPauseArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.activePlayer) {
              if (root.activePlayer.canTogglePlaying) {
                root.activePlayer.togglePlaying()
              } else if (root.activePlayer.isPlaying && root.activePlayer.canPause) {
                root.activePlayer.pause()
              } else if (root.activePlayer.canPlay) {
                root.activePlayer.play()
              }
            }
          }
        }
      }

      // 3. Skip Next Track (Shown only for videos/songs, hidden on calls)
      Rectangle {
        id: btnNext
        visible: root.isSkippable
        width: 38
        height: 38
        radius: 19
        anchors.verticalCenter: parent.verticalCenter

        readonly property bool isPressed: nextArea.pressed
        scale: isPressed ? 0.90 : (nextArea.containsMouse ? 1.08 : 1.0)
        color: nextArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : root.frameConfig.powerButtonInactiveBg

        Behavior on scale {
          NumberAnimation {
            duration: btnNext.isPressed ? 120 : 240
            easing.type: btnNext.isPressed ? Easing.OutQuad : Easing.OutBack
            easing.overshoot: 1.15
          }
        }
        Behavior on color {
          ColorAnimation { duration: 180 }
        }

        Text {
          anchors.centerIn: parent
          text: "󰒭" // Material Skip Next
          font.family: root.iconFont
          font.pixelSize: 18
          color: root.frameConfig.powerButtonInactiveIcon
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: nextArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.activePlayer && root.activePlayer.canGoNext) {
              root.activePlayer.next()
            }
          }
        }
      }
    }

    // =========================================================================
    // Content Layer 3B: Opened While Idle (Big Circular Buttons for WiFi, BT, DNS)
    // Hovering over each button drops down its corresponding subpanel!
    // =========================================================================
    Row {
      id: statusControlsRow
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.borderThickness * 0.5
      spacing: 20
      opacity: (islandContainer.hoverProgress > 0.15 && (!dynamicView.showVisualizer || !root.hasActualMedia))
        ? Math.min(1.0, (islandContainer.hoverProgress - 0.15) * 1.35)
        : 0.0
      scale: 0.88 + (0.12 * islandContainer.hoverProgress)
      visible: opacity > 0.01 && (!dynamicView.showVisualizer || !root.hasActualMedia)
      transformOrigin: Item.Center

      // 1. Wi-Fi Big Circular Button
      Rectangle {
        id: btnWifi
        width: 48
        height: 48
        radius: 24
        anchors.verticalCenter: parent.verticalCenter

        readonly property bool isSelectedTab: Boolean(statusSubpanel && statusSubpanel.isOpen && statusSubpanel.activeTab === "wifi")
        readonly property bool isPressed: wifiArea.pressed

        color: isSelectedTab
          ? root.frameConfig.powerButtonActiveBg
          : (wifiArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : root.frameConfig.powerButtonInactiveBg)

        scale: isPressed ? 0.90 : (wifiArea.containsMouse ? 1.08 : 1.0)

        Behavior on scale {
          NumberAnimation {
            duration: btnWifi.isPressed ? 120 : 240
            easing.type: btnWifi.isPressed ? Easing.OutQuad : Easing.OutBack
            easing.overshoot: 1.15
          }
        }
        Behavior on color {
          ColorAnimation { duration: 180 }
        }

        Text {
          anchors.centerIn: parent
          text: {
            if (!statusSubpanel || !statusSubpanel.wifiData || !statusSubpanel.wifiData.enabled) return "󰤮"
            if (!statusSubpanel.wifiData.connected) return "󰤯"
            var sig = statusSubpanel.wifiData.signal || 50
            if (sig > 75) return "󰤨"
            if (sig > 50) return "󰤥"
            if (sig > 25) return "󰤢"
            return "󰤟"
          }
          font.family: root.iconFont
          font.pixelSize: 22
          color: btnWifi.isSelectedTab
            ? root.frameConfig.powerButtonActiveIcon
            : root.frameConfig.powerButtonInactiveIcon
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: wifiArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: {
            statusSubpanel.activeTab = "wifi"
            statusSubpanel.isOpen = true
          }
          onClicked: {
            statusSubpanel.activeTab = "wifi"
            statusSubpanel.isPinned = !statusSubpanel.isPinned
            if (statusSubpanel.isPinned) statusSubpanel.isOpen = true
          }
        }
      }

      // 2. Bluetooth Big Circular Button
      Rectangle {
        id: btnBluetooth
        width: 48
        height: 48
        radius: 24
        anchors.verticalCenter: parent.verticalCenter

        readonly property bool isSelectedTab: Boolean(statusSubpanel && statusSubpanel.isOpen && statusSubpanel.activeTab === "bluetooth")
        readonly property bool isPressed: btArea.pressed

        color: isSelectedTab
          ? root.frameConfig.powerButtonActiveBg
          : (btArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : root.frameConfig.powerButtonInactiveBg)

        scale: isPressed ? 0.90 : (btArea.containsMouse ? 1.08 : 1.0)

        Behavior on scale {
          NumberAnimation {
            duration: btnBluetooth.isPressed ? 120 : 240
            easing.type: btnBluetooth.isPressed ? Easing.OutQuad : Easing.OutBack
            easing.overshoot: 1.15
          }
        }
        Behavior on color {
          ColorAnimation { duration: 180 }
        }

        Text {
          anchors.centerIn: parent
          text: {
            if (!statusSubpanel || !statusSubpanel.btData || !statusSubpanel.btData.enabled) return "󰂲"
            if (statusSubpanel.btData.connectedCount > 0) return "󰂱"
            return "󰂯"
          }
          font.family: root.iconFont
          font.pixelSize: 22
          color: btnBluetooth.isSelectedTab
            ? root.frameConfig.powerButtonActiveIcon
            : root.frameConfig.powerButtonInactiveIcon
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: btArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: {
            statusSubpanel.activeTab = "bluetooth"
            statusSubpanel.isOpen = true
          }
          onClicked: {
            statusSubpanel.activeTab = "bluetooth"
            statusSubpanel.isPinned = !statusSubpanel.isPinned
            if (statusSubpanel.isPinned) statusSubpanel.isOpen = true
          }
        }
      }

      // 3. DNS Big Circular Button
      Rectangle {
        id: btnDns
        width: 48
        height: 48
        radius: 24
        anchors.verticalCenter: parent.verticalCenter

        readonly property bool isSelectedTab: Boolean(statusSubpanel && statusSubpanel.isOpen && statusSubpanel.activeTab === "dns")
        readonly property bool isPressed: dnsArea.pressed

        color: isSelectedTab
          ? root.frameConfig.powerButtonActiveBg
          : (dnsArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : root.frameConfig.powerButtonInactiveBg)

        scale: isPressed ? 0.90 : (dnsArea.containsMouse ? 1.08 : 1.0)

        Behavior on scale {
          NumberAnimation {
            duration: btnDns.isPressed ? 120 : 240
            easing.type: btnDns.isPressed ? Easing.OutQuad : Easing.OutBack
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
          font.pixelSize: 22
          color: btnDns.isSelectedTab
            ? root.frameConfig.powerButtonActiveIcon
            : root.frameConfig.powerButtonInactiveIcon
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: dnsArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: {
            statusSubpanel.activeTab = "dns"
            statusSubpanel.isOpen = true
          }
          onClicked: {
            statusSubpanel.activeTab = "dns"
            statusSubpanel.isPinned = !statusSubpanel.isPinned
            if (statusSubpanel.isPinned) statusSubpanel.isOpen = true
          }
        }
      }
    }
  }

  // -------------------------------------------------------------
  // Invisible Hover Bridge between Top Notch and Subpanel
  // -------------------------------------------------------------
  Item {
    id: hoverBridge
    anchors.top: islandContainer.bottom
    anchors.bottom: statusSubpanel.top
    anchors.horizontalCenter: islandContainer.horizontalCenter
    width: statusSubpanel.width
    visible: statusSubpanel.isOpen || statusSubpanel.openProgress > 0.01

    HoverHandler {
      id: bridgeHover
    }
  }

  // -------------------------------------------------------------
  // Dropdown Subpanel below Top Notch (Fluid iOS Spring Motion)
  // Flush unibody attachment: sticks directly to the notch!
  // -------------------------------------------------------------
  TopNotchSubpanel {
    id: statusSubpanel
    frameConfig: root.frameConfig
    anchors.top: islandContainer.bottom
    anchors.topMargin: root.frameConfig.statusSubpanelTopMargin
    anchors.horizontalCenter: islandContainer.horizontalCenter
    fontFamily: root.fontFamily
  }

  // -------------------------------------------------------------
  // Outside Click Dismiss Handler when Subpanel is Pinned
  // -------------------------------------------------------------
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

  // -------------------------------------------------------------
  // Graceful Hover Close Timer for Subpanel
  // -------------------------------------------------------------
  Timer {
    id: subpanelCloseTimer
    interval: 240
    repeat: false
    onTriggered: {
      if (!statusSubpanel.isPinned && !islandHover.hovered && !bridgeHover.hovered && !statusSubpanel.isHovered) {
        statusSubpanel.isOpen = false
      }
    }
  }

  readonly property bool isSubpanelAreaHovered: islandHover.hovered || bridgeHover.hovered || statusSubpanel.isHovered

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
