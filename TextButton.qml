import QtQuick
import qs.Commons

// Plain text that behaves like a link: the quiet action beside a primary one.
Text {
  id: tb

  property SpotlightPalette chrome: SpotlightPalette {}
  signal clicked()

  activeFocusOnTab: true
  Keys.onSpacePressed: tb.clicked()
  Keys.onReturnPressed: tb.clicked()
  Keys.onEnterPressed: tb.clicked()
  color: tb.activeFocus || tbMouse.containsMouse ? tb.chrome.foreground : tb.chrome.dim
  font.family: tb.chrome.fontFamily
  font.pixelSize: Style.font.body
  font.underline: tb.activeFocus

  MouseArea {
    id: tbMouse
    anchors.fill: parent
    anchors.margins: -Style.space(6)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: { tb.forceActiveFocus(); tb.clicked() }
  }
}
