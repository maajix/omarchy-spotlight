import QtQuick
import QtQuick.Controls
import qs.Commons
import "lib/Currency.js" as Currency

// Default-currency input shared by the tour and the settings panel. An
// unfinished code is never reported: only what Currency accepts, or blank,
// reaches picked(), so a half-typed "US" leaves the stored value alone.
TextField {
  id: field

  property SpotlightPalette chrome: SpotlightPalette {}
  property string code: ""
  property bool valid: true
  signal picked(string newCode)

  // Back on the stored code. A fresh binding, because a rejected code leaves
  // `code` unchanged and the old binding would not re-run.
  function revert() {
    field.valid = true
    field.text = Qt.binding(function() { return field.code })
  }

  implicitHeight: Style.space(30)
  text: field.code
  placeholderText: "None or USD"
  maximumLength: 3
  font.family: field.chrome.fontFamily
  font.pixelSize: Style.font.body
  color: field.chrome.foreground
  selectByMouse: true

  // Esc drops the edit and Return keeps it; both hand focus to the enclosing
  // scope. Return stays unaccepted so the owner still sees it (the tour
  // advances on it). Left at the start must not leak out as "back".
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      event.accepted = true
      field.revert()
      field.focus = false
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (field.valid) field.focus = false
    } else if (event.key === Qt.Key_Left && field.cursorPosition === 0) {
      event.accepted = true
    }
  }

  background: Rectangle {
    radius: field.chrome.rowRadius
    color: field.activeFocus ? field.chrome.fillHot : field.chrome.fill
    border.width: field.chrome.hairline
    border.color: !field.valid ? Color.urgent
      : field.activeFocus ? field.chrome.lineFocus : field.chrome.line
  }

  onTextEdited: {
    field.valid = text === "" || Currency.defaultCode(text) !== ""
    if (field.valid) field.picked(Currency.defaultCode(text))
  }
}
