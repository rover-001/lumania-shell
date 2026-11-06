import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons as Commons

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

  // Downwise 1-Column Notch Geometry (anchored on LEFT border in top-left, a little lower)
  readonly property real topMargin: frameConfig ? frameConfig.workspaceTopMargin : 68
  readonly property int workspaceCount: getWorkspacesList().length
  readonly property real targetWidth: frameConfig ? frameConfig.workspaceWidth : 61
  // Horizontal breathing room kept on both sides of the workspace pills
  readonly property real sidePadding: frameConfig ? frameConfig.workspaceSidePadding : 12

  // Rail item geometry (iOS squircle rail)
  readonly property real itemSize: frameConfig ? frameConfig.workspaceItemSize : 32
  readonly property real itemRadius: frameConfig ? frameConfig.workspaceItemRadius : 10
  readonly property real itemSpacing: frameConfig ? frameConfig.workspaceItemSpacing : 12
  readonly property real railPadding: frameConfig ? frameConfig.workspaceRailPadding : 14

  readonly property real baseHeight: frameConfig ? frameConfig.workspaceHeight : 216
  // Rail always keeps its top/bottom padding, growing only if more slots exist
  readonly property real railContentHeight: workspaceCount * itemSize
    + Math.max(0, workspaceCount - 1) * itemSpacing + railPadding * 2
  readonly property real targetHeight: Math.max(baseHeight, railContentHeight)

  readonly property real flareRadius: frameConfig ? frameConfig.workspaceFlareRadius : 8
  readonly property real cornerRadius: frameConfig ? frameConfig.workspaceCornerRadius : 16

  // Hover & interaction state
  readonly property bool isHovered: Boolean(notchHover && notchHover.hovered) || Boolean(edgeTriggerHover && edgeTriggerHover.hovered)

  // When apps are opened, retract inwards flush with the left border (protrusion = 0).
  // When cursor moves to top-left edge OR on empty workspace, spring out immediately!
  // Retracts at the exact same speed as the top Dynamic Island notch goes away (280ms settle).
  readonly property real targetReveal: (!root.hasOpenApps || root.isHovered) ? 1.0 : 0.0
  property real revealProgress: targetReveal

  Behavior on revealProgress {
    NumberAnimation {
      duration: (!root.hasOpenApps || root.isHovered)
        ? (root.frameConfig ? root.frameConfig.workspaceOpenDuration : 340)
        : (root.frameConfig ? root.frameConfig.workspaceCloseDuration : 280)
      easing.type: (!root.hasOpenApps || root.isHovered) ? Easing.OutBack : Easing.OutCubic
      easing.overshoot: (!root.hasOpenApps || root.isHovered)
        ? (root.frameConfig ? root.frameConfig.workspaceOpenOvershoot : 1.08)
        : 1.0
    }
  }

  // Authentic iOS liquid stretch:
  // Downwise notch blooms rightward from left border with sinusoidal liquid volume pulse
  readonly property real currentWidth: root.borderThickness
    + (revealProgress * (root.targetWidth - root.borderThickness))
    + (Math.sin(Math.min(1.0, Math.max(0.0, revealProgress)) * Math.PI) * 5.0)

  readonly property real currentHeight: root.targetHeight

  // Mask item exposed to PanelWindow
  property alias maskItem: activeRegionItem

  // -------------------------------------------------------------
  // Workspace State & Synchronization
  // -------------------------------------------------------------
  property int activeWorkspaceId: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id !== undefined)
    ? Hyprland.focusedWorkspace.id
    : 1
  property string activeWorkspaceName: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.name)
    ? String(Hyprland.focusedWorkspace.name)
    : "1"

  function updateWorkspaceState() {
    if (Hyprland.focusedWorkspace) {
      if (Hyprland.focusedWorkspace.id !== undefined) {
        root.activeWorkspaceId = Hyprland.focusedWorkspace.id
      }
      if (Hyprland.focusedWorkspace.name) {
        root.activeWorkspaceName = String(Hyprland.focusedWorkspace.name)
      }
    }
    if (!wsThrottle.running) wsThrottle.start()
  }

  // Coalesces Hyprland event bursts into at most one hyprctl probe per window
  Timer {
    id: wsThrottle
    interval: 200
    repeat: false
    onTriggered: {
      if (!wsProbe.running) wsProbe.running = true
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      root.updateWorkspaceState()
    }
    function onRawEvent(event) {
      root.updateWorkspaceState()
    }
  }

  Process {
    id: wsProbe
    command: ["hyprctl", "activeworkspace", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw.charAt(0) === "{") {
          try {
            var data = JSON.parse(raw)
            if (data.id !== undefined) {
              root.activeWorkspaceId = Number(data.id)
              root.activeWorkspaceName = String(data.name || data.id)
            }
          } catch (e) {}
        }
      }
    }
  }

  Component.onCompleted: {
    root.updateWorkspaceState()
  }

  function getWorkspacesList() {
    var list = [1, 2, 3, 4, 5]
    if (Hyprland.workspaces && Hyprland.workspaces.values) {
      var vals = Hyprland.workspaces.values
      for (var i = 0; i < vals.length; i++) {
        var wid = vals[i].id
        if (wid > 0 && wid <= 10 && list.indexOf(wid) === -1) {
          list.push(wid)
        }
      }
    }
    list.sort(function(a, b) { return a - b })
    return list
  }

  function isWorkspaceOccupied(id) {
    if (Hyprland.workspaces && Hyprland.workspaces.values) {
      var vals = Hyprland.workspaces.values
      for (var i = 0; i < vals.length; i++) {
        if (vals[i].id === id) {
          return vals[i].toplevels && vals[i].toplevels.values && vals[i].toplevels.values.length > 0
        }
      }
    }
    return false
  }

  Process {
    id: dispatchProc
  }

  function switchToWorkspace(id) {
    if (Hyprland.workspaces && Hyprland.workspaces.values) {
      var vals = Hyprland.workspaces.values
      for (var i = 0; i < vals.length; i++) {
        if (vals[i].id === id && typeof vals[i].activate === "function") {
          try {
            vals[i].activate()
            root.activeWorkspaceId = id
            return
          } catch (e) {}
        }
      }
    }
    dispatchProc.exec(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = '" + id + "' })"])
    root.activeWorkspaceId = id
  }

  // Fast scroll-wheel workspace cycling
  property real lastWheelTime: 0
  function handleWheelCycle(angleDeltaY) {
    var now = Date.now()
    if (now - lastWheelTime < 140) return
    lastWheelTime = now
    var target = angleDeltaY > 0 ? "m-1" : "m+1"
    dispatchProc.exec(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = '" + target + "' })"])
    Qt.callLater(root.updateWorkspaceState)
  }

  // -------------------------------------------------------------
  // Visual Hierarchy: Downwise 1-Column Notch on Left Border
  // -------------------------------------------------------------
  Item {
    id: activeRegionItem
    anchors.left: parent.left
    y: root.topMargin
    width: root.currentWidth + 12
    height: root.currentHeight + 6

    // Invisible Left Edge Trigger Strip: wakes retracted notch immediately when cursor touches left border
    Item {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 28

      HoverHandler {
        id: edgeTriggerHover
      }
    }

    Item {
      id: notchContainer
      anchors.left: parent.left
      anchors.top: parent.top
      width: root.currentWidth
      height: root.currentHeight
      transformOrigin: Item.Left
      scale: notchTap.pressed ? 0.96 : 1.0

      Behavior on scale {
        NumberAnimation {
          duration: notchTap.pressed ? 120 : 280
          easing.type: notchTap.pressed ? Easing.OutQuad : Easing.OutBack
          easing.overshoot: 1.15
        }
      }

      HoverHandler {
        id: notchHover
        cursorShape: Qt.PointingHandCursor
      }

      TapHandler {
        id: notchTap
      }

      WheelHandler {
        id: notchWheel
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          root.handleWheelCycle(event.angleDelta.y)
        }
      }

      // Symmetrical G1 Squircle Curvature fusing into vertical left border
      Shape {
        id: notchShape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        readonly property real w: notchContainer.width
        readonly property real h: notchContainer.height
        readonly property real b: root.borderThickness
        readonly property real rf: root.flareRadius
        readonly property real rc: root.cornerRadius

        readonly property real effRf: Math.min(rf, Math.max(0, (w - b) * 0.35))
        readonly property real effRc: Math.min(rc, Math.max(0, (w - b) - effRf))

        ShapePath {
          strokeWidth: 0
          strokeColor: "transparent"
          fillColor: root.notchColor
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin

          // Start past screen edge behind left border
          startX: -2.0
          startY: 0

          // Line to vertical left border at top of notch
          PathLine {
            x: notchShape.b
            y: 0
          }

          // Top concave flare curving out from border line towards top horizontal edge
          PathCubic {
            x: notchShape.b + notchShape.effRf
            y: notchShape.effRf
            control1X: notchShape.b
            control1Y: notchShape.effRf * 0.5
            control2X: notchShape.b + (notchShape.effRf * 0.5)
            control2Y: notchShape.effRf
          }

          // Top horizontal line to top-right corner
          PathLine {
            x: notchShape.w - notchShape.effRc
            y: notchShape.effRf
          }

          // Top-right convex squircle corner arc
          PathArc {
            x: notchShape.w
            y: notchShape.effRf + notchShape.effRc
            radiusX: Math.max(1, notchShape.effRc)
            radiusY: Math.max(1, notchShape.effRc)
            direction: PathArc.Clockwise
          }

          // Right vertical edge
          PathLine {
            x: notchShape.w
            y: Math.max(notchShape.effRf + notchShape.effRc, notchShape.h - notchShape.effRf - notchShape.effRc)
          }

          // Bottom-right convex squircle corner arc
          PathArc {
            x: notchShape.w - notchShape.effRc
            y: notchShape.h - notchShape.effRf
            radiusX: Math.max(1, notchShape.effRc)
            radiusY: Math.max(1, notchShape.effRc)
            direction: PathArc.Clockwise
          }

          // Bottom horizontal line to bottom-left flare
          PathLine {
            x: notchShape.b + notchShape.effRf
            y: notchShape.h - notchShape.effRf
          }

          // Bottom concave flare curving back into the vertical left border
          PathCubic {
            x: notchShape.b
            y: notchShape.h
            control1X: notchShape.b + (notchShape.effRf * 0.5)
            control1Y: notchShape.h - notchShape.effRf
            control2X: notchShape.b
            control2Y: notchShape.h - (notchShape.effRf * 0.5)
          }

          // Line past left screen edge
          PathLine {
            x: -2.0
            y: notchShape.h
          }
        }
      }

      // Subtle Apple HIG highlight border overlay for organic depth
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: notchShape.w > (notchShape.b + 6)

        ShapePath {
          strokeWidth: 1.0
          strokeColor: Qt.rgba(255, 255, 255, 0.16)
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin

          startX: notchShape.b
          startY: 0

          PathCubic {
            x: notchShape.b + notchShape.effRf
            y: notchShape.effRf
            control1X: notchShape.b
            control1Y: notchShape.effRf * 0.5
            control2X: notchShape.b + (notchShape.effRf * 0.5)
            control2Y: notchShape.effRf
          }

          PathLine {
            x: notchShape.w - notchShape.effRc
            y: notchShape.effRf
          }

          PathArc {
            x: notchShape.w - 0.5
            y: notchShape.effRf + notchShape.effRc
            radiusX: Math.max(1, notchShape.effRc)
            radiusY: Math.max(1, notchShape.effRc)
            direction: PathArc.Clockwise
          }

          PathLine {
            x: notchShape.w - 0.5
            y: Math.max(notchShape.effRf + notchShape.effRc, notchShape.h - notchShape.effRf - notchShape.effRc)
          }

          PathArc {
            x: notchShape.w - notchShape.effRc
            y: notchShape.h - notchShape.effRf
            radiusX: Math.max(1, notchShape.effRc)
            radiusY: Math.max(1, notchShape.effRc)
            direction: PathArc.Clockwise
          }

          PathLine {
            x: notchShape.b + notchShape.effRf
            y: notchShape.h - notchShape.effRf
          }

          PathCubic {
            x: notchShape.b
            y: notchShape.h
            control1X: notchShape.b + (notchShape.effRf * 0.5)
            control1Y: notchShape.h - notchShape.effRf
            control2X: notchShape.b
            control2Y: notchShape.h - (notchShape.effRf * 0.5)
          }
        }
      }

      // =========================================================
      // Refined iOS Rail: 1-Column Workspaces (1 on top, down to 5)
      // Numbers sit on one shared optical axis; only the active one is a pill.
      // =========================================================
      Column {
        id: workspacesColumn
        anchors.verticalCenter: parent.verticalCenter
        // Explicit inset so the pills keep identical left/right padding
        x: root.borderThickness + root.sidePadding
        spacing: root.itemSpacing
        opacity: Math.min(1.0, Math.max(0.0, (root.revealProgress - 0.25) * 1.33))
        visible: opacity > 0.01

        Repeater {
          model: root.getWorkspacesList()

          delegate: Item {
            id: wsItem
            required property int modelData

            readonly property bool isCurrent: root.activeWorkspaceId === modelData
            readonly property bool isOccupied: root.isWorkspaceOccupied(modelData)
            readonly property bool isBtnHovered: Boolean(itemHover && itemHover.hovered) && !wsItem.isCurrent
            readonly property bool isBtnPressed: Boolean(itemTap && itemTap.pressed)

            width: root.itemSize
            height: root.itemSize

            // iOS Press Feedback (instant squish, OutBack spring pop)
            scale: isBtnPressed ? 0.94 : (isBtnHovered ? 1.06 : 1.0)
            transformOrigin: Item.Center

            Behavior on scale {
              NumberAnimation {
                duration: wsItem.isBtnPressed ? 110 : 260
                easing.type: wsItem.isBtnPressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: 1.2
              }
            }

            // Clean number axis: only the active workspace is a white squircle,
            // occupied workspaces read through digit brightness, empty ones recede.
            Rectangle {
              anchors.fill: parent
              radius: root.itemRadius

              color: wsItem.isCurrent
                ? "#ffffff"
                : (wsItem.isBtnHovered ? Qt.rgba(1, 1, 1, 0.18) : "transparent")

              Behavior on color {
                ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
              }

              // Workspace number, optically centered in the pill
              Text {
                anchors.centerIn: parent

                text: String(wsItem.modelData)
                color: wsItem.isCurrent ? root.notchColor : root.textColor
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: wsItem.isCurrent
                  ? Font.DemiBold
                  : (wsItem.isOccupied ? Font.Medium : Font.Normal)
                opacity: wsItem.isCurrent
                  ? 1.0
                  : (wsItem.isOccupied ? 0.92 : (wsItem.isBtnHovered ? 0.88 : 0.50))

                Behavior on opacity {
                  NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
              }
            }

            HoverHandler {
              id: itemHover
              cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
              id: itemTap
              onTapped: {
                root.switchToWorkspace(wsItem.modelData)
              }
            }
          }
        }
      }
    }
  }
}
