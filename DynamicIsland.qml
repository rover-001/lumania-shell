import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
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
  property var notificationManager: null

  readonly property bool hasNotification: Boolean(notificationManager && notificationManager.hasNotification)
  property real notificationProgress: hasNotification ? 1.0 : 0.0

  Behavior on notificationProgress {
    NumberAnimation {
      duration: root.hasNotification ? 380 : 260
      easing.type: root.hasNotification ? Easing.OutBack : Easing.OutCubic
      easing.overshoot: root.hasNotification ? 1.12 : 1.0
    }
  }

  function resolveIcon(iconPath) {
    var s = String(iconPath || "").trim()
    if (!s || s.length === 0) return ""
    if (s.indexOf("file://") === 0 || s.indexOf("image://") === 0) return s
    if (s.charAt(0) === "/") return "file://" + s
    var themed = Quickshell.iconPath(s, true)
    return themed ? String(themed) : ""
  }

  function isFilePath(path) {
    var s = String(path || "").trim()
    return s.indexOf("/") === 0 || s.indexOf("file://") === 0 || s.indexOf("image://") === 0
  }

  // Dynamic Island Geometry
  readonly property int bodyWidth: frameConfig.islandBodyWidth
  readonly property int topCurveRadius: frameConfig.islandTopCurveRadius
  readonly property int islandWidth: bodyWidth + (topCurveRadius * 2)
  readonly property int islandHeight: borderThickness + 32
  readonly property int bottomCornerRadius: frameConfig.islandBottomCornerRadius

  // Mask item exposed to PanelWindow
  readonly property Item islandMaskItem: islandContainer

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

    // Hover interaction state (pointer presence also wakes a retracted island)
    readonly property bool isPointerOver: islandHover.hovered || edgeTriggerHover.hovered

    onIsPointerOverChanged: {
      if (root.notificationManager) {
        root.notificationManager.isHovered = isPointerOver
      }
    }

    // The island only morphs open when there is actual media to control and no notification active;
    // status toggles now live in the bottom-right control center notch.
    readonly property bool isHovered: isPointerOver && root.hasActualMedia && dynamicView.showVisualizer && root.notificationProgress < 0.01
    readonly property real targetHoverProgress: isHovered ? 1.0 : 0.0
    property real hoverProgress: targetHoverProgress

    // Auto-retract inward when apps are opened; springs down immediately when cursor touches top edge
    // or when an active notification is received ("come in show the notif and then move out")
    readonly property bool shouldRetract: root.hasOpenApps
      && !isPointerOver
      && !root.hasNotification
      && root.notificationProgress < 0.01
      && islandContainer.hoverProgress < 0.05
    readonly property real targetRetractY: shouldRetract ? -(root.islandHeight - root.borderThickness) : 0.0

    // Retract offset rides the shared FluidSpring driver: critically damped going
    // in (a settle), a touch of momentum coming back out, and retargeting mid
    // flight keeps velocity so a wake never restarts the motion.
    FluidSpring {
      id: retractSpring
      target: islandContainer.targetRetractY
      response: islandContainer.shouldRetract ? 0.28 : 0.36
      dampingFraction: islandContainer.shouldRetract ? 1.0 : 0.8
      epsilon: 0.05
    }

    readonly property real currentRetractY: retractSpring.value

    // topMargin, not y: anchors.top owns y, so a y binding is overwritten by the
    // anchor layout and the notch would stay parked on the top edge forever.
    anchors.topMargin: currentRetractY

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

    // Dynamic Radii adapting with hover or notification expansion for organic squircle continuity
    readonly property real activeExpansionProgress: Math.max(hoverProgress, root.notificationProgress)

    readonly property real currentTopRadius: root.topCurveRadius
      + (activeExpansionProgress * (root.frameConfig.islandExpandedTopCurveRadius - root.topCurveRadius))
    readonly property real currentBottomRadius: root.bottomCornerRadius
      + (activeExpansionProgress * (root.frameConfig.islandExpandedBottomCornerRadius - root.bottomCornerRadius))

    // Height expansion delta: taller when idle (+42px down to 79px) to fit 48px circles,
    // and sleek when media is playing (+24px down to 61px) to fit 44px media controls
    readonly property real activeHoverHeightDelta: (dynamicView.showVisualizer && root.hasActualMedia)
      ? root.frameConfig.islandHoverHeightDeltaMedia
      : root.frameConfig.islandHoverHeightDeltaIdle

    // Dynamic width calculation based on active notification content size
    readonly property real notifContentTextWidth: Math.max(
      (typeof notifSummaryText !== "undefined" && notifSummaryText) ? notifSummaryText.implicitWidth : 0,
      (typeof notifBodyText !== "undefined" && notifBodyText && notifBodyText.text.length > 0) ? notifBodyText.implicitWidth : 0
    )
    readonly property real notifDynamicTargetWidth: Math.max(
      root.islandWidth,
      Math.min(480, Math.ceil(notifContentTextWidth) + 104)
    )
    readonly property real notifWidthDelta: Math.max(0, notifDynamicTargetWidth - root.islandWidth)
    property real animatedNotifWidthDelta: notifWidthDelta

    Behavior on animatedNotifWidthDelta {
      NumberAnimation {
        duration: 320
        easing.type: Easing.OutBack
        easing.overshoot: 1.08
      }
    }

    readonly property real notifHeightDelta: 18

    // Authentic iOS liquid stretch:
    // Pill widens dynamically based on active notification size, with liquid volume pulse during transitions
    width: root.islandWidth
      + (hoverProgress * root.frameConfig.islandHoverWidthDelta)
      + (root.notificationProgress * animatedNotifWidthDelta)
      + (Math.sin(Math.min(1.0, Math.max(0.0, transitionProgress)) * Math.PI) * 8.0)
      + (Math.sin(Math.min(1.0, Math.max(0.0, hoverProgress)) * Math.PI) * 6.0)
      + (Math.sin(Math.min(1.0, Math.max(0.0, root.notificationProgress)) * Math.PI) * 10.0)

    // Height expands downwards on hover (+42px idle, +24px media) or notification (+18px)
    height: root.islandHeight
      + (hoverProgress * activeHoverHeightDelta)
      + (root.notificationProgress * notifHeightDelta)

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
      enabled: !islandContainer.isHovered && !dynamicView.showVisualizer && root.notificationProgress < 0.01
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

      // Transitions out when audio starts, when hovered/opened, or when notification is active
      opacity: (!islandContainer.isHovered && islandContainer.hoverProgress < 0.02 && root.notificationProgress < 0.01)
        ? Math.max(0.0, 1.0 - islandContainer.transitionProgress * 2.2)
        : 0.0
      scale: Math.max(0.82, 1.0 - islandContainer.transitionProgress * 0.16)
      visible: opacity > 0.01 && !islandContainer.isHovered && islandContainer.hoverProgress < 0.02 && root.notificationProgress < 0.01
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

      opacity: (!islandContainer.isHovered && islandContainer.hoverProgress < 0.02 && root.notificationProgress < 0.01)
        ? Math.min(1.0, Math.max(0.0, (islandContainer.transitionProgress - 0.25) * 1.33))
        : 0.0
      scale: 0.82 + (0.18 * islandContainer.transitionProgress)
      y: 4.0 * (1.0 - islandContainer.transitionProgress)
      visible: opacity > 0.01 && !islandContainer.isHovered && islandContainer.hoverProgress < 0.02 && root.notificationProgress < 0.01
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
      opacity: (islandContainer.hoverProgress > 0.15 && dynamicView.showVisualizer && root.hasActualMedia && root.notificationProgress < 0.01)
        ? Math.min(1.0, (islandContainer.hoverProgress - 0.15) * 1.35)
        : 0.0
      scale: 0.88 + (0.12 * islandContainer.hoverProgress)
      visible: opacity > 0.01 && dynamicView.showVisualizer && root.hasActualMedia && root.notificationProgress < 0.01
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
    // Content Layer 4: Dynamic Island Notification Presentation
    // =========================================================================
    Item {
      id: notificationContent
      anchors.fill: parent
      anchors.topMargin: root.borderThickness
      anchors.leftMargin: islandShape.rTop + 12
      anchors.rightMargin: islandShape.rTop + 14

      opacity: root.notificationProgress
      scale: 0.92 + (0.08 * root.notificationProgress)
      visible: opacity > 0.005
      transformOrigin: Item.Center

      RowLayout {
        anchors.fill: parent
        spacing: 11

        // 1. Left Icon Slot: Fully rounded circular image, app icon, or glyph
        Item {
          id: notifIconContainer
          Layout.preferredWidth: 30
          Layout.preferredHeight: 30
          Layout.alignment: Qt.AlignVCenter

          // Circular mask geometry for MultiEffect shader
          Item {
            id: circleMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle {
              anchors.fill: parent
              radius: width * 0.5
              color: "#000000"
            }
          }

          // Subtle translucent circular background disc
          Rectangle {
            anchors.fill: parent
            radius: width * 0.5
            color: (root.notificationManager && root.notificationManager.currentUrgency === 2)
              ? Qt.rgba(1.0, 0.25, 0.25, 0.28)
              : Qt.rgba(1, 1, 1, 0.16)
          }

          // Shader-masked image wrapper: guarantees 100% circular clipping for avatars, PFPs, screenshots
          Item {
            id: notifImageWrapper
            anchors.fill: parent
            visible: (notifImg.status === Image.Ready && notifImg.source.toString().length > 0)
              || (notifAppIcon.status === Image.Ready && notifAppIcon.source.toString().length > 0)
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: circleMask
              maskThresholdMin: 0.5
              maskSpreadAtMin: 0.5
            }

            // 1a. Direct image / avatar file (WhatsApp PFP, screenshot, sender avatar)
            Image {
              id: notifImg
              anchors.fill: parent
              visible: status === Image.Ready && source.toString().length > 0
              source: {
                if (!root.notificationManager) return ""
                var img = root.notificationManager.currentImage
                if (img && img.length > 0) return root.resolveIcon(img)
                var icon = root.notificationManager.currentAppIcon
                if (icon && root.isFilePath(icon)) return root.resolveIcon(icon)
                return ""
              }
              fillMode: Image.PreserveAspectCrop
              mipmap: true
              smooth: true
            }

            // 1b. App icon from theme (centered 20x20)
            Image {
              id: notifAppIcon
              anchors.centerIn: parent
              width: 20
              height: 20
              visible: !notifImg.visible && status === Image.Ready && source.toString().length > 0
              source: {
                if (!root.notificationManager) return ""
                var icon = root.notificationManager.currentAppIcon
                if (icon && !root.isFilePath(icon)) return root.resolveIcon(icon)
                return ""
              }
              fillMode: Image.PreserveAspectFit
              mipmap: true
              smooth: true
            }
          }

          // 1c. Glyph / Brand symbol / Fallback bell
          Text {
            anchors.centerIn: parent
            visible: !notifImageWrapper.visible
            text: (root.notificationManager && root.notificationManager.currentGlyph.length > 0)
              ? root.notificationManager.currentGlyph
              : ((root.notificationManager && root.notificationManager.currentUrgency === 2) ? "󰀦" : "󰂚")
            font.family: root.iconFont
            font.pixelSize: 15
            color: (root.notificationManager && root.notificationManager.currentUrgency === 2)
              ? "#ff6b6b"
              : "#ffffff"
            renderType: Text.NativeRendering
          }
        }

        // 2. Center Column: Summary and Body with crisp high-contrast tone
        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: 1

          // Row 1: Headline
          Text {
            id: notifSummaryText
            Layout.fillWidth: true
            text: (root.notificationManager && root.notificationManager.currentSummary.length > 0)
              ? root.notificationManager.currentSummary
              : (root.notificationManager ? root.notificationManager.currentAppName : "Notification")
            font.family: root.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: (root.notificationManager && root.notificationManager.currentUrgency === 2)
              ? "#ff6b6b"
              : "#ffffff"
            elide: Text.ElideRight
            renderType: Text.NativeRendering
            maximumLineCount: 1
          }

          // Row 2: Message body details in clean readable high-contrast tone
          Text {
            id: notifBodyText
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.notificationManager ? root.notificationManager.currentBody : ""
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: Font.Normal
            color: Qt.rgba(1, 1, 1, 0.82)
            elide: Text.ElideRight
            renderType: Text.NativeRendering
            maximumLineCount: 1
          }
        }
      }

      // Tap card to execute default action / jump to sending window, right-click to dismiss
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            if (root.notificationManager) root.notificationManager.dismissCurrent()
          } else {
            if (root.notificationManager) root.notificationManager.invokeAction()
          }
        }
      }
    }

  }
}