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
  property bool barHidden: false

  readonly property real maxBottomRadius: Math.max(frameConfig.bottomLeftRadius, frameConfig.bottomRightRadius)

  // 1. Bottom Frame Window (solid border with dock reserved space and corner fillets)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: bottomWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !remapGuardBottom.remapping

        ScreenMoveRemap {
          id: remapGuardBottom
          window: bottomWindow
        }

        anchors {
          bottom: true
          left: true
          right: true
        }

        implicitHeight: root.borderThickness + root.maxBottomRadius

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-frame-bottom"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: root.borderThickness

        mask: Region {
          Region {
            item: bottomBarLine
          }
          Region {
            item: bottomLeftCorner
          }
          Region {
            item: bottomRightCorner
          }
        }

        Rectangle {
          id: bottomBarLine
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.borderThickness
          color: root.islandColor
        }

        // Bottom-Left corner fillet merging left border into bottom border
        FrameCorner {
          id: bottomLeftCorner
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          corner: "bottomLeft"
          thickness: root.borderThickness
          radius: root.frameConfig.bottomLeftRadius
          color: root.islandColor
          style: root.frameConfig.cornerStyle
          squircleFactor: root.frameConfig.squircleFactor
        }

        // Bottom-Right corner fillet merging right border into bottom border
        FrameCorner {
          id: bottomRightCorner
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          corner: "bottomRight"
          thickness: root.borderThickness
          radius: root.frameConfig.bottomRightRadius
          color: root.islandColor
          style: root.frameConfig.cornerStyle
          squircleFactor: root.frameConfig.squircleFactor
        }

        // Slot container ready for bottom widgets / dock items
        Row {
          id: bottomCenterSlot
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          height: root.borderThickness
          spacing: 8
        }
      }
    }
  }

  // 2. Left Frame Window (solid vertical border with dock reserved space)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: leftWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !remapGuardLeft.remapping

        ScreenMoveRemap {
          id: remapGuardLeft
          window: leftWindow
        }

        anchors {
          left: true
          top: true
          bottom: true
        }

        implicitWidth: root.borderThickness

        color: root.islandColor
        surfaceFormat.opaque: true
        WlrLayershell.namespace: "lumania-frame-left"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: root.borderThickness

        // Slot container ready for vertical left items
        Column {
          id: leftCenterSlot
          anchors.centerIn: parent
          spacing: 8
        }
      }
    }
  }

  // 3. Right Frame Window (solid vertical border with dock reserved space)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: rightWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !remapGuardRight.remapping

        ScreenMoveRemap {
          id: remapGuardRight
          window: rightWindow
        }

        anchors {
          right: true
          top: true
          bottom: true
        }

        implicitWidth: root.borderThickness

        color: root.islandColor
        surfaceFormat.opaque: true
        WlrLayershell.namespace: "lumania-frame-right"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: root.borderThickness

        // Slot container ready for vertical right items
        Column {
          id: rightCenterSlot
          anchors.centerIn: parent
          spacing: 8
        }
      }
    }
  }
}
