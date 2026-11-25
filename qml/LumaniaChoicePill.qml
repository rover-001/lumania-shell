import QtQuick

Rectangle {
  id: root
  property string label: ""
  property bool selected: false
  property color accent: "#ba5f58"
  property color foreground: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.65)
  property string fontFamily: "Adwaita Sans, Inter, sans-serif"
  signal chosen()

  height: 24
  width: pillText.implicitWidth + 16
  radius: 6
  color: selected ? accent : Qt.rgba(1, 1, 1, 0.07)

  Text {
    id: pillText
    anchors.centerIn: parent
    text: root.label
    color: root.selected ? "#111111" : root.muted
    font.family: root.fontFamily
    font.pixelSize: 9
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.chosen()
  }
}
