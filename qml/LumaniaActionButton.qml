import QtQuick

Rectangle {
  id: root
  property string label: ""
  property bool primary: false
  property color accent: "#ba5f58"
  property color foreground: "#ffffff"
  property string fontFamily: "Adwaita Sans, Inter, sans-serif"
  property bool busy: false
  signal clicked()

  height: 28
  width: actionText.implicitWidth + 20
  radius: 8
  color: primary ? accent : Qt.rgba(1, 1, 1, 0.08)
  opacity: busy ? 0.55 : 1

  Text {
    id: actionText
    anchors.centerIn: parent
    text: root.label
    color: root.primary ? "#111111" : root.foreground
    font.family: root.fontFamily
    font.pixelSize: 10
    font.weight: Font.Medium
  }

  MouseArea {
    anchors.fill: parent
    enabled: !root.busy
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }
}
