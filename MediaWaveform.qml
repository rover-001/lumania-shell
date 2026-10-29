import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

Item {
  id: root

  property bool active: true
  property bool settling: false
  property int barCount: 18
  property real barWidth: 3.5
  property real barSpacing: 3.5
  property real maxHeight: 18
  property real minHeight: 2.0

  opacity: root.active ? 1.0 : 0.0
  Behavior on opacity {
    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
  }

  onActiveChanged: {
    if (!active) {
      barHeights = []
      settling = true
      settleTimer.restart()
    }
  }

  Timer {
    id: settleTimer
    interval: 320
    onTriggered: {
      root.settling = false
      root.resetHeights()
    }
  }

  function resetHeights() {
    ensureSpringState()
    var d = []
    for (var i = 0; i < barCount; i++) {
      springPos[i] = minHeight
      springVel[i] = 0
      d.push(minHeight)
    }
    displayHeights = d
  }

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
    if (!root.active) return minHeight
    if (!barHeights || barHeights.length <= i) return minHeight
    var t = Number(barHeights[i])
    if (isNaN(t)) return minHeight
    return Math.max(minHeight, Math.min(maxHeight, t))
  }

  // Advance all springs by dt seconds using in-place state integration (zero GC thrashing)
  function stepSprings(dt) {
    ensureSpringState()
    var p = springPos
    var v = springVel
    var remaining = Math.min(dt, 0.033)
    var sub = 1 / 180

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

    var maxDiff = 0
    for (var j = 0; j < barCount; j++) {
      var d = Math.abs(p[j] - (displayHeights.length > j ? displayHeights[j] : minHeight))
      if (d > maxDiff) maxDiff = d
    }
    // If all bars are quiet/settled (e.g. silence or pauses between words), skip repainting
    if (maxDiff < 0.05 && displayHeights.length === barCount) return

    var out = new Array(barCount)
    for (var k = 0; k < barCount; k++) {
      out[k] = Math.max(0, Math.min(maxHeight, p[k]))
    }
    displayHeights = out
  }

  Component.onCompleted: {
    initColors()
    ensureSpringState()
  }

  // Per-frame driver, hardware-synchronized with display refresh rate (144 Hz)
  FrameAnimation {
    id: springDriver
    running: root.active || root.settling
    onTriggered: {
      var dt = Math.max(0.001, Math.min(frameTime > 0 ? frameTime : 0.007, 0.033))
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
