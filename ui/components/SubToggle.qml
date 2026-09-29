import QtQuick
import QtQuick.Layouts
import qs.Commons

// Borderless toggle that lives inside a SettingRow, under its title.
Item {
  id: sub

  property SpotlightPalette chrome: SpotlightPalette {}
  property string text: ""
  property string description: ""
  property bool checked: false
  signal toggled()

  Layout.fillWidth: true
  implicitHeight: subRow.implicitHeight
  activeFocusOnTab: enabled
  opacity: enabled ? 1 : 0.45
  Keys.onSpacePressed: sub.toggled()

  RowLayout {
    id: subRow
    anchors { left: parent.left; right: parent.right }
    spacing: Style.space(10)

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(2)

      Text {
        Layout.fillWidth: true
        text: sub.text
        color: sub.chrome.foreground
        font.family: sub.chrome.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        visible: sub.description !== ""
        text: sub.description
        color: sub.chrome.dim
        font.family: sub.chrome.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    PillSwitch {
      checked: sub.checked
      accent: sub.chrome.accent
      foreground: sub.chrome.foreground
      knobOn: sub.chrome.onAccent
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: sub.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: sub.toggled()
  }
}
