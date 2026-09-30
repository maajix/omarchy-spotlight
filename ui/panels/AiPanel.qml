import QtQuick
import QtQuick.Layouts
import Quickshell.Io
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
  property var helperCommand: []
  property var galleryActions: ({})
  function setGalleryStatus(identity, status) {
    var next = {}, keys = Object.keys(galleryActions).filter(function(key) { return key !== identity }).slice(-15)
    keys.forEach(function(key) { next[key] = panel.galleryActions[key] })
    next[identity] = status
    galleryActions = next
  }
  function imageAction(identity, action) {
    if (galleryProcess.running || !helperCommand.length || !/^[0-9a-f]{64}$/.test(identity)
        || ["save", "apply"].indexOf(action) < 0) return
    galleryProcess.identity = identity
    galleryProcess.delivered = false
    setGalleryStatus(identity, action === "save" ? "Saving…" : "Applying…")
    galleryProcess.command = helperCommand.concat(["gallery", action, identity])
    galleryProcess.running = true
  }
  Process {
    id: galleryProcess
    property string identity: ""
    property bool delivered: false
    stdout: StdioCollector {
      onStreamFinished: {
        galleryProcess.delivered = true
        try {
          var reply = JSON.parse(text)
          panel.setGalleryStatus(galleryProcess.identity, reply.ok ? reply.status : reply.error || "Image action failed")
        } catch (error) { panel.setGalleryStatus(galleryProcess.identity, "Image action failed") }
      }
    }
    onExited: Qt.callLater(function() {
      if (!galleryProcess.delivered) panel.setGalleryStatus(galleryProcess.identity, "Image action failed")
    })
  }
  // ponytail: remember up to 32 checklists in this shell session. Add disk
  // persistence only when progress must survive a shell restart.
  property var checklistProgress: ({})
  function setChecklistProgress(id, completed) {
    var next = {}, keys = Object.keys(checklistProgress).filter(function(key) { return key !== id }).slice(-31)
    keys.forEach(function(key) { next[key] = panel.checklistProgress[key] })
    next[id] = completed.slice()
    checklistProgress = next
  }
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
        model: panel.result && panel.result.artifactWarnings ? panel.result.artifactWarnings : []
        delegate: Text {
          required property var modelData
          Layout.fillWidth: true
          text: modelData
          textFormat: Text.PlainText
          color: panel.bodyColor
          font.family: "sans-serif"
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }

      Repeater {
        model: panel.result && panel.result.artifacts ? panel.result.artifacts : []
        delegate: ArtifactHost {
          required property var modelData
          Layout.fillWidth: true
          artifact: modelData
          checklistCompleted: panel.checklistProgress[modelData.id] || []
          galleryActions: panel.galleryActions
          galleryBusy: galleryProcess.running
          onImageActionRequested: function(identity, action) { panel.imageAction(identity, action) }
          onChecklistProgressRequested: function(completed) { panel.setChecklistProgress(modelData.id, completed) }
          chrome: panel.chrome
          onOpenRequested: function(url) { panel.mapRequested(url) }
          onCopyRequested: function(value) { panel.copyRequested(value) }
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
