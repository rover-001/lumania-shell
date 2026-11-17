import QtQuick

// Keep this compatibility type local to the plugin. Older Omarchy snapshots
// do not provide qs.Ui.ScreenMoveRemap.
Item {
  id: root

  property var window
  property bool remapping: false

  Connections {
    target: root.window
    ignoreUnknownSignals: true

    function onScreenChanged() {
      root.remapping = true
      settleTimer.restart()
    }
  }

  Timer {
    id: settleTimer
    interval: 120
    repeat: false
    onTriggered: root.remapping = false
  }
}
