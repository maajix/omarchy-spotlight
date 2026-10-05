import QtQuick
import qs.Commons

// Rounded accent tile holding one glyph. The badge in front of a feature or a
// settings row.
Rectangle {
  id: tile

  property SpotlightPalette chrome: SpotlightPalette {}
  property string glyph: ""
  property real size: Style.space(40)
  property real glyphSize: Style.font.iconLarge

  implicitWidth: tile.size
  implicitHeight: tile.size
  radius: tile.chrome.rowRadius
  color: tile.chrome.accentFill

  Text {
    anchors.centerIn: parent
    text: tile.glyph
    color: tile.chrome.accent
    font.family: tile.chrome.fontFamily
    font.pixelSize: tile.glyphSize
  }
}
