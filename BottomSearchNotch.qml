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
  property bool isOpen: false       // Manual open from keybind or IPC
  property bool isHoverOpen: false  // Hover open from mouse interaction

  readonly property bool isHovered: Boolean(notchHover && notchHover.hovered)
  readonly property bool isTyping: Boolean(searchInput && searchInput.text.length > 0)
  readonly property bool isOpenEffective: root.isOpen || root.isHoverOpen || isHovered || isTyping

  signal openRequested()
  signal closeRequested()

  function open() {
    root.isOpen = true
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
    root.isOpen = false
    root.isHoverOpen = false
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
  readonly property real collapsedHeight: root.borderThickness + frameConfig.searchCollapsedHeight
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
      duration: root.isOpenEffective ? 380 : 260
      easing.type: root.isOpenEffective ? Easing.OutBack : Easing.OutCubic
      easing.overshoot: root.isOpenEffective ? 1.08 : 1.0
    }
  }

  // Authentic iOS liquid stretch:
  // Width & height stretch smoothly with a sinusoidal volume pulse mid-transition
  readonly property real currentWidth: collapsedWidth
    + (openProgress * (expandedWidth - collapsedWidth))
    + (Math.sin(Math.min(1.0, Math.max(0.0, openProgress)) * Math.PI) * 10.0)

  readonly property real currentHeight: collapsedHeight
    + (openProgress * (expandedHeight - collapsedHeight))
    + (Math.sin(Math.min(1.0, Math.max(0.0, openProgress)) * Math.PI) * 6.0)

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
  // Full-Screen Backdrop Dim & Click-Away Catcher
  // =========================================================================
  Item {
    id: backdropOverlay
    anchors.fill: root.isOpenEffective ? parent : undefined
    width: root.isOpenEffective ? parent.width : 0
    height: root.isOpenEffective ? parent.height : 0
    visible: root.isOpenEffective && root.openProgress > 0.01

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)
      opacity: root.openProgress
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  // =========================================================================
  // Centered Bottom Notch Container
  // =========================================================================
  Item {
    id: notchContainer
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter

    width: root.currentWidth
    height: root.currentHeight

    // OLED Theme Color Animation
    property color activeColor: root.notchColor
    Behavior on activeColor { ColorAnimation { duration: 400 } }

    // Hover handler for effortless blooming interaction
    HoverHandler {
      id: notchHover
      cursorShape: (!root.isOpenEffective) ? Qt.PointingHandCursor : Qt.ArrowCursor
      onHoveredChanged: {
        if (hovered) {
          root.isHoverOpen = true
          root.refreshApps()
          Qt.callLater(function() {
            if (searchInput) searchInput.forceActiveFocus()
          })
        } else if (!root.isOpen && !root.isTyping) {
          root.isHoverOpen = false
        }
      }
    }

    // Tactile press state when resting
    property bool isPillPressed: restingTapHandler.pressed
    scale: (!root.isOpenEffective && isPillPressed) ? 0.96 : 1.0
    transformOrigin: Item.Bottom

    Behavior on scale {
      NumberAnimation {
        duration: notchContainer.isPillPressed ? 120 : 280
        easing.type: notchContainer.isPillPressed ? Easing.OutQuad : Easing.OutBack
        easing.overshoot: 1.15
      }
    }

    // -----------------------------------------------------------------------
    // G1 Continuous Squircle Notch Shape (Mirrors top Dynamic Island)
    // -----------------------------------------------------------------------
    Shape {
      id: notchShape
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      readonly property real w: notchContainer.width
      readonly property real h: notchContainer.height
      readonly property real rFlare: root.currentFlareRadius
      readonly property real rCorner: root.currentCornerRadius
      readonly property real b: root.borderThickness

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: notchContainer.activeColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        // Start at bottom-left below screen edge for zero-bleed seal
        startX: 0
        startY: notchShape.h + 2.0

        // Vertical line up to bottom border top edge
        PathLine {
          x: 0
          y: notchShape.h - notchShape.b
        }

        // Left concave flare curving smoothly from horizontal border upwards
        PathCubic {
          x: notchShape.rFlare
          y: notchShape.h - notchShape.b - notchShape.rFlare
          control1X: notchShape.rFlare * 0.5
          control1Y: notchShape.h - notchShape.b
          control2X: notchShape.rFlare
          control2Y: notchShape.h - notchShape.b - (notchShape.rFlare * 0.5)
        }

        // Left vertical side up to top-left corner arc
        PathLine {
          x: notchShape.rFlare
          y: notchShape.rCorner
        }

        // Top-left convex corner arc
        PathArc {
          x: notchShape.rFlare + notchShape.rCorner
          y: 0
          radiusX: notchShape.rCorner
          radiusY: notchShape.rCorner
          direction: PathArc.Clockwise
        }

        // Top horizontal edge
        PathLine {
          x: notchShape.w - notchShape.rFlare - notchShape.rCorner
          y: 0
        }

        // Top-right convex corner arc
        PathArc {
          x: notchShape.w - notchShape.rFlare
          y: notchShape.rCorner
          radiusX: notchShape.rCorner
          radiusY: notchShape.rCorner
          direction: PathArc.Clockwise
        }

        // Right vertical side down to right flare
        PathLine {
          x: notchShape.w - notchShape.rFlare
          y: notchShape.h - notchShape.b - notchShape.rFlare
        }

        // Right concave flare curving smoothly back down to horizontal border
        PathCubic {
          x: notchShape.w
          y: notchShape.h - notchShape.b
          control1X: notchShape.w - notchShape.rFlare
          control1Y: notchShape.h - notchShape.b - (notchShape.rFlare * 0.5)
          control2X: notchShape.w - (notchShape.rFlare * 0.5)
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
      anchors.leftMargin: root.currentFlareRadius + 8
      anchors.rightMargin: root.currentFlareRadius + 8

      visible: opacity > 0.01
      opacity: root.openProgress
      scale: 0.94 + (0.06 * root.openProgress)
      transformOrigin: Item.Bottom

      ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Fully Rounded Search Input Capsule
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: frameConfig.searchBarHeight
          radius: frameConfig.searchBarRadius
          color: frameConfig.searchFieldBg
          border.color: searchInput.activeFocus ? Qt.rgba(255, 255, 255, 0.32) : Qt.rgba(255, 255, 255, 0.16)
          border.width: 1

          Behavior on border.color { ColorAnimation { duration: 180 } }

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
              color: frameConfig.activeTextColor
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
              width: 24
              height: 24
              radius: 12
              color: clearHover.hovered ? Qt.rgba(255, 255, 255, 0.22) : Qt.rgba(255, 255, 255, 0.10)
              visible: searchInput.text.length > 0

              HoverHandler {
                id: clearHover
                cursorShape: Qt.PointingHandCursor
              }

              TapHandler {
                onTapped: {
                  searchInput.text = ""
                  searchInput.forceActiveFocus()
                }
              }

              Text {
                anchors.centerIn: parent
                text: "✕"
                font.pixelSize: 11
                color: frameConfig.activeTextColor
              }
            }

            // Escape Hint Badge (Pill)
            Rectangle {
              height: 22
              width: escLabel.implicitWidth + 12
              radius: 11
              color: Qt.rgba(255, 255, 255, 0.12)

              Text {
                id: escLabel
                anchors.centerIn: parent
                text: "ESC"
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: frameConfig.mutedColor
                renderType: Text.NativeRendering
              }
            }
          }
        }

        // Application Results Grid (iOS-Style App Grid)
        GridView {
          id: resultsGrid
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: root.filteredApps
          cellWidth: Math.floor(width / Math.max(1, frameConfig.searchGridColumns))
          cellHeight: frameConfig.searchGridCellHeight
          boundsBehavior: Flickable.StopAtBounds

          delegate: Item {
            id: delegateRoot
            width: resultsGrid.cellWidth
            height: resultsGrid.cellHeight

            readonly property bool isSelected: index === root.selectedIndex
            readonly property bool isHovered: itemHover.hovered

            // Highlight card
            Rectangle {
              anchors.fill: parent
              anchors.margins: 4
              radius: 14
              color: delegateRoot.isSelected
                ? frameConfig.searchItemActiveBg
                : (delegateRoot.isHovered ? frameConfig.searchItemHoverBg : "transparent")
              border.color: delegateRoot.isSelected ? frameConfig.searchItemActiveBorder : "transparent"
              border.width: 1

              Behavior on color { ColorAnimation { duration: 120 } }
            }

            // Tactile scale feedback on press
            scale: itemTap.pressed ? 0.94 : 1.0
            Behavior on scale { NumberAnimation { duration: 100 } }

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
              spacing: 6
              width: parent.width - 12

              // App Icon with iOS rounded squircle container
              Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 48
                height: 48
                radius: 12
                color: Qt.rgba(255, 255, 255, 0.08)

                Image {
                  anchors.centerIn: parent
                  width: 36
                  height: 36
                  sourceSize.width: 72
                  sourceSize.height: 72
                  source: {
                    var ic = modelData.icon || ""
                    if (!ic) return Quickshell.iconPath("application-x-executable", true)
                    if (ic.indexOf("/") >= 0 || ic.indexOf("file://") === 0) return ic
                    return Quickshell.iconPath(ic, true)
                  }
                  fillMode: Image.PreserveAspectFit
                }
              }

              // App Name (Centered, Crisp, Elided)
              Text {
                Layout.fillWidth: true
                text: modelData.name || ""
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: delegateRoot.isSelected ? Font.DemiBold : Font.Normal
                color: frameConfig.activeTextColor
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
      }
    }
  }
}
