import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

ArtifactCard {
  id: timelineCard
  glyph: "󰃭"
  subtitle: artifact.note
  retrievedAt: artifact.retrievedAt

  ColumnLayout {
    Layout.fillWidth: true
    spacing: 0
    Repeater {
      model: timelineCard.artifact.entries
      delegate: Item {
        id: event
        required property var modelData
        required property int index
        Layout.fillWidth: true
        implicitHeight: eventContent.implicitHeight + 28
        readonly property color tint: modelData.status === "done" ? "#9ce9d1"
          : modelData.status === "current" ? "#ffd09b" : "#9bd2ff"

        Rectangle {
          x: 7
          y: 17
          width: 2
          height: parent.height - 4
          visible: event.index < timelineCard.artifact.entries.length - 1
          color: "#30a5bdd7"
        }
        Rectangle {
          x: 0
          y: 9
          width: 16
          height: 16
          radius: 8
          color: event.modelData.status === "done" ? event.tint : "#304661"
          border.color: event.tint
          border.width: 2
          ArtifactText {
            anchors.centerIn: parent
            visible: event.modelData.status === "done"
            text: "✓"
            color: "#19283d"
            font.pixelSize: 10
          }
        }

        Rectangle {
          anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 32 }
          height: eventContent.implicitHeight + 20
          radius: 14
          color: event.modelData.status === "current" ? "#16ffd09b" : "#08ffffff"
          border.color: "#18ffffff"
        }
        ColumnLayout {
          id: eventContent
          anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 46; rightMargin: 14; topMargin: 10 }
          spacing: 5
          RowLayout {
            Layout.fillWidth: true
            ArtifactText {
              Layout.fillWidth: true
              text: event.modelData.when
              color: event.tint
              font.pixelSize: Style.font.caption + 1
              font.weight: Font.Medium
            }
            ArtifactText {
              visible: event.modelData.status !== "planned"
              text: event.modelData.status === "done" ? "Completed" : "Current"
              color: event.tint
              font.pixelSize: Style.font.caption
            }
          }
          ArtifactText {
            Layout.fillWidth: true
            text: event.modelData.title
            font.pixelSize: Style.font.subtitle + 2
            font.weight: Font.DemiBold
          }
          ArtifactText {
            Layout.fillWidth: true
            text: event.modelData.description
            color: timelineCard.secondaryText
          }
          TextButton {
            visible: event.modelData.sourceUrl !== ""
            chrome: timelineCard.actionChrome
            text: "Source ↗"
            onClicked: timelineCard.openRequested(event.modelData.sourceUrl)
          }
        }
      }
    }
  }

  Pill {
    chrome: timelineCard.actionChrome
    text: "Copy timeline"
    onClicked: timelineCard.copyRequested(timelineCard.artifact.entries.map(function(entry) {
      return entry.when + " · " + entry.title + "\n" + entry.description
        + (entry.sourceUrl ? "\n" + entry.sourceUrl : "")
    }).join("\n\n"))
  }
}
