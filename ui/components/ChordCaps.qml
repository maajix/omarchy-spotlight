import QtQuick
import QtQuick.Layouts
import qs.Commons

// "CTRL + SPACE" as keycaps with plus signs between them.
RowLayout {
  id: caps

  property SpotlightPalette chrome: SpotlightPalette {}
  property string chord: ""
  property bool small: false
  property string emptyText: "No shortcut yet"

  spacing: Style.space(caps.small ? 4 : 8)

  Repeater {
    model: caps.chord === "" ? [caps.emptyText] : caps.chord.split(" + ")

    RowLayout {
      required property string modelData
      required property int index
      spacing: Style.space(caps.small ? 4 : 8)

      Text {
        visible: index > 0
        text: "+"
        color: caps.chrome.dim
        font.family: caps.chrome.fontFamily
        font.pixelSize: caps.small ? Style.font.caption : Style.font.title
      }

      Keycap {
        chrome: caps.chrome
        text: modelData
        small: caps.small
        dimmed: caps.chord === ""
      }
    }
  }
}
