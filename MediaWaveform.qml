import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

Item {
  id: root

  property bool active: true
  property int barCount: 18
  property real barWidth: 3.5
  property real barSpacing: 3.5
  property real maxHeight: 18
  property real minHeight: 2.0

  property var barHeights: []
  property var barColors: []

  // Symmetrical center-out gradient (Center: Electric Cyan -> Outer wings: Neon Violet)
  property color startColor: "#00f0ff"
  property color endColor: "#b026ff"

  implicitWidth: (barCount * barWidth) + ((barCount - 1) * barSpacing)
  implicitHeight: maxHeight

  function initColors() {
    var cols = []
    var center = (root.barCount - 1) / 2.0 // 8.5
    for (var i = 0; i < root.barCount; i++) {
      var dist = Math.abs(i - center)
      var ratio = dist / Math.max(1, center)
      cols.push(Qt.rgba(
        startColor.r * (1.0 - ratio) + endColor.r * ratio,
        startColor.g * (1.0 - ratio) + endColor.g * ratio,
        startColor.b * (1.0 - ratio) + endColor.b * ratio,
        1.0
      ))
    }
    root.barColors = cols
  }

  Component.onCompleted: {
    initColors()
  }

  // Native compiled Rust visualizer process
  Process {
    id: audioProcess
    running: root.active
    command: [Quickshell.env("HOME") + "/Projects/lumania shell/lumania-vis"]
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line || "").trim()
        if (!str) return
        var parts = str.split(" ")
        if (parts.length >= root.barCount) {
          root.barHeights = parts
        }
      }
    }
  }

  Row {
    anchors.centerIn: parent
    spacing: root.barSpacing

    Repeater {
      model: root.barCount

      Rectangle {
        id: bar
        required property int index

        width: root.barWidth
        radius: root.barWidth / 2
        anchors.verticalCenter: parent.verticalCenter
        color: (root.barColors && root.barColors.length > index)
          ? root.barColors[index]
          : root.startColor

        // Continuous fluid hardware interpolation: center high, cascading smoothly to flanks
        height: (root.barHeights && root.barHeights.length > bar.index)
          ? Math.max(root.minHeight, Math.min(root.maxHeight, Number(root.barHeights[bar.index])))
          : root.minHeight

        // Derived from the bar's own height (single driver): invisible at rest,
        // fades and swells in as the voice wave reaches it
        readonly property real energy: Math.max(0, Math.min(1, (height - root.minHeight) / (root.maxHeight - root.minHeight)))
        opacity: Math.min(1.0, energy * 6.0)

        Behavior on height {
          NumberAnimation {
            duration: 60
            easing.type: Easing.OutQuad
          }
        }
      }
    }
  }
}
