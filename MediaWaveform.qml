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

  // Harmonious gradient for #a7474f bar (Center: Solid White -> Outer wings: Soft White)
  property color startColor: "#ffffff"
  property color endColor: Qt.rgba(1, 1, 1, 0.70)

  // Spring motion: every bar is a damped spring chasing its target from the visualizer.
  // Rising is stiffer and slightly underdamped (a small springy overshoot),
  // falling is heavier and settles without bouncing back up.
  readonly property real springStiffness: 1400
  readonly property real riseDamping: 40
  readonly property real fallDamping: 55

  property var springPos: []
  property var springVel: []
  property var displayHeights: []

  property real lastFrameMs: Date.now()

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

  function ensureSpringState() {
    if (springPos.length === barCount) return
    var p = [], v = [], d = []
    for (var i = 0; i < barCount; i++) {
      p.push(minHeight)
      v.push(0)
      d.push(minHeight)
    }
    springPos = p
    springVel = v
    displayHeights = d
  }

  function targetFor(i) {
    if (!barHeights || barHeights.length <= i) return minHeight
    var t = Number(barHeights[i])
    if (isNaN(t)) return minHeight
    return Math.max(minHeight, Math.min(maxHeight, t))
  }

  // Advance all springs by dt seconds using fixed sub-steps for stable integration
  function stepSprings(dt) {
    ensureSpringState()
    var p = springPos.slice()
    var v = springVel.slice()
    var remaining = Math.min(dt, 1 / 30)
    var sub = 1 / 240

    while (remaining > 0) {
      var s = Math.min(sub, remaining)
      for (var i = 0; i < barCount; i++) {
        var t = targetFor(i)
        var c = (t > p[i]) ? riseDamping : fallDamping
        var a = springStiffness * (t - p[i]) - c * v[i]
        v[i] += a * s
        p[i] += v[i] * s
      }
      remaining -= s
    }

    var out = []
    for (var k = 0; k < barCount; k++) {
      out.push(Math.max(0, Math.min(maxHeight, p[k])))
    }
    springPos = p
    springVel = v
    displayHeights = out
  }

  Component.onCompleted: {
    initColors()
    ensureSpringState()
  }

  // Per-frame driver, runs at display refresh rate while the visualizer is active
  FrameAnimation {
    id: springDriver
    running: root.active
    onTriggered: {
      var now = Date.now()
      var dt = (now - root.lastFrameMs) / 1000
      root.lastFrameMs = now
      root.stepSprings(dt)
    }
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

        // Driven by the per-frame spring simulation (no Behavior, so no stepping)
        height: (root.displayHeights && root.displayHeights.length > bar.index)
          ? root.displayHeights[bar.index]
          : root.minHeight

        // Derived from the bar's own height (single driver): invisible at rest,
        // fades and swells in as the voice wave reaches it
        readonly property real energy: Math.max(0, Math.min(1, (height - root.minHeight) / (root.maxHeight - root.minHeight)))
        opacity: Math.min(1.0, energy * 6.0)
      }
    }
  }
}
