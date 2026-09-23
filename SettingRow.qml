import QtQuick
import QtQuick.Layouts
import qs.Commons

// Bordered settings row: icon tile, title, description, switch. The whole row
// toggles; children declared inside land below the title as extras.
Rectangle {
  id: row

  property SpotlightPalette chrome: SpotlightPalette {}
  property string glyph: ""
  property string title: ""
  property string description: ""
  property bool checked: false
  // false: no switch, the row is a label for whatever sits in `trailing`.
  property bool switchable: true
  default property alias extra: extraCol.data
  property alias trailing: trailingSlot.data
  signal toggled()

  readonly property bool hot: row.switchable && rowMouse.containsMouse

  Layout.fillWidth: true
  implicitHeight: body.implicitHeight + Style.space(24)
  radius: row.chrome.rowRadius
  activeFocusOnTab: row.switchable
  color: row.activeFocus || row.hot ? row.chrome.fillHot : row.chrome.fill
  border.width: row.chrome.hairline
  border.color: row.activeFocus ? row.chrome.lineFocus
    : row.hot ? row.chrome.lineHot : row.chrome.line
  Keys.onSpacePressed: row.toggled()
  Keys.onReturnPressed: row.toggled()
  Keys.onEnterPressed: row.toggled()

  Behavior on color { ColorAnimation { duration: 100 } }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    enabled: row.switchable
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.toggled()
  }

  ColumnLayout {
    id: body
    anchors { left: parent.left; right: parent.right; top: parent.top }
    anchors.margins: Style.space(12)
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(12)

      IconTile {
        chrome: row.chrome
        glyph: row.glyph
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          Layout.fillWidth: true
          text: row.title
          color: row.chrome.foreground
          font.family: row.chrome.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: row.description
          color: row.chrome.dim
          font.family: row.chrome.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      PillSwitch {
        visible: row.switchable
        checked: row.checked
        accent: row.chrome.accent
        foreground: row.chrome.foreground
        knobOn: row.chrome.onAccent
      }

      Item {
        id: trailingSlot
        visible: children.length > 0
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
      }
    }

    ColumnLayout {
      id: extraCol
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(52)
      spacing: Style.space(8)
      visible: extraCol.children.length > 0
    }
  }
}
