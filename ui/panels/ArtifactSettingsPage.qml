import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../components"

ColumnLayout {
  id: page
  required property SpotlightPalette chrome
  property var artifactSettings: ({ weather: { defaultLocation: "" } })
  signal changed(var patch)
  spacing: Style.space(12)

  function commit() {
    var location = locationField.text.trim()
    if (location.length > 120) return
    var current = page.artifactSettings.weather || ({})
    if (location !== (current.defaultLocation || ""))
      page.changed({ artifactSettings: { weather: { defaultLocation: location } } })
  }

  Text {
    Layout.fillWidth: true
    text: "Weather"
    color: page.chrome.foreground
    font.family: page.chrome.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
  }

  SettingRow {
    chrome: page.chrome
    glyph: "󰖐"
    switchable: false
    title: "Weather default location"
    description: "Used only for weather questions without a place. A place in your question wins."

    trailing: TextField {
      id: locationField
      implicitWidth: Style.space(205)
      implicitHeight: Style.space(30)
      text: (page.artifactSettings.weather || {}).defaultLocation || ""
      placeholderText: "City, region"
      maximumLength: 120
      font.family: page.chrome.fontFamily
      font.pixelSize: Style.font.body
      color: page.chrome.foreground
      selectByMouse: true
      onTextEdited: page.commit()
      onEditingFinished: page.commit()
      background: Rectangle {
        radius: page.chrome.rowRadius
        color: locationField.activeFocus ? page.chrome.fillHot : page.chrome.fill
        border.width: page.chrome.hairline
        border.color: locationField.activeFocus ? page.chrome.lineFocus : page.chrome.line
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Weather cards need AI web search. Spotlight does not fetch weather data itself."
    color: page.chrome.dim
    font.family: page.chrome.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Item { Layout.fillHeight: true }
}
