import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

Rectangle {
  id: weather
  required property var artifact
  required property SpotlightPalette chrome
  signal openRequested(string url)

  readonly property var days: artifact.days || []
  readonly property var primaryDay: days.length ? days[0] : ({})
  readonly property bool isRain: artifact.variant === "rain"

  function hasNumber(value) { return typeof value === "number" && isFinite(value) }
  function iconFor(summary) {
    var text = String(summary || "").toLowerCase()
    if (/gewitter|thunder|storm/.test(text)) return "⚡"
    if (/schnee|snow/.test(text)) return "❄"
    if (/regen|rain|schauer|drizzle/.test(text)) return "☂"
    if (/sonn|sun|klar|clear/.test(text)) return "☀"
    return "☁"
  }

  implicitHeight: content.implicitHeight + 40
  radius: 18
  clip: true
  border.width: 1
  border.color: "#526883"
  gradient: Gradient {
    GradientStop { position: 0; color: "#344a68" }
    GradientStop { position: 0.58; color: "#253a57" }
    GradientStop { position: 1; color: "#18263e" }
  }

  Rectangle {
    anchors { right: parent.right; top: parent.top; rightMargin: -52; topMargin: -88 }
    width: 300
    height: 300
    radius: 150
    color: "#145ba7e5"
  }

  ColumnLayout {
    id: content
    anchors { left: parent.left; right: parent.right; top: parent.top }
    anchors.margins: 20
    spacing: 16

    RowLayout {
      Layout.fillWidth: true
      spacing: 12

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Text {
          Layout.fillWidth: true
          text: weather.artifact.location
          textFormat: Text.PlainText
          color: "#f5f9ff"
          font.family: "sans-serif"
          font.pixelSize: Style.font.title + 3
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          text: Qt.formatDate(new Date(weather.primaryDay.date + "T12:00:00"), "dddd, d. MMMM")
          color: "#c4d5e8"
          font.family: "sans-serif"
          font.pixelSize: Style.font.body
        }
      }

      Text {
        text: weather.iconFor(weather.primaryDay.summary)
        color: "#d7efff"
        font.family: "sans-serif"
        font.pixelSize: 44
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 20

      Text {
        text: weather.isRain ? Math.round(weather.primaryDay.rainPercent) + "%"
          : Math.round(weather.artifact.variant === "current"
            ? weather.primaryDay.temperatureC : weather.primaryDay.highC) + "°"
        color: "#ffffff"
        font.family: "sans-serif"
        font.pixelSize: 58
        font.weight: Font.Light
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        Text {
          Layout.fillWidth: true
          text: weather.primaryDay.summary
          textFormat: Text.PlainText
          color: "#ffffff"
          font.family: "sans-serif"
          font.pixelSize: Style.font.subtitle + 1
          font.bold: true
          wrapMode: Text.WordWrap
        }
        Text {
          visible: weather.isRain || (weather.hasNumber(weather.primaryDay.highC)
            && weather.hasNumber(weather.primaryDay.lowC))
          text: weather.isRain ? "Regenwahrscheinlichkeit"
            : "H: " + Math.round(weather.primaryDay.highC) + "°   T: "
              + Math.round(weather.primaryDay.lowC) + "°"
          color: "#c4d5e8"
          font.family: "sans-serif"
          font.pixelSize: Style.font.body
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: forecastColumn.implicitHeight + 24
      radius: 12
      color: "#28212e48"
      border.width: 1
      border.color: "#285e7793"

      ColumnLayout {
        id: forecastColumn
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.margins: 12
        spacing: 10

        Text {
          text: weather.isRain ? "REGENAUSSICHT" : "TAGESÜBERSICHT"
          color: "#bdd3ea"
          font.family: "sans-serif"
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }

        Repeater {
          model: weather.days
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 10

            Text {
              Layout.preferredWidth: 95
              text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd d MMM")
              color: "#f5f9ff"
              font.family: "sans-serif"
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              text: weather.iconFor(modelData.summary)
              color: "#d7efff"
              font.family: "sans-serif"
              font.pixelSize: Style.font.body + 3
            }
            Text {
              Layout.fillWidth: true
              text: modelData.summary
              textFormat: Text.PlainText
              color: "#d5e1ef"
              font.family: "sans-serif"
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Text {
              visible: weather.hasNumber(modelData.lowC) && weather.hasNumber(modelData.highC)
              text: Math.round(modelData.lowC) + "°  /  " + Math.round(modelData.highC) + "°"
              color: "#f5f9ff"
              font.family: "sans-serif"
              font.pixelSize: Style.font.body
            }
            Rectangle {
              visible: weather.hasNumber(modelData.rainPercent)
              Layout.preferredWidth: 56
              implicitHeight: 4
              radius: 2
              color: "#52708e"
              Rectangle {
                width: parent.width * modelData.rainPercent / 100
                height: parent.height
                radius: 2
                color: "#8ed6ff"
              }
            }
            Text {
              visible: weather.hasNumber(modelData.rainPercent)
              Layout.preferredWidth: 48
              horizontalAlignment: Text.AlignRight
              text: Math.round(modelData.rainPercent) + "%"
              color: "#8ed6ff"
              font.family: "sans-serif"
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8
      Text {
        Layout.fillWidth: true
        text: "Stand " + weather.artifact.retrievedAt.slice(11, 16) + " UTC"
        color: "#b2c4d9"
        font.family: "sans-serif"
        font.pixelSize: Style.font.caption
      }
      TextButton {
        chrome: weather.chrome
        text: weather.artifact.sourceUrl.split("/")[2] + " ↗"
        color: "#d8ecff"
        font.family: "sans-serif"
        font.pixelSize: Style.font.caption
        onClicked: weather.openRequested(weather.artifact.sourceUrl)
      }
    }
  }
}
