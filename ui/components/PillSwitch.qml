import QtQuick
import qs.Commons

// Pill switch: accent track when on, dim track when off. Presentation only,
// the surrounding row owns the click. Shared by the setup tour's settings rows
// and by the toggle rows in the result list, so the colours come in from the
// caller rather than from the theme directly: the tour paints on the card and
// the list paints on the menu palette, and those are not the same tokens.
Item {
  id: sw

  property bool checked: false
  property color accent: Color.accent
  property color foreground: Color.foreground
  property color knobOn: Color.background

  implicitWidth: Style.space(40)
  implicitHeight: Style.space(22)

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: sw.checked ? sw.accent : Util.alpha(sw.foreground, 0.18)

    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
      width: parent.height - Style.space(6)
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      x: sw.checked ? parent.width - width - Style.space(3) : Style.space(3)
      color: sw.checked ? sw.knobOn : Util.alpha(sw.foreground, 0.75)

      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 120 } }
    }
  }
}
