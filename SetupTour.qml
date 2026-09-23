import QtQuick
import QtQuick.Layouts
import qs.Commons
import "lib/Chord.js" as Chord
import "lib/Web.js" as Web
import "lib/Currency.js" as Currency

// First-run tour, and the standalone shortcut chooser (singleStep). Pure UI:
// Spotlight.qml owns every read and write and feeds the results back through
// the properties below, so nothing here can touch a file.
//
// Chrome follows the Spotlight card (fixed radii, hairline outlines from the
// foreground at low alpha), not the shell kit: the kit paints square,
// high-contrast control borders on sharp themes and the card is rounded anyway.
FocusScope {
  id: tour

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
  property string currentBinding: ""
  property string previousBinding: ""
  property bool bindingManaged: false
  property var boundChords: ({})
  property string bindingState: ""   // "" | busy | ok | reverted | error | reloadError

  // owned
  property int step: 0
  property bool singleStep: false
  // True from start() until finished(). Spotlight resumes an unfinished tour
  // at the same step after a focus loss instead of restarting it.
  property bool started: false
  property var draft: ({})
  property string selected: ""

  // out
  signal bindingRequested(string chord)
  signal revertRequested()
  signal finished(var patch)        // {} = persist nothing

  readonly property var presets: ["ALT + SPACE", "SUPER + SPACE", "CTRL + ALT + SPACE"]
  readonly property var examples: [["firefox", "open an app"], ["f invoice", "find a file"], ["12*1.19", "calculate"],
    ["5 km in mi", "convert units"], ["remind me tomorrow 9am standup", "set a reminder"], ["tr hallo welt en", "translate"]]
  readonly property var titles: ["Welcome to Spotlight", "Choose your shortcut", "What should Spotlight search?", "You're all set"]
  readonly property var subtitles: [
    "One search box for apps, files, your clipboard, quick calculations and the web. Four short steps, skip any of them.",
    "This key combination opens Spotlight from anywhere. Pick a preset or press your own.",
    "You can change all of this later under Spotlight Settings.",
    "Open Spotlight and start typing. A few things to try:"
  ]
  readonly property bool sameAsCurrent: selected !== "" && selected === currentBinding
  readonly property bool occupied: selected !== "" && selected !== currentBinding
      && Object.prototype.hasOwnProperty.call(boundChords, selected)
  readonly property string owner: occupied ? String(boundChords[selected]) : ""
  readonly property string shownChord: selected !== "" ? selected : currentBinding
  readonly property string chordCaption: selected === ""
      ? (currentBinding ? "Your current shortcut" : "Spotlight has no shortcut yet. Pick one below.")
      : sameAsCurrent ? "This is already your shortcut."
      : occupied ? (owner ? "Currently opens " + owner : "Already assigned") + ". Spotlight will take it over."
      : "Free to use."
  readonly property string primaryText: step === 0 ? "Get started"
      : step === 1 ? (selected === "" ? (singleStep ? "Done" : "Continue") : occupied ? "Replace and set" : "Set shortcut")
      : step === 2 ? "Continue" : "Finish"
  readonly property bool primaryEnabled: step === 2 ? currencyCodeField.valid
      : step !== 1 || (!sameAsCurrent && bindingState !== "busy")
  readonly property string statusText: bindingState === "busy" ? "Saving..."
      : bindingState === "ok" ? "Shortcut set to " + currentBinding
      : bindingState === "reverted" ? (currentBinding ? "Restored " + currentBinding : "Shortcut removed")
      : bindingState === "reloadError" ? "Shortcut saved, but Hyprland could not reload it."
      : bindingState === "error" ? "Could not write the shortcut. Edit ~/.config/hypr/bindings.lua by hand." : ""

  // palette
  // The shared pieces (SettingRow, ChoiceMenu, Pill, ...) read their colours
  // from this one object, and so does the tour's own chrome.
  readonly property SpotlightPalette chrome: SpotlightPalette {
    foreground: tour.foreground
    accent: tour.accent
    fontFamily: tour.fontFamily
    hairline: tour.hairline
    rowRadius: tour.rowRadius
  }
  readonly property color dim: chrome.dim

  function start(current, at, single) {
    draft = {
      fileSearch: current.fileSearch !== false,
      fileSearchAlways: current.fileSearchAlways !== false,
      clipboardSearch: current.clipboardSearch !== false,
      webSuggestions: current.webSuggestions === true,
      currencyRates: current.currencyRates !== false,
      searchEngine: Web.hasEngine(current.searchEngine) ? current.searchEngine : "g",
      defaultCurrency: Currency.defaultCode(current.defaultCurrency),
      learningEnabled: current.learningEnabled !== false
    }
    selected = ""
    currencyCodeField.revert()
    singleStep = single
    step = at
    started = true
    focusStep()
  }

  function set(key, value) {
    var next = Object.assign({}, draft)
    next[key] = value
    draft = next
  }

  function completed(patch) {
    return Object.assign({}, patch, { setupCompleted: true })
  }

  function skip() { finished(singleStep ? {} : completed({})) }
  function back() { if (!singleStep && step > 0) step -= 1 }

  function primary() {
    if (!primaryEnabled) return
    if (step === 1 && selected !== "") { bindingRequested(selected); return }
    if (step === 1 && singleStep) { finished({}); return }
    if (step === 3) { finished(completed(draft)); return }
    step += 1
  }

  function chipCaption(chord) {
    if (chord === currentBinding) return "current"
    if (Object.prototype.hasOwnProperty.call(boundChords, chord)) return String(boundChords[chord])
    if (chord === "ALT + SPACE") return "recommended"
    return ""
  }

  // The recorder takes the keyboard on the shortcut step; everywhere else
  // focusHome does, so Enter/Esc/Left work without a focused control. The
  // scope itself would hand focus back to a control from an earlier step.
  function focusStep() {
    Qt.callLater(function() {
      if (!tour.visible) return
      if (tour.step === 1) recorder.forceActiveFocus()
      else focusHome.forceActiveFocus()
    })
  }

  onStepChanged: focusStep()
  onFinished: started = false
  onBindingStateChanged: if (bindingState === "ok" || bindingState === "reverted") selected = ""

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) { skip(); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { primary(); event.accepted = true }
    else if (event.key === Qt.Key_Left) { back(); event.accepted = true }
  }

  // ------------------------------------------------------------- pieces
  component Feature: RowLayout {
    id: feat
    property string glyph: ""
    property string title: ""
    property string description: ""
    Layout.fillWidth: true
    spacing: Style.space(12)

    IconTile { chrome: tour.chrome; glyph: feat.glyph }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(2)

      Text {
        Layout.fillWidth: true
        text: feat.title
        color: tour.foreground
        font.family: tour.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        Layout.fillWidth: true
        text: feat.description
        color: tour.dim
        font.family: tour.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }


  // ------------------------------------------------------------- surface
  width: Math.min(Style.space(580), (parent ? parent.width : Style.space(800)) - Style.space(48))
  height: column.implicitHeight + Style.space(48)

  Behavior on height {
    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
  }

  Item { id: focusHome }

  Rectangle {
    anchors.fill: parent
    radius: tour.surfaceRadius
    color: tour.surface
    border.width: tour.hairline
    border.color: tour.surfaceBorder
    antialiasing: true

    // Swallow clicks so they don't reach the dismiss MouseArea behind.
    MouseArea { anchors.fill: parent; onClicked: {} }

    // Glass sheen, inset by the corner radius so it ends where the curve starts.
    Rectangle {
      anchors { top: parent.top; left: parent.left; right: parent.right }
      anchors.topMargin: tour.hairline
      anchors.leftMargin: tour.surfaceRadius
      anchors.rightMargin: tour.surfaceRadius
      height: tour.hairline
      color: tour.sheen
      radius: height
    }
  }

  ColumnLayout {
    id: column
    anchors { left: parent.left; right: parent.right; top: parent.top }
    anchors.margins: Style.space(24)
    spacing: Style.space(18)

    // Top bar: progress dots centered, Skip at the right.
    RowLayout {
      Layout.fillWidth: true
      visible: !tour.singleStep

      Item { Layout.preferredWidth: skipBtn.implicitWidth; Layout.preferredHeight: 1 }
      Item { Layout.fillWidth: true }

      Row {
        spacing: Style.space(6)

        Repeater {
          model: 4

          Rectangle {
            required property int index
            width: index === tour.step ? Style.space(18) : Style.space(6)
            height: Style.space(6)
            radius: height / 2
            color: index === tour.step ? tour.accent : Util.alpha(tour.foreground, 0.25)

            Behavior on width {
              NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
          }
        }
      }

      Item { Layout.fillWidth: true }

      TextButton {
        id: skipBtn
        chrome: tour.chrome
        text: "Skip tour"
        opacity: tour.step < 3 ? 1 : 0
        enabled: tour.step < 3
        onClicked: tour.skip()
      }
    }

    // Header
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)

      IconTile {
        chrome: tour.chrome
        visible: tour.step === 0 && !tour.singleStep
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: Style.space(8)
        glyph: "󱓞"
        size: Style.space(56)
        glyphSize: Style.font.displayLarge
      }

      Text {
        Layout.fillWidth: true
        text: tour.titles[tour.step] || ""
        color: tour.foreground
        font.family: tour.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        text: tour.subtitles[tour.step] || ""
        color: tour.dim
        font.family: tour.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }

    StackLayout {
      id: stack
      Layout.fillWidth: true
      Layout.preferredHeight: children[currentIndex] ? children[currentIndex].implicitHeight : 0
      currentIndex: tour.step

      // ------------------------------------------------------- 1 welcome
      ColumnLayout {
        spacing: Style.space(14)

        Feature {
          glyph: "󰍉"
          title: "Search everything"
          description: "Find apps, windows, files, clipboard entries and commands from a single search box."
        }

        Feature {
          glyph: "󰃬"
          title: "Get answers inline"
          description: "Calculate, convert units, set reminders, translate text or search the web without opening anything."
        }

        Feature {
          glyph: "󰌌"
          title: "Keyboard first"
          description: "Enter opens the result, Ctrl + Enter runs the secondary action, Tab completes, Esc closes."
        }
      }

      // ------------------------------------------------------- 2 shortcut
      ColumnLayout {
        spacing: Style.space(14)

        ChordCaps {
          chrome: tour.chrome
          Layout.alignment: Qt.AlignHCenter
          Layout.topMargin: Style.space(4)
          chord: tour.shownChord
        }

        Text {
          Layout.fillWidth: true
          text: tour.chordCaption
          color: tour.owner !== "" ? tour.accent : tour.dim
          font.family: tour.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        Rectangle {
          id: recorder
          Layout.fillWidth: true
          implicitHeight: Style.space(56)
          radius: tour.rowRadius
          activeFocusOnTab: true
          readonly property bool hot: recMouse.containsMouse
          color: activeFocus || hot ? tour.chrome.fillHot : tour.chrome.fill
          border.width: tour.hairline
          border.color: activeFocus ? tour.chrome.lineFocus : hot ? tour.chrome.lineHot : tour.chrome.line

          Behavior on color { ColorAnimation { duration: 100 } }

          // Esc / Enter / Tab keep their tour meaning; everything else is a
          // chord attempt. Modifier-only presses are swallowed on purpose.
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) return
            var chord = Chord.fromEvent(event.key, event.modifiers)
            if (chord !== "") tour.selected = chord
            event.accepted = true
          }

          MouseArea {
            id: recMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: recorder.forceActiveFocus()
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(14)
            spacing: Style.space(12)

            Rectangle {
              width: Style.space(8)
              height: width
              radius: width / 2
              color: recorder.activeFocus ? tour.accent : tour.dim

              SequentialAnimation on opacity {
                running: recorder.activeFocus
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.25; duration: 650 }
                NumberAnimation { to: 1; duration: 650 }
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)

              Text {
                Layout.fillWidth: true
                text: recorder.activeFocus ? "Press your shortcut" : "Click here to record a shortcut"
                color: tour.foreground
                font.family: tour.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                Layout.fillWidth: true
                text: recorder.activeFocus
                  ? "Listening. If nothing happens, Hyprland already uses that combination."
                  : "Or pick a preset below."
                color: tour.dim
                font.family: tour.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            TextButton {
              chrome: tour.chrome
              visible: tour.selected !== ""
              text: "Clear"
              // Clear hides itself, so it must not keep the focus it may hold.
              onClicked: { tour.selected = ""; recorder.forceActiveFocus() }
            }
          }
        }

        Text {
          text: "Presets"
          color: tour.dim
          font.family: tour.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Flow {
          Layout.fillWidth: true
          Layout.topMargin: -Style.space(6)
          spacing: Style.space(8)

          Repeater {
            model: tour.presets

            Pill {
              chrome: tour.chrome
              required property string modelData
              text: modelData
              hint: tour.chipCaption(modelData)
              selected: tour.selected === modelData
              onClicked: tour.selected = modelData
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: tour.statusText !== "" || undoBtn.visible
          spacing: Style.space(12)

          Text {
            Layout.fillWidth: true
            text: tour.statusText
            color: tour.bindingState === "error" || tour.bindingState === "reloadError"
                   ? Color.urgent : tour.dim
            font.family: tour.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Pill {
            id: undoBtn
            chrome: tour.chrome
            visible: tour.bindingManaged && tour.bindingState !== "busy"
            text: tour.bindingState === "ok" || tour.previousBinding === "" ? "Undo" : "Restore " + tour.previousBinding
            onClicked: tour.revertRequested()
          }
        }
      }

      // ------------------------------------------------------- 3 sources
      ColumnLayout {
        spacing: Style.space(10)

        SettingRow {
          chrome: tour.chrome
          glyph: "󰉋"
          title: "Files and folders"
          description: "Find files in your home directory by name."
          checked: tour.draft.fileSearch === true
          onToggled: tour.set("fileSearch", !tour.draft.fileSearch)

          SubToggle {
            chrome: tour.chrome
            enabled: tour.draft.fileSearch === true
            text: "Include files in every search"
            description: "When off, files only appear after you type f, f: or a path."
            checked: tour.draft.fileSearchAlways === true
            onToggled: tour.set("fileSearchAlways", !tour.draft.fileSearchAlways)
          }
        }

        SettingRow {
          chrome: tour.chrome
          glyph: "󰅌"
          title: "Clipboard history"
          description: "Search what you copied earlier and copy it again with Enter."
          checked: tour.draft.clipboardSearch === true
          onToggled: tour.set("clipboardSearch", !tour.draft.clipboardSearch)
        }

        SettingRow {
          chrome: tour.chrome
          glyph: "󱐋"
          title: "Search suggestions"
          description: "Complete your query while you type. Queries are sent to "
            + (tour.draft.searchEngine === "kagi" ? "Kagi" : "Google")
            + ", so this is off by default."
          checked: tour.draft.webSuggestions === true
          onToggled: tour.set("webSuggestions", !tour.draft.webSuggestions)
        }

        SettingRow {
          chrome: tour.chrome
          glyph: "󰖟"
          switchable: false
          title: "Web search engine"
          description: "Where the web search result opens when you press Enter, and which provider answers search suggestions."

          trailing: ChoiceMenu {
            chrome: tour.chrome
            value: tour.draft.searchEngine || "g"
            options: Web.engineOptions()
            onChanged: function(v) { tour.set("searchEngine", v) }
          }
        }

        SettingRow {
          chrome: tour.chrome
          glyph: "󰑤"
          title: "Currency rates"
          description: "Fetch rates from Frankfurter for complete currency queries. On by default."
          checked: tour.draft.currencyRates !== false
          onToggled: tour.set("currencyRates", !tour.draft.currencyRates)
        }

        SettingRow {
          chrome: tour.chrome
          glyph: "󰑤"
          switchable: false
          title: "Default currency"
          description: currencyCodeField.valid
            ? "Type a 3-letter currency code, or leave blank. Explicit targets take priority."
            : "Enter a supported 3-letter currency code, or clear the field."

          trailing: CurrencyField {
            id: currencyCodeField
            chrome: tour.chrome
            implicitWidth: Style.space(200)
            code: tour.draft.defaultCurrency || ""
            onPicked: function(code) { tour.set("defaultCurrency", code) }
          }
        }

        SettingRow {
          chrome: tour.chrome
          glyph: "󰧐"
          title: "Learn from your choices"
          description: "Results you pick often move up over time. Nothing leaves this machine."
          checked: tour.draft.learningEnabled === true
          onToggled: tour.set("learningEnabled", !tour.draft.learningEnabled)
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
          text: "Apps, windows and commands are always included."
          color: tour.dim
          font.family: tour.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }

      // ------------------------------------------------------- 4 done
      ColumnLayout {
        spacing: Style.space(14)

        ChordCaps {
          chrome: tour.chrome
          Layout.alignment: Qt.AlignHCenter
          Layout.topMargin: Style.space(4)
          chord: tour.currentBinding
        }

        Text {
          Layout.fillWidth: true
          text: tour.currentBinding !== "" ? "opens Spotlight from anywhere"
                                           : "Set one any time with Change Spotlight Shortcut."
          color: tour.dim
          font.family: tour.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }

        GridLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(6)
          columns: 2
          columnSpacing: Style.space(12)
          rowSpacing: Style.space(8)

          Repeater {
            model: tour.examples

            // Two cells per example: the query as a keycap, then what it does.
            Item {
              required property var modelData
              Layout.fillWidth: true
              implicitHeight: cell.implicitHeight

              RowLayout {
                id: cell
                anchors { left: parent.left; right: parent.right }
                spacing: Style.space(8)

                Keycap { chrome: tour.chrome; small: true; text: parent.parent.modelData[0] }

                Text {
                  Layout.fillWidth: true
                  text: parent.parent.modelData[1]
                  color: tour.dim
                  font.family: tour.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }
    }

    // Footer
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Style.space(4)
      spacing: Style.space(12)

      Pill {
        chrome: tour.chrome
        visible: !tour.singleStep && tour.step > 0
        text: "󰁍  Back"
        onClicked: tour.back()
      }

      Item { Layout.fillWidth: true }

      PrimaryButton {
        chrome: tour.chrome
        text: tour.primaryText
        glyph: tour.step === 3 || tour.singleStep ? "󰄬" : "󰁔"
        enabled: tour.primaryEnabled
        onClicked: tour.primary()
      }
    }
  }
}
