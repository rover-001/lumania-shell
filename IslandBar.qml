import Quickshell
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

  // State consumed by host shell and overlays
  property bool barHidden: false
  property int barSize: 0
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  property string position: "top"

  // Dynamic Theme Colors (adapts automatically on theme switch)
  property color islandColor: Commons.Color ? Commons.Color.background : "#000000"
  property color islandTextColor: Commons.Color ? Commons.Color.foreground : "#ffffff"
  property color islandMutedColor: Commons.Color ? Commons.Color.muted : Qt.rgba(1, 1, 1, 0.72)

  Behavior on islandColor { ColorAnimation { duration: 300 } }
  Behavior on islandTextColor { ColorAnimation { duration: 300 } }
  Behavior on islandMutedColor { ColorAnimation { duration: 300 } }

  // Standard bar theme colors
  property color themeForeground: islandTextColor
  property color foreground: islandTextColor
  property color barForeground: islandTextColor
  property color background: islandColor
  property color urgent: Commons.Color ? Commons.Color.urgent : "#ff5555"

  // Dynamic Island Geometry
  readonly property int bodyWidth: 206
  readonly property int topCurveRadius: 10
  readonly property int islandWidth: bodyWidth + (topCurveRadius * 2)
  readonly property int islandHeight: 32
  readonly property int bottomCornerRadius: 15
  readonly property int topBarLineHeight: 2

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

        implicitHeight: root.islandHeight

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-island"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
          item: islandContainer
        }

        // Full-width subtle top hairline bar
        Rectangle {
          id: topBarLine
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.topBarLineHeight
          color: root.islandColor
        }

        // Centered Dynamic Island Notch with Smooth Animated Sizing
        Item {
          id: islandContainer
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter

          // iOS Fluid Motion driver value: 0.0 (Clock View) -> 1.0 (Audio Waveform)
          readonly property real targetProgress: dynamicView.showVisualizer ? 1.0 : 0.0
          property real transitionProgress: targetProgress

          Behavior on transitionProgress {
            NumberAnimation {
              duration: 380
              easing.type: Easing.OutBack
              easing.overshoot: 1.15
            }
          }

          // Authentic iOS liquid stretch: pill expands slightly (+8px) mid-transition
          width: root.islandWidth + (Math.sin(Math.min(1.0, Math.max(0.0, transitionProgress)) * Math.PI) * 8.0)
          height: root.islandHeight

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

          TapHandler {
            id: tapHandler
            onTapped: {
              root.use24Hour = !root.use24Hour
              root.updateClock()
            }
          }

          // Main OLED Island Shape (Curved top flare + 15px rounded bottom)
          Shape {
            id: islandShape
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            readonly property real w: islandContainer.width
            readonly property real h: islandContainer.height
            readonly property real rTop: root.topCurveRadius
            readonly property real rBot: root.bottomCornerRadius

            ShapePath {
              strokeWidth: 0
              strokeColor: "transparent"
              fillColor: root.islandColor
              capStyle: ShapePath.RoundCap
              joinStyle: ShapePath.RoundJoin

              // Start at top-left flare edge flush against top line
              startX: 0
              startY: -2.0

              // Top horizontal line
              PathLine {
                x: islandShape.w
                y: -2.0
              }

              // Top-right flare
              PathLine {
                x: islandShape.w
                y: 0
              }
              PathCubic {
                x: islandShape.w - islandShape.rTop
                y: islandShape.rTop
                control1X: islandShape.w - (islandShape.rTop * 0.5)
                control1Y: 0
                control2X: islandShape.w - islandShape.rTop
                control2Y: islandShape.rTop * 0.5
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

              // Left vertical side up to top flare
              PathLine {
                x: islandShape.rTop
                y: islandShape.rTop
              }

              // Top-left flare
              PathCubic {
                x: 0
                y: 0
                control1X: islandShape.rTop
                control1Y: islandShape.rTop * 0.5
                control2X: islandShape.rTop * 0.5
                control2Y: 0
              }

              // Close path
              PathLine {
                x: 0
                y: -2.0
              }
            }
          }

          // Content Layer 1: Standard Clock View (Day, Date, Time)
          Row {
            id: clockContentRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -1.0 + (-5.0 * islandContainer.transitionProgress)
            spacing: 8

            opacity: Math.max(0.0, 1.0 - islandContainer.transitionProgress * 2.2)
            scale: Math.max(0.82, 1.0 - islandContainer.transitionProgress * 0.16)
            visible: opacity > 0.01
            transformOrigin: Item.Center

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

          // Content Layer 2: Adaptive Workspace View (Multi-Color Gradient Audio Waveform)
          DynamicWorkspaceView {
            id: dynamicView
            anchors.fill: parent

            opacity: Math.min(1.0, Math.max(0.0, (islandContainer.transitionProgress - 0.25) * 1.33))
            scale: 0.82 + (0.18 * islandContainer.transitionProgress)
            y: 4.0 * (1.0 - islandContainer.transitionProgress)
            visible: opacity > 0.01
            transformOrigin: Item.Center
          }
        }
      }
    }
  }
}
