import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui

Item {
  id: root

  // Injected configuration & styling
  required property var frameConfig
  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  property var shell: null
  property bool fullscreen: false
  property bool barHidden: false

  // Bottom Search Notch State & IPC Controller
  property bool searchOpen: false

  function toggleSearch() {
    searchOpen = !searchOpen
  }

  function openSearch() {
    searchOpen = true
  }

  function closeSearch() {
    searchOpen = false
  }

  // Entering fullscreen always dismisses the search panel
  onFullscreenChanged: {
    if (fullscreen) root.closeSearch()
  }

  IpcHandler {
    target: "lumania.search"

    function toggle(): void {
      root.toggleSearch()
    }

    function open(): void {
      root.openSearch()
    }

    function close(): void {
      root.closeSearch()
    }
  }

  // Bottom Center Search Notch Window (iOS-fluid search notch blooming upwards from bottom border)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: bottomSearchWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !root.fullscreen && !remapGuardSearch.remapping

        ScreenMoveRemap {
          id: remapGuardSearch
          window: bottomSearchWindow
        }

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-search-notch"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        readonly property bool isCurrentScreen: !Hyprland.focusedMonitor || (modelData && modelData.name === Hyprland.focusedMonitor.name)
        WlrLayershell.keyboardFocus: (searchNotch.isOpenEffective && isCurrentScreen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        mask: Region {
          Region {
            item: searchNotch.maskItem
          }
          Region {
            item: searchNotch.backdropItem
          }
        }

        BottomSearchNotch {
          id: searchNotch
          anchors.fill: parent
          borderThickness: root.borderThickness
          notchColor: root.notchColor
          fontFamily: root.fontFamily
          shell: root.shell
          isOpen: root.searchOpen

          onOpenRequested: root.openSearch()
          onCloseRequested: root.closeSearch()
        }
      }
    }
  }
}
