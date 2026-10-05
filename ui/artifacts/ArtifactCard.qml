import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

Rectangle {
  id: card
  required property var artifact
  default property alias contents: body.data
  property string subtitle: ""
  property string sourceUrl: ""
  property string retrievedAt: ""
  property string glyph: ""
  readonly property color secondaryText: "#c4d5e8"
  readonly property color mutedText: "#a5bdd7"
  readonly property SpotlightPalette actionChrome: SpotlightPalette {
    foreground: "#e8f3ff"
    accent: "#9bd2ff"
    fontFamily: "sans-serif"
    rowRadius: 16
  }
  signal openRequested(string url)
  signal copyRequested(string value)

  implicitHeight: layout.implicitHeight + 40
  radius: 20
  clip: true
  gradient: Gradient {
    GradientStop { position: 0; color: "#304661" }
    GradientStop { position: 0.55; color: "#253951" }
    GradientStop { position: 1; color: "#19283d" }
  }
  border.color: "#526883"
  border.width: 1

  data: [Rectangle {
    anchors { right: parent.right; top: parent.top; rightMargin: -80; topMargin: -130 }
    width: 320
    height: 320
    radius: 160
    color: "#0a9acbff"
  }, ColumnLayout {
    id: layout
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
    spacing: 20

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 5
      RowLayout {
        Layout.fillWidth: true
        spacing: 10
        IconTile {
          visible: card.glyph !== ""
          chrome: card.actionChrome
          glyph: card.glyph
          size: 32
          radius: 10
          color: "#14ffffff"
        }
        ArtifactText {
          Layout.fillWidth: true
          text: card.artifact.title || ""
          font.pixelSize: Style.font.title + 3
          font.weight: Font.DemiBold
        }
      }
      ArtifactText {
        Layout.fillWidth: true
        visible: card.subtitle !== ""
        text: card.subtitle
        color: card.secondaryText
        font.pixelSize: Style.font.body
      }
    }

    ColumnLayout {
      id: body
      Layout.fillWidth: true
      spacing: 16
    }

    RowLayout {
      Layout.fillWidth: true
      visible: card.sourceUrl !== "" || card.retrievedAt !== ""
      ArtifactText {
        Layout.fillWidth: true
        text: card.retrievedAt ? "Checked " + card.retrievedAt.slice(0, 16).replace("T", " ") + " UTC" : ""
        font.pixelSize: Style.font.caption
        color: card.mutedText
      }
      TextButton {
        visible: card.sourceUrl !== ""
        chrome: card.actionChrome
        text: card.sourceUrl.split("/")[2] + " ↗"
        color: "#a8d6ff"
        font.family: "sans-serif"
        onClicked: card.openRequested(card.sourceUrl)
      }
    }
  }]
}
