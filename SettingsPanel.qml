import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "lib/Web.js" as Web
import "lib/Currency.js" as Currency

// Spotlight.qml owns persistence; draft keeps controls responsive during writes.
FocusScope {
  id: panel

  // in
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property color surface: "transparent"
  property color surfaceBorder: "transparent"
  property color sheen: "transparent"
  property int hairline: 1
  property int surfaceRadius: 12
  property int rowRadius: 8
  property var settings: ({})
  property var pendingSettings: ({})
  property bool saveFailed: false
  property string currentBinding: ""
  property real availableHeight: Style.space(720)

  // owned
  // Steppers need values before the first settings read.
  readonly property var defaults: ({
    fileSearch: true,
    fileSearchAlways: true,
    clipboardSearch: true,
    clipboardSearchAlways: true,
    webSuggestions: false,
    currencyRates: true,
    searchEngine: "g",
    defaultCurrency: "",
    learningEnabled: true,
    maxResults: 20,
    maxApps: 8,
    maxSuggestions: 4
  })
  property var draft: panel.defaults
  property bool currencyValid: true
  // Reset requires two presses.
  property bool resetArmed: false

  // out
  signal changed(string key, var value)
  signal action(string name)
  signal closed()

  readonly property SpotlightPalette chrome: SpotlightPalette {
    foreground: panel.foreground
    accent: panel.accent
    fontFamily: panel.fontFamily
    hairline: panel.hairline
    rowRadius: panel.rowRadius
  }

  readonly property color dim: chrome.dim

  function open() {
    var s = Object.assign({}, panel.settings || {}, panel.pendingSettings)
    panel.draft = {
      fileSearch: s.fileSearch !== false,
      fileSearchAlways: s.fileSearchAlways !== false,
      clipboardSearch: s.clipboardSearch !== false,
      clipboardSearchAlways: s.clipboardSearchAlways !== false,
      webSuggestions: s.webSuggestions === true,
      currencyRates: s.currencyRates !== false,
      searchEngine: Web.hasEngine(s.searchEngine) ? s.searchEngine : "g",
      defaultCurrency: Currency.defaultCode(s.defaultCurrency),
      learningEnabled: s.learningEnabled !== false,
      // Util.clamp falls back to the minimum, not to the default, so a key
      // that never made it into the read keeps its documented default here.
      maxResults: Util.clamp(s.maxResults === undefined ? panel.defaults.maxResults : s.maxResults, 8, 50),
      maxApps: Util.clamp(s.maxApps === undefined ? panel.defaults.maxApps : s.maxApps, 3, 24),
      maxSuggestions: Util.clamp(s.maxSuggestions === undefined ? panel.defaults.maxSuggestions : s.maxSuggestions, 0, 8)
    }
    panel.currencyValid = true
    panel.resetArmed = false
    // After the layout has settled: the rows are still being sized when open()
    // runs, and a contentY set against the old height does not survive it.
    Qt.callLater(function() { flick.contentY = 0 })
    focusPanel()
  }

  function set(key, value) {
    var next = Object.assign({}, panel.draft)
    next[key] = value
    panel.draft = next
    panel.changed(key, value)
  }

  function toggle(key) { panel.set(key, panel.draft[key] !== true) }

  function focusPanel() {
    Qt.callLater(function() {
      if (panel.visible) panel.forceActiveFocus()
    })
  }

  // Tab walks the rows; a row below the fold has to bring itself into view or
  // the focus ring lands somewhere the user cannot see.
  function ensureVisible(item) {
    if (!item || !flick.visible) return
    var top = item.mapToItem(content, 0, 0).y
    var bottom = top + item.height
    if (top < flick.contentY) flick.contentY = Math.max(0, top - Style.space(8))
    else if (bottom > flick.contentY + flick.height)
      flick.contentY = Math.min(Math.max(0, content.height - flick.height),
                                bottom - flick.height + Style.space(8))
  }

  // Every exit goes through here. A rejected currency code is still sitting in
  // the field at that point, and nothing was written for it, so the field is
  // put back on the stored value instead of leaving the two disagreeing.
  function finish() {
    if (!panel.currencyValid) {
      panel.currencyValid = true
      panel.draft = Object.assign({}, panel.draft)
    }
    panel.closed()
  }

  // Esc is the only key that closes the panel. Return belongs to whatever holds
  // focus - a row toggles on it - and a panel that closed on a stray Enter from
  // a stepper or a menu would swallow the edit the user was in the middle of.
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) { panel.finish(); event.accepted = true }
  }

  onVisibleChanged: if (!visible) panel.resetArmed = false

  // ------------------------------------------------------------- pieces
  component GroupLabel: Text {
    Layout.fillWidth: true
    Layout.topMargin: Style.space(6)
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  // ------------------------------------------------------------- surface
  width: Math.min(Style.space(620), (parent ? parent.width : Style.space(800)) - Style.space(48))
  height: Math.min(panel.availableHeight, column.implicitHeight + Style.space(48))

  Rectangle {
    anchors.fill: parent
    radius: panel.surfaceRadius
    color: panel.surface
    border.width: panel.hairline
    border.color: panel.surfaceBorder
    antialiasing: true

    // Swallow clicks so they don't reach the dismiss MouseArea behind.
    MouseArea { anchors.fill: parent; onClicked: {} }

    Rectangle {
      anchors { top: parent.top; left: parent.left; right: parent.right }
      anchors.topMargin: panel.hairline
      anchors.leftMargin: panel.surfaceRadius
      anchors.rightMargin: panel.surfaceRadius
      height: panel.hairline
      color: panel.sheen
      radius: height
    }
  }

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.margins: Style.space(24)
    spacing: Style.space(14)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(12)

      IconTile {
        chrome: panel.chrome
        glyph: "󰒓"
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          Layout.fillWidth: true
          text: "Spotlight Settings"
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          Layout.fillWidth: true
          text: panel.saveFailed ? "Settings not saved. Check the file, then retry." : "Changes save as you make them."
          color: panel.saveFailed ? Color.urgent : panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      TextButton {
        visible: panel.saveFailed
        chrome: panel.chrome
        text: "Retry save"
        onClicked: panel.action("retry")
      }

      TextButton {
        chrome: panel.chrome
        text: "Edit file"
        onClicked: panel.action("edit")
      }
    }

    Flickable {
      id: flick
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: content.implicitHeight
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      ScrollBar.vertical: ScrollBar {
        policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
      }

      ColumnLayout {
        id: content
        width: flick.width - (flick.contentHeight > flick.height ? Style.space(10) : 0)
        spacing: Style.space(10)

        GroupLabel { text: "SEARCH" }

        SettingRow {
          id: filesRow
          chrome: panel.chrome
          glyph: "󰉋"
          title: "Files and folders"
          description: "Find files in your home directory by name."
          checked: panel.draft.fileSearch === true
          onToggled: panel.toggle("fileSearch")
          onActiveFocusChanged: if (activeFocus) panel.ensureVisible(filesRow)

          SubToggle {
            chrome: panel.chrome
            enabled: panel.draft.fileSearch === true
            opacity: enabled ? 1 : 0.45
            text: "Include files in every search"
            description: "When off, files only appear after you type f, f: or a path."
            checked: panel.draft.fileSearchAlways === true
            onToggled: panel.toggle("fileSearchAlways")
            onActiveFocusChanged: if (activeFocus) panel.ensureVisible(filesRow)
          }
        }

        SettingRow {
          id: clipboardRow
          chrome: panel.chrome
          glyph: "󰅌"
          title: "Clipboard history"
          description: "Search what you copied earlier and copy it again with Enter."
          checked: panel.draft.clipboardSearch === true
          onToggled: panel.toggle("clipboardSearch")
          onActiveFocusChanged: if (activeFocus) panel.ensureVisible(clipboardRow)

          SubToggle {
            chrome: panel.chrome
            enabled: panel.draft.clipboardSearch === true
            opacity: enabled ? 1 : 0.45
            text: "Include clipboard in every search"
            description: "When off, clipboard entries only appear after you type c or c:."
            checked: panel.draft.clipboardSearchAlways === true
            onToggled: panel.toggle("clipboardSearchAlways")
            onActiveFocusChanged: if (activeFocus) panel.ensureVisible(clipboardRow)
          }
        }

        SettingRow {
          id: learningRow
          chrome: panel.chrome
          glyph: "󰧐"
          title: "Learn from your choices"
          description: "Results you pick often move up over time. Nothing leaves this machine."
          checked: panel.draft.learningEnabled === true
          onToggled: panel.toggle("learningEnabled")
          onActiveFocusChanged: if (activeFocus) panel.ensureVisible(learningRow)
        }

        GroupLabel { text: "WEB" }

        SettingRow {
          id: suggestionsRow
          chrome: panel.chrome
          glyph: "󱐋"
          title: "Search suggestions"
          description: "Complete your query while you type. Queries are sent to "
            + (panel.draft.searchEngine === "kagi" ? "Kagi" : "Google")
            + ", so this is off by default."
          checked: panel.draft.webSuggestions === true
          onToggled: panel.toggle("webSuggestions")
          onActiveFocusChanged: if (activeFocus) panel.ensureVisible(suggestionsRow)
        }

        SettingRow {
          id: engineRow
          chrome: panel.chrome
          glyph: "󰖟"
          switchable: false
          title: "Web search engine"
          description: "Where the web search result opens when you press Enter, and which provider answers search suggestions."

          trailing: ChoiceMenu {
            chrome: panel.chrome
            value: panel.draft.searchEngine || "g"
            options: Web.engineOptions()
            onChanged: function(v) { panel.set("searchEngine", v) }
            onActiveFocusChanged: if (activeFocus) panel.ensureVisible(engineRow)
          }
        }

        GroupLabel { text: "CURRENCY" }

        SettingRow {
          id: currencyRatesRow
          chrome: panel.chrome
          glyph: "󰑤"
          title: "Currency rates"
          description: "Fetch rates from Frankfurter for complete currency queries. On by default."
          checked: panel.draft.currencyRates !== false
          onToggled: panel.toggle("currencyRates")
          onActiveFocusChanged: if (activeFocus) panel.ensureVisible(currencyRatesRow)
        }

        SettingRow {
          id: currencyCodeRow
          chrome: panel.chrome
          glyph: "󰠓"
          switchable: false
          title: "Default currency"
          description: panel.currencyValid
            ? "Type a 3-letter currency code, or leave blank. Explicit targets take priority."
            : "Enter a supported 3-letter currency code, or clear the field."

          trailing: TextField {
            id: currencyCodeField
            implicitWidth: Style.space(160)
            implicitHeight: Style.space(30)
            text: panel.draft.defaultCurrency || ""
            placeholderText: "None or USD"
            maximumLength: 3
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
            color: panel.foreground
            selectByMouse: true
            // Reassigning draft restores the text binding rather than writing
            // `text` directly, which would detach the field from the draft.
            Keys.onEscapePressed: function(event) {
              event.accepted = true
              panel.currencyValid = true
              panel.draft = Object.assign({}, panel.draft)
              panel.forceActiveFocus()
            }
            // Return commits the field by handing focus back, rather than
            // leaving the caret in a control the panel no longer tracks.
            Keys.onReturnPressed: function(event) {
              event.accepted = true
              panel.forceActiveFocus()
            }
            background: Rectangle {
              radius: panel.rowRadius
              color: currencyCodeField.activeFocus ? panel.chrome.fillHot : panel.chrome.fill
              border.width: panel.hairline
              border.color: !panel.currencyValid ? Color.urgent
                : currencyCodeField.activeFocus ? panel.chrome.lineFocus : panel.chrome.line
            }
            // An unfinished code is never written: the field reports only what
            // Currency accepts, so a half-typed "US" leaves the stored value alone.
            onTextEdited: {
              var valid = text === "" || Currency.defaultCode(text) !== ""
              panel.currencyValid = valid
              if (valid) panel.set("defaultCurrency", Currency.defaultCode(text))
            }
            onActiveFocusChanged: if (activeFocus) panel.ensureVisible(currencyCodeRow)
          }
        }

        GroupLabel { text: "RESULTS" }

        SettingRow {
          id: maxResultsRow
          chrome: panel.chrome
          glyph: "󰒺"
          switchable: false
          title: "Results shown"
          description: "How many rows the list holds before it stops adding more."

          trailing: Stepper {
            chrome: panel.chrome
            value: panel.draft.maxResults
            from: 8
            to: 50
            onChanged: function(v) { panel.set("maxResults", v) }
            onActiveFocusChanged: if (activeFocus) panel.ensureVisible(maxResultsRow)
          }
        }

        SettingRow {
          id: maxAppsRow
          chrome: panel.chrome
          glyph: "󰀻"
          switchable: false
          title: "Applications shown"
          description: "How many application matches a query can contribute."

          trailing: Stepper {
            chrome: panel.chrome
            value: panel.draft.maxApps
            from: 3
            to: 24
            onChanged: function(v) { panel.set("maxApps", v) }
            onActiveFocusChanged: if (activeFocus) panel.ensureVisible(maxAppsRow)
          }
        }

        SettingRow {
          id: maxSuggestionsRow
          chrome: panel.chrome
          glyph: "󱐋"
          switchable: false
          title: "Search suggestions shown"
          description: "How many suggestions the web provider may add. Zero hides them."

          trailing: Stepper {
            chrome: panel.chrome
            value: panel.draft.maxSuggestions
            from: 0
            to: 8
            onChanged: function(v) { panel.set("maxSuggestions", v) }
            onActiveFocusChanged: if (activeFocus) panel.ensureVisible(maxSuggestionsRow)
          }
        }

        GroupLabel { text: "SHORTCUT" }

        SettingRow {
          id: shortcutRow
          chrome: panel.chrome
          glyph: "󰌌"
          switchable: false
          title: "Open Spotlight"
          description: panel.currentBinding !== ""
            ? "The shortcut that opens this launcher from anywhere."
            : "No shortcut is set yet. Pick one to open Spotlight from anywhere."

          trailing: RowLayout {
            spacing: Style.space(10)

            ChordCaps {
              chrome: panel.chrome
              chord: panel.currentBinding
              small: true
              emptyText: "None"
            }

            Pill {
              chrome: panel.chrome
              text: "Change"
              onClicked: panel.action("shortcut")
              onActiveFocusChanged: if (activeFocus) panel.ensureVisible(shortcutRow)
            }
          }
        }

        GroupLabel { text: "MAINTENANCE" }

        SettingRow {
          id: maintenanceRow
          chrome: panel.chrome
          glyph: "󰑐"
          switchable: false
          title: "Setup and data"
          description: "Run the tour again, open the folder holding the learning data, or clear that data."

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Pill {
              chrome: panel.chrome
              text: "Run setup tour"
              onClicked: panel.action("tour")
              onActiveFocusChanged: if (activeFocus) panel.ensureVisible(maintenanceRow)
            }

            Pill {
              chrome: panel.chrome
              text: "Data folder"
              onClicked: panel.action("data")
              onActiveFocusChanged: if (activeFocus) panel.ensureVisible(maintenanceRow)
            }

            Pill {
              chrome: panel.chrome
              text: panel.resetArmed ? "Press again to reset" : "Reset learning data"
              selected: panel.resetArmed
              onActiveFocusChanged: if (activeFocus) panel.ensureVisible(maintenanceRow)
              onClicked: {
                if (!panel.resetArmed) { panel.resetArmed = true; return }
                panel.resetArmed = false
                panel.action("reset")
              }
            }

            Item { Layout.fillWidth: true }
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(12)

      Text {
        Layout.fillWidth: true
        text: "Esc closes"
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }

      PrimaryButton {
        chrome: panel.chrome
        text: "Done"
        glyph: "󰄬"
        onClicked: panel.finish()
      }
    }
  }
}
