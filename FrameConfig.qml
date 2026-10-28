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
  // BOTTOM-RIGHT CONTROL CENTER — EDIT SHAPE HERE
  // =========================================================================
  // Mirrors the bottom-left search gusset: a low lip along the BOTTOM border
  // plus a finger climbing the RIGHT border. Clicking the corner blooms the
  // control menu upwards like a start menu.
  //
  //     ╭───────────  <- top edge when open
  //     │        ▐    <- finger width
  //     └──╮     │    <- lip height / finger height
  //        ╰─────┘    <- lip length along the bottom

  // ---- WIDTH --------------------------------------------------------------
  // Lip length: how far the resting gusset reaches left along the bottom
  property real controlCollapsedWidth: 110
  // Finger width: the part merged into the right border
  property real controlRightTabWidth: 10
  // Panel width when the control menu is open
  property real controlExpandedWidth: 248

  // ---- HEIGHT -------------------------------------------------------------
  // Lip rise above the bottom border
  property real controlCollapsedHeight: 5
  // Finger height: how far the gusset climbs up the right border
  property real controlRightTabHeight: 100
  // Panel height when the control menu is open
  property real controlExpandedHeight: 280

  // ---- CURVES / RADII -----------------------------------------------------
  property real controlTabCapRadius: 5
  property real controlInnerRadius: 12
  property real controlCornerRadius: 10
  property real controlFlareRadius: 12
  property real controlExpandedCornerRadius: 20
  property real controlExpandedFlareRadius: 12
  property real controlCurveTension: 0.55

  // ---- MOTION (start-menu bloom) ------------------------------------------
  property int controlOpenDuration: 300            // ms, energetic spring open
  property int controlCloseDuration: 220           // ms, damped settle
  property real controlOpenOvershoot: 1.08         // OutBack overshoot
  property real controlWidthPulse: 10              // sideways stretch mid-open (px)
  property real controlHeightPulse: 6              // vertical stretch mid-open (px)

  // ---- CONTENT ------------------------------------------------------------
  property real controlButtonSize: 54              // Wi-Fi / Bluetooth circles
  property real controlPowerButtonSize: 54         // Power profile circles (same size as bt and wifi)
  property real controlSliderWidth: 124            // Horizontal slider width
  property real controlSliderHeight: 54           // Horizontal slider height (matches 54px buttons)
  property real controlBatteryRowWidth: 124        // Battery capsule width (aligns with slider column)
  property real controlBatteryHeight: 54           // Battery capsule height (matches status circles)

  // ---- STATUS SUBPANEL (blooms leftwards out of the open control card) -----
  property real controlSubpanelWidth: 300          // Subpanel width (Wi-Fi / Bluetooth / DNS views)
  property real controlSubpanelHeight: 236         // Subpanel height
  property real controlSubpanelFlareRadius: 20     // Concave flare melting into the control card edge
  property real controlSubpanelCornerRadius: 22    // Free-end rounded corners

  // =========================================================================
  // TOP-LEFT WORKSPACE NOTCH CONSTANTS (VERTICAL 1-COLUMN ON LEFT BORDER)
  // =========================================================================
  // Vertical distance from top screen edge (top-left, a little lower)
  property real workspaceTopMargin: 68
  // Total protrusion width from left screen edge
  property real workspaceWidth: 61
  // Left/right breathing room around the workspace pills
  property real workspaceSidePadding: 12
  // Vertical height containing the 1-column workspaces downwise
  property real workspaceHeight: 272
  // Rail item geometry (iOS squircle rail)
  property real workspaceItemSize: 32               // Workspace squircle size
  property real workspaceItemRadius: 10             // Squircle radius (32px -> iOS-smooth, not a circle)
  property real workspaceItemSpacing: 12            // Vertical rhythm between workspace numbers
  property real workspaceRailPadding: 32            // Top/bottom breathing room inside the notch
  // Corner and concave flare radii
  property real workspaceCornerRadius: 16
  property real workspaceFlareRadius: 12
  // Animation durations and physics
  property int workspaceOpenDuration: 340         // ms, iOS energetic spring open
  property int workspaceCloseDuration: 280        // ms, matches top Dynamic Island retract speed (response 0.28)
  property real workspaceOpenOvershoot: 1.08      // iOS OutBack spring overshoot

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
  property real searchExpandedHeight: 580

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
  property real searchPowerButtonSize: 42
  property real searchFooterHeight: 60

  // Search input bar styling (fully rounded pill)
  property real searchBarHeight: 46                // Search input height
  property real searchBarRadius: 23                // Search input fully rounded capsule radius
  property int searchGridColumns: 5                // Number of grid columns for applications
  property real searchGridCellHeight: 92           // Height per app grid cell
  property color searchFieldBg: Qt.rgba(0, 0, 0, 0.28)
  property color searchItemHoverBg: Qt.rgba(255, 255, 255, 0.08)
  property color searchItemActiveBg: Qt.rgba(255, 255, 255, 0.16)
  property color searchItemActiveBorder: Qt.rgba(255, 255, 255, 0.24)

  // =========================================================================
  // BOTTOM-CENTER WALLPAPER NOTCH — EDIT SHAPE HERE
  // =========================================================================
  // The top Dynamic Island, flipped upside down and grown out of the middle of
  // the BOTTOM border. Same construction, same numbers:
  //   • the outer edge is full width (wallpaperCollapsedWidth) and runs through
  //     the border band, so the body melts into the frame with zero bleed
  //   • the body is inset by wallpaperFlareRadius on each side (exactly like
  //     islandBodyWidth = islandWidth - 2 * islandTopCurveRadius)
  //   • the shoulders are the island's top flare cubic (control ratio 0.5,
  //     curve below the band), only mirrored downwards
  //   • the free edge uses the island's pill arcs, not beziers
  //   • no text at all, only wallpaper thumbs
  //
  //      ╭────────────────────────────╮   <- free edge (island pill arcs)
  //      │  ▢   ▢   ▢   ▢   ▢         │
  //   ───╯                            ╰───  <- island top-flare, mirrored
  //
  // ---- WIDTH --------------------------------------------------------------
  // Outer lip width where it melts into the band (island: body + 2 * shoulder)
  property real wallpaperCollapsedWidth: 226
  // Open panel width is derived, never hard-coded:
  //   padding * 2 + visibleThumbs * thumb + (visibleThumbs - 1) * spacing
  // The panel follows the catalogue size, so 2 wallpapers give a small capsule
  // and 5 give the full strip. Above this count it stops growing and scrolls.
  property int wallpaperMaxVisibleThumbs: 7

  // ---- HEIGHT (measured above the border band; borderThickness is added) ---
  // Resting lip rise (mirrors the island protrusion)
  property real wallpaperCollapsedHeight: 15
  // Panel rise when the filmstrip is open
  property real wallpaperExpandedHeight: 118

  // ---- CURVES / RADII -----------------------------------------------------
  // Shoulder flare where the lip melts into the bottom band (= island top curve)
  property real wallpaperFlareRadius: 10
  // Free-edge corner radius (= island bottom corner radius, mirrored)
  property real wallpaperCornerRadius: 15
  // Same two radii once the panel is open
  property real wallpaperExpandedFlareRadius: 22
  property real wallpaperExpandedCornerRadius: 36
  // Flare bezier pull: 0.5 is the exact island flare, lower = tighter shoulder
  property real wallpaperFlareControlRatio: 0.5
  // Overlap into the border band so the seam can never show a hairline (px)
  property real wallpaperBleed: 2
  // Horizontal guard: keeps the free edge from inverting on narrow widths
  property real wallpaperTopEdgeGuardRatio: 0.3

  // ---- MOTION (Authentic iOS Fluid Motion matching BottomSearchNotch) ------
  property int wallpaperOpenDuration: 380            // ms, energetic spring open
  property int wallpaperCloseDuration: 260           // ms, critically damped settle
  property real wallpaperOpenOvershoot: 1.04         // Subtle OutBack overshoot
  property real wallpaperOpenResponse: 0.40          // s, bloom out
  property real wallpaperOpenDamping: 0.84           // zeta, slight overshoot
  property real wallpaperCloseResponse: 0.30         // s, settle back
  property real wallpaperCloseDamping: 1.0           // zeta, no bounce on close
  property real wallpaperWidthPulse: 0               // zero pulse to eliminate width shrink/grow oscillation
  property real wallpaperHeightPulse: 4              // vertical liquid stretch (px)
  property real wallpaperRestingPressScale: 0.96     // lip squish on touch-down
  property real wallpaperHoverScale: 1.02            // thumb hover scale
  property real wallpaperSelectedScale: 1.05         // selected thumb scale
  property real wallpaperThumbHoverResponse: 0.30    // s, thumb scale spring
  property real wallpaperThumbHoverDamping: 0.82     // zeta, thumb scale spring
  property int wallpaperHoverCloseDelay: 260         // ms, pointer grace period
  property int wallpaperPointerPollInterval: 120     // ms, real-cursor containment poll
  property int wallpaperWatchdogStrikes: 2           // missed polls before closing
  property real wallpaperPointerGrace: 8             // px forgiveness around the lip
  property real wallpaperSpringEpsilon: 0.0004       // settle threshold
  // Auto-retract (apps open) and wake springs
  property real wallpaperRetractResponse: 0.28       // s, hide into the frame
  property real wallpaperRetractDamping: 1.0         // zeta, no bounce
  property real wallpaperWakeResponse: 0.36          // s, slide back out
  property real wallpaperWakeDamping: 0.8            // zeta, slight life
  // Lip touch-down squish
  property real wallpaperPressResponse: 0.18         // s, squish down
  property real wallpaperPressDamping: 1.0
  property real wallpaperReleaseResponse: 0.30       // s, pop back
  property real wallpaperReleaseDamping: 0.78
  // Retracted-lip wake target (only present while the lip is hidden)
  property real wallpaperWakeZoneWidth: 180          // px, never below the lip
  property real wallpaperWakeZoneHeight: 24          // px above the border band
  property real wallpaperRetractProgressEpsilon: 0.05 // progress under which it hides

  // ---- CONTENT (wallpaper thumbs, nothing else) ---------------------------
  property real wallpaperContentPadding: 48          // Left/right inset of the strip
  property real wallpaperThumbWidth: 140             // Wallpaper thumbnail width
  property real wallpaperThumbHeight: 78             // Wallpaper thumbnail height
  property real wallpaperThumbRadius: 16             // Thumbnail rounded corner radius
  property real wallpaperThumbSpacing: 12            // Gap between thumbnails
  property int wallpaperThumbSourceScale: 2          // Decode size = thumb size * this
  property int wallpaperCacheBuffer: 900             // px pre-rendered either side
  property int wallpaperThumbFadeDuration: 120       // ms, thumb fade-in when decoded
  // Ring widths: selection > live wallpaper > resting hairline
  property real wallpaperSelectedBorderWidth: 2      // px, ring around the selection
  property real wallpaperAppliedBorderWidth: 2       // px, frame on the live wallpaper
  property color wallpaperAppliedBorderColor: Qt.rgba(1, 1, 1, 0.62)  // live frame tint
  // Cross-fades while the silhouette morphs (all values are openProgress based)
  property real wallpaperContentFadeStart: 0.10      // progress where thumbs appear
  property real wallpaperContentFadeRate: 1.6        // opacity per progress unit
  property real wallpaperContentScaleFrom: 0.95      // thumbs scale at first frame
  property real wallpaperRestingFadeRate: 3.0        // lip content fade-out speed
  property real wallpaperRestingHideAt: 0.9          // progress where the lip retires

  // ---- SWITCHING ----------------------------------------------------------
  // true  = wallpaper swaps with zero crossfade (omarchy "setInstant" IPC)
  // false = omarchy's default diagonal reveal wipe (~420ms), used on purpose
  property bool wallpaperInstantSwitch: false
  // Key-repeat coalescing window in ms (single presses are applied at once)
  property int wallpaperApplyDebounce: 40
  // Catalogue is reused while younger than this (ms) before a rescan
  property int wallpaperScanFreshness: 60000

  // ---- DECODE CACHE -------------------------------------------------------
  // Heavy originals (a 17MB 3800x2460 PNG needs 300ms+ to decode inside the
  // background layer, which made it visibly slower than every other wallpaper)
  // are mirrored to a screen-sized JPEG on first scan. The symlink keeps
  // pointing at the original; only the render path uses the twin.
  property bool wallpaperDecodeCacheEnabled: true
  property int wallpaperDecodeCacheMinBytes: 1200000   // skip files smaller than this
  property int wallpaperCacheWidth: 1920               // twin width (screen size)
  property int wallpaperCacheHeight: 1080              // twin height
  property int wallpaperCacheQuality: 92               // JPEG quality of the twin

  // ---- COLORS -------------------------------------------------------------
  property color wallpaperThumbBg: Qt.rgba(0, 0, 0, 0.28)
  property color wallpaperThumbBorder: Qt.rgba(1, 1, 1, 0.14)
  property color wallpaperThumbHoverBorder: Qt.rgba(1, 1, 1, 0.34)
  property color wallpaperThumbActiveBorder: Qt.rgba(1, 1, 1, 0.92)
  property color wallpaperItemHoverBg: Qt.rgba(255, 255, 255, 0.10)

  // Folders scanned for wallpapers (all merged, duplicates removed, ~ = $HOME)
  property var wallpaperScanDirs: [
    "~/.local/state/omarchy/current/theme/backgrounds",
    "~/.config/omarchy/backgrounds",
    "~/Pictures/Wallpapers"
  ]

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
