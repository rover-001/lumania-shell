import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var notificationManager: null

  // Timer state
  property bool active: false
  property bool paused: false
  property int remainingSecs: 0
  property int totalSecs: 0
  property string label: ""

  readonly property real progress: totalSecs > 0 ? (totalSecs - remainingSecs) / totalSecs : 0.0
  readonly property string formattedTime: formatTime(remainingSecs)

  function formatTime(secs) {
    var s = Math.max(0, Math.floor(secs))
    var m = Math.floor(s / 60)
    var remS = s % 60
    var h = Math.floor(m / 60)
    var remM = m % 60
    if (h > 0) {
      return h + ":" + (remM < 10 ? "0" : "") + remM + ":" + (remS < 10 ? "0" : "") + remS
    }
    return (m < 10 ? "0" : "") + m + ":" + (remS < 10 ? "0" : "") + remS
  }

  function parseDuration(str) {
    var s = String(str || "").trim().toLowerCase()
    if (!s) return 0
    var total = 0
    var hMatch = s.match(/(\d+)\s*h/)
    if (hMatch) total += parseInt(hMatch[1]) * 3600
    var mMatch = s.match(/(\d+)\s*m/)
    if (mMatch) total += parseInt(mMatch[1]) * 60
    var sMatch = s.match(/(\d+)\s*s/)
    if (sMatch) total += parseInt(sMatch[1])

    if (!hMatch && !mMatch && !sMatch) {
      var num = parseInt(s)
      if (!isNaN(num)) total = num * 60 // Default pure number to minutes
    }
    return total
  }

  function startTimer(durationStr, labelStr) {
    var secs = parseDuration(durationStr)
    if (secs <= 0) return
    start(secs, labelStr)
  }

  function start(seconds, labelStr) {
    var s = parseInt(seconds)
    if (isNaN(s) || s <= 0) return
    root.totalSecs = s
    root.remainingSecs = s
    root.label = String(labelStr || "").trim()
    root.paused = false
    root.active = true
  }

  function togglePause() {
    if (!root.active) return
    root.paused = !root.paused
  }

  function addSeconds(secs) {
    if (!root.active) return
    var s = parseInt(secs)
    if (isNaN(s)) return
    root.remainingSecs += s
    root.totalSecs = Math.max(root.totalSecs, root.remainingSecs)
  }

  function cancel() {
    root.active = false
    root.paused = false
    root.remainingSecs = 0
    root.totalSecs = 0
    root.label = ""
  }

  function timerFinished() {
    var alertSummary = "Timer Finished"
    var alertBody = root.label.length > 0 ? (root.label + " time is up") : "Time's up"

    root.cancel()

    // Trigger visual notification banner through NotificationManager
    if (root.notificationManager && typeof root.notificationManager.displayNotification === "function") {
      root.notificationManager.displayNotification({
        appName: "Timer",
        summary: alertSummary,
        body: alertBody,
        appIcon: "preferences-system-time",
        image: "",
        urgency: 1,
        glyph: "󰔛",
        execArgv: null,
        ref: null,
        timeout: 4000
      })
    } else {
      Quickshell.execDetached(["notify-send", "-u", "normal", "-i", "preferences-system-time", alertSummary, alertBody])
    }

    // Alert chime
    Quickshell.execDetached(["sh", "-c", "canberra-gtk-play -i complete 2>/dev/null || paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true"])
  }

  Timer {
    id: tickTimer
    interval: 1000
    repeat: true
    running: root.active && !root.paused && root.remainingSecs > 0
    onTriggered: {
      if (root.remainingSecs > 1) {
        root.remainingSecs--
      } else {
        root.timerFinished()
      }
    }
  }
}
