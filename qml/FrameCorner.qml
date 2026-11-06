import QtQuick
import QtQuick.Shapes

Item {
  id: root

  // Target corner: "topLeft", "topRight", "bottomLeft", "bottomRight"
  property string corner: "topLeft"

  // Frame geometry properties
  property real thickness: 5
  property real radius: 16
  property color color: "#ba5f58"
  property string style: "squircle"
  property real squircleFactor: 0.52

  visible: radius > 0

  // The fillet item width is radius; height is thickness + radius
  implicitWidth: Math.max(1.0, radius)
  implicitHeight: thickness + Math.max(1.0, radius)

  readonly property real t: thickness
  readonly property real r: Math.max(1.0, radius)
  readonly property real w: width
  readonly property real h: height
  readonly property real k: Math.min(0.65, Math.max(0.35, squircleFactor))

  // =========================================================================
  // 1. TOP-LEFT CORNER
  // =========================================================================
  Shape {
    id: tlShape
    anchors.fill: parent
    visible: root.corner === "topLeft"
    preferredRendererType: Shape.CurveRenderer
    asynchronous: false

    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillColor: root.color
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      startX: 0
      startY: 0

      // Down along left border
      PathLine { x: 0; y: root.h }

      // Smooth inner fillet from (0, h) to (w, t)
      PathCubic {
        x: root.w
        y: root.t
        control1X: 0
        control1Y: root.t + root.r * (1.0 - root.k)
        control2X: root.r * (1.0 - root.k)
        control2Y: root.t
      }

      // Up to top border
      PathLine { x: root.w; y: 0 }
      // Back to start (0, 0)
      PathLine { x: 0; y: 0 }
    }
  }

  // =========================================================================
  // 2. TOP-RIGHT CORNER (Other side ending)
  // =========================================================================
  Shape {
    id: trShape
    anchors.fill: parent
    visible: root.corner === "topRight"
    preferredRendererType: Shape.CurveRenderer
    asynchronous: false

    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillColor: root.color
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      startX: root.w
      startY: 0

      // Down along right border
      PathLine { x: root.w; y: root.h }

      // Smooth inner fillet from (w, h) to (0, t)
      PathCubic {
        x: 0
        y: root.t
        control1X: root.w
        control1Y: root.t + root.r * (1.0 - root.k)
        control2X: root.r * root.k
        control2Y: root.t
      }

      // Up to top border
      PathLine { x: 0; y: 0 }
      // Back to start (w, 0)
      PathLine { x: root.w; y: 0 }
    }
  }

  // =========================================================================
  // 3. BOTTOM-LEFT CORNER
  // =========================================================================
  Shape {
    id: blShape
    anchors.fill: parent
    visible: root.corner === "bottomLeft"
    preferredRendererType: Shape.CurveRenderer
    asynchronous: false

    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillColor: root.color
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      startX: 0
      startY: root.h

      // Up along left border
      PathLine { x: 0; y: 0 }

      // Smooth inner fillet from (0, 0) to (w, r)
      PathCubic {
        x: root.w
        y: root.r
        control1X: 0
        control1Y: root.r * root.k
        control2X: root.r * (1.0 - root.k)
        control2Y: root.r
      }

      // Down to bottom border
      PathLine { x: root.w; y: root.h }
      // Back to start (0, h)
      PathLine { x: 0; y: root.h }
    }
  }

  // =========================================================================
  // 4. BOTTOM-RIGHT CORNER (Other side ending)
  // =========================================================================
  Shape {
    id: brShape
    anchors.fill: parent
    visible: root.corner === "bottomRight"
    preferredRendererType: Shape.CurveRenderer
    asynchronous: false

    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillColor: root.color
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      startX: root.w
      startY: root.h

      // Up along right border
      PathLine { x: root.w; y: 0 }

      // Smooth inner fillet from (w, 0) to (0, r)
      PathCubic {
        x: 0
        y: root.r
        control1X: root.w
        control1Y: root.r * root.k
        control2X: root.r * root.k
        control2Y: root.r
      }

      // Down to bottom border
      PathLine { x: 0; y: root.h }
      // Back to start (w, h)
      PathLine { x: root.w; y: root.h }
    }
  }
}
