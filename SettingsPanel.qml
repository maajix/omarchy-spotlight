import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "lib/Web.js" as Web

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
  // Spotlight.qml normalizes settings; queued patches only hold values these
  // controls or the tour produced.
  property var draft: panel.settings
  // Reset requires two presses.
  property bool resetArmed: false
  // Set by Spotlight.qml once the helper confirms the reset.
  property bool resetDone: false

  // out
  signal changed(var patch)
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
    panel.draft = Object.assign({}, panel.settings, panel.pendingSettings)
    currencyCodeField.revert()
    panel.resetArmed = false
    panel.resetDone = false
    // After the layout has settled: the rows are still being sized when open()
    // runs, and a contentY set against the old height does not survive it.
    Qt.callLater(function() { flick.contentY = 0 })
    focusPanel()
  }

  function set(key, value) {
    var patch = ({})
    patch[key] = value
    panel.draft = Object.assign({}, panel.draft, patch)
    panel.changed(patch)
  }

  function toggle(key) { panel.set(key, panel.draft[key] !== true) }

  function focusPanel() {
    Qt.callLater(function() {
      if (panel.visible) panel.forceActiveFocus()
    })
  }

  // Tab walks the rows; a row below the fold has to come into view or the focus
  // ring lands somewhere the user cannot see. Whatever holds focus inside a row
  // scrolls that whole row in.
  readonly property Item focusedItem: Window.activeFocusItem
  onFocusedItemChanged: {
    for (var item = panel.focusedItem; item; item = item.parent)
      if (item.parent === content) { panel.ensureVisible(item); break }
  }

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
    currencyCodeField.revert()
    panel.closed()
  }

  // Esc is the only key that closes the panel. Return belongs to whatever holds
  // focus, and a panel that closed on a stray Enter from a stepper or a menu
  // would swallow the edit the user was in the middle of.
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) { panel.finish(); event.accepted = true }
  }

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
          chrome: panel.chrome
          glyph: "󰉋"
          title: "Files and folders"
          description: "Find files in your home directory by name."
          checked: panel.draft.fileSearch === true
          onToggled: panel.toggle("fileSearch")

          SubToggle {
            chrome: panel.chrome
            enabled: panel.draft.fileSearch === true
            text: "Include files in every search"
            description: "When off, files only appear after you type f, f: or a path."
            checked: panel.draft.fileSearchAlways === true
            onToggled: panel.toggle("fileSearchAlways")
          }
        }

        SettingRow {
          chrome: panel.chrome
          glyph: "󰅌"
          title: "Clipboard history"
          description: "Search what you copied earlier and copy it again with Enter."
          checked: panel.draft.clipboardSearch === true
          onToggled: panel.toggle("clipboardSearch")

          SubToggle {
            chrome: panel.chrome
            enabled: panel.draft.clipboardSearch === true
            text: "Include clipboard in every search"
            description: "When off, clipboard entries only appear after you type c or c:."
            checked: panel.draft.clipboardSearchAlways === true
            onToggled: panel.toggle("clipboardSearchAlways")
          }
        }

        SettingRow {
          chrome: panel.chrome
          glyph: "󰧐"
          title: "Learn from your choices"
          description: "Results you pick often move up over time. Nothing leaves this machine."
          checked: panel.draft.learningEnabled === true
          onToggled: panel.toggle("learningEnabled")
        }

        GroupLabel { text: "WEB" }

        SettingRow {
          chrome: panel.chrome
          glyph: "󱐋"
          title: "Search suggestions"
          description: "Complete your query while you type. Queries are sent to "
            + (panel.draft.searchEngine === "kagi" ? "Kagi" : "Google")
            + ", so this is off by default."
          checked: panel.draft.webSuggestions === true
          onToggled: panel.toggle("webSuggestions")
        }

        SettingRow {
          chrome: panel.chrome
          glyph: "󰖟"
          switchable: false
          title: "Web search engine"
          description: "Where the web search result opens when you press Enter, and which provider answers search suggestions."

          trailing: ChoiceMenu {
            chrome: panel.chrome
            value: panel.draft.searchEngine
            options: Web.engineOptions()
            onChanged: function(v) { panel.set("searchEngine", v) }
          }
        }

        GroupLabel { text: "CURRENCY" }

        SettingRow {
          chrome: panel.chrome
          glyph: "󰑤"
          title: "Currency rates"
          description: "Fetch rates from Frankfurter for complete currency queries. On by default."
          checked: panel.draft.currencyRates !== false
          onToggled: panel.toggle("currencyRates")
        }

        SettingRow {
          chrome: panel.chrome
          glyph: "󰠓"
          switchable: false
          title: "Default currency"
          description: currencyCodeField.valid
            ? "Type a 3-letter currency code, or leave blank. Explicit targets take priority."
            : "Enter a supported 3-letter currency code, or clear the field."

          trailing: CurrencyField {
            id: currencyCodeField
            chrome: panel.chrome
            implicitWidth: Style.space(160)
            code: panel.draft.defaultCurrency || ""
            onPicked: function(code) { panel.set("defaultCurrency", code) }
          }
        }

        GroupLabel { text: "RESULTS" }

        SettingRow {
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
          }
        }

        SettingRow {
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
          }
        }

        SettingRow {
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
          }
        }

        GroupLabel { text: "SHORTCUT" }

        SettingRow {
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
            }
          }
        }

        GroupLabel { text: "MAINTENANCE" }

        SettingRow {
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
            }

            Pill {
              chrome: panel.chrome
              text: "Data folder"
              onClicked: panel.action("data")
            }

            Pill {
              chrome: panel.chrome
              text: panel.resetArmed ? "Press again to reset"
                : panel.resetDone ? "Learning data cleared" : "Reset learning data"
              selected: panel.resetArmed
              onClicked: {
                if (!panel.resetArmed) { panel.resetArmed = true; panel.resetDone = false; return }
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
