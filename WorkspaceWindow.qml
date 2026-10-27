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
  property color textColor: frameConfig.activeTextColor
  property color mutedColor: frameConfig.mutedColor
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  property bool fullscreen: false
  property bool barHidden: false
  property bool hasOpenApps: false

  // Top-Left Workspace Notch (iOS-fluid notch blooming from top border)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: workspaceWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !root.fullscreen && !remapGuardWorkspace.remapping

        ScreenMoveRemap {
          id: remapGuardWorkspace
          window: workspaceWindow
        }

        anchors {
          left: true
          top: true
        }

        implicitWidth: root.frameConfig.workspaceWidth + 30
        implicitHeight: root.frameConfig.workspaceTopMargin + root.frameConfig.workspaceHeight + 30

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-workspace-notch"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
          Region {
            item: workspaceNotch.maskItem
          }
        }

        WorkspaceNotch {
          id: workspaceNotch
          anchors.fill: parent
          frameConfig: root.frameConfig
          borderThickness: root.borderThickness
          notchColor: root.notchColor
          textColor: root.textColor
          mutedColor: root.mutedColor
          fontFamily: root.fontFamily
          hasOpenApps: root.hasOpenApps
        }
      }
    }
  }
}
