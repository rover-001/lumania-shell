import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui

Item {
  id: root

  // Injected configuration & styling
  required property var frameConfig
  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  property bool fullscreen: false
  property bool barHidden: false
  property bool hasOpenApps: false

  // Bottom-Right Control Menu State & IPC Controller
  property bool controlOpen: false

  function toggleControl() {
    controlOpen = !controlOpen
  }

  function openControl() {
    controlOpen = true
  }

  function closeControl() {
    controlOpen = false
  }

  // Entering fullscreen always dismisses the control menu
  onFullscreenChanged: {
    if (fullscreen) root.closeControl()
  }

  IpcHandler {
    target: "lumania.control"

    function toggle(): void {
      root.toggleControl()
    }

    function open(): void {
      root.openControl()
    }

    function close(): void {
      root.closeControl()
    }
  }

  // Bottom-Right Control Notch Window (start-menu bloom from the bottom-right corner)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: controlCenterWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !root.fullscreen && !remapGuardControl.remapping

        ScreenMoveRemap {
          id: remapGuardControl
          window: controlCenterWindow
        }

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-control-center"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
          Region {
            item: controlNotch.maskItem
          }
          Region {
            item: controlNotch.backdropItem
          }
        }

        ControlCenterNotch {
          id: controlNotch
          anchors.fill: parent
          borderThickness: root.borderThickness
          notchColor: root.notchColor
          hasOpenApps: root.hasOpenApps
          isOpen: root.controlOpen

          onOpenRequested: root.openControl()
          onCloseRequested: root.closeControl()
        }
      }
    }
  }
}
