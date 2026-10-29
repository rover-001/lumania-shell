import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Item {
  id: root

  // Exposed notification state consumed by Dynamic Island
  property bool hasNotification: false
  property string currentSummary: ""
  property string currentBody: ""
  property string currentAppName: ""
  property string currentAppIcon: ""
  property string currentImage: ""
  property string currentGlyph: ""
  property int currentUrgency: 1 // 0: low, 1: normal, 2: critical
  property var currentExecArgv: null
  property var currentNotificationRef: null

  // Pointer hover state (pauses auto-dismiss timer while user is inspecting)
  property bool isHovered: false

  // Focus / Do Not Disturb: suppress popups (critical urgency still passes)
  property bool dnd: false

  // Per-sender avatar files ($XDG_RUNTIME_DIR/lumania-avatars, owner-only) so repeat
  // messages from the same person keep their picture when the sender omits it, and
  // calls can reuse it. Empty when no private runtime dir exists (avatars not saved).
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  readonly property string avatarDir: runtimeDir ? runtimeDir + "/lumania-avatars" : ""
  property var savedAvatars: ({})

  function senderKey(app, summary) {
    var a = String(app || "").toLowerCase().replace(/[^a-z0-9]+/g, "")
    var n = String(summary || "").toLowerCase().replace(/\s*\(.*$/, "").replace(/[^a-z0-9]+/g, "")
    return a + "__" + n
  }

  // Queue for multiple incoming notifications
  property var notificationQueue: []

  // Ensure Omarchy's default notification plugin remains disabled
  Component.onCompleted: {
    ensureDefaultDisabled()
    legacyCleanupProc.running = true
  }

  // Remove world-readable caches left in /tmp by earlier versions (only our own files)
  Process {
    id: legacyCleanupProc
    command: ["sh", "-c", "for p in /tmp/lumania-avatars /tmp/lumania-call-cache.json; do [ -O \"$p\" ] && rm -rf -- \"$p\"; done; true"]
    running: false
  }

  function ensureDefaultDisabled() {
    ensureDisabledProc.running = true
  }

  Process {
    id: ensureDisabledProc
    command: ["sh", "-c", "grep -q '\"omarchy.notifications\"' ~/.config/omarchy/shell.json 2>/dev/null || omarchy plugin disable omarchy.notifications 2>/dev/null"]
    running: false
  }

  // Native Quickshell Notification Server
  NotificationServer {
    id: server
    keepOnReload: false
    imageSupported: true
    actionsSupported: true
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true
    persistenceSupported: true

    onNotification: function(notification) {
      root.handleIncoming(notification)
    }
  }

  // Auto-expire timer
  Timer {
    id: dismissTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (root.isHovered) {
        root.restartOnUnhover = true
      } else {
        root.dismissCurrent()
      }
    }
  }

  property bool restartOnUnhover: false

  onIsHoveredChanged: {
    if (isHovered) {
      if (dismissTimer.running) {
        dismissTimer.stop()
        restartOnUnhover = true
      }
    } else {
      if (restartOnUnhover && hasNotification) {
        restartOnUnhover = false
        dismissTimer.interval = 2500 // give 2.5s grace period after pointer leaves
        dismissTimer.start()
      }
    }
  }

  // Sanitize markup, domain links (e.g. web.whatsapp.com), and extra whitespace
  function cleanText(str) {
    if (!str) return ""
    return String(str)
      // Strip HTML tags
      .replace(/<[^>]*>/g, "")
      // Strip HTML entities
      .replace(/&amp;/g, "&")
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      // Strip full URLs (http:// or https://)
      .replace(/https?:\/\/\S+/gi, "")
      // Strip leading web domain prefixes e.g. "web.whatsapp.com\n", "web.whatsapp.com - ", "web.whatsapp.com: "
      .replace(/^\s*(?:[a-zA-Z0-9\-]+\.)+[a-zA-Z]{2,}(?::\d+)?(?:\/\S*)?\s*[-—:\s]*/i, "")
      // Strip standalone domain links like web.whatsapp.com, discord.com
      .replace(/\b(?:[a-zA-Z0-9\-]+\.)*(?:whatsapp|telegram|discord|slack|youtube|github|google|twitter|x)\.(?:com|org|net|app|io|me)\b(?:\/\S*)?/gi, "")
      // Collapse newlines and whitespace
      .replace(/\r?\n|\r/g, " ")
      .replace(/\s+/g, " ")
      .trim()
  }

  // Friendly application name fallback (replaces raw domain URLs like web.whatsapp.com)
  function resolveAppName(appName, summary) {
    var raw = (String(appName || "") + " " + String(summary || "")).toLowerCase()
    if (raw.indexOf("whatsapp") !== -1) return "WhatsApp"
    if (raw.indexOf("telegram") !== -1) return "Telegram"
    if (raw.indexOf("discord") !== -1) return "Discord"
    if (raw.indexOf("slack") !== -1) return "Slack"
    if (raw.indexOf("spotify") !== -1) return "Spotify"
    if (raw.indexOf("youtube") !== -1) return "YouTube"
    if (raw.indexOf("steam") !== -1) return "Steam"
    if (raw.indexOf("zed") !== -1) return "Zed"
    if (raw.indexOf("code") !== -1) return "VS Code"

    var name = String(appName || "").trim()
    if (name.indexOf(".") !== -1) {
      name = name.replace(/^(?:https?:\/\/)?(?:web\.)?/i, "").replace(/\.(?:com|org|net|app|io|me|ai)$/i, "")
    }
    return name || "App"
  }

  function handleIncoming(notification) {
    if (!notification) return
    if (root.dnd && notification.urgency !== 2) return
    notification.tracked = true

    var rawSummary = cleanText(notification.summary)
    var rawBody = cleanText(notification.body)
    var appName = String(notification.appName || "").trim()
    var appIcon = String(notification.appIcon || "").trim()
    var image = String(notification.image || "").trim()
    var glyph = ""
    var execArgv = null

    // If summary was just a website link like web.whatsapp.com and got stripped, use friendly app name
    if (!rawSummary || rawSummary.length === 0) {
      rawSummary = resolveAppName(appName, notification.summary)
    }

    try {
      if (notification.hints) {
        if (notification.hints["omarchy-glyph"]) {
          glyph = String(notification.hints["omarchy-glyph"])
        }
        if (notification.hints["image-path"] && !image) {
          image = String(notification.hints["image-path"])
        }
        if (notification.hints["omarchy-exec-argv"]) {
          var parsed = JSON.parse(String(notification.hints["omarchy-exec-argv"]))
          if (Array.isArray(parsed)) execArgv = parsed
        }
      }
    } catch (e) {
      console.warn("Notification hint parsing error:", e)
    }

    // Same sender, no picture this time: reuse the one we saved earlier
    if (!image) {
      var known = root.savedAvatars[root.senderKey(appName, rawSummary)]
      if (known) image = known
    }

    // Default duration: 5000ms. Senders specifying expireTimeout are respected within 3-12s
    var timeout = 5000
    if (notification.expireTimeout && notification.expireTimeout > 0) {
      timeout = Math.max(3000, Math.min(12000, notification.expireTimeout))
    } else if (notification.urgency === 2) {
      timeout = 8000
    }

    var item = {
      summary: rawSummary,
      body: rawBody,
      appName: appName,
      appIcon: appIcon,
      image: image,
      glyph: glyph,
      urgency: typeof notification.urgency === "number" ? notification.urgency : 1,
      execArgv: execArgv,
      timeout: timeout,
      ref: notification
    }

    if (root.hasNotification) {
      // If updating an already showing notification (e.g. replaces_id or progress)
      if (root.currentNotificationRef && (root.currentNotificationRef.id === notification.id || (appName && appName === root.currentAppName && rawSummary === root.currentSummary))) {
        root.displayNotification(item)
        return
      }
      var q = root.notificationQueue.slice()
      q.push(item)
      root.notificationQueue = q
    } else {
      root.displayNotification(item)
    }
  }

  function displayNotification(item) {
    root.currentSummary = item.summary
    root.currentBody = item.body
    root.currentAppName = item.appName
    root.currentAppIcon = item.appIcon
    root.currentImage = item.image
    root.currentGlyph = item.glyph
    root.currentUrgency = item.urgency
    root.currentExecArgv = item.execArgv
    root.currentNotificationRef = item.ref
    root.hasNotification = true

    root.restartOnUnhover = false
    dismissTimer.stop()
    dismissTimer.interval = item.timeout
    if (!root.isHovered) {
      dismissTimer.start()
    } else {
      root.restartOnUnhover = true
    }
  }

  function dismissCurrent() {
    dismissTimer.stop()
    root.restartOnUnhover = false

    var ref = root.currentNotificationRef
    root.currentNotificationRef = null
    if (ref) {
      try {
        if (ref.tracked) {
          ref.tracked = false
        }
      } catch (e) {}
    }

    // Check if more notifications are waiting in queue
    if (root.notificationQueue.length > 0) {
      var q = root.notificationQueue.slice()
      var nextItem = q.shift()
      root.notificationQueue = q
      queueTransitionTimer.nextItem = nextItem
      root.hasNotification = false // brief dip for transition
      queueTransitionTimer.restart()
    } else {
      root.hasNotification = false
    }
  }

  Timer {
    id: queueTransitionTimer
    interval: 220
    repeat: false
    property var nextItem: null
    onTriggered: {
      if (nextItem) {
        root.displayNotification(nextItem)
        nextItem = null
      }
    }
  }

  // Left-click action trigger: invokes default libnotify action AND brings desired window to focus
  function invokeAction() {
    var argv = root.currentExecArgv
    var app = root.currentAppName
    var summary = root.currentSummary
    var ref = root.currentNotificationRef

    if (argv && argv.length > 0) {
      execProc.command = argv
      execProc.running = true
    } else {
      // 1. Invoke default libnotify action so sender knows it was clicked
      if (ref && ref.actions) {
        try {
          for (var i = 0; i < ref.actions.length; i++) {
            var act = ref.actions[i]
            if (act && act.identifier === "default") {
              act.invoke()
              break
            }
          }
        } catch (e) {}
      }

      // 2. Always focus the desired application window in Hyprland
      focusApp(app, summary)
    }

    dismissCurrent()
  }

  function focusApp(app, summary) {
    // Pass the query via environment, not argv: /proc/<pid>/environ is owner-only,
    // while argv is readable by every local account
    focusAppProc.environment = {
      "LUMANIA_FOCUS_APP": String(app || ""),
      "LUMANIA_FOCUS_SUMMARY": String(summary || "")
    }
    focusAppProc.command = [
      decodeURIComponent(Qt.resolvedUrl("lumania-focus").toString().replace(/^file:\/\//, ""))
    ]
    focusAppProc.running = true
  }

  Process { id: execProc; running: false }
  Process { id: focusAppProc; running: false }
}
