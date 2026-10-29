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

  // Filter out calls, communication streams, and players without track metadata
  function isCallOrComm(p) {
    if (!p) return false
    var id = String(p.identity || "").toLowerCase()
    var title = String(p.trackTitle || "").toLowerCase()
    var artist = String(p.trackArtist || "").toLowerCase()
    if (id.indexOf("discord") !== -1 || id.indexOf("whatsapp") !== -1 ||
        id.indexOf("telegram") !== -1 || id.indexOf("slack") !== -1 ||
        id.indexOf("zoom") !== -1 || id.indexOf("teams") !== -1 ||
        id.indexOf("skype") !== -1 || id.indexOf("webrtc") !== -1) {
      return true
    }
    return false
  }

  // Reactive evaluation of MPRIS playback across all active players
  function recheckMpris() {
    var players = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (p && p.isPlaying && !root.isCallOrComm(p) && (p.trackTitle || p.trackArtist || p.canGoNext || p.canGoPrevious)) {
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
    if (root.mprisPlaying) return // MPRIS already drives visualizer with zero subprocess overhead
    if (sinkInputCheck.running) {
      sinkCheckPending = true
      return
    }
    sinkCheckPending = false
    sinkInputCheck.running = true
  }

  // Coalesces bursts of PipeWire events into one throttled sink-input scan
  Timer {
    id: sinkCheckThrottle
    interval: 1000
    repeat: false
    onTriggered: root.triggerSinkCheck()
  }

  // Real-time PipeWire audio event push (only reacts to stream creation/deletion)
  Process {
    id: pactlSubscriber
    command: ["pactl", "subscribe"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line || "")
        if (str.indexOf("sink-input") !== -1) {
          if (!sinkCheckThrottle.running) sinkCheckThrottle.start()
        }
      }
    }
  }

  // Check PipeWire active audio stream for non-MPRIS applications (games, audio tools, etc.)
  // Explicitly excludes lingering uncorked buffers from paused MPRIS browsers and players
  Process {
    id: sinkInputCheck
    command: ["sh", "-c", "pactl list sink-inputs 2>/dev/null | awk 'BEGIN { uncorked=0; mpris=0; call=0; count=0 } /Sink Input/ { if (uncorked && !mpris && !call) count++; uncorked=0; mpris=0; call=0 } /Corked: no/ { uncorked=1 } tolower($0) ~ /application\\.name = \"(chromium|chrome|firefox|zen|brave|opera|vivaldi|spotify|mpv|vlc|amberol)/ { mpris=1 } tolower($0) ~ /(webrtc|voiceengine|discord|whatsapp|telegram|slack|zoom|teams|skype|call|signal)/ { call=1 } END { if (uncorked && !mpris && !call) count++; if (count > 0) exit 0; exit 1 }'"]
    onExited: function(code) {
      root.nonMprisPlaying = (code === 0)
      if (root.sinkCheckPending) {
        root.sinkCheckPending = false
        sinkInputCheck.running = true
      }
    }
  }

  // Fallback polling for non-MPRIS audio
  Timer {
    interval: root.nonMprisPlaying ? 2500 : 4000
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
