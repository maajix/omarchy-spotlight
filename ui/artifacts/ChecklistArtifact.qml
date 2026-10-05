import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

ArtifactCard {
  id: checklistCard
  glyph: "󰄬"
  subtitle: artifact.note
  sourceUrl: artifact.sourceUrl
  retrievedAt: artifact.retrievedAt
  property var completed: []
  signal progressRequested(var completed)
  function toggleItem(index) {
    var next = completed.slice(), position = next.indexOf(index)
    if (position < 0) next.push(index)
    else next.splice(position, 1)
    progressRequested(next)
  }
  function copyText() {
    return artifact.title + "\n\n" + artifact.items.map(function(item, index) {
      return (completed.indexOf(index) >= 0 ? "[x] " : "[ ] ") + item.title + "\n    " + item.description
    }).join("\n\n")
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: 10
    RowLayout {
      Layout.fillWidth: true
      ArtifactText {
        Layout.fillWidth: true
        text: checklistCard.completed.length === checklistCard.artifact.items.length ? "All done" : "Your progress"
        font.weight: Font.DemiBold
      }
      ArtifactText {
        text: checklistCard.completed.length + " of " + checklistCard.artifact.items.length + " completed"
        color: checklistCard.secondaryText
      }
    }
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: 6
      radius: 3
      color: "#22ffffff"
      Rectangle {
        width: parent.width * checklistCard.completed.length / checklistCard.artifact.items.length
        height: parent.height
        radius: 3
        color: "#8bdcd2"
        Behavior on width { NumberAnimation { duration: 140 } }
      }
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: 8
    Repeater {
      model: checklistCard.artifact.items
      delegate: Rectangle {
        id: task
        required property var modelData
        required property int index
        readonly property bool done: checklistCard.completed.indexOf(index) >= 0
        Layout.fillWidth: true
        implicitHeight: Math.max(30, details.implicitHeight) + 24
        radius: 12
        color: activeFocus || pointer.containsMouse ? "#1cffffff" : "#0cffffff"
        border.color: activeFocus ? "#a6d6ff" : "transparent"
        activeFocusOnTab: true
        Accessible.role: Accessible.CheckBox
        Accessible.name: modelData.title
        Accessible.description: modelData.description
        Accessible.checkable: true
        Accessible.checked: done
        Accessible.onPressAction: checklistCard.toggleItem(index)
        Keys.onSpacePressed: checklistCard.toggleItem(index)
        Keys.onReturnPressed: checklistCard.toggleItem(index)
        RowLayout {
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
          spacing: 12
          Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            radius: 13
            color: task.done ? "#8bdcd2" : "transparent"
            border.color: task.done ? "#8bdcd2" : "#7796b7"
            border.width: 1.5
            ArtifactText {
              anchors.centerIn: parent
              text: task.done ? "✓" : ""
              color: "#183445"
              font.weight: Font.Bold
            }
          }
          ColumnLayout {
            id: details
            Layout.fillWidth: true
            spacing: 5
            ArtifactText {
              Layout.fillWidth: true
              text: task.modelData.title
              font.weight: Font.DemiBold
              font.strikeout: task.done
              color: task.done ? checklistCard.mutedText : "#f2f7fc"
            }
            ArtifactText {
              Layout.fillWidth: true
              text: task.modelData.description
              color: task.done ? checklistCard.mutedText : checklistCard.secondaryText
            }
          }
        }
        MouseArea {
          id: pointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { task.forceActiveFocus(); checklistCard.toggleItem(task.index) }
        }
      }
    }
  }

  RowLayout {
    spacing: 8
    Pill {
      chrome: checklistCard.actionChrome
      text: "Copy checklist"
      Accessible.role: Accessible.Button
      Accessible.name: text
      onClicked: checklistCard.copyRequested(checklistCard.copyText())
    }
    Pill {
      chrome: checklistCard.actionChrome
      text: "Reset"
      enabled: checklistCard.completed.length > 0
      opacity: enabled ? 1 : .4
      Accessible.role: Accessible.Button
      Accessible.name: "Reset checklist progress"
      onClicked: checklistCard.progressRequested([])
    }
  }
}
