import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

Item {
  id: root

  FrameConfig {
    id: frameConfig
  }

  // Configuration and Theme
  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  property color activeTextColor: frameConfig.activeTextColor
  property color mutedColor: frameConfig.mutedColor
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  readonly property string iconFont: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"

  // Active Tab: "wifi", "bluetooth", or "dns"
  property string activeTab: "wifi"

  // Visibility and Pinning State
  property bool isOpen: false
  property bool isPinned: false

  // Hover state exposed for bridge detection
  readonly property bool isHovered: cardHover.hovered

  // Driver value for iOS Fluid Motion: 0.0 (closed) -> 1.0 (fully expanded subpanel)
  readonly property real targetProgress: isOpen ? 1.0 : 0.0
  property real openProgress: targetProgress

  // iOS Fluid Spring Animation:
  // Expanding: snappy energetic spring (380ms, OutBack overshoot 1.08)
  // Collapsing: critically damped graceful settle (260ms, OutCubic)
  Behavior on openProgress {
    NumberAnimation {
      duration: root.isOpen ? 380 : 260
      easing.type: root.isOpen ? Easing.OutBack : Easing.OutCubic
      easing.overshoot: root.isOpen ? 1.08 : 1.0
    }
  }

  // Mask item exposed to PanelWindow
  property alias maskItem: subpanelCard

  // Dimensions
  implicitWidth: frameConfig.statusSubpanelWidth
  implicitHeight: frameConfig.statusSubpanelHeight

  // Fluid Motion Transforms (Derived strictly from openProgress)
  opacity: Math.max(0.0, Math.min(1.0, openProgress * 1.15))
  scale: 0.94 + (0.06 * openProgress)
  transformOrigin: Item.Top
  visible: openProgress > 0.01

  // Sinusoidal liquid volume pulse during mid-transition
  readonly property real liquidOffset: Math.sin(Math.min(1.0, Math.max(0.0, openProgress)) * Math.PI) * 4.0

  // -------------------------------------------------------------------------
  // System State & Backend Communications (Native Rust Binary)
  // -------------------------------------------------------------------------
  readonly property string backendScript: "/home/rover/Projects/lumania shell/lumania-status"

  property var wifiData: ({
    enabled: true,
    connected: false,
    ssid: "",
    ip: "",
    signal: 0,
    networks: []
  })

  property var btData: ({
    enabled: false,
    connectedCount: 0,
    devices: []
  })

  property var dnsData: ({
    current: "8.8.8.8",
    preset: "google",
    dot: true
  })

  property bool isRescanningWifi: false

  // Process to fetch full JSON state
  Process {
    id: statusProc
    command: [root.backendScript]
    stdout: StdioCollector {
      onStreamFinished: {
        var str = String(text || "").trim()
        if (str && str.startsWith("{")) {
          try {
            var data = JSON.parse(str)
            if (data.wifi) root.wifiData = data.wifi
            if (data.bluetooth) root.btData = data.bluetooth
            if (data.dns) root.dnsData = data.dns
          } catch (e) {
            console.warn("TopNotchSubpanel parse error:", e)
          }
        }
      }
    }
  }

  // Asynchronous action runner
  Process {
    id: actionProc
    onExited: {
      root.isRescanningWifi = false
      statusProc.running = true
    }
  }

  function runAction(args) {
    actionProc.command = [root.backendScript].concat(args)
    actionProc.running = true
  }

  function toggleWifi() {
    runAction(["--toggle-wifi", root.wifiData.enabled ? "off" : "on"])
  }

  function connectWifi(ssid) {
    runAction(["--connect-wifi", ssid])
  }

  function disconnectWifi() {
    runAction(["--disconnect-wifi"])
  }

  function rescanWifi() {
    root.isRescanningWifi = true
    runAction(["--rescan-wifi"])
  }

  function toggleBluetooth() {
    runAction(["--toggle-bt", root.btData.enabled ? "off" : "on"])
  }

  function connectBt(mac) {
    runAction(["--connect-bt", mac])
  }

  function disconnectBt(mac) {
    runAction(["--disconnect-bt", mac])
  }

  function setDnsPreset(preset) {
    runAction(["--set-dns", preset])
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  Component.onCompleted: {
    refresh()
  }

  // Dynamic poll timer: fast when open, relaxed when closed
  Timer {
    interval: root.isOpen ? 2500 : 8000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  onIsOpenChanged: {
    if (root.isOpen) root.refresh()
  }

  // -------------------------------------------------------------------------
  // Main Subpanel Card Container
  // -------------------------------------------------------------------------
  Rectangle {
    id: subpanelCard
    anchors.fill: parent
    radius: frameConfig.statusSubpanelRadius
    color: frameConfig.statusSubpanelBg
    border.width: 1
    border.color: frameConfig.statusSubpanelBorder
    clip: true

    // Hover handler for maintaining subpanel open state
    HoverHandler {
      id: cardHover
    }

    // Top Segmented Control (Tabs: Wi-Fi, Bluetooth, DNS)
    Rectangle {
      id: tabSegmentedBar
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: 12
      height: 38
      radius: 19
      color: Qt.rgba(255, 255, 255, 0.06)
      border.width: 1
      border.color: Qt.rgba(255, 255, 255, 0.08)

      // Spring-driven sliding active indicator pill
      Rectangle {
        id: tabIndicator
        readonly property real tabWidth: (tabSegmentedBar.width - 8) / 3
        width: tabWidth
        height: tabSegmentedBar.height - 8
        radius: 15
        y: 4
        x: {
          if (root.activeTab === "wifi") return 4
          if (root.activeTab === "bluetooth") return 4 + tabWidth
          return 4 + (tabWidth * 2)
        }
        color: frameConfig.activeBorderColor

        Behavior on x {
          NumberAnimation {
            duration: 280
            easing.type: Easing.OutBack
            easing.overshoot: 1.08
          }
        }
      }

      Row {
        anchors.fill: parent
        anchors.margins: 4

        // Wi-Fi Tab Button
        Item {
          width: parent.width / 3
          height: parent.height

          Rectangle {
            anchors.fill: parent
            radius: 15
            color: "transparent"

            Row {
              anchors.centerIn: parent
              spacing: 6

              Text {
                text: "󰤨"
                font.family: root.iconFont
                font.pixelSize: 13
                color: root.activeTab === "wifi" ? root.activeTextColor : root.mutedColor
                verticalAlignment: Text.AlignVCenter
              }

              Text {
                text: "Wi-Fi"
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: root.activeTab === "wifi" ? Font.DemiBold : Font.Normal
                color: root.activeTab === "wifi" ? root.activeTextColor : root.mutedColor
                verticalAlignment: Text.AlignVCenter
              }
            }

            TapHandler {
              onTapped: {
                root.activeTab = "wifi"
                root.isPinned = true
              }
            }
          }
        }

        // Bluetooth Tab Button
        Item {
          width: parent.width / 3
          height: parent.height

          Rectangle {
            anchors.fill: parent
            radius: 15
            color: "transparent"

            Row {
              anchors.centerIn: parent
              spacing: 6

              Text {
                text: "󰂯"
                font.family: root.iconFont
                font.pixelSize: 13
                color: root.activeTab === "bluetooth" ? root.activeTextColor : root.mutedColor
                verticalAlignment: Text.AlignVCenter
              }

              Text {
                text: "Bluetooth"
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: root.activeTab === "bluetooth" ? Font.DemiBold : Font.Normal
                color: root.activeTab === "bluetooth" ? root.activeTextColor : root.mutedColor
                verticalAlignment: Text.AlignVCenter
              }
            }

            TapHandler {
              onTapped: {
                root.activeTab = "bluetooth"
                root.isPinned = true
              }
            }
          }
        }

        // DNS Tab Button
        Item {
          width: parent.width / 3
          height: parent.height

          Rectangle {
            anchors.fill: parent
            radius: 15
            color: "transparent"

            Row {
              anchors.centerIn: parent
              spacing: 6

              Text {
                text: "󰒃"
                font.family: root.iconFont
                font.pixelSize: 13
                color: root.activeTab === "dns" ? root.activeTextColor : root.mutedColor
                verticalAlignment: Text.AlignVCenter
              }

              Text {
                text: "DNS"
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: root.activeTab === "dns" ? Font.DemiBold : Font.Normal
                color: root.activeTab === "dns" ? root.activeTextColor : root.mutedColor
                verticalAlignment: Text.AlignVCenter
              }
            }

            TapHandler {
              onTapped: {
                root.activeTab = "dns"
                root.isPinned = true
              }
            }
          }
        }
      }
    }

    // -----------------------------------------------------------------------
    // TAB 1: WI-FI VIEW
    // -----------------------------------------------------------------------
    Item {
      id: wifiView
      anchors.top: tabSegmentedBar.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 14
      visible: root.activeTab === "wifi"

      // Active Connection Card
      Rectangle {
        id: wifiActiveCard
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 62
        radius: 14
        color: Qt.rgba(255, 255, 255, 0.05)
        border.width: 1
        border.color: root.wifiData.connected
          ? Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.45)
          : Qt.rgba(255, 255, 255, 0.08)

        RowLayout {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 10

          // Wifi Signal Icon
          Rectangle {
            width: 36
            height: 36
            radius: 18
            color: root.wifiData.connected
              ? Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.22)
              : Qt.rgba(255, 255, 255, 0.08)

            Text {
              anchors.centerIn: parent
              text: {
                if (!root.wifiData.enabled) return "󰤮"
                if (!root.wifiData.connected) return "󰤯"
                var sig = root.wifiData.signal || 50
                if (sig > 75) return "󰤨"
                if (sig > 50) return "󰤥"
                if (sig > 25) return "󰤢"
                return "󰤟"
              }
              font.family: root.iconFont
              font.pixelSize: 17
              color: root.wifiData.connected ? frameConfig.activeBorderColor : root.mutedColor
            }
          }

          // SSID & IP info
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              text: root.wifiData.enabled
                ? (root.wifiData.connected ? (root.wifiData.ssid || "Connected") : "Not Connected")
                : "Wi-Fi Disabled"
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: root.activeTextColor
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            Text {
              text: root.wifiData.enabled
                ? (root.wifiData.connected
                    ? ((root.wifiData.ip ? root.wifiData.ip + " • " : "") + root.wifiData.signal + "% signal")
                    : "Connect to a network below")
                : "Turn on to see networks"
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.mutedColor
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // Rescan Button
          Rectangle {
            width: 32
            height: 32
            radius: 16
            color: rescanTap.pressed ? Qt.rgba(255, 255, 255, 0.15) : Qt.rgba(255, 255, 255, 0.06)
            visible: root.wifiData.enabled

            Text {
              id: rescanIcon
              anchors.centerIn: parent
              text: "󰑐"
              font.family: root.iconFont
              font.pixelSize: 14
              color: root.activeTextColor
              rotation: root.isRescanningWifi ? 360 : 0

              Behavior on rotation {
                NumberAnimation {
                  duration: 600
                  loops: root.isRescanningWifi ? Animation.Infinite : 1
                  easing.type: Easing.Linear
                }
              }
            }

            TapHandler {
              id: rescanTap
              onTapped: root.rescanWifi()
            }
          }

          // iOS Fluid Toggle Switch
          Rectangle {
            id: wifiToggle
            width: 44
            height: 24
            radius: 12
            color: root.wifiData.enabled ? frameConfig.activeBorderColor : Qt.rgba(255, 255, 255, 0.18)

            Behavior on color { ColorAnimation { duration: 200 } }

            Rectangle {
              id: wifiThumb
              width: 18
              height: 18
              radius: 9
              y: 3
              x: root.wifiData.enabled ? 23 : 3
              color: "#ffffff"

              Behavior on x {
                NumberAnimation {
                  duration: 220
                  easing.type: Easing.OutBack
                  easing.overshoot: 1.15
                }
              }
            }

            TapHandler {
              onTapped: root.toggleWifi()
            }
          }
        }
      }

      // Available Networks Section Title
      Text {
        id: networksHeader
        anchors.top: wifiActiveCard.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        text: "AVAILABLE NETWORKS"
        font.family: root.fontFamily
        font.pixelSize: 10
        font.weight: Font.Bold
        color: root.mutedColor
        opacity: 0.75
      }

      // Networks Scrollable List
      ListView {
        id: wifiListView
        anchors.top: networksHeader.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        spacing: 4
        model: root.wifiData.networks || []

        delegate: Item {
          width: wifiListView.width
          height: 38

          Rectangle {
            id: netItemBg
            anchors.fill: parent
            radius: 10
            color: netItemHover.hovered
              ? Qt.rgba(255, 255, 255, 0.08)
              : (modelData.active ? Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.12) : "transparent")

            HoverHandler {
              id: netItemHover
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 10

              // Signal icon
              Text {
                text: {
                  var s = modelData.signal || 50
                  if (s > 75) return "󰤨"
                  if (s > 50) return "󰤥"
                  if (s > 25) return "󰤢"
                  return "󰤟"
                }
                font.family: root.iconFont
                font.pixelSize: 14
                color: modelData.active ? frameConfig.activeBorderColor : root.mutedColor
              }

              // SSID
              Text {
                text: modelData.ssid || ""
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: modelData.active ? Font.DemiBold : Font.Normal
                color: modelData.active ? root.activeTextColor : Qt.rgba(root.activeTextColor.r, root.activeTextColor.g, root.activeTextColor.b, 0.90)
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              // Lock icon if secured
              Text {
                text: ""
                font.family: root.iconFont
                font.pixelSize: 11
                color: root.mutedColor
                visible: Boolean(modelData.security && modelData.security !== "--")
              }

              // Connected / Connect Action
              Item {
                width: modelData.active ? 68 : 62
                height: 24

                Rectangle {
                  anchors.fill: parent
                  radius: 12
                  color: modelData.active
                    ? Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.25)
                    : (netItemHover.hovered ? frameConfig.activeBorderColor : Qt.rgba(255, 255, 255, 0.08))

                  Text {
                    anchors.centerIn: parent
                    text: modelData.active ? "Connected" : "Connect"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: modelData.active
                      ? frameConfig.activeBorderColor
                      : (netItemHover.hovered ? root.activeTextColor : root.mutedColor)
                  }
                }
              }
            }

            TapHandler {
              onTapped: {
                if (!modelData.active) {
                  root.connectWifi(modelData.ssid)
                }
              }
            }
          }
        }
      }
    }

    // -----------------------------------------------------------------------
    // TAB 2: BLUETOOTH VIEW
    // -----------------------------------------------------------------------
    Item {
      id: btView
      anchors.top: tabSegmentedBar.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 14
      visible: root.activeTab === "bluetooth"

      // Bluetooth Status Card
      Rectangle {
        id: btActiveCard
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 62
        radius: 14
        color: Qt.rgba(255, 255, 255, 0.05)
        border.width: 1
        border.color: root.btData.enabled
          ? Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.45)
          : Qt.rgba(255, 255, 255, 0.08)

        RowLayout {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 10

          Rectangle {
            width: 36
            height: 36
            radius: 18
            color: root.btData.enabled
              ? Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.22)
              : Qt.rgba(255, 255, 255, 0.08)

            Text {
              anchors.centerIn: parent
              text: root.btData.enabled ? "󰂯" : "󰂲"
              font.family: root.iconFont
              font.pixelSize: 18
              color: root.btData.enabled ? frameConfig.activeBorderColor : root.mutedColor
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              text: root.btData.enabled ? "Bluetooth Powered On" : "Bluetooth Disabled"
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: root.activeTextColor
            }

            Text {
              text: root.btData.enabled
                ? (root.btData.connectedCount > 0 ? (root.btData.connectedCount + " device(s) connected") : "Discoverable & ready")
                : "Turn on to manage devices"
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.mutedColor
            }
          }

          // iOS Fluid Toggle Switch
          Rectangle {
            id: btToggle
            width: 44
            height: 24
            radius: 12
            color: root.btData.enabled ? frameConfig.activeBorderColor : Qt.rgba(255, 255, 255, 0.18)

            Behavior on color { ColorAnimation { duration: 200 } }

            Rectangle {
              id: btThumb
              width: 18
              height: 18
              radius: 9
              y: 3
              x: root.btData.enabled ? 23 : 3
              color: "#ffffff"

              Behavior on x {
                NumberAnimation {
                  duration: 220
                  easing.type: Easing.OutBack
                  easing.overshoot: 1.15
                }
              }
            }

            TapHandler {
              onTapped: root.toggleBluetooth()
            }
          }
        }
      }

      // Devices Header
      Text {
        id: btDevicesHeader
        anchors.top: btActiveCard.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        text: "PAIRED & KNOWN DEVICES"
        font.family: root.fontFamily
        font.pixelSize: 10
        font.weight: Font.Bold
        color: root.mutedColor
        opacity: 0.75
      }

      // Devices List
      ListView {
        id: btListView
        anchors.top: btDevicesHeader.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        spacing: 4
        model: root.btData.devices || []

        delegate: Item {
          width: btListView.width
          height: 42

          Rectangle {
            id: btItemBg
            anchors.fill: parent
            radius: 10
            color: btItemHover.hovered
              ? Qt.rgba(255, 255, 255, 0.08)
              : (modelData.connected ? Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.12) : "transparent")

            HoverHandler {
              id: btItemHover
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 10

              // Device icon based on type
              Text {
                text: {
                  if (modelData.icon === "headset") return "󰋋"
                  if (modelData.icon === "gamepad") return "󰊴"
                  if (modelData.icon === "phone") return "󰏲"
                  return "󰂯"
                }
                font.family: root.iconFont
                font.pixelSize: 16
                color: modelData.connected ? frameConfig.activeBorderColor : root.mutedColor
              }

              // Device Name
              Text {
                text: modelData.name || modelData.mac
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: modelData.connected ? Font.DemiBold : Font.Normal
                color: modelData.connected ? root.activeTextColor : Qt.rgba(root.activeTextColor.r, root.activeTextColor.g, root.activeTextColor.b, 0.90)
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              // Connect / Disconnect Action Pill
              Item {
                width: 76
                height: 24

                Rectangle {
                  anchors.fill: parent
                  radius: 12
                  color: modelData.connected
                    ? (btItemHover.hovered ? Qt.rgba(255, 85, 85, 0.30) : Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.25))
                    : (btItemHover.hovered ? frameConfig.activeBorderColor : Qt.rgba(255, 255, 255, 0.08))

                  Text {
                    anchors.centerIn: parent
                    text: modelData.connected ? (btItemHover.hovered ? "Disconnect" : "Connected") : "Connect"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: modelData.connected
                      ? (btItemHover.hovered ? "#ff6666" : frameConfig.activeBorderColor)
                      : (btItemHover.hovered ? root.activeTextColor : root.mutedColor)
                  }
                }

                TapHandler {
                  onTapped: {
                    if (modelData.connected) {
                      root.disconnectBt(modelData.mac)
                    } else {
                      root.connectBt(modelData.mac)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // -----------------------------------------------------------------------
    // TAB 3: DNS RESOLVER VIEW
    // -----------------------------------------------------------------------
    Item {
      id: dnsView
      anchors.top: tabSegmentedBar.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 14
      visible: root.activeTab === "dns"

      // Active DNS Card
      Rectangle {
        id: dnsActiveCard
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 60
        radius: 14
        color: Qt.rgba(255, 255, 255, 0.05)
        border.width: 1
        border.color: Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.45)

        RowLayout {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 10

          Rectangle {
            width: 36
            height: 36
            radius: 18
            color: Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.22)

            Text {
              anchors.centerIn: parent
              text: "󰒃"
              font.family: root.iconFont
              font.pixelSize: 18
              color: frameConfig.activeBorderColor
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              text: "Active DNS: " + (root.dnsData.current || "8.8.8.8")
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: root.activeTextColor
            }

            Text {
              text: "Encrypted DNS-over-TLS (DoT) Enabled"
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.mutedColor
            }
          }

          // Secure badge
          Rectangle {
            width: 58
            height: 22
            radius: 11
            color: Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.22)

            Text {
              anchors.centerIn: parent
              text: "Secure"
              font.family: root.fontFamily
              font.pixelSize: 10
              font.weight: Font.Bold
              color: frameConfig.activeBorderColor
            }
          }
        }
      }

      // DNS Presets Header
      Text {
        id: dnsPresetsHeader
        anchors.top: dnsActiveCard.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        text: "FAST 1-CLICK DNS PRESETS"
        font.family: root.fontFamily
        font.pixelSize: 10
        font.weight: Font.Bold
        color: root.mutedColor
        opacity: 0.75
      }

      // 5 Presets List
      Column {
        anchors.top: dnsPresetsHeader.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 5

        // Preset helper component
        Repeater {
          model: [
            { id: "cloudflare", name: "Cloudflare (1.1.1.1)", desc: "Ultra-fast, privacy-first, zero-logging", icon: "󰞀" },
            { id: "google", name: "Google DNS (8.8.8.8)", desc: "Global high-availability resolver", icon: "󰊭" },
            { id: "quad9", name: "Quad9 (9.9.9.9)", desc: "Automated malware & phishing protection", icon: "" },
            { id: "adguard", name: "AdGuard DNS", desc: "Network-wide ad & tracker blocking", icon: "󰘚" },
            { id: "dhcp", name: "System / DHCP Default", desc: "Automatic router-assigned DNS", icon: "󰌘" }
          ]

          delegate: Rectangle {
            id: presetCard
            width: parent.width
            height: 40
            radius: 10
            readonly property bool isSelected: root.dnsData.preset === modelData.id
            color: isSelected
              ? Qt.rgba(frameConfig.activeBorderColor.r, frameConfig.activeBorderColor.g, frameConfig.activeBorderColor.b, 0.18)
              : (presetHover.hovered ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.03))
            border.width: isSelected ? 1 : 0
            border.color: frameConfig.activeBorderColor

            HoverHandler {
              id: presetHover
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 8

              Text {
                text: modelData.icon
                font.family: root.iconFont
                font.pixelSize: 14
                color: presetCard.isSelected ? frameConfig.activeBorderColor : root.mutedColor
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                  text: modelData.name
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  font.weight: presetCard.isSelected ? Font.DemiBold : Font.Normal
                  color: root.activeTextColor
                }

                Text {
                  text: modelData.desc
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  color: root.mutedColor
                }
              }

              // Checkmark badge
              Text {
                text: "✓"
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                color: frameConfig.activeBorderColor
                visible: presetCard.isSelected
              }
            }

            TapHandler {
              onTapped: {
                root.setDnsPreset(modelData.id)
              }
            }
          }
        }
      }
    }
  }
}
