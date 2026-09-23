import QtQuick
import qs.Commons

// Filled accent button; the one call to action on a surface.
Rectangle {
  id: pb

  property SpotlightPalette chrome: SpotlightPalette {}
  property string text: ""
  property string glyph: "󰁔"
  signal clicked()

  implicitWidth: pbLabel.implicitWidth + Style.space(36)
  implicitHeight: Style.space(36)
  radius: pb.chrome.rowRadius
  color: pbMouse.containsMouse && pb.enabled ? Qt.lighter(pb.chrome.accent, 1.12) : pb.chrome.accent
  opacity: pb.enabled ? 1 : 0.4

  Behavior on color { ColorAnimation { duration: 100 } }

  Text {
    id: pbLabel
    anchors.centerIn: parent
    text: pb.glyph === "" ? pb.text : pb.text + "  " + pb.glyph
    color: pb.chrome.onAccent
    font.family: pb.chrome.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  MouseArea {
    id: pbMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: pb.clicked()
  }
}
