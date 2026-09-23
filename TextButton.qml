import QtQuick
import qs.Commons

// Plain text that behaves like a link: the quiet action beside a primary one.
Text {
  id: tb

  property SpotlightPalette chrome: SpotlightPalette {}
  signal clicked()

  color: tbMouse.containsMouse ? tb.chrome.foreground : tb.chrome.dim
  font.family: tb.chrome.fontFamily
  font.pixelSize: Style.font.body

  MouseArea {
    id: tbMouse
    anchors.fill: parent
    anchors.margins: -Style.space(6)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: tb.clicked()
  }
}
