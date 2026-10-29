import QtQuick
import Quickshell
import Quickshell.Wayland
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
  property bool fullscreen: false
  property bool barHidden: false
  property bool hasOpenApps: false
  property var notificationManager: null
  property int islandWindowHeight: 380

  // Host & plugin registry references
  property var shell: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var barConfig: ({})

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: islandWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !root.fullscreen && !remapGuard.remapping

        ScreenMoveRemap {
          id: remapGuard
          window: islandWindow
        }

        anchors {
          top: true
          left: true
          right: true
        }

        implicitHeight: root.islandWindowHeight

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-island"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: root.borderThickness

        mask: Region {
          Region {
            item: topBarLine
          }
          Region {
            item: dynamicIsland.islandMaskItem
          }
          Region {
            item: topLeftCorner
          }
          Region {
            item: topRightCorner
          }
        }

        // Full-width top border bar
        Rectangle {
          id: topBarLine
          visible: true
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.borderThickness
          color: root.islandColor

          // Left slot container for future widgets
          Row {
            id: topLeftSlot
            anchors.left: parent.left
            anchors.leftMargin: root.borderThickness + root.frameConfig.topLeftRadius + 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
          }

          // Right slot container for future widgets
          Row {
            id: topRightSlot
            anchors.right: parent.right
            anchors.rightMargin: root.borderThickness + root.frameConfig.topRightRadius + 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
          }
        }

        // Top-Left corner fillet merging left border into top border
        FrameCorner {
          id: topLeftCorner
          anchors.top: parent.top
          anchors.left: parent.left
          corner: "topLeft"
          thickness: root.borderThickness
          radius: root.frameConfig.topLeftRadius
          color: root.islandColor
          style: root.frameConfig.cornerStyle
          squircleFactor: root.frameConfig.squircleFactor
        }

        // Top-Right corner fillet merging right border into top border
        FrameCorner {
          id: topRightCorner
          anchors.top: parent.top
          anchors.right: parent.right
          corner: "topRight"
          thickness: root.borderThickness
          radius: root.frameConfig.topRightRadius
          color: root.islandColor
          style: root.frameConfig.cornerStyle
          squircleFactor: root.frameConfig.squircleFactor
        }

        // Centered Dynamic Island notch and dropdown subpanel
        DynamicIsland {
          id: dynamicIsland
          anchors.fill: parent
          frameConfig: root.frameConfig
          borderThickness: root.borderThickness
          islandColor: root.islandColor
          islandTextColor: root.islandTextColor
          islandMutedColor: root.islandMutedColor
          fontFamily: root.fontFamily
          hasOpenApps: root.hasOpenApps
          notificationManager: root.notificationManager
        }
      }
    }
  }
}
