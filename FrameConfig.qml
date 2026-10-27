import QtQuick

QtObject {
  id: config

  // =========================================================================
  // SCREEN FRAME BORDER CONSTANTS
  // =========================================================================
  // Border thickness around all 4 sides of the screen (pixels)
  // Windows tile and dock against this margin inside Hyprland
  property int borderThickness: 5

  // =========================================================================
  // MANUAL THEME COLORS (used when dynamicWallpaperColor is false)
  // =========================================================================
  property color borderColor: "#ba5f58"
  property color textColor: "#ffffff"
  property color mutedColor: Qt.rgba(1, 1, 1, 0.90)

  // =========================================================================
  // DYNAMIC WALLPAPER COLOR AUTO-COMPLIMENT (RUST ENGINE)
  // =========================================================================
  // When true, our native Rust decision engine (lumania-colors) analyzes the active
  // wallpaper and extracts the optimal palette in real time (<2ms).
  // Set to false to manually pin the colors to borderColor above.
  property bool dynamicWallpaperColor: true

  // Mode: "accent" (dominant wallpaper tone) or "complementary" (180deg contrasting hue)
  property string wallpaperColorMode: "accent"

  // Dynamic colors populated by native Rust engine:
  property color autoAccentColor: "#ba5f58"
  property color autoComplementaryColor: "#58a8ba"
  property color autoMutedColor: "#7d4843"
  property color autoTextColor: "#ffffff"
  property color autoSliderFill: "#ffffff"
  property color autoSliderIconFilled: "#ba5f58"

  // Effective active colors consumed by the shell
  readonly property color activeBorderColor: dynamicWallpaperColor
    ? (wallpaperColorMode === "complementary" ? autoComplementaryColor : autoAccentColor)
    : borderColor

  readonly property color activeTextColor: dynamicWallpaperColor ? autoTextColor : textColor
  readonly property color activeSliderFillColor: dynamicWallpaperColor ? autoSliderFill : sliderFillColor
  readonly property color activeSliderIconColorFilled: dynamicWallpaperColor ? autoSliderIconFilled : sliderIconColorFilled

  // =========================================================================
  // CORNER CURVATURE & BORDER MERGING CONSTANTS
  // =========================================================================
  // Fillet radius (in pixels) for how the borders curve and merge into each other:
  // - topLeftRadius: curves left border into top border
  // - topRightRadius: curves right border into top border
  // - bottomLeftRadius: curves left border into bottom border
  // - bottomRightRadius: curves right border into bottom border
  property real topLeftRadius: 16
  property real topRightRadius: 16
  property real bottomLeftRadius: 16
  property real bottomRightRadius: 16

  // Corner curvature style:
  // - "squircle": Apple G1 continuous cubic bezier (gentle ramp, fluid unibody feel)
  // - "arc": Exact geometric circular fillet
  property string cornerStyle: "squircle"

  // Squircle tension factor (0.35 - 0.65; 0.52 is Apple standard squircle)
  property real squircleFactor: 0.52

  // =========================================================================
  // DYNAMIC ISLAND CONSTANTS (TOP NOTCH)
  // =========================================================================
  property int islandBodyWidth: 206
  property int islandTopCurveRadius: 10             // Top fillet radius when closed
  property int islandExpandedTopCurveRadius: 14     // Top fillet radius when opened
  property int islandBottomCornerRadius: 15         // Bottom corner radius when closed
  property int islandExpandedBottomCornerRadius: 28 // Bottom corner radius when opened
  property int islandHoverWidthDelta: 140           // Width expansion on hover
  property int islandHoverHeightDeltaIdle: 46       // Height expansion when idle (fits 48px circular status buttons)
  property int islandHoverHeightDeltaMedia: 24      // Height expansion when media playing (fits media controls)

  // =========================================================================
  // RIGHT CONTROL NOTCH CONSTANTS
  // =========================================================================
  // Resting width: protrusion past border (e.g. 5) or total width (e.g. 15-20)
  property real rightCollapsedWidth: 5
  property real rightExpandedWidth: 98
  property real rightCollapsedHeight: 200
  property real rightExpandedHeight: 540

  // Right notch corner & flare radii:
  property real rightCornerRadius: 15             // Outer corner radius when closed
  property real rightExpandedCornerRadius: 28     // Outer corner radius when opened
  property real rightFlareRadius: 6               // Concave flare radius when closed
  property real rightExpandedFlareRadius: 18      // Concave flare radius when opened

  // =========================================================================
  // TOP NOTCH STATUS & FLUID SUBPANEL CONSTANTS (MINIMAL UNIBODY)
  // =========================================================================
  property real statusSubpanelWidth: 320            // Total width of dropdown subpanel
  property real statusSubpanelHeight: 220           // Total height of dropdown subpanel
  property real statusSubpanelFlareRadius: 16       // Concave flare radius curving toward left-top & right-top
  property real statusSubpanelBottomRadius: 20      // Bottom rounded corner radius of subpanel
  property real statusSubpanelTopMargin: -4         // Vertical overlap with bottom of Dynamic Island
  property color statusSubpanelBg: activeBorderColor
  property color statusSubpanelBorder: Qt.rgba(0, 0, 0, 0.15)

  // =========================================================================
  // BOTTOM-LEFT SEARCH NOTCH — EDIT SHAPE HERE
  // =========================================================================
  // Resting state is a "C" gusset: a low lip running along the BOTTOM border
  // plus a finger climbing the LEFT border, so the corner is one solid piece.
  //
  //     │              <- left border
  //     │  finger height
  //     ▌              <- finger width
  //     └──╮
  //        ╰──────────  <- lip height / lip length

  // ---- WIDTH --------------------------------------------------------------
  // Lip length: how far the resting gusset reaches right along the bottom
  property real searchCollapsedWidth: 110
  // Finger width: the part merged into the left border
  property real searchLeftTabWidth: 10
  // Panel width when the search is open
  property real searchExpandedWidth: 560

  // ---- HEIGHT -------------------------------------------------------------
  // Lip rise above the bottom border (keep small for a sleek hairline lip)
  property real searchCollapsedHeight: 5
  // Finger height: how far the gusset climbs up the left border
  property real searchLeftTabHeight: 100
  // Panel height when the search is open
  property real searchExpandedHeight: 460

  // ---- CURVES / RADII -----------------------------------------------------
  // Rounded cap on the finger's free end (0 = square top)
  property real searchTabCapRadius: 5
  // Inner concave radius where the finger melts into the lip (the "C" mouth)
  property real searchInnerRadius: 12
  // Free (right) end of the resting lip
  property real searchCornerRadius: 10
  // Concave merger of the resting gusset into the left + bottom borders
  property real searchFlareRadius: 12
  // Same two radii once the panel is open
  property real searchExpandedCornerRadius: 26
  property real searchExpandedFlareRadius: 20
  // Bezier tension of every concave flare (0.55 default, lower = tighter curve)
  property real searchCurveTension: 0.55

  // ---- SAFETY CLAMPS (advanced: keep the outline from ever self-crossing) --
  property real searchTabWidthMaxRatio: 0.25       // finger width <= notch width * this
  property real searchLipFlareMaxRatio: 0.4        // right flare <= lip height * this
  property real searchLipCornerRatio: 0.55         // lip-end corner <= lip height * this
  property real searchTopEdgeGuardRatio: 0.22      // keeps the top edge from inverting

  // ---- MOTION -------------------------------------------------------------
  property int searchOpenDuration: 380             // ms, open animation
  property int searchCloseDuration: 260            // ms, close animation
  property real searchOpenOvershoot: 1.08          // open spring overshoot
  property real searchWidthPulse: 10               // sideways stretch mid-open (px)
  property real searchHeightPulse: 6               // vertical stretch mid-open (px)

  // Power action row inside the expanded panel
  property real searchPowerButtonSize: 40
  property real searchFooterHeight: 84

  // Search input bar styling (fully rounded pill)
  property real searchBarHeight: 46                // Search input height
  property real searchBarRadius: 23                // Search input fully rounded capsule radius
  property int searchGridColumns: 5                // Number of grid columns for applications
  property real searchGridCellHeight: 96           // Height per app grid cell
  property color searchFieldBg: Qt.rgba(0, 0, 0, 0.28)
  property color searchItemHoverBg: Qt.rgba(255, 255, 255, 0.08)
  property color searchItemActiveBg: Qt.rgba(255, 255, 255, 0.16)
  property color searchItemActiveBorder: Qt.rgba(255, 255, 255, 0.22)

  // =========================================================================
  // PROGRESS BAR & SLIDER THEME CONSTANTS
  // =========================================================================
  // Capsule track background color (unfilled portion of slider)
  property color sliderTrackColor: Qt.rgba(0, 0, 0, 0.22)

  // Progress fill color for volume and brightness capsules
  property color sliderFillColor: "#ffffff"

  // Slider icon color when resting on dark unfilled track
  property color sliderIconColorUnfilled: "#ffffff"

  // Slider icon color when covered by progress fill
  property color sliderIconColorFilled: activeBorderColor

  // Power profile button colors
  property color powerButtonActiveBg: "#ffffff"
  property color powerButtonInactiveBg: Qt.rgba(0, 0, 0, 0.20)
  property color powerButtonActiveIcon: activeBorderColor
  property color powerButtonInactiveIcon: "#ffffff"
}
