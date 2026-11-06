import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
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

  // Geometries matching TopRightNotch & Dynamic Island exactly
  readonly property real baseHeight: frameConfig ? frameConfig.trayNotchBaseHeight : 37
  readonly property real topCurveRadius: frameConfig ? frameConfig.trayNotchTopCurveRadius : 10
  readonly property real bottomCornerRadius: frameConfig ? frameConfig.trayNotchBottomCornerRadius : 15
  readonly property real itemSize: 26
  readonly property real itemRadius: 7
  readonly property real itemSpacing: 6
  readonly property real sidePadding: 12

  readonly property string iconFont: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"

  // Mask and wake items exposed to PanelWindow
  property alias maskItem: activeRegionItem
  property alias wakeItem: edgeTriggerItem

  // -------------------------------------------------------------------------
  // Session & Power Actions (Clean typography, outline icons, no blocky blobs)
  // -------------------------------------------------------------------------
  readonly property var sessionActions: [
    { id: "lock", glyph: "\uf023", label: "Lock", command: ["omarchy-system-lock"], hoverBg: Qt.rgba(255, 255, 255, 0.16) },
    { id: "suspend", glyph: "\uF186", label: "Suspend", command: ["systemctl", "suspend"], hoverBg: Qt.rgba(255, 255, 255, 0.16) },
    { id: "hibernate", glyph: "\uF2DC", label: "Hibernate", command: ["systemctl", "hibernate"], hoverBg: Qt.rgba(255, 255, 255, 0.16) }
  ]

  readonly property var powerActions: [
    { id: "restart", glyph: "\uF021", label: "Restart", command: ["systemctl", "reboot"], hoverBg: Qt.rgba(245, 175, 45, 0.28) },
    { id: "poweroff", glyph: "\uF011", label: "Power off", command: ["systemctl", "poweroff"], hoverBg: Qt.rgba(235, 75, 75, 0.32) }
  ]

  function runPowerAction(command) {
    if (!command) return
    Quickshell.execDetached(command)
  }

  // -------------------------------------------------------------------------
  // Dynamic Width Calculation
  // -------------------------------------------------------------------------
  readonly property int sessionCount: sessionActions.length
  readonly property int powerCount: powerActions.length
  readonly property real sessionSectionWidth: sessionCount * itemSize + Math.max(0, sessionCount - 1) * itemSpacing
  readonly property real powerSectionWidth: powerCount * itemSize + Math.max(0, powerCount - 1) * itemSpacing
  readonly property real dividerWidth: 8 // 1px separator + padding matching TopRightNotch

  readonly property real targetNotchWidth: (sidePadding * 2)
    + (topCurveRadius * 2)
    + sessionSectionWidth
    + dividerWidth
    + powerSectionWidth

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

  // Smooth sinusoidal liquid volume pulse during reveal (identical to TopRightNotch)
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
    anchors.left: parent.left
    width: root.animatedWidth
    height: root.currentHeight
    transformOrigin: Item.Top

    HoverHandler {
      id: notchHover
      cursorShape: Qt.ArrowCursor
    }

    // -----------------------------------------------------------------------
    // Pure Dynamic Island OLED Silhouette
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

        // Up to screen top to close
        PathLine {
          x: 0
          y: -2.0
        }
      }
    }

    // -----------------------------------------------------------------------
    // Button Row: [ Lock, Suspend, Hibernate | Restart, Power Off ]
    // Zero surrounding squares; bare icons matching TopRightNotch aesthetic
    // -----------------------------------------------------------------------
    Row {
      id: contentRow
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: root.borderThickness / 2
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: root.itemSpacing
      opacity: Math.max(0.0, (root.revealProgress - 0.35) / 0.65)
      visible: opacity > 0

      // Section 1: Session Actions (Lock, Suspend, Hibernate)
      Repeater {
        model: root.sessionActions

        delegate: Item {
          id: sessionBtn
          width: root.itemSize
          height: root.itemSize
          anchors.verticalCenter: parent.verticalCenter

          property bool isHovered: sessionHover.hovered
          property bool isPressed: sessionTap.pressed

          scale: isPressed ? 0.92 : 1.0
          Behavior on scale {
            NumberAnimation {
              duration: sessionBtn.isPressed ? 110 : 220
              easing.type: sessionBtn.isPressed ? Easing.OutQuad : Easing.OutBack
              easing.overshoot: 1.15
            }
          }

          // Subtle squircle highlight on hover only; ZERO surrounding square at rest
          Rectangle {
            anchors.fill: parent
            radius: root.itemRadius
            color: sessionBtn.isHovered ? modelData.hoverBg : "transparent"
            Behavior on color { ColorAnimation { duration: 150 } }
          }

          Text {
            anchors.centerIn: parent
            text: modelData.glyph
            font.family: root.iconFont
            font.pixelSize: 14
            color: sessionBtn.isHovered ? root.textColor : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.88)
            renderType: Text.NativeRendering
          }

          HoverHandler {
            id: sessionHover
            cursorShape: Qt.PointingHandCursor
          }

          TapHandler {
            id: sessionTap
            onTapped: root.runPowerAction(modelData.command)
          }
        }
      }

      // Section 2: Subtle vertical hairline separator (matches TopRightNotch separator1)
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 12
        radius: 0.5
        color: Qt.rgba(255, 255, 255, 0.22)
      }

      // Section 3: System Power Actions (Restart, Power Off)
      Repeater {
        model: root.powerActions

        delegate: Item {
          id: powerBtn
          width: root.itemSize
          height: root.itemSize
          anchors.verticalCenter: parent.verticalCenter

          property bool isHovered: powerHover.hovered
          property bool isPressed: powerTap.pressed

          scale: isPressed ? 0.92 : 1.0
          Behavior on scale {
            NumberAnimation {
              duration: powerBtn.isPressed ? 110 : 220
              easing.type: powerBtn.isPressed ? Easing.OutQuad : Easing.OutBack
              easing.overshoot: 1.15
            }
          }

          // Subtle squircle highlight on hover only; ZERO surrounding square at rest
          Rectangle {
            anchors.fill: parent
            radius: root.itemRadius
            color: powerBtn.isHovered ? modelData.hoverBg : "transparent"
            Behavior on color { ColorAnimation { duration: 150 } }
          }

          Text {
            anchors.centerIn: parent
            text: modelData.glyph
            font.family: root.iconFont
            font.pixelSize: 14
            color: powerBtn.isHovered ? root.textColor : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.88)
            renderType: Text.NativeRendering
          }

          HoverHandler {
            id: powerHover
            cursorShape: Qt.PointingHandCursor
          }

          TapHandler {
            id: powerTap
            onTapped: root.runPowerAction(modelData.command)
          }
        }
      }
    }
  }
}
