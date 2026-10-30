import QtQuick
import Quickshell
import Quickshell.Io

// Mirrors the live wallpaper tone onto the keyboard backlight.
//
// All hardware knowledge lives in the `lumania-keyboard` helper: it is probed
// once on start, and if this machine has no writable RGB interface the shell
// simply stops there and never touches the backlight. Boards that need their
// own protocol (OpenRGB, monochrome brightness) are opt-in inside the helper,
// so a new keyboard type only ever means teaching the helper, not the shell.
Item {
  id: root

  // Reference to central FrameConfig instance
  required property var frameConfig

  readonly property bool enabled: root.frameConfig ? root.frameConfig.syncKeyboardColor : false

  // Exactly the tone the shell already paints its frame and island with
  readonly property color tone: root.frameConfig ? root.frameConfig.activeBorderColor : "#ffffff"
  readonly property string toneHex: root.toHex(root.tone)

  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("lumania-keyboard").toString().replace(/^file:\/\//, ""))

  // Backend state, reported by `lumania-keyboard --probe`
  property bool supported: false
  property string backend: ""
  property string target: ""

  // Last tone handed to the helper, used to skip redundant sysfs/WMI writes
  property string appliedHex: ""
  property bool applyPending: false

  function toHex(c) {
    if (c === undefined || c === null) return "#ffffff"

    if (typeof c.r === "number" && typeof c.g === "number" && typeof c.b === "number") {
      function part(v) {
        var n = Math.round(Math.max(0, Math.min(1, v)) * 255)
        return (n < 16 ? "0" : "") + n.toString(16)
      }
      return "#" + part(c.r) + part(c.g) + part(c.b)
    }

    // Fallback: QML colour stringify is "#rrggbb", or "#aarrggbb" if it has alpha
    var m = String(c).trim().match(/^#([0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?$/)
    return m ? "#" + m[1].toLowerCase() : "#ffffff"
  }

  function probe() {
    if (!root.enabled) return
    if (probeProc.running) return
    probeProc.running = true
  }

  function schedule() {
    if (!root.enabled || !root.supported) return
    if (root.toneHex === root.appliedHex) return
    debounce.restart()
  }

  function applyNow() {
    if (!root.enabled || !root.supported) return
    if (root.toneHex === root.appliedHex) return
    if (applyProc.running) {
      root.applyPending = true
      return
    }

    var hex = root.toneHex
    root.applyPending = false
    root.appliedHex = hex

    applyProc.command = [root.helperPath, hex]
    applyProc.running = true
  }

  onToneHexChanged: root.schedule()
  onEnabledChanged: {
    if (root.enabled) root.probe()
    else root.appliedHex = ""
  }

  Component.onCompleted: root.probe()

  // Coalesces the burst of colour updates a wallpaper switch produces
  // (accent, complementary, muted) into a single hardware write.
  Timer {
    id: debounce
    interval: 350
    repeat: false
    onTriggered: root.applyNow()
  }

  // Re-probe until something supported shows up (external RGB board plugged in)
  Timer {
    interval: 15000
    repeat: true
    running: root.enabled && !root.supported
    onTriggered: root.probe()
  }

  Process {
    id: probeProc
    command: [root.helperPath, "--probe"]
    stdout: StdioCollector {
      onStreamFinished: {
        var str = String(text || "").trim()
        try {
          var info = JSON.parse(str)
          root.supported = info.supported === true
          root.backend = String(info.backend || "")
          root.target = String(info.target || "")
        } catch (e) {
          root.supported = false
          root.backend = ""
          root.target = ""
        }
        if (root.supported) root.schedule()
      }
    }
  }

  Process {
    id: applyProc
    command: []
    stderr: StdioCollector {
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err) console.warn("lumania keyboard sync:", err)
      }
    }
    onExited: function(exitCode) {
      // A failed write must not be remembered as applied, or the next tone
      // would be skipped; clearing it lets the next change retry.
      if (exitCode !== 0) root.appliedHex = ""
      if (root.applyPending) root.applyNow()
    }
  }
}
