import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

ColumnLayout {
  id: map
  required property var artifact
  required property SpotlightPalette chrome
  signal openRequested(string url)
  spacing: Style.space(9)

  readonly property real latitude: artifact.latitude
  readonly property real longitude: artifact.longitude
  readonly property int zoom: artifact.zoom
  readonly property string coordinates: longitude.toFixed(5) + "," + latitude.toFixed(5)
  readonly property string previewUrl: "https://mapmap.ai/api/static-map?center="
    + coordinates + "&zoom=" + zoom + "&size=720x300&style=dark&markers=" + coordinates
  readonly property string openUrl: "https://www.openstreetmap.org/?mlat=" + latitude
    + "&mlon=" + longitude + "#map=" + zoom + "/" + latitude + "/" + longitude

  Rectangle {
    id: preview
    Layout.fillWidth: true
    implicitHeight: 300
    radius: 18
    color: "#111d30"
    border.width: 1
    border.color: "#49607a"
    clip: true

    Image {
      id: mapImage
      anchors.fill: parent
      anchors.margins: 8
      source: map.previewUrl
      sourceSize: Qt.size(720, 300)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: true
    }

    Text {
      anchors.centerIn: parent
      visible: mapImage.status !== Image.Ready
      text: mapImage.status === Image.Error ? "Map preview unavailable" : "Loading map…"
      color: "#bbccdf"
      font.family: "sans-serif"
      font.pixelSize: Style.font.body
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: map.openRequested(map.openUrl)
    }

    Rectangle {
      anchors { left: parent.left; top: parent.top; margins: 20 }
      width: Math.min(preview.width - 40, titleText.implicitWidth + 34)
      height: 44
      radius: 12
      color: "#dc111c2d"
      border.width: 1
      border.color: "#52718d"

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8
        Text {
          text: "󰍎"
          color: "#9fd6ff"
          font.family: map.chrome.fontFamily
          font.pixelSize: Style.font.subtitle + 2
        }
        Text {
          id: titleText
          Layout.fillWidth: true
          text: map.artifact.title
          textFormat: Text.PlainText
          color: "#f3f8ff"
          font.family: "sans-serif"
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }
      }
    }

  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(8)

    Text {
      Layout.fillWidth: true
      text: map.latitude.toFixed(4) + "°, " + map.longitude.toFixed(4) + "°"
      color: map.chrome.dim
      font.family: map.chrome.fontFamily
      font.pixelSize: Style.font.caption
    }

    TextButton {
      chrome: map.chrome
      text: "Open in OpenStreetMap ↗"
      color: "#bfe4ff"
      font.family: "sans-serif"
      onClicked: map.openRequested(map.openUrl)
    }
  }
}
