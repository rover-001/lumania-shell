import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell

// ===========================================================================
// Control Center Status Subpanel (Wi-Fi / Bluetooth)
// ---------------------------------------------------------------------------
// Blooms LEFTWARDS out of the open bottom-right control card, exactly like the
// top island's status subpanel drops downwards out of the Dynamic Island.
//  • Right edge is flush with the control card's left edge (unibody).
//  • Concave G1 flares melt the attachment into the card edge.
//  • Hover a status button in the card -> its panel opens here.
//  • Click a status button -> pins this subpanel until click-away.
// Data is owned by the control center (single source of truth); every action
// is requested upwards through signals.
// ===========================================================================
Item {
  id: root

  required property var frameConfig

  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  property color activeTextColor: "#ffffff"
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  readonly property string iconFont: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"

  // Active Panel: "wifi" or "bluetooth"
  property string activeTab: "wifi"

  // Visibility and Pinning State
  property bool isOpen: false
  property bool isPinned: false

  // Hover state exposed for the parent's grace-period close timer
  readonly property bool isHovered: cardHover.hovered

  // Backend state (bound from the control center)
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
  property bool isRescanningWifi: false

  // Reduced motion is owned by the control center (Hyprland global switch).
  property bool reduceMotion: false

  // Actions requested upwards (the control center owns the backend process)
  signal toggleWifiRequested()
  signal rescanWifiRequested()
  signal connectWifiRequested(string ssid)
  signal toggleBluetoothRequested()
  signal connectBluetoothRequested(string mac)
  signal disconnectBluetoothRequested(string mac)

  function openTab(tab) {
    if (root.activeTab !== tab) root.activeTab = tab
    root.isOpen = true
  }

  function close() {
    root.isPinned = false
    root.isOpen = false
  }

  // Driver value for iOS Fluid Motion: 0.0 (closed) -> 1.0 (fully bloomed)
  readonly property real targetProgress: isOpen ? 1.0 : 0.0

  // Blooming is a large surface: 0.42s at zeta 0.85 (energetic, ~0.6% settle
  // overshoot). Collapsing is critically damped so it never bounces away from
  // the card edge it melts into. Retargeting mid-flight keeps velocity.
  FluidSpring {
    id: bloomSpring
    target: root.targetProgress
    response: root.isOpen ? 0.42 : 0.34
    dampingFraction: root.isOpen ? 0.85 : 1.0
    epsilon: 0.0004
    reduceMotion: root.reduceMotion
  }

  readonly property real openProgress: bloomSpring.value

  // Mask item exposed to PanelWindow
  property alias maskItem: subpanelCard

  // Dimensions
  implicitWidth: frameConfig.controlSubpanelWidth

  // Height follows the row count so the panel never carries empty space
  readonly property int rowPitch: 30
  readonly property real verticalPadding: (frameConfig.controlSubpanelFlareRadius * 2) + 16
  readonly property var wifiNetworks: {
    var nets = root.wifiData.networks || []
    var filtered = []
    for (var i = 0; i < nets.length; i++) {
      var n = nets[i]
      if (n.ssid && n.ssid.length > 0 && n.ssid !== "--") filtered.push(n)
    }
    // The backend already lists the joined network first; keep it pinned there.
    filtered.sort(function (a, b) { return (b.active ? 1 : 0) - (a.active ? 1 : 0) })
    return filtered
  }
  readonly property int activeRowCount: root.activeTab === "wifi"
    ? root.wifiNetworks.length
    : (root.btData.devices || []).length

  // Height follows the row count so the panel never carries empty space.
  // Critically damped: the mask window must never overshoot past the bounds.
  FluidSpring {
    id: heightSpring
    target: Math.min(frameConfig.controlSubpanelHeight,
                     root.verticalPadding + (Math.max(1, root.activeRowCount) * root.rowPitch))
    response: 0.32
    dampingFraction: 1.0
    epsilon: 0.5
    reduceMotion: root.reduceMotion
  }

  implicitHeight: heightSpring.value

  // Fluid Motion Transforms (blooms out of the right attachment edge)
  opacity: Math.max(0.0, Math.min(1.0, openProgress * 1.15))
  scale: 0.94 + (0.06 * openProgress)
  transformOrigin: Item.Right
  visible: openProgress > 0.01

  // -------------------------------------------------------------------------
  // Main Container (Unibody shape, flush right edge, concave G1 flares)
  // -------------------------------------------------------------------------
  Item {
    id: subpanelCard
    anchors.fill: parent

    HoverHandler {
      id: cardHover
    }

    Shape {
      id: cardShape
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      readonly property real w: subpanelCard.width
      readonly property real h: subpanelCard.height

      // Radii are clamped against the live panel size so a two-row panel never
      // gets a flare/corner pair taller than itself (which would kink the path).
      readonly property real rf: Math.max(2, Math.min(root.frameConfig.controlSubpanelFlareRadius,
                                                     h * 0.30, w * 0.5))
      readonly property real rc: Math.max(2, Math.min(root.frameConfig.controlSubpanelCornerRadius,
                                                     (h - 2 * Math.min(root.frameConfig.controlSubpanelFlareRadius, h * 0.30)) / 2,
                                                     w - Math.min(root.frameConfig.controlSubpanelFlareRadius, h * 0.30)))
      readonly property real flareR: rf
      readonly property real rCorner: rc

      // Bezier tension. 0.5523 reproduces a true quarter circle; pushing it
      // higher flattens the tangent run-off for a continuous-curvature squircle.
      readonly property real tension: 0.62

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: root.notchColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        // Start at the top of the flush right edge (contact with control card)
        startX: cardShape.w
        startY: 0

        // Top-right concave flare: melts the contact edge into the top edge
        PathCubic {
          x: cardShape.w - cardShape.rf
          y: cardShape.rf
          control1X: cardShape.w
          control1Y: cardShape.rf * cardShape.tension
          control2X: cardShape.w - cardShape.rf + (cardShape.rf * cardShape.tension)
          control2Y: cardShape.rf
        }

        // Top edge running left towards the free end
        PathLine {
          x: cardShape.rc
          y: cardShape.rf
        }

        // Top-left rounded corner (free end)
        PathCubic {
          x: 0
          y: cardShape.rf + cardShape.rc
          control1X: cardShape.rc - (cardShape.rc * cardShape.tension)
          control1Y: cardShape.rf
          control2X: 0
          control2Y: cardShape.rf + (cardShape.rc * (1 - cardShape.tension))
        }

        // Left free edge
        PathLine {
          x: 0
          y: cardShape.h - cardShape.rf - cardShape.rc
        }

        // Bottom-left rounded corner (free end)
        PathCubic {
          x: cardShape.rc
          y: cardShape.h - cardShape.rf
          control1X: 0
          control1Y: cardShape.h - cardShape.rf - (cardShape.rc * (1 - cardShape.tension))
          control2X: cardShape.rc - (cardShape.rc * cardShape.tension)
          control2Y: cardShape.h - cardShape.rf
        }

        // Bottom edge running right towards the contact edge
        PathLine {
          x: cardShape.w - cardShape.rf
          y: cardShape.h - cardShape.rf
        }

        // Bottom-right concave flare back into the flush contact edge
        PathCubic {
          x: cardShape.w
          y: cardShape.h
          control1X: cardShape.w - cardShape.rf + (cardShape.rf * cardShape.tension)
          control1Y: cardShape.h - cardShape.rf
          control2X: cardShape.w
          control2Y: cardShape.h - (cardShape.rf * cardShape.tension)
        }

        // Flush right contact edge (closes the path at the start point)
        PathLine {
          x: cardShape.w
          y: 0
        }
      }
    }

    // =========================================================================
    // PANEL 1: MINIMAL WI-FI VIEW
    // =========================================================================
    ColumnLayout {
      id: wifiView
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: cardShape.flareR + 14
      anchors.topMargin: cardShape.flareR + 8
      anchors.bottomMargin: cardShape.flareR + 8
      spacing: 8
      visible: root.activeTab === "wifi"

      // Available networks — bare list, no enclosing box
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ListView {
          id: wifiList
          anchors.fill: parent
          spacing: 2
          boundsBehavior: Flickable.StopAtBounds
          visible: root.wifiData.enabled

          model: root.wifiNetworks

          delegate: Rectangle {
            id: netItem
            width: wifiList.width
            height: 28
            radius: 6

            // Press feedback lands on touch-down (not on release) — 120ms ease
            // is a passive colour change, so no spring is needed here.
            readonly property bool isPressed: netTap.pressed

            color: netItem.isPressed
              ? Qt.rgba(255, 255, 255, 0.24)
              : (netItemHover.hovered ? Qt.rgba(255, 255, 255, 0.15) : "transparent")

            // Passive colour feedback eases out; press highlight still lands
            // instantly on touch-down.
            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

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
              id: netTap
              onTapped: {
                if (!modelData.active) {
                  root.connectWifiRequested(modelData.ssid)
                }
              }
            }
          }
        }

        // Empty / disabled state placeholder
        Text {
          anchors.centerIn: parent
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: !root.wifiData.enabled || wifiList.count === 0
          text: !root.wifiData.enabled
            ? "Wi-Fi off"
            : (root.isRescanningWifi ? "Scanning for networks..."
                : (root.wifiData.connected ? "No other networks" : "No networks found"))
          font.family: root.fontFamily
          font.pixelSize: 11
          color: Qt.rgba(255, 255, 255, 0.60)
        }
      }
    }

    // =========================================================================
    // PANEL 2: MINIMAL BLUETOOTH VIEW
    // =========================================================================
    ColumnLayout {
      id: btView
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: cardShape.flareR + 14
      anchors.topMargin: cardShape.flareR + 8
      anchors.bottomMargin: cardShape.flareR + 8
      spacing: 8
      visible: root.activeTab === "bluetooth"

      // Paired & known devices — bare list, no enclosing box
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ListView {
          id: btList
          anchors.fill: parent
          spacing: 2
          boundsBehavior: Flickable.StopAtBounds
          visible: root.btData.enabled
          model: root.btData.devices || []

          delegate: Rectangle {
            id: btItem
            width: btList.width
            height: 28
            radius: 6

            readonly property bool isPressed: btTap.pressed

            color: btItem.isPressed
              ? Qt.rgba(255, 255, 255, 0.24)
              : (btItemHover.hovered ? Qt.rgba(255, 255, 255, 0.15) : "transparent")

            // Passive colour feedback eases out; press highlight still lands
            // instantly on touch-down.
            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

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
              id: btTap
              onTapped: {
                if (modelData.connected) root.disconnectBluetoothRequested(modelData.mac)
                else root.connectBluetoothRequested(modelData.mac)
              }
            }
          }

        }

        // Empty / disabled state placeholder
        Text {
          anchors.centerIn: parent
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: !root.btData.enabled || btList.count === 0
          text: root.btData.enabled ? "No devices found" : "Bluetooth off"
          font.family: root.fontFamily
          font.pixelSize: 11
          color: Qt.rgba(255, 255, 255, 0.60)
        }
      }
    }
  }
}
