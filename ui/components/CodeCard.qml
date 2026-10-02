import QtQuick
import QtQuick.Layouts
import qs.Commons

Rectangle {
  id: card
  required property SpotlightPalette chrome
  property string code: ""
  property string label: "terminal"
  signal copyRequested(string value)
  radius: Style.space(8)
  color: "#171b20"
  border.width: 1
  border.color: card.chrome.lineFocus
  implicitHeight: contents.implicitHeight + Style.space(22)

  ColumnLayout {
    id: contents
    anchors.fill: parent
    anchors.margins: Style.space(11)
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)
      Text {
        Layout.fillWidth: true
        text: "󰆍  " + card.label
        textFormat: Text.PlainText
        color: "#b5bac1"
        font.family: "monospace"
        font.pixelSize: Style.font.caption
      }
      Rectangle {
        implicitWidth: actionLabel.implicitWidth + Style.space(16)
        implicitHeight: Style.space(26)
        radius: Style.space(5)
        color: actionMouse.containsMouse || activeFocus ? "#303844" : "#222a34"
        border.width: 1
        border.color: card.chrome.lineFocus
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: "Copy command"
        Keys.onSpacePressed: card.copyRequested(card.code)
        Keys.onReturnPressed: card.copyRequested(card.code)
        Text {
          id: actionLabel
          anchors.centerIn: parent
          text: "󰆏  Copy"
          color: "#c3d7e9"
          font.family: card.chrome.fontFamily
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          id: actionMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: card.copyRequested(card.code)
        }
      }
    }

    TextEdit {
      Layout.fillWidth: true
      Layout.preferredHeight: contentHeight
      text: card.code
      textFormat: TextEdit.PlainText
      readOnly: true
      selectByMouse: true
      wrapMode: TextEdit.WrapAnywhere
      color: "#dce4e8"
      font.family: "monospace"
      font.pixelSize: Style.font.body
    }
  }
}
