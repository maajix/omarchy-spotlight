import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

ArtifactCard {
  id: diffCard
  glyph: "󰕚"
  subtitle: artifact.note
  ArtifactText {
    Layout.fillWidth: true
    text: "PREVIEW ONLY · NO FILES CHANGED"
    color: diffCard.mutedText
    font.pixelSize: Style.font.caption
    font.weight: Font.DemiBold
  }
  Repeater {
    model: diffCard.artifact.files
    delegate: ColumnLayout {
      id: file
      required property var modelData
      Layout.fillWidth: true
      spacing: 12
      RowLayout {
        Layout.fillWidth: true
        ArtifactText {
          Layout.fillWidth: true
          text: file.modelData.path
          font.family: "monospace"
          font.weight: Font.DemiBold
        }
        ArtifactText { text: "+" + file.modelData.added; color: "#9be1ba"; font.weight: Font.DemiBold }
        ArtifactText { text: "−" + file.modelData.removed; color: "#ffb4ac"; font.weight: Font.DemiBold }
      }
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: lines.implicitHeight + 16
        radius: 12
        color: "#172332"
        border.color: "#41617e"
        clip: true
        ColumnLayout {
          id: lines
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
          spacing: 0
          ArtifactText {
            Layout.fillWidth: true
            visible: file.modelData.rows.length === 0
            text: "No changes"
            color: diffCard.mutedText
          }
          Repeater {
            model: file.modelData.rows
            delegate: Rectangle {
              id: line
              required property var modelData
              Layout.fillWidth: true
              implicitHeight: Math.max(code.implicitHeight, 18) + 8
              color: modelData.kind === "added" ? "#203dd988" : modelData.kind === "removed" ? "#25e3776c"
                : modelData.kind === "hunk" ? "#1c82b8ed" : "transparent"
              RowLayout {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
                spacing: 8
                ArtifactText {
                  Layout.preferredWidth: 30
                  text: line.modelData.old
                  color: "#8aa4bb"
                  horizontalAlignment: Text.AlignRight
                  font.family: "monospace"
                  font.pixelSize: Style.font.caption + 1
                }
                ArtifactText {
                  Layout.preferredWidth: 30
                  text: line.modelData.new
                  color: "#8aa4bb"
                  horizontalAlignment: Text.AlignRight
                  font.family: "monospace"
                  font.pixelSize: Style.font.caption + 1
                }
                ArtifactText {
                  Layout.preferredWidth: 12
                  text: line.modelData.kind === "added" ? "+" : line.modelData.kind === "removed" ? "−" : ""
                  color: line.modelData.kind === "added" ? "#9be1ba" : "#ffb4ac"
                  font.family: "monospace"
                }
                ArtifactText {
                  id: code
                  Layout.fillWidth: true
                  text: line.modelData.text
                  font.family: "monospace"
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WrapAnywhere
                  color: line.modelData.kind === "added" ? "#c7f4d9" : line.modelData.kind === "removed" ? "#ffccc6"
                    : line.modelData.kind === "hunk" ? "#a8d6ff" : "#dce5ed"
                }
              }
            }
          }
        }
      }
      RowLayout {
        spacing: 8
        Pill {
          chrome: diffCard.actionChrome
          text: "Copy proposed config"
          Accessible.role: Accessible.Button
          Accessible.name: "Copy proposed configuration for " + file.modelData.path
          onClicked: diffCard.copyRequested(file.modelData.after)
        }
        Pill {
          chrome: diffCard.actionChrome
          text: "Copy diff"
          enabled: file.modelData.diff !== ""
          opacity: enabled ? 1 : .4
          Accessible.role: Accessible.Button
          Accessible.name: "Copy diff for " + file.modelData.path
          onClicked: diffCard.copyRequested(file.modelData.diff)
        }
      }
    }
  }
}
