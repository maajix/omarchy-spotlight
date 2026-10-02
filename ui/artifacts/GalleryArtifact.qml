import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.Commons
import "../components"

ArtifactCard {
  id: gallery
  glyph: "󰋩"
  subtitle: artifact.note
  property var actions: ({})
  property bool actionBusy: false
  signal imageActionRequested(string identity, string action)
  GridLayout {
    Layout.fillWidth: true
    columns: width < 500 ? 1 : 2
    columnSpacing: 14
    rowSpacing: 14
    Repeater {
      model: gallery.artifact.images
      delegate: Rectangle {
        id: tile
        required property var modelData
        readonly property bool ready: modelData.id !== "" && picture.status === Image.Ready
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        implicitHeight: details.implicitHeight + 28
        radius: 16
        color: "#12ffffff"
        border.color: "#20ffffff"
        ColumnLayout {
          id: details
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
          spacing: 10
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.round(width * 0.75)
            radius: 12
            color: "#152437"
            clip: true
            Image {
              id: picture
              objectName: "gallery-preview"
              anchors.fill: parent
              // Only the broker's sanitized local JPEG reaches Qt's image decoder.
              source: tile.modelData.previewUrl || ""
              sourceSize { width: 1280; height: 720 }
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              visible: false
            }
            Rectangle {
              id: imageMask
              anchors.fill: parent
              radius: 12
              layer.enabled: true
              visible: false
            }
            MultiEffect {
              anchors.fill: parent
              source: picture
              maskEnabled: true
              maskSource: imageMask
              visible: picture.status === Image.Ready
            }
            ArtifactText {
              anchors { fill: parent; margins: 16 }
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              visible: picture.status !== Image.Ready
              text: tile.modelData.error || (picture.status === Image.Loading ? "Loading preview…" : "Preview unavailable")
              color: gallery.mutedText
            }
          }
          ArtifactText { Layout.fillWidth: true; text: tile.modelData.title; font.weight: Font.DemiBold; font.pixelSize: Style.font.title }
          ArtifactText { Layout.fillWidth: true; text: tile.modelData.description; color: gallery.secondaryText }
          ArtifactText { Layout.fillWidth: true; text: tile.modelData.credit; color: gallery.mutedText; font.pixelSize: Style.font.caption + 1 }
          RowLayout {
            spacing: 8
            Pill {
              chrome: gallery.actionChrome
              text: "Save"
              enabled: tile.ready && !gallery.actionBusy
              opacity: enabled ? 1 : 0.45
              Accessible.role: Accessible.Button
              Accessible.name: "Save " + tile.modelData.title
              onClicked: gallery.imageActionRequested(tile.modelData.id, "save")
            }
            Pill {
              chrome: gallery.actionChrome
              text: "Apply"
              enabled: tile.ready && !gallery.actionBusy
              opacity: enabled ? 1 : 0.45
              Accessible.role: Accessible.Button
              Accessible.name: "Apply " + tile.modelData.title + " as wallpaper"
              onClicked: gallery.imageActionRequested(tile.modelData.id, "apply")
            }
            TextButton {
              chrome: gallery.actionChrome
              text: "Source ↗"
              font.family: "sans-serif"
              onClicked: gallery.openRequested(tile.modelData.sourceUrl)
            }
          }
          ArtifactText {
            Layout.fillWidth: true
            text: gallery.actions[tile.modelData.id] || ""
            visible: text !== ""
            color: gallery.secondaryText
            font.pixelSize: Style.font.caption + 1
          }
        }
      }
    }
  }
  ArtifactText {
    Layout.fillWidth: true
    text: "Save keeps a copy in Pictures/Spotlight. Apply saves it and changes your wallpaper. Check the source license before reuse."
    color: gallery.mutedText
    font.pixelSize: Style.font.caption + 1
  }
}
