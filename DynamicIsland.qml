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
  property var timerManager: null

  readonly property bool isTimerRunning: Boolean(timerManager && timerManager.active)
  readonly property bool hasBothMediaAndTimer: Boolean(root.hasActualMedia && root.isTimerRunning)

  readonly property var availablePages: {
    var pages = []
    if (root.inCall) pages.push("call")
    if (root.hasActualMedia) pages.push("media")
    pages.push("timer")
    return pages
  }
  property int activePageIndex: 0
  readonly property string currentPageType: {
    var p = availablePages
    if (activePageIndex >= 0 && activePageIndex < p.length) return p[activePageIndex]
    return p[0] || "timer"
  }

  onInCallChanged: {
    if (root.inCall) root.activePageIndex = 0
  }

  onHasActualMediaChanged: {
    if (root.hasActualMedia && !root.inCall) {
      root.activePageIndex = 0
    }
  }

  onIsTimerRunningChanged: {
    if (root.isTimerRunning && !root.inCall && !root.hasActualMedia) {
      root.activePageIndex = 0
    }
  }

  readonly property bool hasNotification: Boolean(notificationManager && notificationManager.hasNotification)
  property real notificationProgress: hasNotification ? 1.0 : 0.0

  // -------------------------------------------------------------------------
  // Persist a notification's sender picture so repeat messages / calls can reuse it
  function saveAvatar(img) {
    var nm = root.notificationManager
    if (!nm || !nm.avatarDir || String(img.source).indexOf("image://") !== 0) return
    var key = nm.senderKey(nm.currentAppName, nm.currentSummary)
    var path = nm.avatarDir + "/" + key + ".png"
    Quickshell.execDetached(["sh", "-c", "mkdir -p -m 700 \"$1\" && chmod 700 \"$1\"", "sh", nm.avatarDir])
    img.grabToImage(function(result) {
      if (result.saveToFile(path)) {
        var m = nm.savedAvatars
        m[key] = path
        nm.savedAvatars = m
      }
    }, Qt.size(96, 96))
  }

  // Active Voice Call Engine (Discord, WhatsApp, Telegram, WebRTC)
  // -------------------------------------------------------------------------
  property bool inCall: false
  property string callApp: ""
  property string callCaller: ""
  property string callAvatar: ""
  // Call view yields the island to an incoming notification, then returns
  readonly property bool callShowing: inCall && !hasNotification

  Process {
    id: callStatusProc
    command: [decodeURIComponent(Qt.resolvedUrl("lumania-call-status").toString().replace(/^file:\/\//, ""))]
    stdout: StdioCollector {
      onStreamFinished: {
        var str = String(text || "").trim()
        if (str.length > 0) {
          try {
            var data = JSON.parse(str)
            root.inCall = Boolean(data.inCall)
            root.callApp = String(data.app || "")
            root.callCaller = String(data.caller || "")
            root.callAvatar = String(data.avatar || "")
          } catch(e) {}
        }
      }
    }
  }

  Timer {
    id: callPollTimer
    interval: root.inCall ? 3000 : 3500
    running: true
    repeat: true
    onTriggered: {
      if (!callStatusProc.running) callStatusProc.running = true
    }
  }

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
    root.refreshStickyPlayer()
    if (!callStatusProc.running) callStatusProc.running = true
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.updateClock()
  }

  // -------------------------------------------------------------------------
  // Media artwork resolution (Spotify/MPRIS cover art + YouTube thumbnails)
  // -------------------------------------------------------------------------
  // Extracts the 11-char video id from any YouTube URL shape
  // (watch?v=, youtu.be/, shorts/, embed/, live/, music.youtube.com).
  function youTubeIdFrom(url) {
    var s = String(url || "")
    if (s.length === 0) return ""
    var m = s.match(/[?&]v=([A-Za-z0-9_-]{6,})/)
    if (m) return m[1]
    m = s.match(/youtu\.be\/([A-Za-z0-9_-]{6,})/)
    if (m) return m[1]
    m = s.match(/youtube\.com\/(?:shorts|embed|live|v)\/([A-Za-z0-9_-]{6,})/)
    if (m) return m[1]
    return ""
  }

  // Cover art for the active player:
  // 1. the player's own MPRIS artwork (Spotify, local players, data: URIs),
  // 2. a YouTube page URL converted into its native thumbnail,
  // 3. nothing (the notch falls back to a music glyph).
  function resolveMediaArt(p) {
    if (!p) return ""
    var art = String(p.trackArtUrl || "").trim()

    // Some browsers publish the page URL as "artwork": map it to the real thumbnail
    var ytId = root.youTubeIdFrom(art)
    if (ytId.length > 0) return "https://i.ytimg.com/vi/" + ytId + "/hqdefault.jpg"
    if (art.length > 0) return art

    // Browsers that expose no artwork still expose the media/page URL
    var meta = p.metadata || ({})
    var pageUrl = String(meta["xesam:url"] || "")
    ytId = root.youTubeIdFrom(pageUrl)
    if (ytId.length > 0) return "https://i.ytimg.com/vi/" + ytId + "/hqdefault.jpg"

    return ""
  }

  // -------------------------------------------------------------
  // MPRIS Media Detection & Track Capability Evaluation
  // Excludes voice calls (Discord, WhatsApp, Zoom, Teams, WebRTC)
  // -------------------------------------------------------------
  function isCallOrComm(p) {
    if (!p) return false
    var id = String(p.identity || "").toLowerCase()
    var dbus = String(p.dbusName || "").toLowerCase()
    var title = String(p.trackTitle || "").toLowerCase()
    var artist = String(p.trackArtist || "").toLowerCase()
    if (id.indexOf("discord") !== -1 || dbus.indexOf("discord") !== -1 ||
        id.indexOf("whatsapp") !== -1 || dbus.indexOf("whatsapp") !== -1 ||
        id.indexOf("telegram") !== -1 || dbus.indexOf("telegram") !== -1 ||
        id.indexOf("slack") !== -1 || dbus.indexOf("slack") !== -1 ||
        id.indexOf("zoom") !== -1 || dbus.indexOf("zoom") !== -1 ||
        id.indexOf("teams") !== -1 || dbus.indexOf("teams") !== -1 ||
        id.indexOf("skype") !== -1 || dbus.indexOf("skype") !== -1 ||
        id.indexOf("webrtc") !== -1 || dbus.indexOf("webrtc") !== -1) {
      return true
    }
    return false
  }

  // -------------------------------------------------------------------------
  // Sticky player selection
  // The player the user last started (or resumed) keeps the island controls even
  // while it is paused. Without this, a second player still playing in the
  // background (e.g. Spotify) steals the Play button and resumes the wrong app.
  // -------------------------------------------------------------------------
  property string stickyPlayerName: ""

  function playerKey(p) {
    return p ? String(p.dbusName || p.identity || "") : ""
  }

  function findStickyPlayer(players) {
    if (root.stickyPlayerName.length === 0) return null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (p && !root.isCallOrComm(p) && root.playerKey(p) === root.stickyPlayerName) {
        if (p.playbackStatus === "Stopped") return null
        return p
      }
    }
    return null
  }

  // Drops a stale sticky reference and adopts a playing player when none is set
  function refreshStickyPlayer() {
    var players = Mpris.players ? Mpris.players.values : []
    if (root.stickyPlayerName.length > 0 && root.findStickyPlayer(players)) return
    root.stickyPlayerName = ""
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (p && p.isPlaying && !root.isCallOrComm(p)) {
        root.stickyPlayerName = root.playerKey(p)
        return
      }
    }
  }

  function getActivePlayer() {
    var players = Mpris.players ? Mpris.players.values : []
    // 0. The player the user actually started or resumed keeps the controls (including while paused)
    var sticky = root.findStickyPlayer(players)
    if (sticky && (sticky.trackTitle || sticky.trackArtist || sticky.canGoNext || sticky.canGoPrevious)) {
      return sticky
    }
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
    // Never fall back to cold/idle players with leftover metadata when nothing is playing!
    // This guarantees that on startup or when no media app was opened, no buttons are shown.
    return null
  }

  readonly property var activePlayer: getActivePlayer()

  // Actual media is active only when an authentic music/video player is playing or in a paused state with track data
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
      function onIsPlayingChanged() {
        // Whoever just started playing becomes the sticky target of the island
        if (modelData && modelData.isPlaying) root.stickyPlayerName = root.playerKey(modelData)
        root.activePlayerChanged()
      }
      function onTrackTitleChanged() { root.activePlayerChanged() }
      function onTrackArtUrlChanged() { root.activePlayerChanged() }
      function onMetadataChanged() { root.activePlayerChanged() }
      function onCanGoNextChanged() { root.activePlayerChanged() }
      function onCanGoPreviousChanged() { root.activePlayerChanged() }
    }
  }

  Connections {
    target: Mpris.players
    function onValuesChanged() {
      root.refreshStickyPlayer()
      root.activePlayerChanged()
    }
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

    // The island morphs open on hover to expose media controls, active timer, or quick presets
    readonly property bool isHovered: isPointerOver && root.notificationProgress < 0.01
    readonly property real targetHoverProgress: isHovered ? 1.0 : 0.0
    property real hoverProgress: targetHoverProgress

    // Auto-retract inward when apps are opened; springs down immediately when cursor touches top edge
    // or when an active notification is received ("come in show the notif and then move out")
    // NEVER retracts while a call is active, a track is actively playing, or a countdown timer is running!
    readonly property bool shouldRetract: root.hasOpenApps
      && !isPointerOver
      && !root.hasNotification
      && !root.inCall
      && !dynamicView.mprisPlaying
      && !root.isTimerRunning
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

    // iOS Fluid Motion driver value: 0.0 (Clock View) -> 1.0 (Audio Waveform / cover art)
    readonly property bool isMediaActive: Boolean(root.hasActualMedia && dynamicView.showVisualizer)
    readonly property real targetProgress: isMediaActive ? 1.0 : 0.0
    property real transitionProgress: targetProgress

    Behavior on transitionProgress {
      NumberAnimation {
        duration: islandContainer.isMediaActive ? 380 : 240
        easing.type: islandContainer.isMediaActive ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: islandContainer.isMediaActive ? 1.15 : 1.0
      }
    }

    // Dynamic Radii adapting with hover or notification expansion for organic squircle continuity
    readonly property real activeExpansionProgress: Math.max(hoverProgress, root.notificationProgress)

    readonly property real currentTopRadius: root.topCurveRadius
      + (activeExpansionProgress * (root.frameConfig.islandExpandedTopCurveRadius - root.topCurveRadius))
    readonly property real currentBottomRadius: root.bottomCornerRadius
      + (activeExpansionProgress * (root.frameConfig.islandExpandedBottomCornerRadius - root.bottomCornerRadius))

    // Height expansion delta: sleek (+24px down to 61px, +6px when multi-activities to give bottom dots breathing room)
    readonly property real activeHoverHeightDelta: root.frameConfig.islandHoverHeightDeltaMedia + (root.availablePages.length > 1 ? 6 : 0)

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

    // Authentic iOS liquid stretch: pure continuous spring function (zero discontinuous steps)
    readonly property real baseWidth: root.callShowing ? 206 : root.islandWidth
    readonly property real normalWidth: baseWidth
      + (hoverProgress * root.frameConfig.islandHoverWidthDelta)
      + (root.notificationProgress * animatedNotifWidthDelta)
      + (Math.sin(Math.min(1.0, Math.max(0.0, transitionProgress)) * Math.PI) * 8.0)
      + (Math.sin(Math.min(1.0, Math.max(0.0, hoverProgress)) * Math.PI) * 6.0)
      + (Math.sin(Math.min(1.0, Math.max(0.0, root.notificationProgress)) * Math.PI) * 10.0)

    width: normalWidth

    // Height expands downwards on hover (+42px idle, +24px media/timer/call) or notification (+18px)
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

    // Scroll wheel flips between available activities (Call, Media, Timer)
    WheelHandler {
      id: islandWheel
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      enabled: islandContainer.isHovered && root.availablePages.length > 1
      onWheel: function(event) {
        if (event.angleDelta.y < 0) {
          root.activePageIndex = Math.min(root.availablePages.length - 1, root.activePageIndex + 1)
        } else if (event.angleDelta.y > 0) {
          root.activePageIndex = Math.max(0, root.activePageIndex - 1)
        }
      }
    }

    TapHandler {
      id: tapHandler
      enabled: !islandContainer.isHovered && !root.hasActualMedia && !root.isTimerRunning && !root.inCall && root.notificationProgress < 0.01
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

      // Transitions out when audio starts, when in call, when hovered/opened, when timer is running, or when notification is active
      opacity: (!root.inCall && !islandContainer.isHovered && islandContainer.hoverProgress < 0.02 && root.notificationProgress < 0.01 && !root.isTimerRunning)
        ? Math.max(0.0, 1.0 - islandContainer.transitionProgress * 2.2)
        : 0.0
      scale: Math.max(0.82, 1.0 - islandContainer.transitionProgress * 0.16)
      visible: opacity > 0.01 && !root.inCall && !islandContainer.isHovered && islandContainer.hoverProgress < 0.02 && root.notificationProgress < 0.01 && !root.isTimerRunning
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
    // Content Layer 1B: Collapsed Timer View (Icon, Countdown, Optional Label)
    // Shown when timer is running and no audio/media is active.
    // =========================================================================
    Row {
      id: collapsedTimerRow
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -5.0 * islandContainer.transitionProgress
      spacing: 7

      opacity: (!root.inCall && !islandContainer.isHovered && islandContainer.hoverProgress < 0.02 && root.notificationProgress < 0.01 && !dynamicView.showVisualizer && root.isTimerRunning)
        ? 1.0
        : 0.0
      scale: opacity > 0.01 ? 1.0 : 0.85
      visible: opacity > 0.01 && !root.inCall && !islandContainer.isHovered && islandContainer.hoverProgress < 0.02 && root.notificationProgress < 0.01 && !dynamicView.showVisualizer && root.isTimerRunning
      transformOrigin: Item.Center

      Behavior on opacity {
        NumberAnimation { duration: 140 }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰔛"
        font.family: root.iconFont
        font.pixelSize: 13
        color: (root.timerManager && root.timerManager.paused) ? root.islandMutedColor : root.islandTextColor
        renderType: Text.NativeRendering
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.timerManager ? root.timerManager.formattedTime : ""
        color: (root.timerManager && root.timerManager.paused) ? root.islandMutedColor : root.islandTextColor
        font.family: "JetBrainsMono Nerd Font, monospace"
        font.pixelSize: 13
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
        verticalAlignment: Text.AlignVCenter
      }

      Rectangle {
        visible: Boolean(root.timerManager && root.timerManager.label)
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: 3
        radius: 1.5
        color: Qt.rgba(root.islandTextColor.r, root.islandTextColor.g, root.islandTextColor.b, 0.35)
      }

      Text {
        visible: Boolean(root.timerManager && root.timerManager.label)
        anchors.verticalCenter: parent.verticalCenter
        text: root.timerManager ? root.timerManager.label : ""
        color: root.islandMutedColor
        font.family: root.fontFamily
        font.pixelSize: 11
        font.weight: Font.Medium
        renderType: Text.NativeRendering
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: 1
        elide: Text.ElideRight
      }
    }

    // =========================================================================
    // Content Layer 2: Adaptive Audio Visualizer (Multi-Color Gradient Waveform)
    // Active when video/song or audio stream is playing. Hidden when opened.
    // =========================================================================
    DynamicWorkspaceView {
      id: dynamicView
      anchors.fill: parent
      artUrl: (root.hasActualMedia && root.activePlayer) ? root.resolveMediaArt(root.activePlayer) : ""

      opacity: (!root.inCall && !islandContainer.isHovered && islandContainer.hoverProgress < 0.02 && root.notificationProgress < 0.01)
        ? Math.min(1.0, Math.max(0.0, (islandContainer.transitionProgress - 0.25) * 1.33))
        : 0.0
      scale: 0.82 + (0.18 * islandContainer.transitionProgress)
      y: 4.0 * (1.0 - islandContainer.transitionProgress)
      visible: opacity > 0.01 && !root.inCall && !islandContainer.isHovered && islandContainer.hoverProgress < 0.02 && root.notificationProgress < 0.01
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
      anchors.verticalCenterOffset: root.availablePages.length > 1 ? (root.borderThickness * 0.5 - 2) : (root.borderThickness * 0.5)
      spacing: 18

      readonly property bool mediaPageActive: root.currentPageType === "media"
      opacity: (islandContainer.hoverProgress > 0.15 && root.hasActualMedia && root.notificationProgress < 0.01 && mediaPageActive)
        ? Math.min(1.0, (islandContainer.hoverProgress - 0.15) * 1.35)
        : 0.0
      scale: 0.88 + (0.12 * islandContainer.hoverProgress)
      visible: opacity > 0.01 && root.hasActualMedia && root.notificationProgress < 0.01
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
            var p = root.activePlayer
            if (!p) return
            if (p.canGoPrevious || p.canControl) p.previous()
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
            var p = root.activePlayer
            if (!p) return
            // Explicit play/pause by state is the only reliable path on MPRIS players that
            // implement Pause but refuse Resume through PlayPause (Spotify).
            if (p.isPlaying) {
              if (p.canPause) p.pause()
              else if (p.canTogglePlaying) p.togglePlaying()
            } else {
              if (p.canPlay) p.play()
              else if (p.canTogglePlaying) p.togglePlaying()
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
            var p = root.activePlayer
            if (!p) return
            if (p.canGoNext || p.canControl) p.next()
          }
        }
      }
    }

    // =========================================================================
    // Content Layer 3B: Opened Dynamic Island Timer Controls
    // Play/Pause on Left, Countdown Time in Center, Cancel on Right End
    // Sleek Progress Bar spanning Left to Right across the notch
    // =========================================================================
    // =========================================================================
    // Content Layer 3B: Opened Dynamic Island Timer Controls
    // Time Left on Left, Sleek Progress Bar in Center, Cross on Right
    // =========================================================================
    Row {
      id: timerControlsRow
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.availablePages.length > 1 ? (root.borderThickness * 0.5 - 3) : (root.borderThickness * 0.5)
      spacing: 10

      readonly property bool timerPageActive: root.currentPageType === "timer"
      opacity: (islandContainer.hoverProgress > 0.15 && root.isTimerRunning && root.notificationProgress < 0.01 && timerPageActive)
        ? Math.min(1.0, (islandContainer.hoverProgress - 0.15) * 1.35)
        : 0.0
      scale: 0.88 + (0.12 * islandContainer.hoverProgress)
      visible: opacity > 0.01 && root.isTimerRunning && root.notificationProgress < 0.01
      transformOrigin: Item.Center

      // 1. Time Left (Clean Mono digits, no extra text)
      Text {
        id: timerDigitsText
        anchors.verticalCenter: parent.verticalCenter
        text: root.timerManager ? root.timerManager.formattedTime : "00:00"
        color: "#ffffff"
        font.family: "JetBrainsMono Nerd Font, monospace"
        font.pixelSize: 15
        font.weight: Font.Bold
        renderType: Text.NativeRendering
      }

      // 2. Sleek Progress Bar (Crisp solid fill from left to right)
      Rectangle {
        id: timerProgressBarTrack
        width: 130
        height: 6
        radius: 3
        color: Qt.rgba(1, 1, 1, 0.20)
        anchors.verticalCenter: parent.verticalCenter
        clip: true

        Rectangle {
          id: timerProgressBarFill
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Math.max(0, Math.min(parent.width, parent.width * (root.timerManager ? root.timerManager.progress : 0.0)))
          radius: 3
          color: root.frameConfig.powerButtonActiveBg

          Behavior on width {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
          }
        }
      }

      // 3. Cross (Cancel) on Right of Progress Bar
      Rectangle {
        id: btnTimerCancel
        width: 30
        height: 30
        radius: 15
        anchors.verticalCenter: parent.verticalCenter
        color: cancelArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : root.frameConfig.powerButtonInactiveBg
        scale: cancelArea.pressed ? 0.90 : (cancelArea.containsMouse ? 1.08 : 1.0)

        Behavior on scale {
          NumberAnimation {
            duration: 120
            easing.type: Easing.OutBack
            easing.overshoot: 1.15
          }
        }
        Behavior on color { ColorAnimation { duration: 180 } }

        Text {
          anchors.centerIn: parent
          text: "󰅖"
          font.family: root.iconFont
          font.pixelSize: 14
          color: root.frameConfig.powerButtonInactiveIcon
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: cancelArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.timerManager) root.timerManager.cancel()
          }
        }
      }
    }

    // =========================================================================
    // Content Layer 3C: One-Tap Quick Timer Presets (Page 1 when no timer is active)
    // Compact: 5m, 15m, 25m (Pomodoro), 45m
    // =========================================================================
    Row {
      id: timerPresetsRow
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.availablePages.length > 1 ? (root.borderThickness * 0.5 - 3) : (root.borderThickness * 0.5)
      spacing: 8

      readonly property bool timerPageActive: root.currentPageType === "timer"
      opacity: (islandContainer.hoverProgress > 0.15 && !root.isTimerRunning && root.notificationProgress < 0.01 && timerPageActive)
        ? Math.min(1.0, (islandContainer.hoverProgress - 0.15) * 1.35)
        : 0.0
      scale: 0.88 + (0.12 * islandContainer.hoverProgress)
      visible: opacity > 0.01 && !root.isTimerRunning && root.notificationProgress < 0.01
      transformOrigin: Item.Center

      // Icon Disc
      Rectangle {
        width: 32
        height: 32
        radius: 16
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(1, 1, 1, 0.12)

        Text {
          anchors.centerIn: parent
          text: "󰔛"
          font.family: root.iconFont
          font.pixelSize: 15
          color: root.frameConfig.powerButtonActiveBg
          renderType: Text.NativeRendering
        }
      }

      // 5m Preset
      Rectangle {
        width: 44
        height: 32
        radius: 16
        anchors.verticalCenter: parent.verticalCenter
        color: p5Area.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : root.frameConfig.powerButtonInactiveBg
        scale: p5Area.pressed ? 0.90 : (p5Area.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
        Behavior on color { ColorAnimation { duration: 160 } }

        Text {
          anchors.centerIn: parent
          text: "5m"
          font.family: root.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
          color: root.islandTextColor
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: p5Area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.timerManager) root.timerManager.start(5 * 60, "5m")
        }
      }

      // 15m Preset
      Rectangle {
        width: 48
        height: 32
        radius: 16
        anchors.verticalCenter: parent.verticalCenter
        color: p15Area.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : root.frameConfig.powerButtonInactiveBg
        scale: p15Area.pressed ? 0.90 : (p15Area.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
        Behavior on color { ColorAnimation { duration: 160 } }

        Text {
          anchors.centerIn: parent
          text: "15m"
          font.family: root.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
          color: root.islandTextColor
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: p15Area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.timerManager) root.timerManager.start(15 * 60, "15m")
        }
      }

      // 25m Preset (Pomodoro hero accent)
      Rectangle {
        width: 50
        height: 32
        radius: 16
        anchors.verticalCenter: parent.verticalCenter
        color: p25Area.containsMouse ? Qt.rgba(1, 1, 1, 0.32) : root.frameConfig.powerButtonActiveBg
        scale: p25Area.pressed ? 0.90 : (p25Area.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
        Behavior on color { ColorAnimation { duration: 160 } }

        Text {
          anchors.centerIn: parent
          text: "25m"
          font.family: root.fontFamily
          font.pixelSize: 12
          font.weight: Font.Bold
          color: root.frameConfig.powerButtonActiveIcon
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: p25Area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.timerManager) root.timerManager.start(25 * 60, "Pomodoro")
        }
      }

      // 45m Preset
      Rectangle {
        width: 48
        height: 32
        radius: 16
        anchors.verticalCenter: parent.verticalCenter
        color: p45Area.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : root.frameConfig.powerButtonInactiveBg
        scale: p45Area.pressed ? 0.90 : (p45Area.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
        Behavior on color { ColorAnimation { duration: 160 } }

        Text {
          anchors.centerIn: parent
          text: "45m"
          font.family: root.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
          color: root.islandTextColor
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: p45Area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.timerManager) root.timerManager.start(45 * 60, "Focus")
        }
      }
    }

    // =========================================================================
    // Multi-Activity Pagination Capsule Dots (Call • / Media • / Timer •)
    // Visible on hover whenever multiple activities are available to flip between
    // =========================================================================
    Row {
      id: multiActivityPagination
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 4
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 4
      visible: islandContainer.hoverProgress > 0.3 && root.availablePages.length > 1 && root.notificationProgress < 0.01
      opacity: islandContainer.hoverProgress

      Repeater {
        model: root.availablePages.length
        delegate: Rectangle {
          required property int index
          width: root.activePageIndex === index ? 10 : 3
          height: 3
          radius: 1.5
          color: root.activePageIndex === index ? root.islandTextColor : Qt.rgba(root.islandTextColor.r, root.islandTextColor.g, root.islandTextColor.b, 0.35)
          Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 160 } }

          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activePageIndex = index
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
            color: Qt.rgba(1, 1, 1, 0.16)
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
              onStatusChanged: if (status === Image.Ready) root.saveAvatar(notifImg)
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
            color: "#ffffff"
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
            textFormat: Text.PlainText // untrusted external text: never parse as markup
            id: notifSummaryText
            Layout.fillWidth: true
            text: (root.notificationManager && root.notificationManager.currentSummary.length > 0)
              ? root.notificationManager.currentSummary
              : (root.notificationManager ? root.notificationManager.currentAppName : "Notification")
            font.family: root.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: "#ffffff"
            elide: Text.ElideRight
            renderType: Text.NativeRendering
            maximumLineCount: 1
          }

          // Row 2: Message body details in clean readable high-contrast tone
          Text {
            textFormat: Text.PlainText // untrusted external text: never parse as markup
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

    // =========================================================================
    // Content Layer 5: Active Call View (PFP on left, Name & Waveform in center, Red Cut on right)
    // =========================================================================
    Row {
      id: callContentRow
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.availablePages.length > 1 ? (root.borderThickness * 0.5 - 2) : (root.borderThickness / 2)
      spacing: islandContainer.isHovered ? 14 : 12
      readonly property bool callPageActive: root.callShowing && (!islandContainer.isHovered || root.currentPageType === "call")
      opacity: callPageActive ? (islandContainer.isHovered ? Math.min(1.0, (islandContainer.hoverProgress - 0.15) * 1.35) : 1.0) : 0.0
      visible: opacity > 0.01

      Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }

      // Left: Profile Picture (PFP) with circular clipping and active call indicator
      Item {
        width: islandContainer.isHovered ? 34 : 24
        height: width
        anchors.verticalCenter: parent.verticalCenter

        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: Qt.rgba(255, 255, 255, 0.16)
        }

        Image {
          id: callAvatarImg
          anchors.fill: parent
          source: (root.callAvatar && root.callAvatar.length > 0) ? ("file://" + root.callAvatar) : ""
          fillMode: Image.PreserveAspectCrop
          mipmap: true
          smooth: true
          visible: status === Image.Ready
          cache: false
          layer.enabled: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: callAvatarMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.5
          }
        }

        Item {
          id: callAvatarMask
          anchors.fill: parent
          visible: false
          layer.enabled: true
          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
          }
        }

        // Fallback icon if no pfp image is found
        Text {
          anchors.centerIn: parent
          visible: callAvatarImg.status !== Image.Ready
          text: root.callApp === "discord" ? "\uF392" : (root.callApp === "whatsapp" ? "\uF232" : "\uF095")
          font.family: root.iconFont
          font.pixelSize: islandContainer.isHovered ? 16 : 13
          color: "#ffffff"
        }

        // Green active call dot
        Rectangle {
          width: islandContainer.isHovered ? 9 : 7
          height: width
          radius: width / 2
          color: "#23a55a"
          border.color: root.islandColor
          border.width: 1.5
          anchors.bottom: parent.bottom
          anchors.right: parent.right
        }
      }

      // Center: Name & Waveform in expanded view
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        visible: islandContainer.isHovered

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.callCaller ? root.callCaller : (root.callApp ? (root.callApp.charAt(0).toUpperCase() + root.callApp.slice(1) + " Call") : "Voice Call")
          color: "#ffffff"
          font.family: root.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
          renderType: Text.NativeRendering
          maximumLineCount: 1
          elide: Text.ElideRight
        }

        MediaWaveform {
          anchors.horizontalCenter: parent.horizontalCenter
          active: root.inCall
          barCount: 14
          barWidth: 3.0
          barSpacing: 3.0
          maxHeight: 12
          minHeight: 2.0
        }
      }

      // Center: Waveform in resting view
      MediaWaveform {
        id: callWaveform
        anchors.verticalCenter: parent.verticalCenter
        visible: !islandContainer.isHovered
        active: root.inCall
        barCount: 16
        barWidth: 3.0
        barSpacing: 3.0
        maxHeight: 16
        minHeight: 2.0
      }

      // Right: Tactile End / Cut Call Button (Red Hero Button when expanded)
      Rectangle {
        id: cutBtn
        width: islandContainer.isHovered ? 34 : 24
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: islandContainer.isHovered ? (cutHover.hovered ? "#f44336" : "#e53935") : "transparent"

        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        Behavior on color { ColorAnimation { duration: 150 } }

        scale: cutTap.pressed ? 0.90 : (cutHover.hovered ? 1.08 : 1.0)
        Behavior on scale {
          NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
        }

        Text {
          anchors.centerIn: parent
          text: "\u{F03F6}" // nf-md-phone_hangup
          font.family: root.iconFont
          font.pixelSize: islandContainer.isHovered ? 16 : 20
          color: "#ffffff"
          renderType: Text.NativeRendering
        }

        HoverHandler {
          id: cutHover
          cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
          id: cutTap
          onTapped: {
            Quickshell.execDetached([decodeURIComponent(Qt.resolvedUrl("lumania-call-cut").toString().replace(/^file:\/\//, ""))])
            root.inCall = false
          }
        }
      }
    }

  }
}