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

  // Host & plugin registry references
  property var shell: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var barConfig: ({})

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: topRightWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !root.fullscreen && !remapGuardTopRight.remapping

        ScreenMoveRemap {
          id: remapGuardTopRight
          window: topRightWindow
        }

        anchors {
          top: true
          left: true
          right: true
        }

        // Window height accurately matches the top right notch.
        // Rock-solid fixed height prevents any hover bouncing or layout jitter.
        implicitHeight: Math.ceil(topRightNotch.baseHeight + 8)

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-top-right-notch"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
          Region {
            item: topRightNotch.maskItem
          }
          Region {
            item: topRightNotch.wakeItem
          }
        }

        TopRightNotch {
          id: topRightNotch
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.rightMargin: root.borderThickness + root.frameConfig.topRightRadius + root.frameConfig.trayNotchRightMargin
          frameConfig: root.frameConfig
          borderThickness: root.borderThickness
          notchColor: root.notchColor
          textColor: root.textColor
          mutedColor: root.mutedColor
          fontFamily: root.fontFamily
          hasOpenApps: root.hasOpenApps
          shell: root.shell
          barWidgetRegistry: root.barWidgetRegistry
          pluginRegistry: root.pluginRegistry
          barConfig: root.barConfig
          parentWindow: topRightWindow
        }
      }
    }
  }
}
