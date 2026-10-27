import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons as Commons

Item {
  id: root

  // Media Playback State
  property bool mprisPlaying: false
  property bool nonMprisPlaying: false

  // Reactive evaluation of MPRIS playback across all active players
  function recheckMpris() {
    var players = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (p && p.isPlaying) {
        root.mprisPlaying = true
        return
      }
    }
    root.mprisPlaying = false
  }

  // Instantiator tracks each individual MPRIS player's playback state reactively (0ms latency)
  Instantiator {
    model: Mpris.players ? Mpris.players.values : []
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { root.recheckMpris() }
    }
    onCountChanged: root.recheckMpris()
  }

  Connections {
    target: Mpris.players
    function onValuesChanged() { root.recheckMpris() }
  }

  // Active condition: any MPRIS media playing OR non-MPRIS active audio stream
  readonly property bool showVisualizer: mprisPlaying || nonMprisPlaying

  property bool sinkCheckPending: false

  function triggerSinkCheck() {
    if (sinkInputCheck.running) {
      sinkCheckPending = true
      return
    }
    sinkCheckPending = false
    sinkInputCheck.running = true
  }

  // Real-time PipeWire audio event push (sub-millisecond notification on non-MPRIS stream state change)
  Process {
    id: pactlSubscriber
    command: ["pactl", "subscribe"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line || "")
        if (str.indexOf("sink-input") !== -1 || str.indexOf("sink") !== -1) {
          root.triggerSinkCheck()
        }
      }
    }
  }

  // Check PipeWire active audio stream for non-MPRIS applications (games, audio tools, etc.)
  // Explicitly excludes lingering uncorked buffers from paused MPRIS browsers and players
  Process {
    id: sinkInputCheck
    command: ["sh", "-c", "pactl list sink-inputs 2>/dev/null | awk 'BEGIN { uncorked=0; mpris=0; count=0 } /Sink Input/ { if (uncorked && !mpris) count++; uncorked=0; mpris=0 } /Corked: no/ { uncorked=1 } tolower($0) ~ /application\\.name = \"(chromium|chrome|firefox|zen|brave|opera|vivaldi|spotify|mpv|vlc|amberol)/ { mpris=1 } END { if (uncorked && !mpris) count++; if (count > 0) exit 0; exit 1 }'"]
    onExited: function(code) {
      root.nonMprisPlaying = (code === 0)
      if (root.sinkCheckPending) {
        root.sinkCheckPending = false
        sinkInputCheck.running = true
      }
    }
  }

  // Fast fallback polling for non-MPRIS audio
  Timer {
    interval: root.nonMprisPlaying ? 300 : 1000
    running: true
    repeat: true
    onTriggered: {
      root.recheckMpris()
      root.triggerSinkCheck()
    }
  }

  Component.onCompleted: {
    root.recheckMpris()
    root.triggerSinkCheck()
  }

  // --- Dynamic Waveform Centered in Island ---
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
