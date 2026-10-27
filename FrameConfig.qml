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
  property int islandBodyWidth: 76
  property int islandTopCurveRadius: 10             // Top fillet radius when closed
  property int islandExpandedTopCurveRadius: 14     // Top fillet radius when opened
  property int islandBottomCornerRadius: 15         // Bottom corner radius when closed
  property int islandExpandedBottomCornerRadius: 28 // Bottom corner radius when opened

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
  // TOP NOTCH STATUS & FLUID SUBPANEL CONSTANTS
  // =========================================================================
  property real statusSubpanelWidth: 350
  property real statusSubpanelHeight: 380
  property real statusSubpanelRadius: 20
  property color statusSubpanelBg: Qt.rgba(14 / 255, 14 / 255, 18 / 255, 0.96)
  property color statusSubpanelBorder: Qt.rgba(activeBorderColor.r, activeBorderColor.g, activeBorderColor.b, 0.35)

  // =========================================================================
  // BOTTOM SEARCH NOTCH CONSTANTS
  // =========================================================================
  // Resting notch width: adjust here to make the bottom notch wider or narrower
  property real searchCollapsedWidth: 280

  // Expanded search panel width & height
  property real searchExpandedWidth: 560
  property real searchCollapsedHeight: 10           // Resting protrusion past bottom border (sleek low profile)
  property real searchExpandedHeight: 460           // Expanded search window height

  // Search notch corner & flare radii:
  property real searchCornerRadius: 10             // Top corner radius when closed
  property real searchExpandedCornerRadius: 26     // Top corner radius when opened
  property real searchFlareRadius: 8               // Concave flare radius when closed
  property real searchExpandedFlareRadius: 18      // Concave flare radius when opened

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
