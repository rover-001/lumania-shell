import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// ===========================================================================
// Bottom-Center Wallpaper Notch
// ---------------------------------------------------------------------------
//  • Resting: the mirror twin of the top Dynamic Island — a squircle lip rising
//    out of the middle of the BOTTOM border with two G1 concave shoulders that
//    melt into the border band (same unibody silhouette as the island, flipped).
//  • Hover (or click) blooms a horizontal filmstrip of wallpaper thumbnails.
//    No text anywhere: thumbs, a selection ring and a live-wallpaper frame only.
//  • ← / → step through the wallpapers and apply them live; Home / End jump to
//    the ends; ⏎ closes; esc dismisses. Clicking a thumb applies it directly,
//    the wheel steps too.
//  • Switching uses omarchy's own diagonal reveal (wallpaperInstantSwitch = false).
//    Heavy originals are pre-rendered to screen-sized twins so the reveal never
//    waits on a multi-megapixel decode.
//  • When apps are open the lip retracts flush into the frame and wakes again
//    when the cursor touches the bottom-centre edge.
//  • Motion is FluidSpring only: no durations, no easing curves, and an
//    interrupted bloom keeps its velocity.
//  • One silhouette morphs between resting and open, so there is no shape swap
//    (and therefore no pop) at any point of the transition.
// ===========================================================================
Item {
  id: root

  required property var frameConfig
  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  property color textColor: frameConfig.activeTextColor
  property color mutedColor: frameConfig.mutedColor
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  property bool isOpen: false
  property bool hasOpenApps: false
  // Screen origin, so screen-space pointer coordinates can be mapped locally
  property real screenX: 0
  property real screenY: 0

  // Reduced motion: keep direct manipulation, drop the bounce.
  property bool reduceMotion: false

  signal openRequested()
  signal closeRequested()

  // Interaction state: hover blooms, keyboard pins, esc / click-away closes
  property bool isHoverOpen: false
  property bool isPinned: false

  readonly property bool isOpenEffective: root.isOpen || root.isHoverOpen || root.isPinned
  readonly property bool isHovered: Boolean(notchHover && notchHover.hovered)

  // The window owns the authoritative open state; if it drops (IPC close,
  // fullscreen entry), clear every local latch so nothing lingers open.
  onIsOpenChanged: {
    if (!root.isOpen) {
      root.isPinned = false
      root.isHoverOpen = false
    }
  }

  // Hover only lifts the local latch: the window's own open flag stays clean so
  // a pointer leave can retract the panel without a stuck host binding.
  function hoverOpen() {
    root.isHoverOpen = true
    root.refreshWallpapers()
    root.refreshMotionPreference()
  }

  // Explicit open (IPC / keybind): local latch + host state + keyboard focus.
  function open() {
    root.isHoverOpen = true
    root.openRequested()
    root.refreshWallpapers()
    root.refreshMotionPreference()
  }

  function close() {
    root.isPinned = false
    root.isHoverOpen = false
    root.closeRequested()
  }

  // Pointer left the notch: retract unless the panel was explicitly pinned
  // (click on the lip) or opened by IPC / keybind.
  function hoverClose() {
    if (root.isPinned || root.isOpen) return
    root.isHoverOpen = false
  }

  function armHoverClose() {
    if (root.isPinned || root.isOpen) return
    hoverCloseTimer.restart()
  }

  function toggle() {
    if (root.isOpenEffective) root.close()
    else root.open()
  }

  // Hover opens -> the first tap pins (so the pointer may leave), a second tap
  // dismisses. Never closes a panel the pointer is still resting on.
  function tapPin() {
    if (root.isPinned) root.close()
    else root.isPinned = true
  }

  // -------------------------------------------------------------------------
  // Wallpaper catalogue
  // -------------------------------------------------------------------------
  property var wallpapers: []       // [{ path, name }]
  property int selectedIndex: 0
  property string selectedPath: ""
  property string activePath: ""
  property string pendingPath: ""
  property int pendingStep: 0
  property bool userNavigated: false
  property double lastScanAt: 0
  property bool scanQueued: false

  function baseName(path) {
    var parts = String(path || "").split("/")
    return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
  }

  function fileUrl(path) {
    return path ? ("file://" + path) : ""
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function scanDirs() {
    var home = Quickshell.env("HOME")
    var raw = root.frameConfig.wallpaperScanDirs || []
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var dir = String(raw[i] || "").trim()
      if (!dir) continue
      if (dir === "~") dir = home
      else if (dir.indexOf("~/") === 0) dir = home + dir.slice(1)
      out.push(dir)
    }
    return out
  }

  // force = true bypasses the freshness window (used right after a change).
  function refreshWallpapers(force) {
    var fresh = (Date.now() - root.lastScanAt) < root.frameConfig.wallpaperScanFreshness
    if (!force && root.wallpapers.length > 0 && fresh) {
      root.syncActiveWallpaper()
      return
    }
    if (listProc.running) {
      root.scanQueued = true
      return
    }

    var dirs = root.scanDirs()
    var parts = []
    for (var i = 0; i < dirs.length; i++) {
      var q = root.shellQuote(dirs[i])
      parts.push("[ -d " + q + " ] && find " + q + " -maxdepth 2 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.avif' \\) -print")
    }
    if (parts.length === 0) return

    // Canonical paths so the list can be compared against the live symlink
    // target (~/.local/state/omarchy/current/background).
    listProc.command = ["sh", "-c", parts.join("; ")
      + " | while IFS= read -r f; do readlink -f \"$f\"; done | sort -u"]
    listProc.running = true
  }

  function syncActiveWallpaper() {
    if (!activeProc.running) activeProc.running = true
  }

  function indexOfPath(path) {
    if (!path) return -1
    for (var i = 0; i < root.wallpapers.length; i++) {
      if (root.wallpapers[i].path === path) return i
    }
    return -1
  }

  function syncSelectionToActive() {
    if (root.userNavigated) return
    var idx = root.indexOfPath(root.activePath)
    if (idx >= 0) root.selectedIndex = idx
  }

  // instant = apply right now (pointer click, fresh key press, IPC hop).
  // Otherwise the call is coalesced, which keeps held arrow keys from spawning
  // a shell per auto-repeat tick.
  function select(index, instant) {
    if (index < 0 || index >= root.wallpapers.length) return
    var entry = root.wallpapers[index]
    if (!entry) return
    root.userNavigated = true
    root.selectedIndex = index
    root.selectedPath = entry.path
    root.pendingPath = entry.path
    if (instant) {
      applyDebounce.stop()
      root.applyPath(entry.path)
    } else {
      applyDebounce.restart()
    }
    Qt.callLater(root.revealSelection)
  }

  function step(delta, instant, pin) {
    if (root.wallpapers.length === 0) {
      root.pendingStep = delta
      root.refreshWallpapers(true)
      return
    }
    // Only an explicit pin keeps the panel alive after the pointer leaves.
    // Keyboard stepping never pins, so hovering out always retracts.
    if (pin === true) root.isPinned = true
    var count = root.wallpapers.length
    root.select((root.selectedIndex + delta + count) % count, instant === true)
  }

  function nextWallpaper(instant) {
    root.step(1, instant !== false, false)
  }

  function previousWallpaper(instant) {
    root.step(-1, instant !== false, false)
  }

  function jumpTo(edge) {
    if (root.wallpapers.length === 0) return
    root.select(edge === "start" ? 0 : root.wallpapers.length - 1, true)
  }

  function revealSelection() {
    if (filmstrip && filmstrip.count > 0) {
      filmstrip.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }
  }

  // -------------------------------------------------------------------------
  // Applying: one burst per wallpaper.
  //   1. repoint the live symlink (the color engine watches it)
  //   2. swap the background in the shell (instant IPC, crossfade fallback)
  // In-flight applies are never killed (that could leave the symlink and the
  // visible background out of sync); rapid steps coalesce onto the latest.
  // -------------------------------------------------------------------------
  property string applyInFlight: ""
  property string applyQueued: ""

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string backgroundMode: root.frameConfig.wallpaperInstantSwitch ? "setInstant" : "set"

  function applyPath(path) {
    if (!path) return
    // Optimistic: the ring / dot must not wait for a process.
    root.activePath = path
    root.applyQueued = path
    root.pumpApply()
  }

  function pumpApply() {
    if (applyProc.running || !root.applyQueued) return
    var path = root.applyQueued
    root.applyQueued = ""
    root.applyInFlight = path

    // $1 = canonical original (the state symlink the color engine watches)
    // $2 = render source (fast twin when the original is heavy)
    applyProc.command = ["sh", "-c",
      "ln -nsf -- \"$1\" \"$HOME/.local/state/omarchy/current/background\" && { "
      + "qs ipc -n -p \"$OMARCHY_PATH/shell\" call -- background " + root.backgroundMode + " \"$2\""
      + " || omarchy-shell -q background " + root.backgroundMode + " \"$2\"; }",
      "lumania-wallpaper", path, root.fastPathFor(path)]
    applyProc.running = true
  }

  Process {
    id: applyProc
    environment: ({
      "HOME": Quickshell.env("HOME") || "/home/rover",
      "PATH": (Quickshell.env("HOME") || "/home/rover") + "/.local/bin:/usr/local/bin:/usr/bin:/bin",
      "OMARCHY_PATH": root.omarchyPath,
      "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + (Quickshell.env("UID") || "1000")),
      "WAYLAND_DISPLAY": Quickshell.env("WAYLAND_DISPLAY") || "wayland-1"
    })
    onExited: function() {
      root.applyInFlight = ""
      if (root.applyQueued) root.pumpApply()
      else root.syncActiveWallpaper()
    }
  }

  // Debounce window for coalesced (auto-repeat) steps.
  Timer {
    id: applyDebounce
    interval: root.frameConfig.wallpaperApplyDebounce
    repeat: false
    onTriggered: root.applyPath(root.pendingPath)
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var list = []
        for (var i = 0; i < lines.length; i++) {
          var path = lines[i].trim()
          if (!path) continue
          list.push({ path: path, name: root.baseName(path) })
        }
        var changed = list.length !== root.wallpapers.length
        if (!changed) {
          for (var j = 0; j < list.length; j++) {
            if (list[j].path !== root.wallpapers[j].path) {
              changed = true
              break
            }
          }
        }
        if (changed) {
          root.wallpapers = list
          root.warmDecodeCache()
          if (root.selectedIndex >= list.length) {
            root.selectedIndex = Math.max(0, list.length - 1)
          }
        }
        root.lastScanAt = Date.now()
        root.syncSelectionToActive()

        // A keybind/IPC step may have arrived before the catalogue was ready.
        if (root.pendingStep !== 0 && list.length > 0) {
          var delta = root.pendingStep
          root.pendingStep = 0
          root.select((root.selectedIndex + delta + list.length) % list.length, true)
        }

        Qt.callLater(root.revealSelection)
        if (root.scanQueued) {
          root.scanQueued = false
          root.refreshWallpapers(true)
        }
      }
    }
  }

  Process {
    id: activeProc
    command: ["readlink", "-f", (Quickshell.env("HOME") || "/home/rover") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (!path) return
        root.activePath = path
        root.syncSelectionToActive()
      }
    }
  }

  // -------------------------------------------------------------------------
  // Decode cache for heavy source files.
  //
  // omarchy's background layer decodes the chosen file at full layer size with
  // `cache: false`, so a multi-megapixel PNG costs 300ms+ before the reveal can
  // even start — that is why one wallpaper always felt slower than the rest.
  // Each heavy file gets a screen-sized JPEG twin under
  // ~/.cache/lumania/wallpapers; the render path uses the twin (identical crop:
  // resize-to-cover + center extent == Image.PreserveAspectCrop), while the
  // omarchy state symlink keeps pointing at the untouched original.
  // -------------------------------------------------------------------------
  property var fastPaths: ({})
  property string cacheWarmKey: ""
  readonly property string cacheDir: (Quickshell.env("HOME") || "/home/rover")
    + "/.cache/lumania/wallpapers"

  function fastPathFor(path) {
    if (!path) return ""
    var fast = root.fastPaths[path]
    return fast ? fast : path
  }

  function warmDecodeCache() {
    if (!root.frameConfig.wallpaperDecodeCacheEnabled) return
    if (cacheWarmProc.running || root.wallpapers.length === 0) return
    var key = ""
    var args = []
    for (var i = 0; i < root.wallpapers.length; i++) {
      var p = root.wallpapers[i].path
      key += p + "|"
      args.push(p)
    }
    if (key === root.cacheWarmKey) return
    root.cacheWarmKey = key

    var script = "cache=\"$1\"; shift; mkdir -p \"$cache\" || exit 0; "
      + "min=" + root.frameConfig.wallpaperDecodeCacheMinBytes + "; "
      + "w=" + root.frameConfig.wallpaperCacheWidth + "; "
      + "h=" + root.frameConfig.wallpaperCacheHeight + "; "
      + "q=" + root.frameConfig.wallpaperCacheQuality + "; "
      + "for p in \"$@\"; do "
      + "  [ -f \"$p\" ] || continue; "
      + "  size=$(stat -c %s \"$p\" 2>/dev/null || echo 0); "
      + "  [ \"$size\" -lt \"$min\" ] 2>/dev/null && continue; "
      + "  key=$(printf '%s|%s|%s' \"$p\" \"$size\" \"$(stat -c %Y \"$p\" 2>/dev/null)\" | md5sum | cut -c1-16); "
      + "  out=\"$cache/$key.jpg\"; "
      + "  if [ ! -s \"$out\" ]; then "
      + "    magick \"$p\" -auto-orient -resize \"${w}x${h}^\" -gravity center -extent \"${w}x${h}\" -quality \"$q\" \"$out\" >/dev/null 2>&1 || { rm -f \"$out\"; continue; }; "
      + "  fi; "
      + "  printf '%s\\t%s\\n' \"$p\" \"$out\"; "
      + "done"

    cacheWarmProc.command = ["sh", "-c", script, "lumania-wallpaper-cache", root.cacheDir]
      .concat(args)
    cacheWarmProc.running = true
  }

  Process {
    id: cacheWarmProc
    environment: ({
      "HOME": Quickshell.env("HOME") || "/home/rover",
      "PATH": (Quickshell.env("HOME") || "/home/rover") + "/.local/bin:/usr/local/bin:/usr/bin:/bin",
      "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + (Quickshell.env("UID") || "1000")),
      "WAYLAND_DISPLAY": Quickshell.env("WAYLAND_DISPLAY") || "wayland-1"
    })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var map = {}
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length < 2) continue
          var src = parts[0].trim()
          var dst = parts[1].trim()
          if (src && dst) map[src] = dst
        }
        root.fastPaths = map
      }
    }
  }

  // Reduced motion: Hyprland owns the global animation switch.
  Process {
    id: motionPreferenceProc
    command: ["hyprctl", "getoption", "animations:enabled"]
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line || "").toLowerCase()
        if (str.indexOf("false") >= 0 || str.indexOf("int: 0") >= 0) root.reduceMotion = true
        else if (str.indexOf("true") >= 0 || str.indexOf("int: 1") >= 0) root.reduceMotion = false
      }
    }
  }

  function refreshMotionPreference() {
    if (!motionPreferenceProc.running) motionPreferenceProc.running = true
  }

  Component.onCompleted: {
    root.syncActiveWallpaper()
    root.refreshMotionPreference()
    root.refreshWallpapers(true)
  }

  onIsOpenEffectiveChanged: {
    if (root.isOpenEffective) {
      // Every open starts from the live wallpaper again; a previous browse
      // must not leave the ring parked on a thumb that is not applied.
      root.userNavigated = false
      root.syncSelectionToActive()
      root.refreshWallpapers()
      Qt.callLater(function() {
        if (keyCatcher) keyCatcher.forceActiveFocus()
      })
    }
  }

  // -------------------------------------------------------------------------
  // Sizing, geometry & bloom driver
  // -------------------------------------------------------------------------
  readonly property real collapsedWidth: root.frameConfig.wallpaperCollapsedWidth
  // The panel is exactly as wide as the strip it carries, so two wallpapers
  // never leave a dead band of empty panel on either side. Past
  // wallpaperMaxVisibleThumbs it stops growing and the strip scrolls instead.
  readonly property int visibleThumbs: Math.max(1, Math.min(
    root.wallpapers.length > 0 ? root.wallpapers.length : root.frameConfig.wallpaperMaxVisibleThumbs,
    root.frameConfig.wallpaperMaxVisibleThumbs))

  readonly property real targetExpandedWidth: Math.max(root.collapsedWidth,
    root.frameConfig.wallpaperContentPadding * 2
      + root.visibleThumbs * root.frameConfig.wallpaperThumbWidth
      + Math.max(0, root.visibleThumbs - 1) * root.frameConfig.wallpaperThumbSpacing
      + 16)

  property real expandedWidth: targetExpandedWidth

  Behavior on expandedWidth {
    NumberAnimation {
      duration: 220
      easing.type: Easing.OutCubic
    }
  }

  readonly property real collapsedHeight: root.borderThickness
    + root.frameConfig.wallpaperCollapsedHeight
  readonly property real expandedHeight: root.borderThickness
    + root.frameConfig.wallpaperExpandedHeight

  readonly property real currentFlareRadius: root.frameConfig.wallpaperFlareRadius
    + (openProgress * (root.frameConfig.wallpaperExpandedFlareRadius - root.frameConfig.wallpaperFlareRadius))
  readonly property real currentCornerRadius: root.frameConfig.wallpaperCornerRadius
    + (openProgress * (root.frameConfig.wallpaperExpandedCornerRadius - root.frameConfig.wallpaperCornerRadius))

  // Driver value for iOS Fluid Motion: 0.0 (Closed / Resting Lip) -> 1.0 (Full Expanded Filmstrip)
  readonly property real targetProgress: root.isOpenEffective ? 1.0 : 0.0
  property real openProgress: targetProgress

  Behavior on openProgress {
    NumberAnimation {
      duration: root.reduceMotion
        ? (root.isOpenEffective ? 180 : 140)
        : (root.isOpenEffective ? (root.frameConfig ? root.frameConfig.wallpaperOpenDuration : 380)
                                : (root.frameConfig ? root.frameConfig.wallpaperCloseDuration : 260))
      easing.type: (root.reduceMotion || !root.isOpenEffective) ? Easing.OutCubic : Easing.OutBack
      easing.overshoot: (root.reduceMotion || !root.isOpenEffective)
        ? 1.0
        : (root.frameConfig ? root.frameConfig.wallpaperOpenOvershoot : 1.04)
    }
  }

  readonly property real progressNorm: Math.min(1.0, Math.max(0.0, openProgress))

  // Authentic iOS fluid motion:
  // Width expands monotonically to the dynamically computed panel width.
  // Using progressNorm guarantees zero overshoot/rebound shrinking on the width axis.
  readonly property real currentWidth: collapsedWidth
    + (progressNorm * (expandedWidth - collapsedWidth))
    + (Math.sin(progressNorm * Math.PI) * (root.frameConfig ? root.frameConfig.wallpaperWidthPulse : 0))

  readonly property real currentHeight: collapsedHeight
    + (openProgress * (expandedHeight - collapsedHeight))
    + (Math.sin(progressNorm * Math.PI) * (root.frameConfig ? root.frameConfig.wallpaperHeightPulse : 4))

  // Exposed items for PanelWindow masking
  property alias maskItem: notchContainer
  property alias backdropItem: backdropOverlay
  property alias wakeItem: wakeZone

  // Grace period so the panel does not snap shut while the pointer crosses it.
  // The timer is armed on pointer leave and cancelled on pointer enter, so it
  // is authoritative: it never consults a cached hovered flag.
  Timer {
    id: hoverCloseTimer
    interval: root.frameConfig.wallpaperHoverCloseDelay
    repeat: false
    onTriggered: root.hoverClose()
  }

  // Pointer containment.
  //
  // A layer surface does not reliably deliver the hover-exit that a
  // HoverHandler needs (the panel grows under the pointer and the leave event
  // can be swallowed), which is why hovering out used to leave it stuck open.
  // So containment is measured against the real cursor position instead.
  property real pointerX: -1
  property real pointerY: -1
  property int outsideTicks: 0

  function probePointer() {
    if (!cursorProbe.running) cursorProbe.running = true
  }

  function pointerInsideNotch() {
    // Unknown position: assume inside rather than closing on a guess.
    if (root.pointerX < 0 || root.pointerY < 0) return true
    var origin = notchContainer.mapToItem(null, 0, 0)
    var pad = root.frameConfig.wallpaperPointerGrace
    var px = root.pointerX - root.screenX
    var py = root.pointerY - root.screenY
    return px >= origin.x - pad && py >= origin.y - pad
      && px <= origin.x + notchContainer.width + pad
      && py <= origin.y + notchContainer.height + pad
  }

  function evaluatePointer() {
    if (root.isPinned) {
      root.outsideTicks = 0
      return
    }
    if (root.pointerInsideNotch()) {
      root.outsideTicks = 0
      return
    }
    root.outsideTicks++
    if (root.outsideTicks < root.frameConfig.wallpaperWatchdogStrikes) return
    root.outsideTicks = 0
    root.hoverClose()
  }

  Process {
    id: cursorProbe
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split(",")
        if (parts.length < 2) return
        var x = parseFloat(parts[0])
        var y = parseFloat(parts[1])
        if (isNaN(x) || isNaN(y)) return
        root.pointerX = x
        root.pointerY = y
        root.evaluatePointer()
      }
    }
  }

  Timer {
    interval: root.frameConfig.wallpaperPointerPollInterval
    repeat: true
    // Only a hover-only open is polled; IPC / keybind opens stay put.
    running: root.isOpenEffective && root.isHoverOpen && !root.isPinned && !root.isOpen
    onTriggered: root.probePointer()
  }

  // -------------------------------------------------------------------------
  // Auto-retract: lip slides down flush into the bottom border when apps are
  // open. The bottom-centre edge strip wakes it again (masked only while the
  // lip is actually retracted, so it never steals clicks from windows).
  // -------------------------------------------------------------------------
  readonly property bool shouldRetract: root.hasOpenApps && !root.isOpenEffective
    && root.openProgress < root.frameConfig.wallpaperRetractProgressEpsilon && !root.isHovered

  readonly property bool wakeZoneActive: root.shouldRetract

  FluidSpring {
    id: retractSpring
    target: root.shouldRetract ? -(root.collapsedHeight - root.borderThickness) : 0.0
    response: root.shouldRetract
      ? root.frameConfig.wallpaperRetractResponse : root.frameConfig.wallpaperWakeResponse
    dampingFraction: root.shouldRetract
      ? root.frameConfig.wallpaperRetractDamping : root.frameConfig.wallpaperWakeDamping
    epsilon: 0.05
    reduceMotion: root.reduceMotion
  }

  Item {
    id: wakeZone
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    width: root.wakeZoneActive
      ? Math.max(root.frameConfig.wallpaperWakeZoneWidth, root.collapsedWidth) : 0
    height: root.wakeZoneActive ? root.borderThickness + root.frameConfig.wallpaperWakeZoneHeight : 0

    // Waking the retracted lip is a HOVER, never an explicit open: a sticky
    // open here used to leave the panel stuck on screen after the pointer left.
    HoverHandler {
      id: wakeHover
      onHoveredChanged: {
        if (hovered) {
          hoverCloseTimer.stop()
          root.hoverOpen()
        } else {
          root.armHoverClose()
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Full-Screen Click-Away Catcher (no backdrop dimming)
  // -------------------------------------------------------------------------
  Item {
    id: backdropOverlay
    width: root.isOpenEffective ? parent.width : 0
    height: root.isOpenEffective ? parent.height : 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    visible: root.isOpenEffective && root.openProgress > 0.01

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  // -------------------------------------------------------------------------
  // Bottom-Center Anchored Notch Container
  // -------------------------------------------------------------------------
  Item {
    id: notchContainer
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: retractSpring.value

    width: root.currentWidth
    height: root.currentHeight

    property color activeColor: root.notchColor
    // Space above the border band: the silhouette lives here
    readonly property real protrusion: Math.max(1, root.currentHeight - root.borderThickness)

    HoverHandler {
      id: notchHover
      cursorShape: root.isOpenEffective ? Qt.ArrowCursor : Qt.PointingHandCursor
      onHoveredChanged: {
        if (hovered) {
          hoverCloseTimer.stop()
          root.outsideTicks = 0
          root.hoverOpen()
        } else {
          root.armHoverClose()
        }
      }
    }

    // Tactile press feedback when resting
    property bool isLipPressed: restingTap.pressed

    FluidSpring {
      id: lipPressSpring
      target: (!root.isOpenEffective && notchContainer.isLipPressed)
        ? root.frameConfig.wallpaperRestingPressScale : 1.0
      response: notchContainer.isLipPressed
        ? root.frameConfig.wallpaperPressResponse : root.frameConfig.wallpaperReleaseResponse
      dampingFraction: notchContainer.isLipPressed
        ? root.frameConfig.wallpaperPressDamping : root.frameConfig.wallpaperReleaseDamping
      epsilon: root.frameConfig.wallpaperSpringEpsilon
      reduceMotion: root.reduceMotion
      value: 1.0
    }

    scale: lipPressSpring.value
    transformOrigin: Item.Bottom

    // -----------------------------------------------------------------------
    // One silhouette, morphed by openProgress: the Dynamic Island flipped over.
    //
    //   bottom-left / bottom-right -> the island's TOP flare, mirrored: the body
    //                                 side curves out and down into the band
    //                                 with the same 0.5 bezier pull
    //   top-left / top-right       -> the island's BOTTOM pill corners, mirrored:
    //                                 real arcs, no bezier approximation
    //
    // The outer edge spans the full container width (like the island spans the
    // screen width through the band) and the body is inset by rFlare, which is
    // exactly the island relation (body + 2 * topCurveRadius).
    // -----------------------------------------------------------------------
    Shape {
      id: silhouette
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      readonly property real w: silhouette.width
      readonly property real h: silhouette.height
      readonly property real b: root.borderThickness
      readonly property real protrusion: Math.max(1, h - b)

      // Shoulder flare: the island's top curve radius, clamped by the height
      readonly property real rFlare: Math.max(0.5,
        Math.min(root.currentFlareRadius, notchContainer.protrusion * 0.5))
      // Free edge corners: the island's bottom corner radius, clamped so the
      // free edge (w - 2 * rFlare) can never invert
      readonly property real freeWidth: Math.max(2, silhouette.w - 2 * silhouette.rFlare)
      readonly property real rCorner: Math.max(0, Math.min(root.currentCornerRadius,
        Math.max(0, notchContainer.protrusion - silhouette.rFlare),
        silhouette.freeWidth * root.frameConfig.wallpaperTopEdgeGuardRatio))
      // Island flare pull (0.5 = identical curve, lower = tighter shoulder)
      readonly property real ctl: root.frameConfig.wallpaperFlareControlRatio
      readonly property real bleed: root.frameConfig.wallpaperBleed
      readonly property real borderTop: silhouette.h - silhouette.b

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: notchContainer.activeColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        // Start below the bottom edge: zero-bleed seal with the border band
        startX: 0
        startY: silhouette.h + silhouette.bleed

        // Bottom edge of the outer band, all the way to the right side.
        // This vertex is mandatory: without it the path cuts a diagonal from
        // the bottom-left corner straight to the right shoulder and the whole
        // left half of the silhouette is sliced away.
        PathLine {
          x: silhouette.w
          y: silhouette.h + silhouette.bleed
        }

        // Right outer edge up through the band to the right shoulder
        PathLine {
          x: silhouette.w
          y: silhouette.borderTop
        }

        // Right shoulder: band edge sweeps out and up into the body side
        // (mirror of the island's top-right flare)
        PathCubic {
          x: silhouette.w - silhouette.rFlare
          y: silhouette.borderTop - silhouette.rFlare
          control1X: silhouette.w - (silhouette.rFlare * silhouette.ctl)
          control1Y: silhouette.borderTop
          control2X: silhouette.w - silhouette.rFlare
          control2Y: silhouette.borderTop - (silhouette.rFlare * silhouette.ctl)
        }

        // Body side up to the free corner
        PathLine {
          x: silhouette.w - silhouette.rFlare
          y: silhouette.rCorner
        }

        // Free top-right corner: island bottom-corner pill arc, mirrored
        PathArc {
          x: silhouette.w - silhouette.rFlare - silhouette.rCorner
          y: 0
          radiusX: silhouette.rCorner
          radiusY: silhouette.rCorner
          direction: PathArc.Counterclockwise
        }

        // Free top edge
        PathLine {
          x: silhouette.rFlare + silhouette.rCorner
          y: 0
        }

        // Free top-left corner: island bottom-corner pill arc, mirrored
        PathArc {
          x: silhouette.rFlare
          y: silhouette.rCorner
          radiusX: silhouette.rCorner
          radiusY: silhouette.rCorner
          direction: PathArc.Counterclockwise
        }

        // Body side down to the left shoulder
        PathLine {
          x: silhouette.rFlare
          y: silhouette.borderTop - silhouette.rFlare
        }

        // Left shoulder: body side curves out and down into the band
        PathCubic {
          x: 0
          y: silhouette.borderTop
          control1X: silhouette.rFlare
          control1Y: silhouette.borderTop - (silhouette.rFlare * silhouette.ctl)
          control2X: silhouette.rFlare * silhouette.ctl
          control2Y: silhouette.borderTop
        }

        // Outer edge back down through the band (zero-bleed seal)
        PathLine {
          x: 0
          y: silhouette.h + silhouette.bleed
        }
      }
    }

    // -----------------------------------------------------------------------
    // Resting state: the lip itself is the hover / tap target
    // -----------------------------------------------------------------------
    Item {
      id: restingArea
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: root.collapsedWidth
      height: root.collapsedHeight
      visible: root.openProgress < root.frameConfig.wallpaperRestingHideAt
      opacity: Math.max(0.0, 1.0 - root.openProgress * root.frameConfig.wallpaperRestingFadeRate)

      TapHandler {
        id: restingTap
        onTapped: root.tapPin()
      }
    }

    // -----------------------------------------------------------------------
    // Wallpaper filmstrip — thumbs only, no text at all
    // -----------------------------------------------------------------------
    Item {
      id: expandedView
      anchors.fill: parent
      anchors.bottomMargin: root.borderThickness
      anchors.leftMargin: root.frameConfig.wallpaperContentPadding
      anchors.rightMargin: root.frameConfig.wallpaperContentPadding

      visible: opacity > 0.01
      opacity: Math.max(0.0, Math.min(1.0,
        (root.openProgress - root.frameConfig.wallpaperContentFadeStart)
          * root.frameConfig.wallpaperContentFadeRate))
      scale: root.frameConfig.wallpaperContentScaleFrom
        + ((1.0 - root.frameConfig.wallpaperContentScaleFrom) * root.progressNorm)
      transformOrigin: Item.Bottom

      ListView {
        id: filmstrip
        anchors.fill: parent

        orientation: ListView.Horizontal
        spacing: root.frameConfig.wallpaperThumbSpacing
        clip: false
        boundsBehavior: Flickable.StopAtBounds
        model: root.wallpapers
        currentIndex: root.selectedIndex
        cacheBuffer: root.frameConfig.wallpaperCacheBuffer
        reuseItems: true

        delegate: Item {
          id: thumbDelegate

          readonly property var entry: modelData
          readonly property int itemIndex: index
          readonly property bool isSelected: itemIndex === root.selectedIndex
          readonly property bool isApplied: Boolean(entry) && entry.path === root.activePath

          width: root.frameConfig.wallpaperThumbWidth
          height: filmstrip.height

          Item {
            id: thumbFrame
            anchors.centerIn: parent
            width: root.frameConfig.wallpaperThumbWidth
            height: root.frameConfig.wallpaperThumbHeight

            FluidSpring {
              id: thumbSpring
              target: thumbDelegate.isSelected
                ? root.frameConfig.wallpaperSelectedScale
                : (thumbArea.containsMouse ? root.frameConfig.wallpaperHoverScale : 1.0)
              response: root.frameConfig.wallpaperThumbHoverResponse
              dampingFraction: root.frameConfig.wallpaperThumbHoverDamping
              epsilon: root.frameConfig.wallpaperSpringEpsilon
              reduceMotion: root.reduceMotion
              value: 1.0
            }

            scale: thumbSpring.value

            // Rounded plate: the placeholder the thumb fades in over.
            Rectangle {
              anchors.fill: parent
              radius: root.frameConfig.wallpaperThumbRadius
              color: root.frameConfig.wallpaperThumbBg
            }

            // Rounded GPU mask. It must stay rendered for the effect to sample
            // it, but it is never painted itself (visible: false) — leaving it
            // visible is what used to flash a grey card on a decoding thumb.
            Rectangle {
              id: thumbMask
              anchors.fill: parent
              radius: root.frameConfig.wallpaperThumbRadius
              color: "#ffffff"
              visible: false
              layer.enabled: true
            }

            // Stable layer around the image so recycling a delegate never tears
            // down the effect, and the fade-in happens inside the mask.
            Item {
              anchors.fill: parent
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: thumbMask
              }

              Image {
                id: thumbImage
                anchors.fill: parent
                source: root.fileUrl(thumbDelegate.entry
                  ? root.fastPathFor(thumbDelegate.entry.path) : "")
                sourceSize.width: root.frameConfig.wallpaperThumbWidth
                  * root.frameConfig.wallpaperThumbSourceScale
                sourceSize.height: root.frameConfig.wallpaperThumbHeight
                  * root.frameConfig.wallpaperThumbSourceScale
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true

                // Never show a half-decoded frame: the plate stays until the
                // pixels exist, then the thumb fades in. No grey, no stutter.
                opacity: status === Image.Ready ? 1 : 0
                onStatusChanged: {
                  console.log("[LUMANIA-THUMB]", thumbDelegate.itemIndex, "status=" + status, "source=" + source)
                }
                Behavior on opacity {
                  NumberAnimation {
                    duration: root.frameConfig.wallpaperThumbFadeDuration
                    easing.type: Easing.OutCubic
                  }
                }
              }
            }

            // Hover wash (under the ring so the ring stays crisp)
            Rectangle {
              anchors.fill: parent
              radius: root.frameConfig.wallpaperThumbRadius
              color: root.frameConfig.wallpaperItemHoverBg
              opacity: (thumbArea.containsMouse && !thumbDelegate.isSelected) ? 1 : 0

              Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            // Selection ring / live-wallpaper frame / rest hairline.
            // The live wallpaper is marked by a border, never by a dot.
            Rectangle {
              anchors.fill: parent
              radius: root.frameConfig.wallpaperThumbRadius
              color: "transparent"
              border.width: thumbDelegate.isSelected
                ? root.frameConfig.wallpaperSelectedBorderWidth
                : (thumbDelegate.isApplied
                  ? root.frameConfig.wallpaperAppliedBorderWidth
                  : 1)
              border.color: thumbDelegate.isSelected
                ? root.frameConfig.wallpaperThumbActiveBorder
                : (thumbDelegate.isApplied
                  ? root.frameConfig.wallpaperAppliedBorderColor
                  : (thumbArea.containsMouse ? root.frameConfig.wallpaperThumbHoverBorder
                                             : root.frameConfig.wallpaperThumbBorder))

              Behavior on border.color { ColorAnimation { duration: 150 } }
            }

            MouseArea {
              id: thumbArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.select(thumbDelegate.itemIndex, true)
            }
          }
        }
      }

      // Decode pre-warm: one hidden image per wallpaper at the exact thumbnail
      // decode size. Qt caches by (url, sourceSize), so every delegate paints
      // on its first frame instead of flashing grey and decoding on the fly.
      Row {
        visible: false
        Repeater {
          model: root.wallpapers

          delegate: Image {
            required property var modelData
            width: 0
            height: 0
            source: root.fileUrl(root.fastPathFor(modelData.path))
            sourceSize.width: root.frameConfig.wallpaperThumbWidth
              * root.frameConfig.wallpaperThumbSourceScale
            sourceSize.height: root.frameConfig.wallpaperThumbHeight
              * root.frameConfig.wallpaperThumbSourceScale
            asynchronous: true
            cache: true
          }
        }
      }

      // Mouse wheel / two-finger swipe steps the wallpapers. Sits above the
      // strip (so the Flickable cannot swallow the wheel) but only claims wheel
      // events, leaving clicks and hover to the thumbs underneath.
      Item {
        anchors.fill: parent

        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            if (Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)) {
              if (event.angleDelta.x > 0) root.step(1, true)
              else if (event.angleDelta.x < 0) root.step(-1, true)
            } else if (event.angleDelta.y !== 0) {
              root.step(event.angleDelta.y > 0 ? -1 : 1, true)
            }
            event.accepted = true
          }
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Keyboard: the window owns exclusive keyboard focus while open
  // -------------------------------------------------------------------------
  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: root.isOpenEffective

    Keys.onPressed: function(event) {
      if (!root.isOpenEffective) return

      // Fresh presses land instantly; auto-repeat is coalesced by select().
      var instant = !event.isAutoRepeat

      switch (event.key) {
      case Qt.Key_Left:
        root.step(-1, instant)
        event.accepted = true
        break
      case Qt.Key_Right:
        root.step(1, instant)
        event.accepted = true
        break
      case Qt.Key_Up:
        root.step(-1, instant)
        event.accepted = true
        break
      case Qt.Key_Down:
        root.step(1, instant)
        event.accepted = true
        break
      case Qt.Key_Home:
        root.jumpTo("start")
        event.accepted = true
        break
      case Qt.Key_End:
        root.jumpTo("end")
        event.accepted = true
        break
      case Qt.Key_Return:
      case Qt.Key_Enter:
        root.close()
        event.accepted = true
        break
      case Qt.Key_Escape:
        root.close()
        event.accepted = true
        break
      default:
        break
      }
    }
  }
}
