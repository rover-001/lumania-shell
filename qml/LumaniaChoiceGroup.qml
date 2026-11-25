import QtQuick

Column {
  id: root
  property string label: ""
  property var values: []
  property var labels: []
  property string suffix: ""
  property var selectedValue
  property color accent: "#ba5f58"
  property color foreground: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.65)
  property string fontFamily: "Adwaita Sans, Inter, sans-serif"
  signal chosen(var value)

  width: parent ? parent.width : implicitWidth
  spacing: 4

  Text {
    text: root.label
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: 10
  }

  Flow {
    width: root.width
    spacing: 4

    Repeater {
      model: root.values
      delegate: Rectangle {
        required property var modelData
        required property int index
        width: optionText.implicitWidth + 14
        height: 24
        radius: 6
        color: modelData === root.selectedValue ? root.accent : Qt.rgba(1, 1, 1, 0.07)

        Text {
          id: optionText
          anchors.centerIn: parent
          text: root.labels.length > index ? root.labels[index] : String(modelData) + root.suffix
          color: modelData === root.selectedValue ? "#111111" : root.muted
          font.family: root.fontFamily
          font.pixelSize: 9
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.chosen(modelData)
        }
      }
    }
  }
}
