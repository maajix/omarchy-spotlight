import QtQuick
import qs.Commons

// Bounded integer control: minus, value, plus. A slider would need a drag to
// land on an exact number and every one of these settings is a small count
// the user picks deliberately, so the two buttons are the whole interaction.
// Left/Right work while it holds focus.
Rectangle {
  id: stepper

  property SpotlightPalette chrome: SpotlightPalette {}
  property int value: 0
  property int from: 0
  property int to: 10
  property int step: 1
  signal changed(int value)

  readonly property bool canDecrease: stepper.value > stepper.from
  readonly property bool canIncrease: stepper.value < stepper.to

  // Only reports; `value` stays bound to whatever the owner holds, so writing
  // it here would break that binding and freeze the display on the first step.
  function apply(next) {
    var clamped = Math.max(stepper.from, Math.min(stepper.to, next))
    if (clamped === stepper.value) return
    stepper.changed(clamped)
  }

  implicitWidth: Style.space(120)
  implicitHeight: Style.space(30)
  radius: stepper.chrome.rowRadius
  activeFocusOnTab: true
  color: stepper.activeFocus ? stepper.chrome.fillHot : stepper.chrome.fill
  border.width: stepper.chrome.hairline
  border.color: stepper.activeFocus ? stepper.chrome.lineFocus : stepper.chrome.line

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left) stepper.apply(stepper.value - stepper.step)
    else if (event.key === Qt.Key_Right) stepper.apply(stepper.value + stepper.step)
    else return
    event.accepted = true
  }

  component Arrow: Item {
    id: arrow
    property string glyph: ""
    property bool active: true
    signal clicked()
    width: Style.space(32)
    height: parent ? parent.height : Style.space(30)
    opacity: arrow.active ? 1 : 0.3

    Text {
      anchors.centerIn: parent
      text: arrow.glyph
      color: arrowMouse.containsMouse && arrow.active ? stepper.chrome.accent : stepper.chrome.foreground
      font.family: stepper.chrome.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: arrowMouse
      anchors.fill: parent
      enabled: arrow.active
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: arrow.clicked()
    }
  }

  Arrow {
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    glyph: "−"
    active: stepper.canDecrease
    onClicked: stepper.apply(stepper.value - stepper.step)
  }

  Text {
    anchors.centerIn: parent
    text: String(stepper.value)
    color: stepper.chrome.foreground
    font.family: stepper.chrome.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Arrow {
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    glyph: "+"
    active: stepper.canIncrease
    onClicked: stepper.apply(stepper.value + stepper.step)
  }
}
