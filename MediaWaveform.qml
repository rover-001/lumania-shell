import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

Item {
  id: root

  property bool active: true
  property int barCount: 22
  property real barWidth: 3.5
  property real barSpacing: 3.5
  property real maxHeight: 18
  property real minHeight: 2.0

  property var barHeights: []
  property var barColors: []

  // Cohesive 2-color gradient (Electric Cyan -> Neon Violet)
  property color startColor: "#00f0ff"
  property color endColor: "#b026ff"

  implicitWidth: (barCount * barWidth) + ((barCount - 1) * barSpacing)
  implicitHeight: maxHeight

  function initColors() {
    var cols = []
    for (var i = 0; i < root.barCount; i++) {
      var ratio = i / Math.max(1, root.barCount - 1)
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

        // Direct reactive height with fluid 144Hz hardware interpolation
        height: (root.barHeights && root.barHeights.length > bar.index)
          ? Math.max(root.minHeight, Math.min(root.maxHeight, Number(root.barHeights[bar.index])))
          : root.minHeight

        Behavior on height {
          NumberAnimation {
            duration: 45
            easing.type: Easing.OutQuad
          }
        }
      }
    }
  }
}
