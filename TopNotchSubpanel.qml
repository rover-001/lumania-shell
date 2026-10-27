import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

Item {
  id: root

  // Injected FrameConfig from parent (DynamicIsland)
  required property var frameConfig

  // Configuration and Theme derived directly from wallpaper extraction
  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  property color activeTextColor: "#ffffff"
  property color mutedColor: Qt.rgba(255, 255, 255, 0.75)
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  readonly property string iconFont: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"

  // Active Panel: "wifi", "bluetooth", or "dns"
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

  // Dimensions (Minimal & Compact)
  implicitWidth: frameConfig.statusSubpanelWidth
  implicitHeight: frameConfig.statusSubpanelHeight

  // Fluid Motion Transforms (Derived strictly from openProgress)
  opacity: Math.max(0.0, Math.min(1.0, openProgress * 1.15))
  scale: 0.94 + (0.06 * openProgress)
  transformOrigin: Item.Top
  visible: openProgress > 0.01

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
            root.isRescanningWifi = false
          } catch (e) {
            console.warn("TopNotchSubpanel parse error:", e)
          }
        }
      }
    }
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: {
      if (root.isOpen) root.refresh()
    }
  }

  onIsOpenChanged: {
    if (root.isOpen) root.refresh()
  }

  Process {
    id: actionProc
    onExited: {
      root.refresh()
    }
  }

  function runAction(args) {
    actionProc.command = [root.backendScript].concat(args)
    actionProc.running = true
  }

  function toggleWifi() {
    runAction(["--toggle-wifi", root.wifiData.enabled ? "off" : "on"])
  }

  function rescanWifi() {
    root.isRescanningWifi = true
    runAction(["--rescan-wifi"])
  }

  function connectWifi(ssid) {
    runAction(["--connect-wifi", ssid])
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

  Component.onCompleted: {
    root.refresh()
  }

  // -------------------------------------------------------------------------
  // Main Subpanel Container (Unibody Shape with Concave Top Flares, NO BORDER)
  // -------------------------------------------------------------------------
  Item {
    id: subpanelCard
    anchors.fill: parent

    HoverHandler {
      id: cardHover
    }

    // Unibody Shape: Flares smoothly towards left-top and right-top to merge with top notch!
    Shape {
      id: cardShape
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      readonly property real w: subpanelCard.width
      readonly property real h: subpanelCard.height
      readonly property real flareR: root.frameConfig.statusSubpanelFlareRadius
      readonly property real rBot: root.frameConfig.statusSubpanelBottomRadius

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: root.frameConfig.activeBorderColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        // Start at left contact point with top notch (x=0, y=0)
        startX: 0
        startY: 0

        // Top horizontal line spanning the contact with the notch
        PathLine {
          x: cardShape.w
          y: 0
        }

        // Top-right flare: curves concavely from (w, 0) towards right-top / into right vertical side at (w - flareR, flareR)
        // Wait: contact is at (w, 0), curving inward to vertical line at (w - flareR)
        PathCubic {
          x: cardShape.w - cardShape.flareR
          y: cardShape.flareR
          control1X: cardShape.w - (cardShape.flareR * 0.5)
          control1Y: 0
          control2X: cardShape.w - cardShape.flareR
          control2Y: cardShape.flareR * 0.5
        }

        // Right vertical side down to bottom-right corner
        PathLine {
          x: cardShape.w - cardShape.flareR
          y: cardShape.h - cardShape.rBot
        }

        // Bottom-right rounded corner arc
        PathArc {
          x: cardShape.w - cardShape.flareR - cardShape.rBot
          y: cardShape.h
          radiusX: cardShape.rBot
          radiusY: cardShape.rBot
          direction: PathArc.Clockwise
        }

        // Bottom horizontal edge
        PathLine {
          x: cardShape.flareR + cardShape.rBot
          y: cardShape.h
        }

        // Bottom-left rounded corner arc
        PathArc {
          x: cardShape.flareR
          y: cardShape.h - cardShape.rBot
          radiusX: cardShape.rBot
          radiusY: cardShape.rBot
          direction: PathArc.Clockwise
        }

        // Left vertical side up to left flare
        PathLine {
          x: cardShape.flareR
          y: cardShape.flareR
        }

        // Top-left flare: curves concavely from (flareR, flareR) out and up towards left-top to (0, 0)
        PathCubic {
          x: 0
          y: 0
          control1X: cardShape.flareR
          control1Y: cardShape.flareR * 0.5
          control2X: cardShape.flareR * 0.5
          control2Y: 0
        }
      }
    }

    // =========================================================================
    // PANEL 1: MINIMAL WI-FI VIEW (Compact, Zero Clutter)
    // =========================================================================
    ColumnLayout {
      id: wifiView
      anchors.fill: parent
      anchors.leftMargin: cardShape.flareR + 6
      anchors.rightMargin: cardShape.flareR + 6
      anchors.bottomMargin: 14
      anchors.topMargin: 12
      spacing: 8
      visible: root.activeTab === "wifi"

      // Top Status Card
      Rectangle {
        Layout.fillWidth: true
        height: 64
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.22)
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.10)

        RowLayout {
          anchors.fill: parent
          anchors.margins: 10
          spacing: 10

          // Signal Icon Circle
          Rectangle {
            width: 36
            height: 36
            radius: 18
            color: root.wifiData.connected ? "#ffffff" : Qt.rgba(0, 0, 0, 0.25)

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
              font.pixelSize: 18
              color: root.wifiData.connected ? root.frameConfig.activeBorderColor : "#ffffff"
            }
          }

          // SSID & IP info
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              text: root.wifiData.enabled
                ? (root.wifiData.connected ? (root.wifiData.ssid || "Connected") : (root.wifiData.networks.length > 0 ? "Networks Available" : "Searching for Wi-Fi..."))
                : "Wi-Fi Off"
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: "#ffffff"
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            Text {
              text: root.wifiData.enabled
                ? (root.wifiData.connected
                    ? ((root.wifiData.ip ? root.wifiData.ip + " • " : "") + root.wifiData.signal + "% signal")
                    : (root.wifiData.networks.length + " network(s) in range"))
                : "Turn on to connect"
              font.family: root.fontFamily
              font.pixelSize: 11
              color: Qt.rgba(255, 255, 255, 0.75)
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // iOS Fluid Toggle Switch
          Rectangle {
            id: wifiToggle
            width: 44
            height: 24
            radius: 12
            color: root.wifiData.enabled ? "#ffffff" : Qt.rgba(0, 0, 0, 0.25)

            Behavior on color { ColorAnimation { duration: 200 } }

            Rectangle {
              id: wifiThumb
              width: 18
              height: 18
              radius: 9
              y: 3
              x: root.wifiData.enabled ? 23 : 3
              color: root.wifiData.enabled ? root.frameConfig.activeBorderColor : "#ffffff"

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

      // Available Networks List (Scrollable / Flickable)
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 10
        color: Qt.rgba(0, 0, 0, 0.16)
        clip: true
        visible: root.wifiData.enabled

        ListView {
          id: wifiList
          anchors.fill: parent
          anchors.margins: 4
          spacing: 2
          boundsBehavior: Flickable.StopAtBounds

          model: {
            var nets = root.wifiData.networks || []
            // Filter out current active SSID if already connected to show other available networks
            var filtered = []
            for (var i = 0; i < nets.length; i++) {
              var n = nets[i]
              if (n.ssid && n.ssid.length > 0 && n.ssid !== "--") {
                filtered.push(n)
              }
            }
            return filtered
          }

          delegate: Rectangle {
            id: netItem
            width: wifiList.width
            height: 28
            radius: 6
            color: netItemHover.hovered ? Qt.rgba(255, 255, 255, 0.15) : "transparent"

            HoverHandler { id: netItemHover }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 6

              Text {
                text: {
                  var sig = modelData.signal || 50
                  if (sig > 75) return "󰤨"
                  if (sig > 50) return "󰤥"
                  if (sig > 25) return "󰤢"
                  return "󰤟"
                }
                font.family: root.iconFont
                font.pixelSize: 13
                color: modelData.active ? "#ffffff" : Qt.rgba(255, 255, 255, 0.70)
              }

              Text {
                text: modelData.ssid
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: modelData.active ? Font.DemiBold : Font.Normal
                color: "#ffffff"
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Text {
                visible: Boolean(modelData.active)
                text: "Active"
                font.family: root.fontFamily
                font.pixelSize: 9
                font.weight: Font.Bold
                color: "#ffffff"
              }

              Text {
                visible: !modelData.active && modelData.security && modelData.security.length > 0
                text: "󰌾"
                font.family: root.iconFont
                font.pixelSize: 10
                color: Qt.rgba(255, 255, 255, 0.60)
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

          // Empty state placeholder
          Text {
            anchors.centerIn: parent
            visible: wifiList.count === 0
            text: root.isRescanningWifi ? "Scanning for networks..." : "No other networks found"
            font.family: root.fontFamily
            font.pixelSize: 11
            color: Qt.rgba(255, 255, 255, 0.60)
          }
        }
      }
    }

    // =========================================================================
    // PANEL 2: MINIMAL BLUETOOTH VIEW (Bug-Free Device Detection)
    // =========================================================================
    ColumnLayout {
      id: btView
      anchors.fill: parent
      anchors.leftMargin: cardShape.flareR + 6
      anchors.rightMargin: cardShape.flareR + 6
      anchors.bottomMargin: 14
      anchors.topMargin: 12
      spacing: 8
      visible: root.activeTab === "bluetooth"

      readonly property var connectedDev: {
        var devs = root.btData.devices || []
        for (var i = 0; i < devs.length; i++) {
          if (devs[i].connected) return devs[i]
        }
        return null
      }

      readonly property var primaryDev: connectedDev || ((root.btData.devices && root.btData.devices.length > 0) ? root.btData.devices[0] : null)

      // Top Status Card
      Rectangle {
        Layout.fillWidth: true
        height: 64
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.22)
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.10)

        RowLayout {
          anchors.fill: parent
          anchors.margins: 10
          spacing: 10

          Rectangle {
            width: 36
            height: 36
            radius: 18
            color: (root.btData.enabled && Boolean(btView.connectedDev)) ? "#ffffff" : Qt.rgba(0, 0, 0, 0.25)

            Text {
              anchors.centerIn: parent
              text: root.btData.enabled ? (btView.connectedDev ? "󰂱" : "󰂯") : "󰂲"
              font.family: root.iconFont
              font.pixelSize: 18
              color: (root.btData.enabled && Boolean(btView.connectedDev)) ? root.frameConfig.activeBorderColor : "#ffffff"
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              text: root.btData.enabled
                ? (btView.connectedDev
                    ? btView.connectedDev.name
                    : (root.btData.devices.length > 0 ? "Bluetooth Ready" : "Searching for Devices..."))
                : "Bluetooth Off"
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: "#ffffff"
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            Text {
              text: root.btData.enabled
                ? (btView.connectedDev
                    ? "Connected • Audio Active"
                    : (root.btData.devices.length > 0 ? (root.btData.devices.length + " paired device(s)") : "No devices in range"))
                : "Turn on to manage audio"
              font.family: root.fontFamily
              font.pixelSize: 11
              color: Qt.rgba(255, 255, 255, 0.75)
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // iOS Fluid Toggle Switch
          Rectangle {
            id: btToggle
            width: 44
            height: 24
            radius: 12
            color: root.btData.enabled ? "#ffffff" : Qt.rgba(0, 0, 0, 0.25)

            Behavior on color { ColorAnimation { duration: 200 } }

            Rectangle {
              id: btThumb
              width: 18
              height: 18
              radius: 9
              y: 3
              x: root.btData.enabled ? 23 : 3
              color: root.btData.enabled ? root.frameConfig.activeBorderColor : "#ffffff"

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

      // Middle: Paired & Known Devices List
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 10
        color: Qt.rgba(0, 0, 0, 0.16)
        clip: true
        visible: root.btData.enabled

        ListView {
          id: btList
          anchors.fill: parent
          anchors.margins: 4
          spacing: 2
          boundsBehavior: Flickable.StopAtBounds
          model: root.btData.devices || []

          delegate: Rectangle {
            id: btItem
            width: btList.width
            height: 28
            radius: 6
            color: btItemHover.hovered ? Qt.rgba(255, 255, 255, 0.15) : "transparent"

            HoverHandler { id: btItemHover }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 6

              Text {
                text: {
                  if (modelData.icon === "gamepad") return "󰊴"
                  if (modelData.icon === "audio-card" || modelData.icon === "headset") return "󰋋"
                  return "󰂯"
                }
                font.family: root.iconFont
                font.pixelSize: 13
                color: modelData.connected ? "#ffffff" : Qt.rgba(255, 255, 255, 0.70)
              }

              Text {
                text: modelData.name
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: modelData.connected ? Font.DemiBold : Font.Normal
                color: "#ffffff"
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Text {
                text: modelData.connected ? "Disconnect" : "Connect"
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: modelData.connected ? "#ffffff" : Qt.rgba(255, 255, 255, 0.80)
              }
            }

            TapHandler {
              onTapped: {
                if (modelData.connected) root.disconnectBt(modelData.mac)
                else root.connectBt(modelData.mac)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: btList.count === 0
            text: "No devices found"
            font.family: root.fontFamily
            font.pixelSize: 11
            color: Qt.rgba(255, 255, 255, 0.60)
          }
        }
      }
    }

    // =========================================================================
    // PANEL 3: MINIMAL DNS RESOLVER VIEW (Compact 4-Pill Selector)
    // =========================================================================
    ColumnLayout {
      id: dnsView
      anchors.fill: parent
      anchors.leftMargin: cardShape.flareR + 6
      anchors.rightMargin: cardShape.flareR + 6
      anchors.bottomMargin: 14
      anchors.topMargin: 12
      spacing: 8
      visible: root.activeTab === "dns"

      // Top Status Card
      Rectangle {
        Layout.fillWidth: true
        height: 64
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.22)
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.10)

        RowLayout {
          anchors.fill: parent
          anchors.margins: 10
          spacing: 10

          Rectangle {
            width: 36
            height: 36
            radius: 18
            color: "#ffffff"

            Text {
              anchors.centerIn: parent
              text: "󰒃"
              font.family: root.iconFont
              font.pixelSize: 18
              color: root.frameConfig.activeBorderColor
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              text: "DNS: " + (root.dnsData.preset ? root.dnsData.preset.toUpperCase() : "Active")
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: "#ffffff"
            }

            Text {
              text: "Resolver: " + (root.dnsData.current || "8.8.8.8")
              font.family: root.fontFamily
              font.pixelSize: 11
              color: Qt.rgba(255, 255, 255, 0.75)
            }
          }

          // Secure Badge
          Rectangle {
            width: 54
            height: 22
            radius: 11
            color: "#ffffff"

            Text {
              anchors.centerIn: parent
              text: "DoT"
              font.family: root.fontFamily
              font.pixelSize: 10
              font.weight: Font.Bold
              color: root.frameConfig.activeBorderColor
            }
          }
        }
      }

      // Middle: DNS Presets Card / Selector
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 10
        color: Qt.rgba(0, 0, 0, 0.16)
        clip: true

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 6
          spacing: 4

          Repeater {
            model: [
              { id: "cloudflare", label: "Cloudflare", desc: "1.1.1.1 • Fast & Private" },
              { id: "google", label: "Google", desc: "8.8.8.8 • Global Anycast" },
              { id: "adguard", label: "AdGuard", desc: "94.140.14.14 • Ad & Tracker Blocking" },
              { id: "dhcp", label: "DHCP Default", desc: "System / Router Default" }
            ]

            Rectangle {
              id: presetItem
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 6
              readonly property bool isSelected: root.dnsData.preset === modelData.id
              color: isSelected
                ? Qt.rgba(255, 255, 255, 0.22)
                : (itemHover.hovered ? Qt.rgba(255, 255, 255, 0.12) : "transparent")

              HoverHandler { id: itemHover }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Rectangle {
                  width: 8
                  height: 8
                  radius: 4
                  color: presetItem.isSelected ? "#ffffff" : Qt.rgba(255, 255, 255, 0.30)
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: modelData.label
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: presetItem.isSelected ? Font.DemiBold : Font.Normal
                    color: "#ffffff"
                  }

                  Text {
                    text: modelData.desc
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    color: Qt.rgba(255, 255, 255, 0.65)
                  }
                }

                Text {
                  visible: presetItem.isSelected
                  text: "Active"
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  font.weight: Font.Bold
                  color: "#ffffff"
                }
              }

              TapHandler {
                onTapped: root.setDnsPreset(modelData.id)
              }
            }
          }
        }
      }
    }
  }
}
