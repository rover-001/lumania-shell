import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Ui

Item {
  id: root

  // Injected configuration & styling
  required property var frameConfig
  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  property bool barHidden: false

  // Right Center Hover Control Notch (iOS-fluid notch blooming from right border)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: rightControlWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !remapGuardPanel.remapping

        ScreenMoveRemap {
          id: remapGuardPanel
          window: rightControlWindow
        }

        anchors {
          right: true
        }

        implicitWidth: Math.max(124, root.frameConfig.rightExpandedWidth + 30)
        implicitHeight: Math.max(680, root.frameConfig.rightExpandedHeight + 100)

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-right-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
          Region {
            item: controlPanel.maskItem
          }
        }

        RightControlPanel {
          id: controlPanel
          anchors.fill: parent
          borderThickness: root.borderThickness
          notchColor: root.notchColor
        }
      }
    }
  }
}
