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
//    - Row 5: Battery capsule (bottom-most row)
//  • Motion follows iOS fluid interfaces: every driver value is a spring that
//    carries velocity through interruption (FluidSpring), never a duration +
//    easing curve. Sliders track the finger 1:1 and only spring when the value
//    changes without a finger.
//  • Hovering Wi-Fi / Bluetooth blooms the matching status subpanel to the LEFT
//    of the card (network list, device list) — identical behaviour to the top
//    island's dropdown subpanel. Clicking pins it.
// ===========================================================================
Item {
  id: root

  // Injected so the panel shares the live wallpaper-extracted palette instead of
  // spinning up a private FrameConfig with default colours.
  required property var frameConfig

  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  readonly property var frame: frameConfig
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  property bool isOpen: false
  property bool hasOpenApps: false

  // Interaction state: hover blooms the menu, click pins it open
  property bool isHoverOpen: false
  property bool isPinned: false

  signal openRequested()
  signal closeRequested()

  readonly property bool isOpenEffective: root.isOpen || root.isHoverOpen || root.isPinned

  // The window owns the authoritative open state; if it drops (IPC close,
  // fullscreen entry), clear every local latch so nothing lingers open.
  onIsOpenChanged: {
    if (!root.isOpen) {
      root.isPinned = false
      root.isHoverOpen = false
      if (statusSubpanel) statusSubpanel.close()
    }
  }

  function open() {
    // Opening never pins: the panel follows the pointer, so leaving it for the
    // desktop dismisses it just like a hover-opened bloom.
    root.isHoverOpen = true
    root.openRequested()
    root.refreshAll()
    root.refreshStatus()
    root.refreshMotionPreference()
  }

  function close() {
    root.isPinned = false
    root.isHoverOpen = false
    root.closeSubpanel()
    root.closeRequested()
  }

  function closeSubpanel() {
    if (statusSubpanel) statusSubpanel.close()
  }

  function toggle() {
    if (root.isOpenEffective) root.close()
    else root.open()
  }

  // Grace period so the menu doesn't snap shut while the cursor crosses a gap
  Timer {
    id: hoverCloseTimer
    interval: 240
    repeat: false
    onTriggered: {
      var subpanelHovered = Boolean(statusSubpanel && statusSubpanel.isHovered)
      if (statusSubpanel && statusSubpanel.isOpen && !statusSubpanel.isPinned
          && !notchHover.hovered && !subpanelHovered) {
        statusSubpanel.isOpen = false
      }
      if (!root.isPinned && !root.isOpen && !notchHover.hovered && !subpanelHovered) {
        root.isHoverOpen = false
      }
    }
  }

  // Pointer watchdog -------------------------------------------------------
  // Hover-exit events are not guaranteed (fast warps, surface leaves, pointer
  // grabs), which used to leave the card or its subpanel stuck open. Poll the
  // real containment instead and retract once the pointer is truly gone.
  property bool pointerEngaged: true
  property int outsideTicks: 0

  function syncPointerWatchdog() {
    var subpanelHovered = Boolean(statusSubpanel && statusSubpanel.isHovered)
    var inside = notchHover.hovered || subpanelHovered
    if (inside) {
      root.pointerEngaged = true
      root.outsideTicks = 0
      return
    }
    if (!root.pointerEngaged || root.isPinned) return
    root.outsideTicks++
    // Two ticks (~360ms) of separation so a diagonal pass over the gap between
    // the card and the subpanel does not slam it shut.
    if (root.outsideTicks < 2) return
    root.outsideTicks = 0
    root.pointerEngaged = false
    root.close()
  }

  Timer {
    interval: 180
    repeat: true
    running: root.isOpenEffective
    onTriggered: root.syncPointerWatchdog()
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

  // Large surface: slower, heavier spring. Present ~0.42s at zeta 0.85 (0.6%
  // settle overshoot); dismiss ~0.34s critically damped so it never bounces on
  // the way back into the frame. Retargeting mid-flight keeps velocity.
  FluidSpring {
    id: bloomSpring
    target: root.targetProgress
    response: root.isOpenEffective ? 0.42 : 0.34
    dampingFraction: root.isOpenEffective ? 0.85 : 1.0
    epsilon: 0.0004
    reduceMotion: root.reduceMotion
  }

  readonly property real openProgress: bloomSpring.value

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
  property alias statusPanel: statusSubpanel
  readonly property Item subpanelMaskItem: (statusSubpanel && (statusSubpanel.isOpen || statusSubpanel.openProgress > 0.01)) ? statusSubpanel.maskItem : null

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
    connectedCount: 0,
    devices: []
  })

  property var batteryData: ({
    present: false,
    capacity: 0,
    charging: false,
    plugged: false
  })

  property bool isRescanningWifi: false
  property double lastBtScan: 0
  property string debugTab: ""

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
            if (data.battery) root.batteryData = data.battery
            root.isRescanningWifi = false
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

  function rescanWifi() {
    root.isRescanningWifi = true
    runStatusAction(["--rescan-wifi"])
  }

  function connectWifi(ssid) {
    if (!ssid) return
    runStatusAction(["--connect-wifi", ssid])
  }

  function connectBluetooth(mac) {
    if (!mac) return
    runStatusAction(["--connect-bt", mac])
  }

  function disconnectBluetooth(mac) {
    if (!mac) return
    runStatusAction(["--disconnect-bt", mac])
  }

  // -------------------------------------------------------------------------
  // Status subpanel bloom (Wi-Fi / Bluetooth) — mirrors the top island
  // -------------------------------------------------------------------------
  function showStatusTab(tab) {
    if (!statusSubpanel) return
    statusSubpanel.openTab(tab)
    root.refreshStatus()
    // Bluetooth needs active discovery running to surface nearby devices that
    // were never paired, so kick a scan whenever the panel is summoned. Rate
    // limited because the hover sync re-enters this on every pointer move.
    if (tab === "bluetooth" && !statusActionProc.running && root.btData.enabled
        && (Date.now() - root.lastBtScan) > 15000) {
      root.lastBtScan = Date.now()
      root.runStatusAction(["--scan-bt"])
    }
  }

  function togglePinStatusTab(tab) {
    if (!statusSubpanel) return
    if (statusSubpanel.isPinned && statusSubpanel.activeTab === tab) {
      statusSubpanel.close()
    } else {
      statusSubpanel.openTab(tab)
      statusSubpanel.isPinned = true
    }
  }

  // Hit-test the pointer against the status buttons directly. The per-button
  // MouseAreas only refresh `containsMouse` on real pointer motion, so a fast
  // entry into the card can land on a button without ever activating it.
  // Mapping the handler point keeps the bloom reliable for every entry path.
  function syncStatusTabFromPointer() {
    if (!cardProbe || !cardProbe.hovered) return
    var sp = cardProbe.point.scenePosition
    var wp = btnWifi.mapFromItem(null, sp.x, sp.y)
    var bp = btnBluetooth.mapFromItem(null, sp.x, sp.y)

    if (wp.x >= 0 && wp.x <= btnWifi.width && wp.y >= 0 && wp.y <= btnWifi.height) {
      showStatusTab("wifi")
      return
    }
    if (bp.x >= 0 && bp.x <= btnBluetooth.width && bp.y >= 0 && bp.y <= btnBluetooth.height) {
      showStatusTab("bluetooth")
      return
    }

    // Pointer is inside the card but no longer on the status buttons: let the
    // bloom retract instead of lingering behind the cursor. The hot zone is
    // padded towards the subpanel side so travelling from a button into the
    // subpanel never trips the close.
    var cp = statusColumn.mapFromItem(null, sp.x, sp.y)
    var inHotZone = cp.x >= -48 && cp.x <= statusColumn.width + 6
      && cp.y >= -10 && cp.y <= statusColumn.height + 10
    if (!inHotZone) closeStatusTab()
  }

  function closeStatusTab() {
    if (!statusSubpanel || statusSubpanel.isPinned) return
    if (statusSubpanel.isOpen) statusSubpanel.isOpen = false
  }

  function debugStatus(tab) {
    root.isPinned = false
    root.showStatusTab(tab)
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

  // Reduced motion: keep direct manipulation, drop the bounce. Hyprland owns
  // the global animation switch, so read it on startup and whenever the menu
  // is summoned (never on a timer — this panel stays cheap when idle).
  property bool reduceMotion: false

  Process {
    id: motionPreferenceProc
    command: ["hyprctl", "getoption", "animations:enabled"]
    stdout: SplitParser {
      onRead: function(line) {
        // hyprctl prints "bool: true" / "bool: false" (older builds: "int: 1").
        var str = String(line || "").toLowerCase()
        if (str.indexOf("false") >= 0 || str.indexOf("int: 0") >= 0) root.reduceMotion = true
        else if (str.indexOf("true") >= 0 || str.indexOf("int: 1") >= 0) root.reduceMotion = false
      }
    }
  }

  function refreshMotionPreference() {
    if (!motionPreferenceProc.running) motionPreferenceProc.running = true
  }

  Component.onCompleted: {
    root.refreshAll()
    root.refreshMotionPreference()
  }

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

  onIsOpenEffectiveChanged: {
    if (root.isOpenEffective) {
      root.refreshAll()
      root.refreshStatus()
    } else {
      root.closeSubpanel()
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

  function getBatteryIcon() {
    if (!root.batteryData || !root.batteryData.present) return "󰂑"
    var cap = root.batteryData.capacity || 0
    if (root.batteryData.charging) return cap >= 95 ? "󰂅" : "󰂄"
    if (cap >= 90) return "󰁹"
    if (cap >= 70) return "󰂀"
    if (cap >= 50) return "󰁿"
    if (cap >= 30) return "󰁾"
    if (cap >= 15) return "󰁻"
    return "󰁺"
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

  readonly property bool isCornerActive: cornerTriggerHover.hovered
    || (notchHover && notchHover.hovered)
    || Boolean(statusSubpanel && (statusSubpanel.isOpen || statusSubpanel.isHovered || statusSubpanel.isPinned))
    || root.isOpenEffective

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

    // Retracting is a settle (critically damped); waking back out gets a little
    // momentum. Both springs keep their velocity if a wake lands mid-retract.
    FluidSpring {
      id: retractYSpring
      target: notchContainer.targetRetractY
      response: root.shouldRetract ? 0.28 : 0.36
      dampingFraction: root.shouldRetract ? 1.0 : 0.8
      epsilon: 0.05
      reduceMotion: root.reduceMotion
    }

    FluidSpring {
      id: retractXSpring
      target: notchContainer.targetRetractX
      response: root.shouldRetract ? 0.28 : 0.36
      dampingFraction: root.shouldRetract ? 1.0 : 0.8
      epsilon: 0.05
      reduceMotion: root.reduceMotion
    }

    readonly property real currentRetractY: retractYSpring.value
    readonly property real currentRetractX: retractXSpring.value

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
          hoverCloseTimer.stop()
          root.isHoverOpen = true
          root.refreshAll()
          root.refreshStatus()
        } else {
          hoverCloseTimer.restart()
        }
      }
    }

    // Tactile press feedback: appears on touch-down (0.18s, critically damped,
    // no bounce) and pops back with a flickable release spring.
    property bool isGussetPressed: restingTapHandler.pressed

    FluidSpring {
      id: gussetPressSpring
      target: (!root.isOpenEffective && notchContainer.isGussetPressed) ? 0.96 : 1.0
      response: notchContainer.isGussetPressed ? 0.18 : 0.30
      dampingFraction: notchContainer.isGussetPressed ? 1.0 : 0.78
      epsilon: 0.0004
      reduceMotion: root.reduceMotion
      value: 1.0
    }

    scale: gussetPressSpring.value
    transformOrigin: Item.BottomRight

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
          if (root.isOpenEffective) root.close()
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

      HoverHandler {
        id: cardProbe
        onHoveredChanged: root.syncStatusTabFromPointer()
        onPointChanged: root.syncStatusTabFromPointer()
      }

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
            id: statusColumn
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

              // Press lands on touch-down, hover is a slow idle lift.
              FluidSpring {
                id: wifiPressSpring
                target: btnWifi.isPressed ? 0.90 : (wifiArea.containsMouse ? 1.08 : 1.0)
                response: btnWifi.isPressed ? 0.18 : 0.30
                dampingFraction: btnWifi.isPressed ? 1.0 : 0.78
                epsilon: 0.0004
                reduceMotion: root.reduceMotion
                value: 1.0
              }

              color: isActive
                ? frameConfig.powerButtonActiveBg
                : (wifiArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
              scale: wifiPressSpring.value

              Behavior on color { ColorAnimation { duration: 180 } }

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
                onContainsMouseChanged: if (containsMouse) root.showStatusTab("wifi")
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

              FluidSpring {
                id: btPressSpring
                target: btnBluetooth.isPressed ? 0.90 : (btArea.containsMouse ? 1.08 : 1.0)
                response: btnBluetooth.isPressed ? 0.18 : 0.30
                dampingFraction: btnBluetooth.isPressed ? 1.0 : 0.78
                epsilon: 0.0004
                reduceMotion: root.reduceMotion
                value: 1.0
              }

              color: isActive
                ? frameConfig.powerButtonActiveBg
                : (btArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
              scale: btPressSpring.value

              Behavior on color { ColorAnimation { duration: 180 } }

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
                onContainsMouseChanged: if (containsMouse) root.showStatusTab("bluetooth")
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

              // Press feedback: instant on touch-down, springs back on release.
              FluidSpring {
                id: brightPressSpring
                target: brightArea.pressed ? 0.98 : 1.0
                response: brightArea.pressed ? 0.18 : 0.30
                dampingFraction: brightArea.pressed ? 1.0 : 0.78
                epsilon: 0.0004
                reduceMotion: root.reduceMotion
                value: 1.0
              }

              scale: brightPressSpring.value

              // Fill driver. While the finger is down this tracks 1:1 (no
              // smoothing, no lag); any change that happens without a finger
              // (media keys, system sync) glides in on a spring.
              FluidSpring {
                id: brightFillSpring
                target: root.brightnessFraction
                tracking: brightArea.pressed
                response: 0.36
                dampingFraction: 0.80
                epsilon: 0.0004
                reduceMotion: root.reduceMotion
                value: root.brightnessFraction
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
                width: Math.max(0, parent.width * brightFillSpring.value)
                clip: true
                visible: brightFillSpring.value > 0.002 && width > 0.5

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

              FluidSpring {
                id: volPressSpring
                target: volArea.pressed ? 0.98 : 1.0
                response: volArea.pressed ? 0.18 : 0.30
                dampingFraction: volArea.pressed ? 1.0 : 0.78
                epsilon: 0.0004
                reduceMotion: root.reduceMotion
                value: 1.0
              }

              scale: volPressSpring.value

              Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: frameConfig.sliderTrackColor
              }

              // Fill driver: 1:1 under the finger, spring for every value the
              // system pushes in (volume keys, pamixer sync).
              FluidSpring {
                id: volFillSpring
                target: root.volumeFraction
                tracking: volArea.pressed
                response: 0.36
                dampingFraction: 0.80
                epsilon: 0.0004
                reduceMotion: root.reduceMotion
                value: root.volumeFraction
              }

              Item {
                id: volFillContainer
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, parent.width * volFillSpring.value)
                clip: true
                visible: volFillSpring.value > 0.002 && width > 0.5

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

            FluidSpring {
              id: lpPressSpring
              target: lpArea.pressed ? 0.90 : (lpArea.containsMouse ? 1.08 : 1.0)
              response: lpArea.pressed ? 0.18 : 0.30
              dampingFraction: lpArea.pressed ? 1.0 : 0.78
              epsilon: 0.0004
              reduceMotion: root.reduceMotion
              value: 1.0
            }

            color: isActive
              ? frameConfig.powerButtonActiveBg
              : (lpArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
            scale: lpPressSpring.value

            Behavior on color { ColorAnimation { duration: 180 } }

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

            FluidSpring {
              id: balPressSpring
              target: balArea.pressed ? 0.90 : (balArea.containsMouse ? 1.08 : 1.0)
              response: balArea.pressed ? 0.18 : 0.30
              dampingFraction: balArea.pressed ? 1.0 : 0.78
              epsilon: 0.0004
              reduceMotion: root.reduceMotion
              value: 1.0
            }

            color: isActive
              ? frameConfig.powerButtonActiveBg
              : (balArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
            scale: balPressSpring.value

            Behavior on color { ColorAnimation { duration: 180 } }

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

            FluidSpring {
              id: perfPressSpring
              target: perfArea.pressed ? 0.90 : (perfArea.containsMouse ? 1.08 : 1.0)
              response: perfArea.pressed ? 0.18 : 0.30
              dampingFraction: perfArea.pressed ? 1.0 : 0.78
              epsilon: 0.0004
              reduceMotion: root.reduceMotion
              value: 1.0
            }

            color: isActive
              ? frameConfig.powerButtonActiveBg
              : (perfArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : frameConfig.powerButtonInactiveBg)
            scale: perfPressSpring.value

            Behavior on color { ColorAnimation { duration: 180 } }

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

        // Row 5: Battery capsule (bottom-most row)
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 14

          // Battery capsule (icon + charge percentage)
          Rectangle {
            id: batteryCapsule
            width: frameConfig.controlBatteryRowWidth
            height: frameConfig.controlButtonSize
            radius: height / 2
            color: frameConfig.sliderTrackColor

            Row {
              anchors.centerIn: parent
              spacing: 8

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.getBatteryIcon()
                font.family: root.iconFont
                font.pixelSize: 20
                color: root.batteryData.present && root.batteryData.charging
                  ? frameConfig.powerButtonActiveIcon
                  : frameConfig.powerButtonInactiveIcon
                renderType: Text.NativeRendering
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.batteryData.present
                text: root.batteryData.capacity + "%"
                font.family: "Adwaita Sans, Inter, sans-serif"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: frameConfig.powerButtonInactiveIcon
                renderType: Text.NativeRendering
              }
            }
          }
        }
      }
    }
  }

  // =========================================================================
  // Status Subpanel: blooms LEFTWARDS out of the control card (unibody, flush)
  // =========================================================================
  ControlCenterSubpanel {
    id: statusSubpanel
    frameConfig: root.frameConfig
    notchColor: root.notchColor
    borderThickness: root.borderThickness
    fontFamily: root.fontFamily
    anchors.right: notchContainer.left
    // Overlap the card's own flare inset so the subpanel's contact edge lands
    // exactly on the visible left edge of the open card (seamless unibody).
    anchors.rightMargin: -frameConfig.controlExpandedFlareRadius
    anchors.verticalCenter: notchContainer.verticalCenter

    wifiData: root.wifiData
    btData: root.btData
    isRescanningWifi: root.isRescanningWifi
    reduceMotion: root.reduceMotion

    onToggleWifiRequested: root.toggleWifi()
    onRescanWifiRequested: root.rescanWifi()
    onConnectWifiRequested: function(ssid) { root.connectWifi(ssid) }
    onToggleBluetoothRequested: root.toggleBluetooth()
    onConnectBluetoothRequested: function(mac) { root.connectBluetooth(mac) }
    onDisconnectBluetoothRequested: function(mac) { root.disconnectBluetooth(mac) }
  }

  // Re-arm the grace timer when the pointer leaves the subpanel
  Connections {
    target: statusSubpanel
    function onIsHoveredChanged() {
      if (!statusSubpanel.isHovered) hoverCloseTimer.restart()
    }
  }
}
