import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui

Item {
  id: root

  required property var frameConfig
  property var anchorItem: null
  property var bar: null
  property bool open: false
  signal dismissed()
  property string page: "settings"
  property string saveMessage: ""
  property string updateStatus: "idle"
  property string updateMessage: ""
  property string updateLogs: ""
  property string projectDir: ""
  property string version: "0.2.0"
  property string commit: "unknown"
  property string commitMessage: "Lumania Shell release"
  property string processOutput: ""
  property int behindCount: 0
  property bool shellEnabled: true
  property var settings: defaultSettings()

  readonly property color accent: frameConfig.activeBorderColor
  readonly property color foreground: frameConfig.activeTextColor
  readonly property color muted: frameConfig.mutedColor
  readonly property string fontFamily: bar && bar.fontFamily ? bar.fontFamily : "Adwaita Sans, Inter, sans-serif"
  readonly property color card: Qt.rgba(0, 0, 0, 0.22)
  readonly property color line: Qt.rgba(1, 1, 1, 0.10)
  readonly property string compactUpdateLogs: updateLogs.split("\n").filter(function(line) { return line.length > 0 }).slice(-3).join("\n")
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/lumania.json"

  function defaultSettings() {
    return {
      borderThickness: 5,
      dynamicWallpaperColor: true,
      wallpaperColorMode: "accent",
      borderColor: "#ba5f58",
      cornerStyle: "squircle",
      cornerRadius: 16,
      islandBodyWidth: 206,
      wallpaperInstantSwitch: false,
      wallpaperMaxVisibleThumbs: 4
    }
  }

  function loadSettings() {
    var raw = String(settingsFile.text() || "").trim()
    if (!raw || raw.charAt(0) !== "{") return
    try {
      var parsed = JSON.parse(raw)
      var defaults = defaultSettings()
      for (var key in defaults) {
        if (parsed[key] !== undefined) defaults[key] = parsed[key]
      }
      root.settings = defaults
    } catch (e) {
      root.saveMessage = "Could not read shell settings."
    }
  }

  function saveSettings(next) {
    root.settings = next
    root.saveMessage = "Saving…"
    settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function setSetting(key, value) {
    var next = Object.assign({}, root.settings)
    next[key] = value
    saveSettings(next)
  }

  function resetSettings() {
    saveSettings(defaultSettings())
    root.saveMessage = "Reset to standard defaults."
  }

  function appendLog(line) {
    var clean = String(line || "").trim()
    if (clean.length > 0) root.updateLogs = (root.updateLogs + clean + "\n").slice(-6000)
  }

  function checkForUpdates() {
    if (!root.projectDir || updateProc.running || root.updateStatus === "updating") return
    root.updateStatus = "checking"
    root.updateMessage = "Checking…"
    root.updateLogs = "Fetching latest updates from remote…\n"
    updatePhase = "fetch"
    updateProc.command = ["git", "-C", root.projectDir, "fetch", "--quiet", "origin"]
    updateProc.running = true
  }

  function installUpdate() {
    if (root.updateStatus !== "available" || updateProc.running) return
    root.updateStatus = "updating"
    root.updateMessage = "Updating…"
    root.updateLogs = "Pulling latest commits from origin/main…\n"
    updatePhase = "pull"
    updateProc.command = ["git", "-C", root.projectDir, "pull", "--ff-only", "origin", "main"]
    updateProc.running = true
  }

  function updateFinished() {
    root.updateStatus = "success"
    root.updateMessage = "Updated. Restarting…"
    restartProc.forUpdate = true
    restartProc.running = true
  }

  function restartShell() {
    root.saveMessage = "Restarting shell…"
    restartProc.forUpdate = false
    restartProc.running = true
  }

  function toggleShellEnabled() {
    if (shellToggleProc.running) return
    var next = !root.shellEnabled
    root.shellEnabled = next
    root.saveMessage = next ? "Enabling Lumania shell…" : "Disabling Lumania shell…"
    if (!next) root.close()
    if (next) {
      shellToggleProc.command = ["sh", "-c", "omarchy plugin enable lumania.island && hyprctl reload"]
    } else {
      shellToggleProc.command = ["sh", "-c", "omarchy plugin enable omarchy.notifications >/dev/null 2>&1; omarchy plugin disable lumania.island && hyprctl reload"]
    }
    shellToggleProc.running = true
  }

  function startMetadataRead() {
    if (!root.projectDir) return
    gitMetaProc.command = ["git", "-C", root.projectDir, "log", "-1", "--pretty=%h%n%s"]
    gitMetaProc.running = true
  }

  function close() {
    root.dismissed()
  }

  onOpenChanged: {
    if (!root.bar) return
    if (root.open) root.bar.requestPopout(root)
    else if (root.bar.activePopout === root) root.bar.releasePopout(root)
  }

  FileView {
    id: settingsFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings()
    onFileChanged: settingsFile.reload()
    onSaved: root.saveMessage = "Saved"
    onSaveFailed: root.saveMessage = "Could not save shell settings."
  }

  FileView {
    id: manifestFile
    path: root.projectDir ? root.projectDir + "/manifest.json" : ""
    printErrors: false
    onLoaded: {
      try {
        var data = JSON.parse(manifestFile.text())
        if (data.version) root.version = String(data.version)
      } catch (e) {}
    }
  }

  Process {
    id: projectLookupProc
    command: ["sh", "-c", "for d in \"$PWD\" \"$PWD/..\" \"$HOME/Projects/lumania shell\" \"$HOME/.config/omarchy/plugins/lumania.island\"; do if [ -f \"$d/manifest.json\" ] && git -C \"$d\" rev-parse --git-dir >/dev/null 2>&1; then printf '%s' \"$d\"; exit 0; fi; done; exit 1"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.projectDir = String(text || "").trim()
        root.startMetadataRead()
      }
    }
  }

  Process {
    id: gitMetaProc
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        if (lines.length > 0 && lines[0]) root.commit = lines[0]
        if (lines.length > 1 && lines[1]) root.commitMessage = lines.slice(1).join(" ")
      }
    }
  }

  property string updatePhase: ""

  Process {
    id: updateProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.processOutput = String(text || "").trim()
        if (root.updatePhase === "count") {
          var count = parseInt(root.processOutput, 10)
          if (!isNaN(count)) {
            root.behindCount = count
            root.updateStatus = count > 0 ? "available" : "current"
            root.updateMessage = count > 0 ? count + " updates available." : "Up to date."
            root.appendLog(count > 0 ? count + " updates available." : "Up to date.")
          }
        } else if (root.updatePhase === "dirty") {
          if (root.processOutput.length > 0) root.appendLog("Local changes found.")
        } else {
          root.appendLog(text)
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: root.appendLog(text)
    }
    onExited: function(exitCode) {
      var phase = root.updatePhase
      if (phase === "fetch") {
        if (exitCode !== 0) {
          root.updateStatus = "failed"
          root.updateMessage = "Check failed."
          return
        }
        root.appendLog("Checking commits on origin/main…")
        updatePhase = "dirty"
        updateProc.command = ["git", "-C", root.projectDir, "status", "--porcelain"]
        updateProc.running = true
      } else if (phase === "dirty") {
        root.processOutput = ""
        updatePhase = "count"
        updateProc.command = ["git", "-C", root.projectDir, "rev-list", "--count", "HEAD..origin/main"]
        updateProc.running = true
      } else if (phase === "count") {
        if (exitCode !== 0) {
          root.updateStatus = "failed"
          root.updateMessage = "Could not compare versions."
        }
      } else if (phase === "pull") {
        if (exitCode !== 0) {
          root.updateStatus = "failed"
          root.updateMessage = "Update failed."
          return
        }
        root.appendLog("Building helpers…")
        updatePhase = "build"
        updateProc.command = ["bash", root.projectDir + "/build.sh"]
        updateProc.workingDirectory = root.projectDir
        updateProc.running = true
      } else if (phase === "build") {
        if (exitCode !== 0) root.appendLog("Build failed; restarting shell.")
        else root.appendLog("Build complete.")
        root.updatePhase = "restart"
        root.updateFinished()
      }
    }
  }

  Process {
    id: restartProc
    command: ["omarchy", "restart", "shell"]
    property bool forUpdate: false
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (restartProc.forUpdate) {
          root.updateStatus = "failed"
          root.updateMessage = "Restart failed."
          root.appendLog("omarchy restart shell exited with code " + exitCode + ".")
        } else {
          root.saveMessage = "Restart error (exit " + exitCode + ")."
        }
      } else if (!restartProc.forUpdate) {
        root.saveMessage = "Lumania shell restarted."
      }
    }
  }

  Process {
    id: shellToggleProc
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.shellEnabled = !root.shellEnabled
        root.saveMessage = "Could not toggle Lumania shell (exit " + exitCode + ")."
      }
    }
  }

  Component.onCompleted: {
    settingsFile.reload()
    projectLookupProc.running = true
  }

  PopupWindow {
    id: trayPanel
    color: "transparent"
    implicitWidth: 420
    implicitHeight: 556
    visible: root.open || trayPanel.shown > 0.01
    mask: Region { item: root.open ? panelSurface : null }

    readonly property var anchorWindow: root.anchorItem ? root.anchorItem.QsWindow.window : null

    property real shown: root.open ? 1 : 0
    Behavior on shown {
      NumberAnimation {
        duration: trayPanel.shown > 0 ? 340 : 260
        easing.type: trayPanel.shown > 0 ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: trayPanel.shown > 0 ? 1.06 : 1.0
      }
    }

    anchor {
      id: popupAnchor
      window: trayPanel.anchorWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        var target = root.anchorItem
        var window = trayPanel.anchorWindow
        if (!target || !window) return
        var popupWidth = trayPanel.implicitWidth
        var localX = target.width / 2 - popupWidth / 2
        var localY = target.height + 6
        var point = window.contentItem.mapFromItem(target, localX, localY)
        point.x = Math.max(8, Math.min(point.x, window.width - popupWidth - 8))
        popupAnchor.rect.x = Math.round(point.x)
        popupAnchor.rect.y = Math.round(point.y)
      }
    }

    HyprlandFocusGrab {
      active: root.open
      windows: trayPanel.anchorWindow ? [trayPanel, trayPanel.anchorWindow] : [trayPanel]
      onCleared: root.close()
    }

    Item {
      id: panelSurface
      anchors.fill: parent
      opacity: trayPanel.shown
      scale: 0.94 + 0.06 * trayPanel.shown
      transformOrigin: Item.TopRight

      readonly property real cornerRadius: Math.min(root.frameConfig.controlExpandedCornerRadius, width / 2, height / 2)

      Rectangle {
        anchors.fill: parent
        radius: panelSurface.cornerRadius
        color: root.accent
        clip: true

      }

      Column {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 20
        anchors.bottomMargin: 16
      spacing: 8

      RowLayout {
        width: parent.width
        height: 34

        Text {
          Layout.fillWidth: true
          text: "☾  Lumania"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 14
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          text: "v" + root.version
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 10
        }
      }

      Row {
        width: parent.width
        height: 30
        spacing: 4

        Repeater {
          model: ["Settings", "Updates"]
          delegate: Rectangle {
            required property string modelData
            width: (parent.width - 4) / 2
            height: 30
            radius: 8
            color: root.page === modelData.toLowerCase() ? Qt.rgba(0, 0, 0, 0.20) : Qt.rgba(1, 1, 1, 0.06)
            border.width: root.page === modelData.toLowerCase() ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.14)

            Text {
              anchors.centerIn: parent
              text: parent.modelData
              color: root.page === parent.modelData.toLowerCase() ? root.foreground : root.muted
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.Medium
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.page = parent.modelData.toLowerCase()
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: root.line }

      Flickable {
        id: pageScroll
        width: parent.width
        height: parent.height - 90
        contentWidth: width
        contentHeight: root.page === "settings" ? settingsColumn.implicitHeight : updatesColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }

        Column {
          id: settingsColumn
          width: pageScroll.width
          spacing: 8
          visible: root.page === "settings"

          Rectangle {
            width: parent.width
            height: shellSection.implicitHeight + 20
            radius: 12
            color: root.card
            border.width: 1
            border.color: root.line
            Column {
              id: shellSection
              x: 10; y: 10
              width: parent.width - 20
              spacing: 8
              RowLayout {
                width: parent.width
                Text { Layout.fillWidth: true; text: "Lumania shell"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 12; font.bold: true }
                Rectangle {
                  Layout.preferredWidth: 42; Layout.preferredHeight: 24; radius: 12
                  color: root.shellEnabled ? root.accent : Qt.rgba(1, 1, 1, 0.14)
                  Rectangle { width: 18; height: 18; radius: 9; y: 3; x: root.shellEnabled ? 21 : 3; color: "white" }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleShellEnabled() }
                }
              }
              Text {
                width: parent.width
                text: root.shellEnabled ? "Active desktop shell. Turn off to restore default Omarchy bar." : "Enabling Lumania shell…"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: 10
                wrapMode: Text.WordWrap
              }
            }
          }

          Rectangle {
            width: parent.width
            height: geometrySection.implicitHeight + 20
            radius: 12
            color: root.card
            border.width: 1
            border.color: root.line
            Column {
              id: geometrySection
              x: 10; y: 10
              width: parent.width - 20
              spacing: 8
              Text { text: "Frame"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 12; font.bold: true }
              RowLayout {
                width: parent.width
                Text { Layout.fillWidth: true; text: "Color tone"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 10 }
                Rectangle {
                  Layout.preferredWidth: 42; Layout.preferredHeight: 24; radius: 12
                  color: root.settings.dynamicWallpaperColor ? root.accent : Qt.rgba(1, 1, 1, 0.14)
                  Rectangle { width: 18; height: 18; radius: 9; y: 3; x: root.settings.dynamicWallpaperColor ? 21 : 3; color: "white" }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setSetting("dynamicWallpaperColor", !root.settings.dynamicWallpaperColor) }
                }
              }
              Row {
                visible: !root.settings.dynamicWallpaperColor
                spacing: 8
                Repeater {
                  model: ["#ba5f58", "#58a8ba", "#9d7cd8", "#41a6b5", "#e0af68", "#7aa2f7"]
                  delegate: Rectangle {
                    required property string modelData
                    width: 22; height: 22; radius: 11
                    color: modelData
                    border.width: root.settings.borderColor === modelData ? 2 : 1
                    border.color: root.settings.borderColor === modelData ? "white" : Qt.rgba(0, 0, 0, 0.4)
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setSetting("borderColor", parent.modelData) }
                  }
                }
              }
              LumaniaChoiceGroup {
                label: "Border"
                values: [0, 3, 5, 8, 10]
                suffix: "px"
                selectedValue: root.settings.borderThickness
                accent: root.accent
                muted: root.muted
                fontFamily: root.fontFamily
                onChosen: function(value) { root.setSetting("borderThickness", value) }
              }
              LumaniaChoiceGroup {
                label: "Corner style"
                values: ["squircle", "arc"]
                labels: ["Squircle", "Arc"]
                selectedValue: root.settings.cornerStyle
                accent: root.accent
                muted: root.muted
                fontFamily: root.fontFamily
                onChosen: function(value) { root.setSetting("cornerStyle", value) }
              }
              LumaniaChoiceGroup {
                label: "Radius"
                values: [8, 12, 16, 20, 24]
                suffix: "px"
                selectedValue: root.settings.cornerRadius
                accent: root.accent
                muted: root.muted
                fontFamily: root.fontFamily
                onChosen: function(value) { root.setSetting("cornerRadius", value) }
              }
              LumaniaChoiceGroup {
                label: "Island width"
                values: [180, 206, 230, 260]
                suffix: "px"
                selectedValue: root.settings.islandBodyWidth
                accent: root.accent
                muted: root.muted
                fontFamily: root.fontFamily
                onChosen: function(value) { root.setSetting("islandBodyWidth", value) }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: wallpaperSection.implicitHeight + 20
            radius: 12
            color: root.card
            border.width: 1
            border.color: root.line
            Column {
              id: wallpaperSection
              x: 10; y: 10
              width: parent.width - 20
              spacing: 8
              Text { text: "Wallpaper"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 12; font.bold: true }
              RowLayout {
                width: parent.width
                Text { Layout.fillWidth: true; text: "Instant swap"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 10 }
                Rectangle {
                  Layout.preferredWidth: 42; Layout.preferredHeight: 24; radius: 12
                  color: root.settings.wallpaperInstantSwitch ? root.accent : Qt.rgba(1, 1, 1, 0.14)
                  Rectangle { width: 18; height: 18; radius: 9; y: 3; x: root.settings.wallpaperInstantSwitch ? 21 : 3; color: "white" }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setSetting("wallpaperInstantSwitch", !root.settings.wallpaperInstantSwitch) }
                }
              }
              LumaniaChoiceGroup {
                label: "Thumbnails"
                values: [4, 5, 7]
                selectedValue: root.settings.wallpaperMaxVisibleThumbs
                accent: root.accent
                muted: root.muted
                fontFamily: root.fontFamily
                onChosen: function(value) { root.setSetting("wallpaperMaxVisibleThumbs", value) }
              }
            }
          }

          Row {
            width: parent.width
            spacing: 6
            LumaniaActionButton { label: "Reset"; accent: root.accent; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.resetSettings() }
            LumaniaActionButton { label: "Restart"; primary: true; accent: root.accent; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.restartShell() }
          }
          Text { text: root.saveMessage; color: root.accent; font.family: root.fontFamily; font.pixelSize: 10; visible: text.length > 0 }
        }

        Column {
          id: updatesColumn
          width: pageScroll.width
          spacing: 8
          visible: root.page === "updates"

          Rectangle {
            width: parent.width
            height: statusSection.implicitHeight + 20
            radius: 12
            color: root.card
            border.width: 1
            border.color: root.line
            Column {
              id: statusSection
              x: 10; y: 10
              width: parent.width - 20
              spacing: 8
              RowLayout {
                width: parent.width
                Column {
                  Layout.fillWidth: true
                  Text { text: "v" + root.version; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 12; font.bold: true }
                  Text { text: root.commit; color: root.muted; font.family: root.fontFamily; font.pixelSize: 9 }
                }
                LumaniaActionButton { label: "Check"; accent: root.accent; foreground: root.foreground; fontFamily: root.fontFamily; busy: root.updateStatus === "checking" || root.updateStatus === "updating"; onClicked: root.checkForUpdates() }
              }
              Text {
                width: parent.width
                text: root.updateMessage || "Check for updates."
                color: root.updateStatus === "failed" ? "#f7768e" : root.updateStatus === "available" ? "#e0af68" : root.updateStatus === "current" || root.updateStatus === "success" ? "#41cd52" : root.muted
                font.family: root.fontFamily
                font.pixelSize: 10
                wrapMode: Text.WordWrap
              }
              LumaniaActionButton { visible: root.updateStatus === "available"; label: "Update now"; primary: true; accent: root.accent; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.installUpdate() }
              Text { visible: root.compactUpdateLogs.length > 0; text: root.compactUpdateLogs; color: root.muted; font.family: "JetBrainsMono Nerd Font, monospace"; font.pixelSize: 9; wrapMode: Text.Wrap; width: parent.width }
            }
          }

          Rectangle {
            width: parent.width
            height: changelogSection.implicitHeight + 20
            radius: 12
            color: root.card
            border.width: 1
            border.color: root.line
            Column {
              id: changelogSection
              x: 10; y: 10
              width: parent.width - 20
              spacing: 6
              Text { text: "Highlights"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 12; font.bold: true }
              Text { text: "v0.1.1 · Timers, media and calls"; color: root.accent; font.family: root.fontFamily; font.pixelSize: 10 }
              Text { text: "v0.1.0 · Frame, island and notches"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 10 }
            }
          }
        }
      }
      }
    }
  }

}
