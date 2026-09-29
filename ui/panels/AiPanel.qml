import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"
import "../artifacts"
import "../../lib/AiMarkdown.js" as AiMarkdown

Item {
  id: panel
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool busy: false
  property string error: ""
  property string progress: ""
  property var result: null
  signal copyRequested(string value)
  signal mapRequested(string url)
  signal backRequested()
  readonly property var sections: AiMarkdown.split(panel.result ? panel.result.text : "")
  readonly property real scrollY: scroll.contentY
  property bool restoringScroll: false
  property real restoreTarget: 0
  onResultChanged: if (panel.result) scroll.contentY = 0

  readonly property SpotlightPalette chrome: SpotlightPalette {
    foreground: panel.foreground
    accent: panel.accent
    fontFamily: panel.fontFamily
  }
  readonly property color bodyColor: {
    var bg = Color.menu.background
    return bg.r * 0.21 + bg.g * 0.72 + bg.b * 0.07 < 0.5 ? "#f2f0ed" : "#242225"
  }

  function focusFirst() { backButton.forceActiveFocus() }
  function scrollBy(amount) {
    scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, scroll.contentY + amount))
  }
  function restoreScroll(position) {
    panel.restoringScroll = true
    panel.restoreTarget = position
    restoreTimer.restart()
  }
  Keys.onEscapePressed: panel.backRequested()

  Timer {
    id: restoreTimer
    interval: 120
    onTriggered: {
      if (panel.result)
        scroll.contentY = Math.max(0, Math.min(panel.restoreTarget, scroll.contentHeight - scroll.height))
      panel.restoringScroll = false
    }
  }

  Flickable {
    id: scroll
    anchors.fill: parent
    anchors.margins: Style.space(18)
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    property real previousHeight: 0
    onContentHeightChanged: {
      var atBottom = contentY >= Math.max(0, previousHeight - height) - Style.space(24)
      previousHeight = contentHeight
      if (panel.restoringScroll && panel.result) restoreTimer.restart()
      if (panel.busy && atBottom) Qt.callLater(function() { scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height) })
    }

    ColumnLayout {
      id: content
      width: scroll.width
      spacing: Style.space(14)

      TextButton {
        id: backButton
        chrome: panel.chrome
        text: "← Results"
        onClicked: panel.backRequested()
      }

      Text {
        Layout.fillWidth: true
        text: panel.busy ? "THINKING" : "ERROR"
        visible: panel.busy || panel.error !== ""
        color: panel.busy ? panel.accent : Color.urgent
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        Layout.fillWidth: true
        text: panel.busy ? (panel.progress || "Starting…") : panel.error
        visible: panel.busy || panel.error !== ""
        color: panel.error ? Color.urgent : panel.bodyColor
        font.family: "sans-serif"
        font.pixelSize: Style.font.body + 1
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        visible: panel.result && panel.result.text !== ""
        Text {
          Layout.fillWidth: true
          text: "ANSWER"
          color: panel.accent
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        PrimaryButton {
          chrome: panel.chrome
          text: "Copy answer"
          glyph: "󰆏"
          implicitHeight: Style.space(29)
          onClicked: panel.copyRequested(panel.result.text)
        }
      }

      Repeater {
        model: panel.sections
        delegate: ColumnLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 0

          TextEdit {
            Layout.fillWidth: true
            Layout.preferredHeight: contentHeight
            visible: modelData.type === "markdown"
            text: visible ? AiMarkdown.highlightInlineCode(modelData.text) : ""
            textFormat: TextEdit.MarkdownText
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            color: panel.bodyColor
            font.family: "sans-serif"
            font.pixelSize: Style.font.body + 1
            onLinkActivated: function(link) {
              if (/^https?:\/\//i.test(link)) panel.mapRequested(link)
            }
          }

          CodeCard {
            Layout.fillWidth: true
            visible: modelData.type === "code"
            chrome: panel.chrome
            code: visible ? modelData.text : ""
            label: modelData.language || "code"
            onCopyRequested: function(value) { panel.copyRequested(value) }
          }
        }
      }

      Repeater {
        model: panel.result && panel.result.artifacts ? panel.result.artifacts : []
        delegate: ArtifactHost {
          required property var modelData
          Layout.fillWidth: true
          artifact: modelData
          chrome: panel.chrome
          onOpenRequested: function(url) { panel.mapRequested(url) }
        }
      }

      Repeater {
        model: panel.result ? panel.result.commands : []
        delegate: ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(7)
          required property var modelData
          required property int index

          Text {
            Layout.fillWidth: true
            text: "COMMAND " + (index + 1)
            textFormat: Text.PlainText
            color: panel.accent
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: modelData.explanation
            textFormat: Text.PlainText
            color: panel.bodyColor
            font.family: "sans-serif"
            font.pixelSize: Style.font.body + 1
            wrapMode: Text.WordWrap
          }

          CodeCard {
            Layout.fillWidth: true
            chrome: panel.chrome
            code: modelData.command
            label: "terminal"
            onCopyRequested: function(value) { panel.copyRequested(value) }
          }
        }
      }
    }
  }
}
