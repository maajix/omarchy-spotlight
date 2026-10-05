import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

ArtifactCard {
  id: placesCard
  glyph: "󰍎"
  subtitle: artifact.note
  retrievedAt: artifact.retrievedAt
  Repeater {
    model: placesCard.artifact.places
    delegate: Rectangle {
      id: venue
      required property var modelData
      Layout.fillWidth: true
      implicitHeight: details.implicitHeight + 32
      radius: 16
      color: "#10ffffff"
      border.color: "#1bffffff"
      ColumnLayout {
        id: details
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 12
        RowLayout {
          Layout.fillWidth: true
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 5
            ArtifactText {
              Layout.fillWidth: true
              text: venue.modelData.name
              font.pixelSize: Style.font.title + 2
              font.weight: Font.DemiBold
            }
            ArtifactText {
              Layout.fillWidth: true
              text: venue.modelData.category
              color: placesCard.mutedText
            }
          }
          Rectangle {
            visible: venue.modelData.rating !== null
            Layout.alignment: Qt.AlignTop
            implicitWidth: rating.implicitWidth + 20
            implicitHeight: 30
            radius: 15
            color: "#20ffcd76"
            ArtifactText {
              id: rating
              anchors.centerIn: parent
              text: venue.modelData.rating !== null ? "★ " + venue.modelData.rating.toFixed(1) + " / 5" : ""
              color: "#ffdb9e"
              font.weight: Font.DemiBold
            }
          }
        }
        ArtifactText { Layout.fillWidth: true; text: venue.modelData.summary; color: placesCard.secondaryText }
        RowLayout {
          Layout.fillWidth: true
          IconTile { chrome: placesCard.actionChrome; glyph: "󰍎"; size: 24; color: "transparent"; Layout.alignment: Qt.AlignTop }
          ArtifactText { Layout.fillWidth: true; text: venue.modelData.address; color: placesCard.secondaryText }
        }
        RowLayout {
          Layout.fillWidth: true
          IconTile { chrome: placesCard.actionChrome; glyph: "󰥔"; size: 24; color: "transparent"; Layout.alignment: Qt.AlignTop }
          ArtifactText { Layout.fillWidth: true; text: venue.modelData.hours; color: placesCard.secondaryText }
        }
        ArtifactText {
          Layout.fillWidth: true
          text: venue.modelData.rating !== null ? "Rating · " + venue.modelData.ratingSource : "Rating not verified"
          color: placesCard.mutedText
          font.pixelSize: Style.font.caption + 1
        }
        RowLayout {
          spacing: 8
          Pill {
            chrome: placesCard.actionChrome
            text: "View map ↗"
            Accessible.role: Accessible.Button
            Accessible.name: "View " + venue.modelData.name + " on OpenStreetMap"
            onClicked: placesCard.openRequested(venue.modelData.mapUrl)
          }
          Pill {
            chrome: placesCard.actionChrome
            text: "Copy address"
            Accessible.role: Accessible.Button
            Accessible.name: text
            onClicked: placesCard.copyRequested(venue.modelData.address)
          }
          Pill {
            visible: venue.modelData.sourceUrl !== ""
            chrome: placesCard.actionChrome
            text: "Source ↗"
            Accessible.role: Accessible.Button
            Accessible.name: "Open source for " + venue.modelData.name
            onClicked: placesCard.openRequested(venue.modelData.sourceUrl)
          }
        }
      }
    }
  }
}
