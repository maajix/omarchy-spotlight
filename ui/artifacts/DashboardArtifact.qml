import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

ArtifactCard {
  id: dashboardCard
  glyph: "󰍛"
  subtitle: "Measured locally · snapshot, not live monitoring"
  retrievedAt: artifact.retrievedAt
  function bytes(value) {
    var units = ["B", "KiB", "MiB", "GiB", "TiB"], index = 0
    while (value >= 1024 && index < units.length - 1) { value /= 1024; index++ }
    return value.toFixed(index ? 1 : 0) + " " + units[index]
  }

  RowLayout {
    Layout.fillWidth: true
    visible: dashboardCard.artifact.cpu || dashboardCard.artifact.memory
    spacing: 12
    Repeater {
      model: ["cpu", "memory"].filter(function(key) { return dashboardCard.artifact[key] })
      delegate: Rectangle {
        required property string modelData
        readonly property var metric: dashboardCard.artifact[modelData]
        Layout.fillWidth: true
        implicitHeight: 142
        radius: 16
        color: "#12ffffff"
        border.color: "#18ffffff"
        ColumnLayout {
          anchors { fill: parent; margins: 16 }
          spacing: 8
          ArtifactText {
            text: parent.parent.modelData === "cpu" ? "CPU" : "MEMORY"
            color: dashboardCard.mutedText
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
          }
          ArtifactText {
            Layout.fillWidth: true
            text: parent.parent.modelData === "cpu" ? parent.parent.metric.percent.toFixed(1) + "%"
              : dashboardCard.bytes(parent.parent.metric.used)
            font.pixelSize: 34
            font.weight: Font.Light
          }
          ArtifactText {
            Layout.fillWidth: true
            text: parent.parent.modelData === "cpu" ? parent.parent.metric.cores + " logical CPUs · 200 ms sample"
              : dashboardCard.bytes(parent.parent.metric.available) + " available of " + dashboardCard.bytes(parent.parent.metric.total)
            color: dashboardCard.secondaryText
            font.pixelSize: Style.font.caption + 1
          }
        }
      }
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: dashboardCard.artifact.disks.length > 0
    spacing: 12
    ArtifactText { text: "STORAGE"; color: dashboardCard.mutedText; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
    Repeater {
      model: dashboardCard.artifact.disks
      delegate: ColumnLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: 8
        RowLayout {
          Layout.fillWidth: true
          ArtifactText { Layout.fillWidth: true; text: modelData.label; font.weight: Font.DemiBold }
          ArtifactText { text: Math.round(100 * modelData.used / modelData.total) + "% used"; color: dashboardCard.secondaryText }
        }
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: 8
          radius: 4
          color: "#20ffffff"
          Rectangle {
            width: parent.width * modelData.used / modelData.total
            height: parent.height
            radius: 4
            color: modelData.used / modelData.total > .9 ? "#f3bd79" : "#9bd2ff"
          }
        }
        ArtifactText {
          Layout.fillWidth: true
          text: dashboardCard.bytes(modelData.used) + " used of " + dashboardCard.bytes(modelData.total)
            + " · " + dashboardCard.bytes(modelData.available) + " available"
          color: dashboardCard.secondaryText
        }
      }
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: dashboardCard.artifact.folders.length > 0
    spacing: 10
    ArtifactText {
      Layout.fillWidth: true
      text: "LARGEST HOME FOLDERS" + (dashboardCard.artifact.foldersPartial ? " · PARTIAL SCAN" : "")
      color: dashboardCard.mutedText
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
    }
    Repeater {
      model: dashboardCard.artifact.folders
      delegate: RowLayout {
        required property var modelData
        Layout.fillWidth: true
        ArtifactText { Layout.preferredWidth: 150; text: modelData.name; elide: Text.ElideMiddle }
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: 6
          radius: 3
          color: "#16ffffff"
          Rectangle {
            width: parent.width * modelData.bytes / Math.max(1, dashboardCard.artifact.folders[0].bytes)
            height: parent.height
            radius: 3
            color: "#8bdcd2"
          }
        }
        ArtifactText { Layout.preferredWidth: 95; text: dashboardCard.bytes(modelData.bytes); horizontalAlignment: Text.AlignRight; color: dashboardCard.secondaryText }
      }
    }
    ArtifactText {
      Layout.fillWidth: true
      text: "Sizes include hidden folders. A partial scan may omit larger folders not reached within three seconds."
      color: dashboardCard.mutedText
      font.pixelSize: Style.font.caption + 1
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: dashboardCard.artifact.services.length > 0
    spacing: 10
    ArtifactText { text: "SERVICES"; color: dashboardCard.mutedText; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
    Repeater {
      model: dashboardCard.artifact.services
      delegate: Rectangle {
        required property var modelData
        Layout.fillWidth: true
        implicitHeight: serviceText.implicitHeight + 24
        radius: 12
        color: "#0cffffff"
        ColumnLayout {
          id: serviceText
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
          spacing: 6
          RowLayout {
            Layout.fillWidth: true
            ArtifactText { Layout.fillWidth: true; text: modelData.scope === "system" ? "System services" : "User services"; font.weight: Font.DemiBold }
            ArtifactText {
              text: modelData.active + " active · " + modelData.failed + " failed" + (modelData.partial ? " · partial list" : "")
              color: modelData.failed ? "#ffd195" : "#8bdcd2"
            }
          }
          ArtifactText {
            Layout.fillWidth: true
            visible: text !== ""
            text: modelData.failedNames.join(" · ")
            color: "#ffd195"
          }
        }
      }
    }
  }

  Repeater {
    model: dashboardCard.artifact.errors
    delegate: ArtifactText {
      required property string modelData
      Layout.fillWidth: true
      text: modelData
      color: "#ffd195"
    }
  }
  Pill {
    chrome: dashboardCard.actionChrome
    text: "Copy snapshot"
    Accessible.role: Accessible.Button
    Accessible.name: text
    onClicked: dashboardCard.copyRequested(JSON.stringify(dashboardCard.artifact, null, 2))
  }
}
