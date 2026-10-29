import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  // Injected configuration & styling
  required property var frameConfig
  property int borderThickness: frameConfig ? frameConfig.borderThickness : 5
  property color notchColor: frameConfig ? frameConfig.activeBorderColor : "#ba5f58"
  property color textColor: frameConfig ? frameConfig.activeTextColor : "#ffffff"
  property color mutedColor: frameConfig ? frameConfig.mutedColor : Qt.rgba(1, 1, 1, 0.6)
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  property bool hasOpenApps: false

  // Injected host & plugin registry handles
  property var shell: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var barConfig: ({})
  property var parentWindow: null

  // Geometries matching Dynamic Island
  readonly property real baseHeight: frameConfig ? frameConfig.trayNotchBaseHeight : 37
  readonly property real topCurveRadius: frameConfig ? frameConfig.trayNotchTopCurveRadius : 10
  readonly property real bottomCornerRadius: frameConfig ? frameConfig.trayNotchBottomCornerRadius : 15
  readonly property real itemSize: 26
  readonly property real itemRadius: 7
  readonly property real itemSpacing: 6
  readonly property real sidePadding: 12

  // Mask and wake items exposed to PanelWindow
  property alias maskItem: activeRegionItem
  property alias wakeItem: edgeTriggerItem

  // -------------------------------------------------------------------------
  // 1. Whimsy Plugin Integration
  // -------------------------------------------------------------------------
  Process {
    id: whimsyIpcProc
    command: ["sh", "-c", "omarchy-shell whimsy toggle || omarchy-shell shell togglePopout whimsy 2>/dev/null"]
  }

  function toggleWhimsy() {
    if (whimsyLoader.item && typeof whimsyLoader.item.togglePanel === "function") {
      whimsyLoader.item.togglePanel()
    } else {
      whimsyIpcProc.running = true
    }
  }

  QtObject {
    id: pluginBarFacade
    property color foreground: root.textColor
    property color barForeground: root.textColor
    property color background: root.notchColor
    property color urgent: Commons.Color ? Commons.Color.urgent : "#ff5555"
    property string fontFamily: root.fontFamily
    property string position: "top"
    property bool vertical: false
    property int barSize: Math.ceil(root.baseHeight)
    property bool transparent: false
    property var shell: root.shell
    property bool foregroundAnimationEnabled: true
    property var activePopout: null
    property var clickTargets: []
    property var layoutConfig: (root.barConfig && root.barConfig.layout) ? root.barConfig.layout : ({})

    function registerClickTarget(target) {
      if (!target) return
      if (clickTargets.indexOf(target) === -1) {
        var copy = clickTargets.slice()
        copy.push(target)
        clickTargets = copy
      }
    }

    function unregisterClickTarget(target) {
      if (!target) return
      var idx = clickTargets.indexOf(target)
      if (idx !== -1) {
        var copy = clickTargets.slice()
        copy.splice(idx, 1)
        clickTargets = copy
      }
    }

    function targetBelongsToWindow(target, window) {
      if (!target || !window) return false
      return target.QsWindow && target.QsWindow.window === window
    }

    function switchPanelFrom(owner, direction) {
      return false
    }

    function requestPopout(owner) {
      if (activePopout === owner) return
      if (activePopout) {
        if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
        else if ("close" in activePopout) activePopout.close()
      }
      activePopout = owner
    }

    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }

    function run(cmd) {
      if (!cmd) return
      Commons.Util.execDetached(cmd)
    }
    function showTooltip(tgt, txt) {}
    function hideTooltip(tgt) {}
  }

  // -------------------------------------------------------------------------
  // 2. Global Microphone Mute / Unmute Controller
  // -------------------------------------------------------------------------
  property bool micMuted: false

  Process {
    id: micProbe
    command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED && echo 1 || echo 0"]
    stdout: StdioCollector {
      onStreamFinished: {
        var val = String(text || "").trim()
        root.micMuted = (val === "1")
      }
    }
  }

  function syncMic() {
    if (!micProbe.running) micProbe.running = true
  }

  Process {
    id: micToggleProc
    command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]
    onExited: {
      root.syncMic()
    }
  }

  function toggleGlobalMic() {
    root.micMuted = !root.micMuted // Optimistic instantaneous feedback
    micToggleProc.running = true
  }

  // -------------------------------------------------------------------------
  // 3. Background Apps (Discord, Steam, Scratchpad Clients)
  // -------------------------------------------------------------------------
  property var backgroundApps: []

  Process {
    id: bgAppsProbe
    command: ["sh", "-c", "hyprctl clients -j 2>/dev/null | jq -c '[.[] | select((.workspace.name | startswith(\"special\")) or .hidden == true or (.workspace.id < 0)) | {address: .address, class: .class, title: .title, pid: .pid}]' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        var str = String(text || "").trim()
        if (str && str.startsWith("[")) {
          try {
            var rawApps = JSON.parse(str)
            var deduplicated = []
            for (var a = 0; a < rawApps.length; a++) {
              var cls = String(rawApps[a].class || "").toLowerCase()
              var inTray = false
              for (var t = 0; t < root.trayList.length; t++) {
                var tid = String(root.trayList[t].id || "").toLowerCase()
                var ttitle = String(root.trayList[t].title || "").toLowerCase()
                if ((cls.indexOf("steam") !== -1 && (tid.indexOf("steam") !== -1 || ttitle.indexOf("steam") !== -1)) ||
                    (cls.indexOf("discord") !== -1 && (tid.indexOf("discord") !== -1 || ttitle.indexOf("discord") !== -1))) {
                  inTray = true
                  break
                }
              }
              if (!inTray) deduplicated.push(rawApps[a])
            }
            root.backgroundApps = deduplicated
          } catch(e) {
            root.backgroundApps = []
          }
        } else {
          root.backgroundApps = []
        }
      }
    }
    onExited: {
      if (root.bgAppsSyncPending) root.syncBackgroundApps()
    }
  }

  property bool bgAppsSyncPending: false

  function syncBackgroundApps() {
    if (bgAppsProbe.running) {
      root.bgAppsSyncPending = true
      return
    }
    root.bgAppsSyncPending = false
    bgAppsProbe.running = true
  }

  Process {
    id: appFocusProc
  }

  function activateBackgroundApp(app) {
    if (!app) return
    var addr = String(app.address || "")
    if (addr) {
      appFocusProc.exec(["hyprctl", "dispatch", "hl.dsp.focus({ window = 'address:" + addr + "' })"])
    } else {
      appFocusProc.exec(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special('scratchpad')"])
    }
  }

  // -------------------------------------------------------------------------
  // 4. Background Services & Native SystemTray Apps
  // -------------------------------------------------------------------------
  // Discovers background applets (Hermes Agents, Tailscale)
  function fetchBackgroundApplets() {
    var list = []
    if (!barWidgetRegistry || !barWidgetRegistry.widgets) return list
    var w = barWidgetRegistry.widgets

    if (w["omarchy.agents"] && w["omarchy.agents"].component) {
      list.push({ id: "omarchy.agents", title: "Hermes Agents", component: w["omarchy.agents"].component })
    }
    if (w["omarchy.tailscale"] && w["omarchy.tailscale"].component) {
      list.push({ id: "omarchy.tailscale", title: "Tailscale", component: w["omarchy.tailscale"].component })
    }
    return list
  }

  property var backgroundApplets: fetchBackgroundApplets()

  // Live DBus SystemTray (StatusNotifierItem)
  function fetchTrayItems() {
    var raw = (SystemTray && SystemTray.items && SystemTray.items.values) ? SystemTray.items.values : []
    var list = []
    for (var i = 0; i < raw.length; i++) {
      var item = raw[i]
      if (!item) continue
      if (item.status === Status.Passive) continue
      var idStr = String(item.id || "").toLowerCase()
      if (idStr.indexOf("localsend") !== -1) continue
      list.push(item)
    }
    return list
  }

  property var trayList: fetchTrayItems()

  // Reactive listeners & heartbeat
  Connections {
    target: (SystemTray && SystemTray.items) ? SystemTray.items : null
    function onValuesChanged() {
      root.trayList = root.fetchTrayItems()
    }
  }

  // Coalesces Hyprland event bursts into at most one client probe per window
  Timer {
    id: bgAppsThrottle
    interval: 200
    repeat: false
    onTriggered: root.syncBackgroundApps()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!bgAppsThrottle.running) bgAppsThrottle.start()
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: {
      root.syncMic()
      root.syncBackgroundApps()
      root.trayList = root.fetchTrayItems()
    }
  }

  Component.onCompleted: {
    root.syncMic()
    root.syncBackgroundApps()
  }

  // -------------------------------------------------------------------------
  // Dynamic Width Calculation
  // -------------------------------------------------------------------------
  readonly property int bgAppCount: backgroundApps.length
  readonly property int appletCount: backgroundApplets.length
  readonly property int trayCount: trayList.length
  readonly property int totalBgCount: bgAppCount + appletCount + trayCount

  readonly property real pluginWidth: root.itemSize // Whimsy button
  readonly property real micWidth: root.itemSize     // Global Mic button
  readonly property real dividerWidth: 8            // 1px separator + padding
  readonly property real bgSectionWidth: totalBgCount > 0
    ? (totalBgCount * root.itemSize + (totalBgCount - 1) * root.itemSpacing)
    : 0

  readonly property real targetNotchWidth: (root.sidePadding * 2)
    + (root.topCurveRadius * 2)
    + pluginWidth
    + dividerWidth
    + micWidth
    + (totalBgCount > 0 ? (dividerWidth + bgSectionWidth) : 0)

  property real animatedWidth: targetNotchWidth
  Behavior on animatedWidth {
    NumberAnimation {
      duration: 260
      easing.type: Easing.OutCubic
    }
  }

  // -------------------------------------------------------------------------
  // iOS Fluid Motion Reveal / Retract Physics
  // -------------------------------------------------------------------------
  readonly property bool isPointerOver: notchHover.hovered || edgeTriggerHover.hovered

  readonly property real targetReveal: (!root.hasOpenApps || root.isPointerOver) ? 1.0 : 0.0
  property real revealProgress: targetReveal

  Behavior on revealProgress {
    NumberAnimation {
      duration: (!root.hasOpenApps || root.isPointerOver) ? 340 : 280
      easing.type: (!root.hasOpenApps || root.isPointerOver) ? Easing.OutBack : Easing.OutCubic
      easing.overshoot: (!root.hasOpenApps || root.isPointerOver) ? 1.08 : 1.0
    }
  }

  // Smooth sinusoidal liquid volume pulse during reveal
  readonly property real currentHeight: root.borderThickness
    + (revealProgress * (root.baseHeight - root.borderThickness))
    + (Math.sin(Math.min(1.0, Math.max(0.0, revealProgress)) * Math.PI) * 4.0)

  // Dynamic G1 curvature adaptation as notch reveals
  readonly property real effectiveFlare: Math.min(root.topCurveRadius, Math.max(0, (currentHeight - root.borderThickness) * 0.35))
  readonly property real effectiveCorner: Math.min(root.bottomCornerRadius, Math.max(0, (currentHeight - root.borderThickness) - effectiveFlare))

  // Thin edge wake trigger strip right on top border
  Item {
    id: edgeTriggerItem
    anchors.top: parent.top
    anchors.horizontalCenter: notchContainer.horizontalCenter
    width: notchContainer.width
    height: root.borderThickness + 14

    HoverHandler {
      id: edgeTriggerHover
    }
  }

  // Hitmask region following notchContainer exactly
  Item {
    id: activeRegionItem
    anchors.top: notchContainer.top
    anchors.horizontalCenter: notchContainer.horizontalCenter
    width: notchContainer.width + 10
    height: notchContainer.height
  }

  // Main Notch Container
  Item {
    id: notchContainer
    anchors.top: parent.top
    anchors.right: parent.right
    width: root.animatedWidth
    height: root.currentHeight
    transformOrigin: Item.Top

    HoverHandler {
      id: notchHover
      cursorShape: Qt.ArrowCursor
    }

    // -----------------------------------------------------------------------
    // Pure Dynamic Island OLED Silhouette (Exact Match with DynamicIsland.qml)
    // -----------------------------------------------------------------------
    Shape {
      id: notchShape
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      readonly property real w: notchContainer.width
      readonly property real h: notchContainer.height
      readonly property real rTop: root.effectiveFlare
      readonly property real rBot: root.effectiveCorner
      readonly property real b: root.borderThickness

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: root.notchColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        // Start at top-left flare edge flush against screen top edge
        startX: 0
        startY: -2.0

        // Top horizontal line to top-right screen edge
        PathLine {
          x: notchShape.w
          y: -2.0
        }

        // Down to top border line
        PathLine {
          x: notchShape.w
          y: notchShape.b
        }

        // Top-right flare curving into pill side
        PathCubic {
          x: notchShape.w - notchShape.rTop
          y: notchShape.b + notchShape.rTop
          control1X: notchShape.w - (notchShape.rTop * 0.5)
          control1Y: notchShape.b
          control2X: notchShape.w - notchShape.rTop
          control2Y: notchShape.b + (notchShape.rTop * 0.5)
        }

        // Right vertical side down to bottom arc
        PathLine {
          x: notchShape.w - notchShape.rTop
          y: Math.max(notchShape.b + notchShape.rTop, notchShape.h - notchShape.rBot)
        }

        // Bottom-right convex arc
        PathArc {
          x: notchShape.w - notchShape.rTop - notchShape.rBot
          y: notchShape.h
          radiusX: Math.max(1, notchShape.rBot)
          radiusY: Math.max(1, notchShape.rBot)
          direction: PathArc.Clockwise
        }

        // Bottom horizontal edge
        PathLine {
          x: notchShape.rTop + notchShape.rBot
          y: notchShape.h
        }

        // Bottom-left convex arc
        PathArc {
          x: notchShape.rTop
          y: Math.max(notchShape.b + notchShape.rTop, notchShape.h - notchShape.rBot)
          radiusX: Math.max(1, notchShape.rBot)
          radiusY: Math.max(1, notchShape.rBot)
          direction: PathArc.Clockwise
        }

        // Left vertical side up to left flare
        PathLine {
          x: notchShape.rTop
          y: notchShape.b + notchShape.rTop
        }

        // Top-left flare curving out to border line
        PathCubic {
          x: 0
          y: notchShape.b
          control1X: notchShape.rTop
          control1Y: notchShape.b + (notchShape.rTop * 0.5)
          control2X: notchShape.rTop * 0.5
          control2Y: notchShape.b
        }

        // Line back to start
        PathLine {
          x: 0
          y: -2.0
        }
      }
    }

    // -----------------------------------------------------------------------
    // Content Layout: Whimsy Plugin | Global Mic Mute | Background Apps
    // -----------------------------------------------------------------------
    Row {
      id: contentRow
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: root.borderThickness / 2
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 6
      opacity: Math.max(0.0, (root.revealProgress - 0.35) / 0.65)
      visible: opacity > 0

      // SECTION 1: Whimsy Desktop Widgets Plugin Button
      Item {
        id: whimsyBtn
        width: root.itemSize
        height: root.itemSize
        anchors.verticalCenter: parent.verticalCenter

        Loader {
          id: whimsyLoader
          anchors.fill: parent
          active: true
          source: Quickshell.env("HOME") + "/.config/omarchy/plugins/whimsy/BarWidget.qml"
          visible: true
          opacity: 0
          onLoaded: {
            if (item) {
              if ("bar" in item) item.bar = pluginBarFacade
              if ("moduleName" in item) item.moduleName = "whimsy"
              if ("settings" in item) item.settings = {}
            }
          }
        }

        property bool isHovered: whimsyHover.hovered
        property bool isPressed: whimsyMouse.pressed

        scale: isPressed ? 0.92 : 1.0
        Behavior on scale {
          NumberAnimation {
            duration: whimsyBtn.isPressed ? 110 : 220
            easing.type: whimsyBtn.isPressed ? Easing.OutQuad : Easing.OutBack
            easing.overshoot: 1.15
          }
        }

        Rectangle {
          anchors.fill: parent
          radius: root.itemRadius
          color: whimsyBtn.isHovered ? Qt.rgba(255, 255, 255, 0.16) : "transparent"
          Behavior on color { ColorAnimation { duration: 150 } }
        }

        Text {
          anchors.centerIn: parent
          text: "\u{F056E}"
          font.family: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"
          font.pixelSize: 14
          color: whimsyBtn.isHovered ? root.textColor : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.88)
        }

        HoverHandler {
          id: whimsyHover
          cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
          id: whimsyMouse
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.toggleWhimsy()
          }
        }
      }

      // SECTION 2: Divider
      Rectangle {
        id: separator1
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 12
        radius: 0.5
        color: Qt.rgba(255, 255, 255, 0.22)
      }

      // SECTION 3: Global Microphone Mute / Unmute Button
      Item {
        id: micBtn
        width: root.itemSize
        height: root.itemSize
        anchors.verticalCenter: parent.verticalCenter

        property bool isHovered: micHover.hovered
        property bool isPressed: micMouse.pressed

        scale: isPressed ? 0.92 : 1.0
        Behavior on scale {
          NumberAnimation {
            duration: micBtn.isPressed ? 110 : 220
            easing.type: micBtn.isPressed ? Easing.OutQuad : Easing.OutBack
            easing.overshoot: 1.15
          }
        }

        Rectangle {
          anchors.fill: parent
          radius: root.itemRadius
          color: root.micMuted
            ? Qt.rgba(1.0, 0.35, 0.35, micBtn.isHovered ? 0.35 : 0.22)
            : (micBtn.isHovered ? Qt.rgba(255, 255, 255, 0.16) : "transparent")
          Behavior on color { ColorAnimation { duration: 150 } }
        }

        Text {
          anchors.centerIn: parent
          text: root.micMuted ? "\uf131" : "\uf130"
          font.family: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"
          font.pixelSize: 14
          color: root.micMuted ? "#ff7878" : (micBtn.isHovered ? root.textColor : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.90))
        }

        HoverHandler {
          id: micHover
          cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
          id: micMouse
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.toggleGlobalMic()
          }
        }
      }

      // SECTION 4: Divider before Background Apps (if any exist)
      Rectangle {
        id: separator2
        visible: root.totalBgCount > 0
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 12
        radius: 0.5
        color: Qt.rgba(255, 255, 255, 0.22)
      }

      // SECTION 5: Background Apps (Discord, Steam, Tailscale, Agents, SystemTray)
      Row {
        id: bgAppsRow
        visible: root.totalBgCount > 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.itemSpacing

        // Hyprland Background & Scratchpad Apps (Discord, Steam, etc.)
        Repeater {
          model: root.backgroundApps

          delegate: Item {
            id: bgClientSlot
            required property var modelData
            width: root.itemSize
            height: root.itemSize
            anchors.verticalCenter: parent.verticalCenter

            readonly property string appClass: String(modelData.class || "").toLowerCase()
            readonly property bool isDiscord: appClass.indexOf("discord") !== -1
            readonly property bool isSteam: appClass.indexOf("steam") !== -1
            readonly property bool isSpotify: appClass.indexOf("spotify") !== -1

            property bool isHovered: clientMouse.containsMouse
            property bool isPressed: clientMouse.pressed

            scale: isPressed ? 0.92 : 1.0
            Behavior on scale {
              NumberAnimation {
                duration: bgClientSlot.isPressed ? 110 : 220
                easing.type: bgClientSlot.isPressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: 1.15
              }
            }

            Rectangle {
              anchors.fill: parent
              radius: root.itemRadius
              color: bgClientSlot.isHovered ? Qt.rgba(255, 255, 255, 0.16) : "transparent"
              Behavior on color { ColorAnimation { duration: 150 } }
            }

            // High-res icon / NerdFont glyph
            Text {
              anchors.centerIn: parent
              visible: bgClientSlot.isDiscord || bgClientSlot.isSteam || bgClientSlot.isSpotify
              text: bgClientSlot.isDiscord ? "\uF392" : (bgClientSlot.isSteam ? "\uF1B6" : "\uF1BC")
              font.family: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"
              font.pixelSize: 14
              color: bgClientSlot.isHovered ? root.textColor : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.92)
            }

            IconImage {
              anchors.centerIn: parent
              visible: !bgClientSlot.isDiscord && !bgClientSlot.isSteam && !bgClientSlot.isSpotify
              width: 14
              height: 14
              source: "image://icon/" + bgClientSlot.modelData.class
            }

            MouseArea {
              id: clientMouse
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                root.activateBackgroundApp(bgClientSlot.modelData)
              }
            }
          }
        }

        // Background Applets (Hermes Agents, Tailscale)
        Repeater {
          model: root.backgroundApplets

          delegate: Item {
            id: appletSlot
            required property var modelData
            width: root.itemSize
            height: root.itemSize
            anchors.verticalCenter: parent.verticalCenter

            Loader {
              anchors.fill: parent
              sourceComponent: appletSlot.modelData.component
              onLoaded: {
                if (item) {
                  if ("bar" in item) item.bar = pluginBarFacade
                  if ("moduleName" in item) item.moduleName = appletSlot.modelData.id
                  if ("settings" in item) item.settings = {}
                }
              }
            }
          }
        }

        // Live SNI System Tray Items
        Repeater {
          model: root.trayList

          delegate: Item {
            id: traySlot
            required property var modelData
            width: root.itemSize
            height: root.itemSize
            anchors.verticalCenter: parent.verticalCenter

            property bool isHovered: itemMouse.containsMouse
            property bool isPressed: itemMouse.pressed

            scale: isPressed ? 0.92 : 1.0
            Behavior on scale {
              NumberAnimation {
                duration: traySlot.isPressed ? 110 : 220
                easing.type: traySlot.isPressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: 1.15
              }
            }

            Rectangle {
              anchors.fill: parent
              radius: root.itemRadius
              color: traySlot.isHovered ? Qt.rgba(255, 255, 255, 0.16) : "transparent"
              Behavior on color { ColorAnimation { duration: 150 } }
            }

            IconImage {
              id: trayIcon
              anchors.centerIn: parent
              width: 14
              height: 14
              source: String(traySlot.modelData.icon || "")
            }

            Text {
              anchors.centerIn: parent
              visible: trayIcon.status !== Image.Ready
              text: (traySlot.modelData.title && traySlot.modelData.title.length > 0)
                ? traySlot.modelData.title.charAt(0).toUpperCase()
                : "\uf02d"
              font.family: root.fontFamily
              font.pixelSize: 10
              font.bold: true
              color: root.textColor
            }

            MouseArea {
              id: itemMouse
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor

              onPressed: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  root.openItemMenu(traySlot.modelData, traySlot, mouse)
                  mouse.accepted = true
                }
              }

              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  mouse.accepted = true
                } else if (mouse.button === Qt.MiddleButton) {
                  traySlot.modelData.secondaryActivate()
                } else if (traySlot.modelData.onlyMenu) {
                  root.openItemMenu(traySlot.modelData, traySlot, mouse)
                } else {
                  traySlot.modelData.activate()
                }
              }

              onWheel: function(wheel) {
                traySlot.modelData.scroll(wheel.angleDelta.y, false)
              }
            }
          }
        }
      }
    }

    // -----------------------------------------------------------------------
  } // ends notchContainer

  // -------------------------------------------------------------------------
  // Interactive Tray Popup Menu Summoning & Native Opener (Root Scope)
  // -------------------------------------------------------------------------
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  property bool trayMenuOpen: false
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // Prevents accidental re-click on whichever entry lands under the cursor
  // after a submenu level change (same guard as omarchy's Tray.qml).
  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    root.menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    root.menuLevelSettling = false
    menuLevelSettleTimer.stop()
    trayMenuFlick.contentY = 0
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) {
      if (openers[i] && openers[i].opener) openers[i].opener.destroy()
    }
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    trayMenuFlick.contentY = 0
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    root.settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    trayMenuFlick.contentY = 0
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    if (top && top.opener) top.opener.destroy()
    root.settleMenuLevel()
  }

  function close() {
    root.trayMenuOpen = false
    root.resetTrayMenu()
  }

  function openItemMenu(item, anchor, mouse) {
    if (!item) return
    if (!item.menu) {
      // Items without a D-Bus menu use display() (requires UseQApplication —
      // silently no-ops in standard omarchy shell, same behaviour as Tray.qml)
      var win = anchor && anchor.QsWindow ? anchor.QsWindow.window : null
      if (!win) win = root.parentWindow
      if (win && typeof item.display === "function") {
        var point = (anchor.QsWindow && anchor.QsWindow.contentItem)
          ? anchor.QsWindow.contentItem.mapFromItem(anchor, mouse.x, mouse.y)
          : anchor.mapToItem(null, mouse.x, mouse.y)
        item.display(win, Math.round(point.x), Math.round(point.y))
      }
      return
    }
    // Reset before switching items so the old root's children are torn down
    // before trayMenuOpener.menu binding fires (avoids stale children flash).
    root.resetTrayMenu()
    root.activeTrayItem = item
    root.activeTrayAnchor = anchor
    root.trayMenuOpen = true
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  PopupCard {
    id: trayMenuPopup
    anchorItem: root.activeTrayAnchor || notchContainer
    owner: root
    bar: pluginBarFacade
    open: root.trayMenuOpen
    padding: 6
    contentWidth: 200
    contentHeight: Math.min(360, (root.submenuDepth > 0 ? 32 : 0) + trayMenuColumn.implicitHeight + 16)

    onVisibleChanged: {
      if (!visible) root.resetTrayMenu()
    }

    Column {
      id: trayMenuLayout
      anchors.fill: parent
      spacing: 0

      // Submenu back header
      Item {
        id: menuHeader
        visible: root.submenuDepth > 0
        width: trayMenuLayout.width
        implicitHeight: visible ? 28 : 0

        Rectangle {
          anchors.fill: parent
          radius: 5
          color: headerMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : "transparent"
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 6
          text: "‹ " + root.currentTitle
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
          font.bold: true
          elide: Text.ElideRight
        }

        MouseArea {
          id: headerMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.menuLevelSettling) return
            trayMenuFlick.contentY = 0
            root.leaveSubmenu()
          }
        }
      }

      Flickable {
        id: trayMenuFlick
        width: trayMenuLayout.width
        height: trayMenuLayout.height - (menuHeader.visible ? menuHeader.implicitHeight : 0)
        contentWidth: width
        contentHeight: trayMenuColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: trayMenuColumn
          width: trayMenuFlick.width
          spacing: 2

          Repeater {
            model: root.currentChildren

            delegate: Item {
              id: menuRow
              required property var modelData
              required property int index
              readonly property string rowText: String(modelData.text || "")
              visible: !modelData.isSeparator || index > 0
              width: trayMenuColumn.width
              implicitHeight: modelData.isSeparator ? 8 : 26
              opacity: modelData.enabled ? 1.0 : 0.45

              Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.centerIn: parent
                width: parent.width - 12
                height: 1
                color: Qt.rgba(255, 255, 255, 0.15)
              }

              Rectangle {
                visible: !menuRow.modelData.isSeparator
                anchors.fill: parent
                radius: 5
                color: rowMouse.containsMouse && menuRow.modelData.enabled ? Qt.rgba(255, 255, 255, 0.12) : "transparent"
              }

              Text {
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 6
                width: 14
                text: menuRow.modelData.checkState === Qt.Checked ? "✓" : ""
                color: root.textColor
                font.pixelSize: 11
              }

              Text {
                visible: !menuRow.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.right: menuRow.modelData.hasChildren ? submenuIndicator.left : parent.right
                anchors.rightMargin: 6
                text: menuRow.rowText
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
              }

              Text {
                id: submenuIndicator
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 8
                text: "›"
                color: root.textColor
                font.pixelSize: 12
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: menuRow.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.menuLevelSettling) return
                  if (!menuRow.modelData.enabled) return
                  if (menuRow.modelData.hasChildren) {
                    trayMenuFlick.contentY = 0
                    root.enterSubmenu(menuRow.modelData, menuRow.rowText)
                  } else {
                    menuRow.modelData.triggered()
                    root.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
