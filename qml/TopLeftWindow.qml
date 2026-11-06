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

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: topLeftWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !root.fullscreen && !remapGuardTopLeft.remapping

        ScreenMoveRemap {
          id: remapGuardTopLeft
          window: topLeftWindow
        }

        anchors {
          top: true
          left: true
          right: true
        }

        // Window height accurately matches the top left notch.
        // Rock-solid fixed height prevents any hover bouncing or layout jitter.
        implicitHeight: Math.ceil(topLeftNotch.baseHeight + 8)

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-top-left-notch"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
          Region {
            item: topLeftNotch.maskItem
          }
          Region {
            item: topLeftNotch.wakeItem
          }
        }

        TopLeftNotch {
          id: topLeftNotch
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.leftMargin: root.borderThickness + root.frameConfig.topLeftRadius + root.frameConfig.powerNotchLeftMargin
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
