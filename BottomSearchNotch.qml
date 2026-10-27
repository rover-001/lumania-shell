import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

Item {
  id: root

  FrameConfig {
    id: frameConfig
  }

  // Properties passed from IslandBar / host
  property int borderThickness: frameConfig.borderThickness
  property color notchColor: frameConfig.activeBorderColor
  property string fontFamily: "Adwaita Sans, Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  property var shell: null
  property bool isOpen: false       // Manual open from keybind or IPC (owned by the host)
  property bool isHoverOpen: false  // Hover open from mouse interaction
  property bool hasOpenApps: false
  // Local open request. Never assigned to isOpen: writing isOpen here would
  // destroy the host's `isOpen: root.searchOpen` binding, which permanently
  // disconnected the notch from the IPC/keybind state after the first Esc.
  property bool requestedOpen: false
  // Set after an explicit dismissal so a pointer that is still over the panel
  // cannot instantly re-open it.
  property bool hoverSuppressed: false

  readonly property bool isHovered: Boolean(notchHover && notchHover.hovered) || Boolean(edgeTriggerHover && edgeTriggerHover.hovered)
  readonly property bool isTyping: Boolean(searchInput && searchInput.text.length > 0)
  readonly property bool isOpenEffective: root.isOpen || root.requestedOpen
    || (!root.hoverSuppressed && (root.isHoverOpen || root.isHovered))
    || root.isTyping

  signal openRequested()
  signal closeRequested()

  function open() {
    root.requestedOpen = true
    root.openRequested()
    refreshApps()
    Qt.callLater(function() {
      if (searchInput) {
        searchInput.forceActiveFocus()
        searchInput.selectAll()
      }
    })
  }

  function close() {
    root.requestedOpen = false
    root.isHoverOpen = false
    root.hoverSuppressed = root.isHovered
    root.closeRequested()
    if (searchInput) {
      searchInput.text = ""
      searchInput.focus = false
    }
  }

  function toggle() {
    if (root.isOpenEffective) root.close()
    else root.open()
  }

  // Host-driven close (IPC / fullscreen) must also drop a pending local request
  onIsOpenChanged: {
    if (!root.isOpen) root.requestedOpen = false
  }

  onIsOpenEffectiveChanged: {
    if (root.isOpenEffective) {
      refreshApps()
      Qt.callLater(function() {
        if (searchInput) {
          searchInput.forceActiveFocus()
        }
      })
    } else {
      if (searchInput) {
        searchInput.text = ""
        searchInput.focus = false
      }
    }
  }

  // Sizing bounds driven by FrameConfig
  readonly property real collapsedWidth: frameConfig.searchCollapsedWidth
  readonly property real expandedWidth: frameConfig.searchExpandedWidth
  readonly property real collapsedHeight: root.borderThickness
    + Math.max(frameConfig.searchCollapsedHeight, frameConfig.searchLeftTabHeight)
  readonly property real expandedHeight: root.borderThickness + frameConfig.searchExpandedHeight

  // Flare & corner radii adapting dynamically with openProgress
  readonly property real currentFlareRadius: frameConfig.searchFlareRadius
    + (openProgress * (frameConfig.searchExpandedFlareRadius - frameConfig.searchFlareRadius))
  readonly property real currentCornerRadius: frameConfig.searchCornerRadius
    + (openProgress * (frameConfig.searchExpandedCornerRadius - frameConfig.searchCornerRadius))

  // Driver value for iOS Fluid Motion: 0.0 (Closed / Resting Pill) -> 1.0 (Full Expanded Search Card)
  readonly property real targetProgress: root.isOpenEffective ? 1.0 : 0.0
  property real openProgress: targetProgress

  Behavior on openProgress {
    NumberAnimation {
      duration: root.isOpenEffective ? frameConfig.searchOpenDuration
                                     : frameConfig.searchCloseDuration
      easing.type: root.isOpenEffective ? Easing.OutBack : Easing.OutCubic
      easing.overshoot: root.isOpenEffective ? frameConfig.searchOpenOvershoot : 1.0
    }
  }

  // Authentic iOS liquid stretch:
  // Width & height stretch smoothly with a sinusoidal volume pulse mid-transition
  readonly property real currentWidth: collapsedWidth
    + (openProgress * (expandedWidth - collapsedWidth))
    + (Math.sin(Math.min(1.0, Math.max(0.0, openProgress)) * Math.PI) * frameConfig.searchWidthPulse)

  readonly property real currentHeight: collapsedHeight
    + (openProgress * (expandedHeight - collapsedHeight))
    + (Math.sin(Math.min(1.0, Math.max(0.0, openProgress)) * Math.PI) * frameConfig.searchHeightPulse)

  // Exposed items for PanelWindow masking
  property alias maskItem: notchContainer
  property alias backdropItem: backdropOverlay

  readonly property string iconFont: "JetBrainsMono Nerd Font, Font Awesome 7 Free, sans-serif"

  // -------------------------------------------------------------------------
  // Application Data & Search Engine
  // -------------------------------------------------------------------------
  property var allApps: []
  property var filteredApps: []
  property int selectedIndex: 0
  property string filterQuery: ""

  function refreshApps() {
    var list = []
    var seen = {}

    // Method 1: Check shell.appLibrary from Omarchy
    if (root.shell && root.shell.appLibrary) {
      try {
        var sorted = root.shell.appLibrary.sortedEntries("") || []
        for (var i = 0; i < sorted.length; i++) {
          var e = sorted[i].entry
          if (!e || !e.id) continue
          var aid = String(e.id)
          if (seen[aid]) continue
          seen[aid] = true

          var name = root.shell.appLibrary.entryName(e)
          var sub = root.shell.appLibrary.entrySubtext(e)
          var icon = String(e.icon || "")
          list.push({
            id: aid,
            name: name,
            subtext: sub,
            icon: icon,
            entry: e,
            isCommand: false
          })
        }
      } catch (err) {
        console.warn("Lumania appLibrary fetch failed, falling back to DesktopEntries:", err)
      }
    }

    // Method 2: Direct Quickshell DesktopEntries
    if (list.length === 0) {
      try {
        var raw = DesktopEntries.applications.values || []
        for (var j = 0; j < raw.length; j++) {
          var app = raw[j]
          if (!app || !app.id) continue
          var appId = String(app.id)
          if (seen[appId]) continue
          seen[appId] = true

          list.push({
            id: appId,
            name: String(app.name || app.id),
            subtext: String(app.comment || app.genericName || ""),
            icon: String(app.icon || ""),
            entry: app,
            isCommand: false
          })
        }
      } catch (e2) {
        console.warn("Lumania DesktopEntries fetch error:", e2)
      }
    }

    // Sort alphabetically by name
    list.sort(function(a, b) {
      return a.name.localeCompare(b.name)
    })

    root.allApps = list
    updateFilter()
  }

  function updateFilter() {
    var q = filterQuery.trim().toLowerCase()
    if (!q) {
      root.filteredApps = root.allApps
      root.selectedIndex = 0
      return
    }

    var exactMatches = []
    var prefixMatches = []
    var fuzzyMatches = []

    for (var i = 0; i < root.allApps.length; i++) {
      var item = root.allApps[i]
      var n = item.name.toLowerCase()
      var s = item.subtext.toLowerCase()
      var id = item.id.toLowerCase()

      if (n === q) {
        exactMatches.push(item)
      } else if (n.indexOf(q) === 0 || id.indexOf(q) === 0) {
        prefixMatches.push(item)
      } else if (n.indexOf(q) > 0 || s.indexOf(q) >= 0 || id.indexOf(q) >= 0) {
        fuzzyMatches.push(item)
      }
    }

    var result = exactMatches.concat(prefixMatches).concat(fuzzyMatches)

    // If query has non-empty text, append "Run Command" option
    if (q.length > 0) {
      result.push({
        id: "cmd_" + q,
        name: "Run: " + filterQuery.trim(),
        subtext: "Execute in shell environment",
        icon: "utilities-terminal",
        command: filterQuery.trim(),
        isCommand: true
      })
    }

    root.filteredApps = result
    root.selectedIndex = 0
  }

  readonly property int gridColumns: frameConfig.searchGridColumns

  function selectNext() {
    if (root.filteredApps.length === 0) return
    root.selectedIndex = (root.selectedIndex + 1) % root.filteredApps.length
    resultsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function selectPrev() {
    if (root.filteredApps.length === 0) return
    root.selectedIndex = (root.selectedIndex - 1 + root.filteredApps.length) % root.filteredApps.length
    resultsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function selectDown() {
    if (root.filteredApps.length === 0) return
    var next = root.selectedIndex + gridColumns
    if (next < root.filteredApps.length) {
      root.selectedIndex = next
    } else {
      root.selectedIndex = root.filteredApps.length - 1
    }
    resultsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function selectUp() {
    if (root.filteredApps.length === 0) return
    var prev = root.selectedIndex - gridColumns
    if (prev >= 0) {
      root.selectedIndex = prev
    } else {
      root.selectedIndex = 0
    }
    resultsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function activateCurrent() {
    if (root.filteredApps.length === 0) return
    if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredApps.length) {
      launchItem(root.filteredApps[root.selectedIndex])
    }
  }

  function launchItem(item) {
    if (!item) return
    root.close()

    if (item.isCommand) {
      Quickshell.execDetached(["bash", "-c", item.command])
      return
    }

    if (root.shell && root.shell.appLibrary) {
      root.shell.appLibrary.launch(item.id, item.name)
      return
    }

    if (item.entry && typeof item.entry.execute === "function") {
      item.entry.execute()
      return
    }

    Quickshell.execDetached(["gtk-launch", item.id + ".desktop"])
  }

  // -------------------------------------------------------------------------
  // Power Actions
  // -------------------------------------------------------------------------
  readonly property var powerActions: [
    { glyph: "󰒲", label: "Suspend", command: ["systemctl", "suspend"] },          // zzz
    { glyph: "󰖔", label: "Hibernate", command: ["systemctl", "hibernate"] },      // moon + stars
    { glyph: "󰜉", label: "Restart", command: ["systemctl", "reboot"] },           // circular arrow
    { glyph: "󰐥", label: "Power off", command: ["systemctl", "poweroff"] }        // power
  ]

  function runPowerAction(command) {
    if (!command) return
    root.close()
    Quickshell.execDetached(command)
  }

  Component.onCompleted: {
    refreshApps()
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.refreshApps()
    }
  }

  // =========================================================================
  // Full-Screen Click-Away Catcher (no backdrop dimming)
  // =========================================================================
  Item {
    id: backdropOverlay
    anchors.fill: root.isOpenEffective ? parent : undefined
    width: root.isOpenEffective ? parent.width : 0
    height: root.isOpenEffective ? parent.height : 0
    visible: root.isOpenEffective && root.openProgress > 0.01

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  // =========================================================================
  // Bottom-Left Anchored Notch Container (merged into left + bottom borders)
  // =========================================================================
  Item {
    id: notchContainer
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    // Flush to the screen's left edge so the notch owns the left border band:
    // hovering anywhere on the far-left bottom corner opens it.
    anchors.leftMargin: 0

    // Auto-retract inward when apps are opened; springs up immediately when cursor touches bottom-left edge
    readonly property bool shouldRetract: root.hasOpenApps && !root.isOpenEffective
    readonly property real targetRetractOffset: shouldRetract ? -(root.collapsedHeight - root.borderThickness) : 0.0
    property real currentRetractOffset: targetRetractOffset

    Behavior on currentRetractOffset {
      NumberAnimation {
        duration: notchContainer.shouldRetract ? 280 : 380
        easing.type: notchContainer.shouldRetract ? Easing.OutCubic : Easing.OutBack
        easing.overshoot: 1.08
      }
    }

    anchors.bottomMargin: currentRetractOffset

    width: root.currentWidth
    height: root.currentHeight

    // Bottom-Left Edge Trigger: wakes retracted notch when mouse touches corner
    Item {
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.bottomMargin: -notchContainer.currentRetractOffset
      width: Math.max(64, root.collapsedWidth)
      height: root.borderThickness + 14

      HoverHandler {
        id: edgeTriggerHover
      }
    }

    // OLED Theme Color: follows the theme tone instantly.
    // The host (IslandBar) already animates islandColor over 500ms, so a second
    // Behaviour here would chain two animations and make the notch visibly lag.
    property color activeColor: root.notchColor

    // Hover handler for effortless blooming interaction
    HoverHandler {
      id: notchHover
      cursorShape: (!root.isOpenEffective) ? Qt.PointingHandCursor : Qt.ArrowCursor
      onHoveredChanged: {
        if (hovered) {
          root.hoverSuppressed = false
          root.isHoverOpen = true
          root.refreshApps()
          Qt.callLater(function() {
            if (searchInput) searchInput.forceActiveFocus()
          })
        } else {
          if (!root.isOpen && !root.requestedOpen && !root.isTyping) {
            root.isHoverOpen = false
          }
          root.hoverSuppressed = false
        }
      }
    }

    // Tactile press state when resting
    property bool isPillPressed: restingTapHandler.pressed
    scale: (!root.isOpenEffective && isPillPressed) ? 0.96 : 1.0
    transformOrigin: Item.BottomLeft

    Behavior on scale {
      NumberAnimation {
        duration: notchContainer.isPillPressed ? 120 : 280
        easing.type: notchContainer.isPillPressed ? Easing.OutQuad : Easing.OutBack
        easing.overshoot: 1.15
      }
    }

    // -----------------------------------------------------------------------
    // Resting "C" gusset: a tall finger up the LEFT border joined to a low
    // strip along the BOTTOM border. Both are part of the same silhouette, so
    // the corner reads as one merged piece of the frame.
    // -----------------------------------------------------------------------
    Shape {
      id: gussetShape
      anchors.fill: parent
      visible: root.openProgress < 0.05
      preferredRendererType: Shape.CurveRenderer

      readonly property real w: notchContainer.width
      readonly property real h: notchContainer.height
      readonly property real b: root.borderThickness
      // Top edge of the low part that hugs the bottom border
      readonly property real stripTop: h - b - frameConfig.searchCollapsedHeight
      // Vertical finger hugging the left border
      readonly property real tabW: Math.max(2, Math.min(frameConfig.searchLeftTabWidth,
                                                        w * frameConfig.searchTabWidthMaxRatio))
      readonly property real tabTop: Math.max(0, h - b - frameConfig.searchLeftTabHeight)
      readonly property real rTab: Math.max(0, Math.min(frameConfig.searchTabCapRadius,
                                                        tabW * 0.5,
                                                        (stripTop - tabTop) * 0.45))
      readonly property real fillet: Math.max(0, Math.min(frameConfig.searchInnerRadius,
                                                          stripTop - tabTop))
      readonly property real rCorner: Math.max(0, Math.min(frameConfig.searchCornerRadius,
                                                           (h - stripTop) * frameConfig.searchLipCornerRatio))
      readonly property real stripEnd: Math.max(tabW + fillet + 1, w - rCorner)
      // Bezier pull of the concave fillet (shared with every flare below)
      readonly property real slack: 1.0 - frameConfig.searchCurveTension

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: notchContainer.activeColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        // Start below the bottom edge for a zero-bleed seal
        startX: 0
        startY: gussetShape.h + 2.0

        // Up the left edge (fully covers the left border band)
        PathLine {
          x: 0
          y: gussetShape.tabTop + gussetShape.rTab
        }

        // Rounded finger top
        PathCubic {
          x: gussetShape.tabW
          y: gussetShape.tabTop + gussetShape.rTab
          control1X: 0
          control1Y: gussetShape.tabTop
          control2X: gussetShape.tabW
          control2Y: gussetShape.tabTop
        }

        // Down the finger's inner face
        PathLine {
          x: gussetShape.tabW
          y: gussetShape.stripTop - gussetShape.fillet
        }

        // Concave fillet: finger melts into the bottom strip (the "C" mouth)
        PathCubic {
          x: gussetShape.tabW + gussetShape.fillet
          y: gussetShape.stripTop
          control1X: gussetShape.tabW
          control1Y: gussetShape.stripTop - gussetShape.fillet * gussetShape.slack
          control2X: gussetShape.tabW + gussetShape.fillet * gussetShape.slack
          control2Y: gussetShape.stripTop
        }

        // Strip top edge
        PathLine {
          x: gussetShape.stripEnd
          y: gussetShape.stripTop
        }

        // Rounded right end of the strip
        PathArc {
          x: gussetShape.w
          y: gussetShape.stripTop + gussetShape.rCorner
          radiusX: gussetShape.rCorner
          radiusY: gussetShape.rCorner
          direction: PathArc.Clockwise
        }

        // Down past the bottom edge for a zero-bleed seal
        PathLine {
          x: gussetShape.w
          y: gussetShape.h + 2.0
        }

        // Close along the bottom
        PathLine {
          x: 0
          y: gussetShape.h + 2.0
        }
      }
    }

    // -----------------------------------------------------------------------
    // Corner Gusset Shape: merges into BOTH the left border and bottom border
    // - left edge   : flush against the left border's inner face
    // - bottom edge : flush into the bottom border band
    // - top-left    : concave flare melting out of the left border
    // - top-right   : free convex corner
    // - right       : concave flare melting into the bottom border
    // -----------------------------------------------------------------------
    Shape {
      id: notchShape
      anchors.fill: parent
      visible: root.openProgress >= 0.05
      preferredRendererType: Shape.CurveRenderer

      readonly property real w: notchContainer.width
      readonly property real h: notchContainer.height
      readonly property real rFlare: root.currentFlareRadius
      readonly property real rCorner: root.currentCornerRadius
      readonly property real b: root.borderThickness

      // Vertical space available above the bottom border's top edge
      readonly property real protrusion: Math.max(0, h - b)
      // G1 continuity: the free corner and the bottom flare share the protrusion
      // so the resting gusset can never self-intersect (no kinks / cut corners)
      readonly property real effRfL: Math.max(0.5, rFlare)
      readonly property real effRfR: Math.min(rFlare, Math.max(0.5, protrusion * frameConfig.searchLipFlareMaxRatio))
      readonly property real effRc: Math.max(0, Math.min(rCorner, protrusion - effRfR))
      // Horizontal guard: keep the top edge from inverting on narrow widths
      readonly property real topStart: Math.min(effRfL, w * frameConfig.searchTopEdgeGuardRatio)
      readonly property real topEnd: Math.max(topStart + 1, w - effRfR - effRc)
      // Bezier pull of the concave flares
      readonly property real slack: 1.0 - frameConfig.searchCurveTension

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: notchContainer.activeColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        // Start below the bottom edge for a zero-bleed seal with the border band
        startX: 0
        startY: notchShape.h + 2.0

        // Up the left edge and past the top edge: the flare grows out of the
        // left border, so the shoulder sits above the notch's own top edge
        PathLine {
          x: 0
          y: -notchShape.effRfL
        }

        // Top-left concave flare: left border sweeps out into the notch top edge
        PathCubic {
          x: notchShape.topStart
          y: 0
          control1X: 0
          control1Y: -notchShape.effRfL * notchShape.slack
          control2X: notchShape.topStart * frameConfig.searchCurveTension
          control2Y: 0
        }

        // Top horizontal edge
        PathLine {
          x: notchShape.topEnd
          y: 0
        }

        // Free top-right convex corner arc
        PathArc {
          x: notchShape.topEnd + notchShape.effRc
          y: notchShape.effRc
          radiusX: Math.max(1, notchShape.effRc)
          radiusY: Math.max(1, notchShape.effRc)
          direction: PathArc.Clockwise
        }

        // Right side down to the bottom border's top edge
        PathLine {
          x: notchShape.w - notchShape.effRfR
          y: notchShape.h - notchShape.b - notchShape.effRfR
        }

        // Right concave flare: notch melts back down into the bottom border
        PathCubic {
          x: notchShape.w
          y: notchShape.h - notchShape.b
          control1X: notchShape.w - notchShape.effRfR
          control1Y: notchShape.h - notchShape.b - (notchShape.effRfR * notchShape.slack)
          control2X: notchShape.w - (notchShape.effRfR * notchShape.slack)
          control2Y: notchShape.h - notchShape.b
        }

        // Down past bottom edge for zero-bleed seal
        PathLine {
          x: notchShape.w
          y: notchShape.h + 2.0
        }

        // Across bottom edge to close path
        PathLine {
          x: 0
          y: notchShape.h + 2.0
        }
      }
    }

    // -----------------------------------------------------------------------
    // Content Layer 1: Resting Notch Pill (Closed State - Clean & Minimal)
    // -----------------------------------------------------------------------
    Item {
      id: restingPill
      anchors.fill: parent
      visible: opacity > 0.01
      opacity: Math.max(0.0, 1.0 - root.openProgress * 3.0)

      HoverHandler {
        id: restingHoverHandler
        cursorShape: Qt.PointingHandCursor
      }

      TapHandler {
        id: restingTapHandler
        onTapped: root.open()
      }
    }

    // -----------------------------------------------------------------------
    // Content Layer 2: Expanded Search Card (Open State)
    // -----------------------------------------------------------------------
    Item {
      id: expandedView
      anchors.fill: parent
      anchors.topMargin: 12
      anchors.bottomMargin: root.borderThickness + 8
      // Container sits on the left border, so inset content from the border face
      anchors.leftMargin: root.borderThickness + 14
      anchors.rightMargin: root.currentFlareRadius + 8

      visible: opacity > 0.01
      opacity: root.openProgress
      scale: 0.94 + (0.06 * root.openProgress)
      transformOrigin: Item.BottomLeft

      ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Fully Rounded Search Input Capsule
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: frameConfig.searchBarHeight
          radius: frameConfig.searchBarRadius
          color: frameConfig.searchFieldBg
          border.color: searchInput.activeFocus ? Qt.rgba(255, 255, 255, 0.38) : Qt.rgba(255, 255, 255, 0.14)
          border.width: 1

          Behavior on border.color { ColorAnimation { duration: 180 } }

          // Subtle top highlight reflection line
          Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 32
            height: 1
            color: Qt.rgba(255, 255, 255, 0.16)
            radius: 1
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 10

            // Magnifying Glass Icon
            Text {
              text: "\uf002"
              font.family: root.iconFont
              font.pixelSize: 15
              color: searchInput.activeFocus ? frameConfig.activeTextColor : frameConfig.mutedColor
              Behavior on color { ColorAnimation { duration: 150 } }
              renderType: Text.NativeRendering
            }

            // Real-Time Filter Input Field
            TextInput {
              id: searchInput
              Layout.fillWidth: true
              Layout.fillHeight: true
              verticalAlignment: TextInput.AlignVCenter
              font.family: root.fontFamily
              font.pixelSize: 14
              font.weight: Font.Normal
              color: frameConfig.activeTextColor
              selectionColor: frameConfig.activeSliderIconColorFilled
              selectedTextColor: "#ffffff"
              clip: true

              onTextChanged: {
                root.filterQuery = text
                root.updateFilter()
              }

              Keys.onRightPressed: root.selectNext()
              Keys.onLeftPressed: root.selectPrev()
              Keys.onDownPressed: root.selectDown()
              Keys.onUpPressed: root.selectUp()
              Keys.onReturnPressed: root.activateCurrent()
              Keys.onEnterPressed: root.activateCurrent()
              Keys.onEscapePressed: root.close()

              Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "Search applications or commands..."
                font.family: root.fontFamily
                font.pixelSize: 14
                color: frameConfig.mutedColor
                visible: !searchInput.text && !searchInput.activeFocus
                renderType: Text.NativeRendering
              }
            }

            // Clear button ('×')
            Rectangle {
              id: clearBtn
              width: 24
              height: 24
              radius: 12
              color: clearHover.hovered
                ? Qt.rgba(255, 255, 255, 0.25)
                : (clearTap.pressed ? Qt.rgba(255, 255, 255, 0.35) : Qt.rgba(255, 255, 255, 0.12))
              border.color: clearHover.hovered ? Qt.rgba(255, 255, 255, 0.30) : "transparent"
              border.width: 1
              scale: clearTap.pressed ? 0.90 : (clearHover.hovered ? 1.08 : 1.0)
              visible: searchInput.text.length > 0

              Behavior on color { ColorAnimation { duration: 120 } }
              Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

              HoverHandler {
                id: clearHover
                cursorShape: Qt.PointingHandCursor
              }

              TapHandler {
                id: clearTap
                onTapped: {
                  searchInput.text = ""
                  searchInput.forceActiveFocus()
                }
              }

              Text {
                anchors.centerIn: parent
                text: "✕"
                font.pixelSize: 11
                color: clearHover.hovered ? "#ffffff" : frameConfig.activeTextColor
              }
            }

            // Escape Keycap Button (Interactive Dismissal)
            Rectangle {
              id: escBtn
              height: 24
              width: escRow.implicitWidth + 14
              radius: 7
              color: escHover.hovered
                ? Qt.rgba(255, 255, 255, 0.22)
                : (escTap.pressed ? Qt.rgba(255, 255, 255, 0.30) : Qt.rgba(255, 255, 255, 0.10))
              border.color: escHover.hovered ? Qt.rgba(255, 255, 255, 0.30) : Qt.rgba(255, 255, 255, 0.16)
              border.width: 1
              scale: escTap.pressed ? 0.92 : (escHover.hovered ? 1.05 : 1.0)

              Behavior on color { ColorAnimation { duration: 120 } }
              Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

              HoverHandler {
                id: escHover
                cursorShape: Qt.PointingHandCursor
              }

              TapHandler {
                id: escTap
                onTapped: root.close()
              }

              Row {
                id: escRow
                anchors.centerIn: parent
                spacing: 3

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "⎋"
                  font.pixelSize: 11
                  color: escHover.hovered ? "#ffffff" : frameConfig.activeTextColor
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "esc"
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  font.weight: Font.DemiBold
                  color: escHover.hovered ? "#ffffff" : frameConfig.activeTextColor
                  renderType: Text.NativeRendering
                }
              }
            }
          }
        }

        // Application Results Grid Area with iOS-style Scroll Indicator
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          GridView {
            id: resultsGrid
            anchors.fill: parent
            clip: true
            model: root.filteredApps
            cellWidth: Math.floor(width / Math.max(1, frameConfig.searchGridColumns))
            cellHeight: frameConfig.searchGridCellHeight
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: frameConfig.searchGridCellHeight * 2

            onContentYChanged: {
              if (scrollTimer) scrollTimer.restart()
            }

            // Snappier wheel / trackpad scrolling
            WheelHandler {
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var delta = event.pixelDelta.y !== 0
                  ? event.pixelDelta.y * 2.0
                  : (event.angleDelta.y / 120) * frameConfig.searchGridCellHeight * 1.5
                var maxY = Math.max(0, resultsGrid.contentHeight - resultsGrid.height)
                resultsGrid.contentY = Math.max(0, Math.min(maxY, resultsGrid.contentY - delta))
                event.accepted = true
              }
            }

            delegate: Item {
              id: delegateRoot
              width: resultsGrid.cellWidth
              height: resultsGrid.cellHeight

              readonly property bool isSelected: index === root.selectedIndex
              readonly property bool isHovered: itemHover.hovered

              // Outer selection card: transparent when unselected, soft glass highlight when selected
              Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: 14
                color: delegateRoot.isSelected
                  ? frameConfig.searchItemActiveBg
                  : (delegateRoot.isHovered ? frameConfig.searchItemHoverBg : "transparent")
                border.color: delegateRoot.isSelected ? frameConfig.searchItemActiveBorder : "transparent"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
              }

              // Tactile spring scale feedback
              scale: itemTap.pressed ? 0.93 : (delegateRoot.isSelected ? 1.03 : 1.0)
              Behavior on scale {
                NumberAnimation {
                  duration: itemTap.pressed ? 100 : 220
                  easing.type: itemTap.pressed ? Easing.OutQuad : Easing.OutBack
                  easing.overshoot: 1.15
                }
              }

              HoverHandler {
                id: itemHover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: {
                  if (hovered) root.selectedIndex = index
                }
              }

              TapHandler {
                id: itemTap
                onTapped: root.launchItem(modelData)
              }

              ColumnLayout {
                anchors.centerIn: parent
                spacing: 5
                width: parent.width - 10

                // App Icon Container: cleanly renders squircle without nested double-box artifacts
                Rectangle {
                  Layout.alignment: Qt.AlignHCenter
                  width: 48
                  height: 48
                  radius: 13
                  // Transparent when selected so icon sits directly inside the outer card highlight
                  color: delegateRoot.isSelected
                    ? "transparent"
                    : (delegateRoot.isHovered ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(0, 0, 0, 0.18))
                  border.color: delegateRoot.isSelected ? "transparent" : Qt.rgba(255, 255, 255, 0.08)
                  border.width: 1

                  Behavior on color { ColorAnimation { duration: 140 } }

                  // Terminal icon indicator for command runner
                  Item {
                    anchors.fill: parent
                    visible: Boolean(modelData && modelData.isCommand)

                    Text {
                      anchors.centerIn: parent
                      text: "󰞷"
                      font.family: root.iconFont
                      font.pixelSize: 22
                      color: frameConfig.activeTextColor
                      renderType: Text.NativeRendering
                    }
                  }

                  // Application Desktop Icon
                  Image {
                    id: appIconImg
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    sourceSize.width: 68
                    sourceSize.height: 68
                    visible: !(modelData && modelData.isCommand)
                    source: {
                      var ic = modelData.icon || ""
                      if (!ic) return Quickshell.iconPath("application-x-executable", true)
                      if (ic.indexOf("/") >= 0 || ic.indexOf("file://") === 0) return ic
                      return Quickshell.iconPath(ic, true)
                    }
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                  }

                  // Fallback letter initial if icon asset is unavailable
                  Text {
                    anchors.centerIn: parent
                    visible: !(modelData && modelData.isCommand) && (appIconImg.status === Image.Error || appIconImg.status === Image.Null || !appIconImg.source)
                    text: modelData.name && modelData.name.length > 0 ? modelData.name.charAt(0).toUpperCase() : "󰘔"
                    font.family: root.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.Bold
                    color: frameConfig.activeTextColor
                    renderType: Text.NativeRendering
                  }
                }

                // App Name Label (Centered, Crisp, Elided)
                Text {
                  Layout.fillWidth: true
                  text: modelData.name || ""
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  font.weight: delegateRoot.isSelected ? Font.DemiBold : Font.Normal
                  color: delegateRoot.isSelected ? "#ffffff" : frameConfig.activeTextColor
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  maximumLineCount: 1
                  renderType: Text.NativeRendering
                }
              }
            }

            // Empty Results State
            Item {
              anchors.centerIn: parent
              width: parent.width - 40
              height: 100
              visible: root.filteredApps.length === 0

              ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: "No applications found"
                  font.family: root.fontFamily
                  font.pixelSize: 14
                  font.weight: Font.DemiBold
                  color: frameConfig.activeTextColor
                  renderType: Text.NativeRendering
                }

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: "Try searching with a different keyword"
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  color: frameConfig.mutedColor
                  renderType: Text.NativeRendering
                }
              }
            }
          }

          // iOS-style subtle floating scroll indicator
          Rectangle {
            id: scrollIndicator
            anchors.right: parent.right
            anchors.rightMargin: 1
            width: 3.5
            radius: 1.75
            color: Qt.rgba(255, 255, 255, 0.38)
            visible: resultsGrid.contentHeight > resultsGrid.height

            property real visibleRatio: Math.min(1.0, resultsGrid.height / Math.max(1, resultsGrid.contentHeight))
            height: Math.max(22, (resultsGrid.height - 8) * visibleRatio)
            property real maxContentY: Math.max(1, resultsGrid.contentHeight - resultsGrid.height)
            property real scrollNorm: Math.max(0.0, Math.min(1.0, resultsGrid.contentY / maxContentY))
            y: 4 + (scrollNorm * (resultsGrid.height - 8 - height))

            opacity: (resultsGrid.moving || resultsGrid.flicking || (scrollTimer && scrollTimer.running)) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 250 } }

            Timer {
              id: scrollTimer
              interval: 900
              running: false
              repeat: false
            }
          }
        }

        // Refined Apple HIG Control Bar & Power Dock
        // Refined Footer with Improved Tactile Power Buttons (Zero text)
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: frameConfig.searchFooterHeight

          // Hairline divider
          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(255, 255, 255, 0.10)
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            Repeater {
              model: root.powerActions

              delegate: Item {
                width: frameConfig.searchPowerButtonSize
                height: frameConfig.searchPowerButtonSize

                Rectangle {
                  id: powerButton
                  anchors.centerIn: parent
                  width: frameConfig.searchPowerButtonSize
                  height: frameConfig.searchPowerButtonSize
                  radius: width / 2

                  readonly property bool isPowerOff: index === 3
                  readonly property bool isRestart: index === 2
                  readonly property bool isHibernate: index === 1
                  readonly property bool isSuspend: index === 0

                  color: {
                    if (powerTap.pressed) return Qt.rgba(255, 255, 255, 0.35)
                    if (powerHover.hovered) {
                      if (isPowerOff) return Qt.rgba(235, 65, 65, 0.38)
                      if (isRestart) return Qt.rgba(245, 175, 45, 0.35)
                      if (isHibernate) return Qt.rgba(165, 105, 245, 0.35)
                      return Qt.rgba(85, 165, 245, 0.35)
                    }
                    return frameConfig.powerButtonInactiveBg
                  }

                  border.color: powerHover.hovered
                    ? Qt.rgba(255, 255, 255, 0.38)
                    : Qt.rgba(255, 255, 255, 0.14)
                  border.width: 1

                  scale: powerTap.pressed ? 0.90 : (powerHover.hovered ? 1.08 : 1.0)

                  Behavior on color { ColorAnimation { duration: 150 } }
                  Behavior on border.color { ColorAnimation { duration: 150 } }
                  Behavior on scale {
                    NumberAnimation {
                      duration: 160
                      easing.type: Easing.OutBack
                      easing.overshoot: 1.15
                    }
                  }

                  Text {
                    anchors.centerIn: parent
                    text: modelData.glyph
                    font.family: root.iconFont
                    font.pixelSize: 19
                    color: powerHover.hovered ? "#ffffff" : frameConfig.powerButtonInactiveIcon
                    renderType: Text.NativeRendering
                  }

                  HoverHandler {
                    id: powerHover
                    cursorShape: Qt.PointingHandCursor
                  }

                  TapHandler {
                    id: powerTap
                    onTapped: root.runPowerAction(modelData.command)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
