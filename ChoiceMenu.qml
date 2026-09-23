import QtQuick
import QtQuick.Controls
import qs.Commons

// Single-select menu in Spotlight's own chrome. Enter/Space/Down open,
// Up/Down or j/k move, Enter picks, Esc closes without leaving the surface.
Rectangle {
  id: menu

  property SpotlightPalette chrome: SpotlightPalette {}
  property string value: ""
  property var options: []
  signal changed(string value)

  readonly property bool hot: menuMouse.containsMouse

  implicitWidth: Style.space(200)
  implicitHeight: Style.space(30)
  radius: menu.chrome.rowRadius
  activeFocusOnTab: true
  color: menu.activeFocus || menu.hot ? menu.chrome.fillHot : menu.chrome.fill
  border.width: menu.chrome.hairline
  border.color: menu.activeFocus ? menu.chrome.lineFocus
    : menu.hot ? menu.chrome.lineHot : menu.chrome.line

  function currentLabel() {
    for (var i = 0; i < menu.options.length; i++)
      if (menu.options[i].value === menu.value) return menu.options[i].label
    return menu.value
  }

  function indexOfValue() {
    for (var i = 0; i < menu.options.length; i++)
      if (menu.options[i].value === menu.value) return i
    return 0
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
      popup.opened ? popup.close() : popup.open()
      event.accepted = true
    }
  }

  Text {
    anchors { left: parent.left; right: chevron.left; verticalCenter: parent.verticalCenter }
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(8)
    text: menu.currentLabel()
    color: menu.chrome.foreground
    font.family: menu.chrome.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  Text {
    id: chevron
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    anchors.rightMargin: Style.space(10)
    text: "󰅀"
    color: menu.chrome.dim
    font.family: menu.chrome.fontFamily
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: menuMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      menu.forceActiveFocus()
      popup.opened ? popup.close() : popup.open()
    }
  }

  Popup {
    id: popup
    y: menu.height + Style.space(4)
    width: menu.width
    padding: Style.space(4)
    implicitHeight: Math.min(list.contentHeight + padding * 2, Style.space(240))
    focus: true

    background: Rectangle {
      radius: menu.chrome.rowRadius
      color: Color.popups.background
      border.width: menu.chrome.hairline
      border.color: menu.chrome.lineHot
    }

    onOpened: {
      list.currentIndex = menu.indexOfValue()
      list.positionViewAtIndex(list.currentIndex, ListView.Contain)
      list.forceActiveFocus()
    }

    contentItem: ListView {
      id: list
      clip: true
      spacing: Style.space(2)
      boundsBehavior: Flickable.StopAtBounds
      model: menu.options

      // Only reports the pick. Assigning menu.value here would overwrite the
      // owner's binding, and the menu would stop following it from then on.
      function pick() {
        var o = menu.options[list.currentIndex]
        if (!o) return
        menu.changed(o.value)
        popup.close()
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) popup.close()
        else if (event.key === Qt.Key_Down || event.text === "j") list.currentIndex = Math.min(menu.options.length - 1, list.currentIndex + 1)
        else if (event.key === Qt.Key_Up || event.text === "k") list.currentIndex = Math.max(0, list.currentIndex - 1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) list.pick()
        else return
        event.accepted = true
      }

      delegate: Rectangle {
        required property var modelData
        required property int index
        width: list.width
        height: Style.space(28)
        radius: Style.space(5)
        color: index === list.currentIndex ? menu.chrome.fillHot : "transparent"

        Text {
          anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          text: modelData.label
          color: modelData.value === menu.value ? menu.chrome.accent : menu.chrome.foreground
          font.family: menu.chrome.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: list.currentIndex = parent.index
          onClicked: list.pick()
        }
      }
    }
  }
}
