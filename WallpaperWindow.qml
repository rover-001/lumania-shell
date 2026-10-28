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
  property color textColor: frameConfig.activeTextColor
  property color mutedColor: frameConfig.mutedColor
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  property bool fullscreen: false
  property bool barHidden: false
  property bool hasOpenApps: false

  // Bottom-Center Wallpaper Notch State & IPC Controller
  property bool wallpaperOpen: false

  // The notch instance on the focused screen; IPC stepping needs a real
  // object because the delegates live inside the Variants model.
  property var activeNotch: null

  function stepWallpaper(delta) {
    if (root.activeNotch) root.activeNotch.step(delta, true, false)
  }

  function toggleWallpapers() {
    wallpaperOpen = !wallpaperOpen
  }

  function openWallpapers() {
    wallpaperOpen = true
  }

  function closeWallpapers() {
    wallpaperOpen = false
  }

  // Entering fullscreen always dismisses the filmstrip
  onFullscreenChanged: {
    if (fullscreen) root.closeWallpapers()
  }

  IpcHandler {
    target: "lumania.wallpaper"

    function toggle(): void {
      root.toggleWallpapers()
    }

    function open(): void {
      root.openWallpapers()
    }

    function close(): void {
      root.closeWallpapers()
    }

    // Step without opening the notch (bindable to a keyboard shortcut).
    function next(): void {
      root.stepWallpaper(1)
    }

    function prev(): void {
      root.stepWallpaper(-1)
    }
  }

  // Bottom Center Wallpaper Notch Window (filmstrip blooming up from the border)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: wallpaperWindow

        required property var modelData
        screen: modelData

        visible: !root.barHidden && !root.fullscreen && !remapGuardWallpaper.remapping

        ScreenMoveRemap {
          id: remapGuardWallpaper
          window: wallpaperWindow
        }

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "lumania-wallpaper-notch"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        readonly property bool isCurrentScreen: !Hyprland.focusedMonitor || (modelData && modelData.name === Hyprland.focusedMonitor.name)
        WlrLayershell.keyboardFocus: (wallpaperNotch.isOpenEffective && isCurrentScreen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        mask: Region {
          Region {
            item: wallpaperNotch.maskItem
          }
          Region {
            item: wallpaperNotch.backdropItem
          }
          // Empty (0x0) unless the lip is retracted, so it never steals clicks.
          Region {
            item: wallpaperNotch.wakeItem
          }
        }

        WallpaperNotch {
          id: wallpaperNotch
          anchors.fill: parent
          frameConfig: root.frameConfig
          borderThickness: root.borderThickness
          notchColor: root.notchColor
          textColor: root.textColor
          mutedColor: root.mutedColor
          fontFamily: root.fontFamily
          isOpen: root.wallpaperOpen
          hasOpenApps: root.hasOpenApps
          screenX: wallpaperWindow.screen ? wallpaperWindow.screen.x : 0
          screenY: wallpaperWindow.screen ? wallpaperWindow.screen.y : 0

          onOpenRequested: root.openWallpapers()
          onCloseRequested: root.closeWallpapers()

          Component.onCompleted: {
            if (wallpaperWindow.isCurrentScreen) root.activeNotch = wallpaperNotch
          }
        }

        onIsCurrentScreenChanged: {
          if (isCurrentScreen) root.activeNotch = wallpaperNotch
        }
      }
    }
  }
}
