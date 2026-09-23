import QtQuick
import qs.Commons

// Outlined button with an optional caption beside its label. Selected state
// swaps the outline for the accent.
Rectangle {
  id: pill

  property SpotlightPalette chrome: SpotlightPalette {}
  property string text: ""
  property string hint: ""
  property bool selected: false
  signal clicked()

  readonly property bool hot: pillMouse.containsMouse

  implicitWidth: pillRow.implicitWidth + Style.space(24)
  implicitHeight: Style.space(32)
  radius: pill.chrome.rowRadius
  activeFocusOnTab: true
  Keys.onSpacePressed: pill.clicked()
  Keys.onReturnPressed: pill.clicked()
  Keys.onEnterPressed: pill.clicked()
  color: pill.selected ? pill.chrome.accentFill : pill.activeFocus || pill.hot ? pill.chrome.fillHot : pill.chrome.fill
  border.width: pill.chrome.hairline
  border.color: pill.activeFocus || pill.selected ? pill.chrome.lineFocus : pill.hot ? pill.chrome.lineHot : pill.chrome.line

  Behavior on color { ColorAnimation { duration: 100 } }

  Row {
    id: pillRow
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: pillLabel
      text: pill.text
      color: pill.selected ? pill.chrome.accent : pill.chrome.foreground
      font.family: pill.chrome.fontFamily
      font.pixelSize: Style.font.body
      font.bold: pill.selected
    }

    Text {
      visible: pill.hint !== ""
      anchors.baseline: pillLabel.baseline
      text: pill.hint
      color: pill.chrome.dim
      font.family: pill.chrome.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: pillMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: { pill.forceActiveFocus(); pill.clicked() }
  }
}
