import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons as Commons

Item {
  id: root

  // Adaptive Workspace State
  property bool hasYouTube: false
  property string mediaTitle: ""

  // MPRIS Media Playback State
  readonly property var playersList: Mpris.players ? Mpris.players.values : []

  readonly property bool isPlaying: {
    if (!playersList || playersList.length === 0) return false
    for (var i = 0; i < playersList.length; i++) {
      var p = playersList[i]
      if (p && p.isPlaying) return true
    }
    return false
  }

  // Active condition: on workspace with media AND media is actively playing (not paused)
  readonly property bool showVisualizer: hasYouTube && isPlaying

  function cleanTitle(raw) {
    var t = String(raw || "").trim()
    t = t.replace(/\s*-\s*YouTube\s*-\s*Chromium$/i, "")
         .replace(/\s*-\s*YouTube\s*-\s*Firefox$/i, "")
         .replace(/\s*-\s*YouTube$/i, "")
         .replace(/^\(\d+\)\s*/, "")
    return t.trim()
  }

  function parseWorkspaceInfo(jsonStr) {
    try {
      var data = JSON.parse(jsonStr)
      if (!data) return
      var title = String(data.lastwindowtitle || "")
      if (title.toLowerCase().indexOf("youtube") !== -1 || title.toLowerCase().indexOf("spotify") !== -1) {
        hasYouTube = true
        mediaTitle = cleanTitle(title)
        return
      }
    } catch (e) {}
    clientsProcess.running = true
  }

  function parseClients(jsonStr) {
    try {
      var clients = JSON.parse(jsonStr)
      if (!Array.isArray(clients)) return

      var currentWs = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
      for (var i = 0; i < clients.length; i++) {
        var c = clients[i]
        if (c && c.workspace && c.workspace.id === currentWs) {
          var t = String(c.title || "")
          var cls = String(c.class || "")
          if (t.toLowerCase().indexOf("youtube") !== -1 || t.toLowerCase().indexOf("spotify") !== -1 || cls.toLowerCase().indexOf("spotify") !== -1) {
            hasYouTube = true
            mediaTitle = cleanTitle(t)
            return
          }
        }
      }
      hasYouTube = false
      mediaTitle = ""
    } catch (e) {
      hasYouTube = false
      mediaTitle = ""
    }
  }

  // Poll active workspace & clients
  Process {
    id: activeWsProcess
    command: ["hyprctl", "activeworkspace", "-j"]
    stdout: StdioCollector {
      id: activeWsStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.parseWorkspaceInfo(activeWsStdout.text)
      }
    }
  }

  Process {
    id: clientsProcess
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      id: clientsStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.parseClients(clientsStdout.text)
      }
    }
  }

  function refresh() {
    if (!activeWsProcess.running) {
      activeWsProcess.running = true
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      root.refresh()
    }
  }

  Timer {
    interval: 1200
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    refresh()
  }

  // --- Dynamic Waveform Centered in Island ---
  anchors.fill: parent

  MediaWaveform {
    id: waveform
    anchors.centerIn: parent
    active: root.showVisualizer
    barCount: 18
    barWidth: 3.5
    barSpacing: 3.5
    maxHeight: 18
  }
}
