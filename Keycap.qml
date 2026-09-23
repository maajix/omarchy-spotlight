import QtQuick
import qs.Commons

// One key of a shortcut, drawn as a physical cap.
Rectangle {
  id: cap

  property SpotlightPalette chrome: SpotlightPalette {}
  property string text: ""
  property bool small: false
  property bool dimmed: false

  implicitWidth: Math.max(cap.small ? 0 : Style.space(52),
                          capLabel.implicitWidth + Style.space(cap.small ? 14 : 28))
  implicitHeight: cap.small ? Style.space(24) : Style.space(44)
  radius: cap.small ? Style.space(5) : cap.chrome.rowRadius
  color: cap.chrome.fillHot
  border.width: cap.chrome.hairline
  border.color: cap.chrome.lineHot

  Text {
    id: capLabel
    anchors.centerIn: parent
    text: cap.text
    color: cap.dimmed ? cap.chrome.dim : cap.chrome.foreground
    font.family: cap.chrome.fontFamily
    font.pixelSize: cap.small ? Style.font.caption : Style.font.title
    font.bold: !cap.small
  }
}
