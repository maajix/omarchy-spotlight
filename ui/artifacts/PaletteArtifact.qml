import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

ArtifactCard {
  id: paletteCard
  subtitle: "Select a swatch to copy its HEX value"
  glyph: "󰏘"

  function ink(color) {
    var hex = String(color)
    var luminance = parseInt(hex.slice(1, 3), 16) * 0.21
      + parseInt(hex.slice(3, 5), 16) * 0.72 + parseInt(hex.slice(5, 7), 16) * 0.07
    return luminance > 140 ? "#111722" : "#ffffff"
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: 10
    Repeater {
      model: paletteCard.artifact.colors
      delegate: Rectangle {
        id: swatch
        required property var modelData
        Layout.fillWidth: true
        implicitHeight: 138
        radius: 14
        color: modelData.hex
        border.color: activeFocus || hover.containsMouse ? "#ffffff" : "#30ffffff"
        border.width: activeFocus || hover.containsMouse ? 2 : 1
        activeFocusOnTab: true
        Keys.onReturnPressed: paletteCard.copyRequested(modelData.hex)
        Keys.onSpacePressed: paletteCard.copyRequested(modelData.hex)
        Accessible.role: Accessible.Button
        Accessible.name: "Copy " + modelData.label + " " + modelData.hex

        ColumnLayout {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
          spacing: 4
          ArtifactText {
            Layout.fillWidth: true
            text: swatch.modelData.label
            color: paletteCard.ink(swatch.modelData.hex)
            font.bold: true
            font.pixelSize: Style.font.caption + 1
          }
          ArtifactText {
            Layout.fillWidth: true
            text: swatch.modelData.hex
            color: paletteCard.ink(swatch.modelData.hex)
            font.pixelSize: Style.font.caption
          }
        }
        MouseArea {
          id: hover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { swatch.forceActiveFocus(); paletteCard.copyRequested(swatch.modelData.hex) }
        }
      }
    }
  }

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: 78
    radius: 14
    color: paletteCard.artifact.colors[0].hex
    border.color: "#30ffffff"
    RowLayout {
      anchors.fill: parent
      anchors.margins: 14
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        ArtifactText { text: "A little preview"; color: paletteCard.ink(paletteCard.artifact.colors[0].hex); font.bold: true }
        ArtifactText { text: "Background · accent · action"; color: paletteCard.ink(paletteCard.artifact.colors[0].hex); font.pixelSize: Style.font.caption }
      }
      Rectangle {
        implicitWidth: 100
        implicitHeight: 36
        radius: 10
        color: paletteCard.artifact.colors[1].hex
        ArtifactText { anchors.centerIn: parent; text: "Button"; color: paletteCard.ink(paletteCard.artifact.colors[1].hex); font.bold: true }
      }
    }
  }

  Pill {
    chrome: paletteCard.actionChrome
    text: "Copy palette"
    onClicked: paletteCard.copyRequested(paletteCard.artifact.colors.map(function(color) { return color.label + ": " + color.hex }).join("\n"))
  }
}
