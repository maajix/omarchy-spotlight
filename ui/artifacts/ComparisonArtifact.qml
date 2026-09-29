import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"
import "../../lib/Comparison.js" as Comparison

ArtifactCard {
  id: comparisonCard
  subtitle: artifact.note
  retrievedAt: artifact.retrievedAt
  glyph: "󰦨"

  Repeater {
    model: Comparison.groups(comparisonCard.artifact.options)
    delegate: Item {
      id: group
      required property var modelData
      required property int index
      Layout.fillWidth: true
      implicitHeight: details.implicitHeight + 36
      readonly property real columnWidth: (width - (modelData.length - 1) * 12) / modelData.length

      Repeater {
        model: group.modelData
        delegate: Rectangle {
          required property var modelData
          required property int index
          x: index * (group.columnWidth + 12)
          width: group.columnWidth
          height: group.height
          radius: 16
          color: modelData.recommended ? "#244d94dd" : "#08ffffff"
          border.color: modelData.recommended ? "#7097cfff" : "#20ffffff"
        }
      }

      GridLayout {
        id: details
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 18 }
        columns: group.modelData.length
        columnSpacing: 12
        rowSpacing: 12

        Repeater {
          model: Comparison.cells(group.modelData)
          delegate: ColumnLayout {
            id: cell
            required property var modelData
            required property int index
            objectName: "comparison-cell-" + group.index + "-" + Layout.row + "-" + Layout.column
            Layout.row: Math.floor(index / group.modelData.length)
            Layout.column: index % group.modelData.length
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: 4

            Rectangle {
              Layout.leftMargin: 16
              visible: cell.modelData.kind === "status"
              implicitWidth: statusLabel.implicitWidth + 18
              implicitHeight: 24
              radius: 12
              color: cell.modelData.text === "SUGGESTED PICK" ? "#3078baff" : "#12ffffff"
              ArtifactText {
                id: statusLabel
                anchors.centerIn: parent
                text: cell.modelData.text === "SUGGESTED PICK" ? "✓ Suggested pick" : "Option"
                color: cell.modelData.text === "SUGGESTED PICK" ? "#c5e6ff" : comparisonCard.secondaryText
                font.pixelSize: Style.font.caption + 1
                font.weight: Font.Medium
              }
            }

            ArtifactText {
              Layout.fillWidth: true
              Layout.leftMargin: 16
              Layout.rightMargin: 16
              visible: cell.modelData.kind === "fact"
              text: cell.modelData.label
              color: comparisonCard.mutedText
              font.pixelSize: Style.font.caption + 1
            }

            ArtifactText {
              Layout.fillWidth: true
              Layout.leftMargin: 16
              Layout.rightMargin: 16
              visible: ["name", "price", "summary", "fact", "section"].indexOf(cell.modelData.kind) >= 0
              text: cell.modelData.text
              font.pixelSize: cell.modelData.kind === "name" ? Style.font.display
                : cell.modelData.kind === "section" ? Style.font.caption + 1 : Style.font.body + 1
              font.weight: ["name", "section"].indexOf(cell.modelData.kind) >= 0 ? Font.DemiBold : Font.Normal
              color: cell.modelData.kind === "price" || cell.modelData.kind === "summary"
                ? comparisonCard.secondaryText : cell.modelData.kind === "section"
                ? comparisonCard.mutedText : "#f5f9ff"
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.leftMargin: 16
              Layout.rightMargin: 16
              visible: cell.modelData.kind === "divider"
              implicitHeight: 1
              color: "#20ffffff"
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 16
              Layout.rightMargin: 16
              visible: (cell.modelData.kind === "pros" || cell.modelData.kind === "cons") && cell.modelData.text !== ""
              spacing: 8
              Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 18
                implicitHeight: 18
                radius: 9
                color: cell.modelData.kind === "pros" ? "#2077d9ba" : "#20f5b881"
                ArtifactText {
                  anchors.centerIn: parent
                  text: cell.modelData.kind === "pros" ? "✓" : "−"
                  font.pixelSize: Style.font.caption + 1
                  color: cell.modelData.kind === "pros" ? "#9ce9d1" : "#ffd1a1"
                }
              }
              ArtifactText {
                Layout.fillWidth: true
                text: cell.modelData.text
                color: cell.modelData.kind === "pros" ? "#f5f9ff" : comparisonCard.secondaryText
              }
            }

            TextButton {
              Layout.leftMargin: 16
              visible: cell.modelData.kind === "source" && cell.modelData.text !== ""
              chrome: comparisonCard.actionChrome
              text: "Source ↗"
              color: "#a8d6ff"
              font.family: "sans-serif"
              onClicked: comparisonCard.openRequested(cell.modelData.text)
            }
          }
        }
      }
    }
  }

  Pill {
    chrome: comparisonCard.actionChrome
    text: "Copy comparison"
    onClicked: comparisonCard.copyRequested(comparisonCard.artifact.options.map(function(option) {
      return option.name + " — " + option.price + "\n" + option.summary + "\n"
        + option.facts.map(function(fact) { return fact.label + ": " + fact.value }).join("\n")
        + "\nPros: " + option.pros.join("; ") + "\nCons: " + option.cons.join("; ")
        + (option.sourceUrl ? "\nSource: " + option.sourceUrl : "")
    }).join("\n\n"))
  }
}
