import QtQuick
import Quickshell.Wayland
import qs.Commons

// Paints the blocks lib/Preview.js builds for the selected row. It holds no
// state of its own beyond scroll position: Spotlight.qml decides what to show
// and runs any helper call, and this only draws the result.
Item {
  id: pane
  property var preview: null
  property string folderPath: ""
  property var folderRows: []
  property int folderIndex: 0

  Column {
    anchors.fill: parent
    anchors.margins: pane.gutter
    spacing: Style.space(10)
    visible: pane.folderPath !== ""
    Text {
      width: parent.width
      text: pane.folderPath
      textFormat: Text.PlainText
      color: pane.accent
      font.family: pane.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }
    ListView {
      id: folderList
      width: parent.width
      height: parent.height - y
      clip: true
      model: pane.folderRows
      currentIndex: pane.folderIndex
      onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
      delegate: Rectangle {
        required property var modelData
        required property int index
        width: folderList.width
        height: Style.space(30)
        radius: Style.space(6)
        color: index === pane.folderIndex ? Util.alpha(pane.accent, 0.16) : "transparent"
        Text {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          text: (modelData.icon || "") + "  " + modelData.title
          textFormat: Text.PlainText
          color: index === pane.folderIndex ? pane.accent : pane.foreground
          font.family: pane.fontFamily
          font.pixelSize: Style.font.subtitle
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }
      }
    }
  }
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int gutter: Style.space(20)
  // A window capture only runs while the pane is on screen.
  property bool live: false

  readonly property var blocks: pane.preview && pane.preview.blocks ? pane.preview.blocks : []

  onPreviewChanged: flick.contentY = 0

  Flickable {
    id: flick
    visible: pane.folderPath === ""
    anchors.fill: parent
    anchors.leftMargin: pane.gutter
    anchors.rightMargin: pane.gutter
    contentWidth: width
    contentHeight: column.implicitHeight + Style.space(28)
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: column
      objectName: "preview-blocks"
      y: Style.space(14)
      width: flick.width
      spacing: Style.space(10)

      Repeater {
        model: pane.blocks

        delegate: Loader {
          required property var modelData
          width: column.width
          sourceComponent: modelData.type === "label" ? labelBlock
            : modelData.type === "hero" ? heroBlock
            : modelData.type === "lines" ? linesBlock
            : modelData.type === "fields" ? fieldsBlock
            : modelData.type === "text" ? textBlock
            : modelData.type === "image" ? imageBlock
            : modelData.type === "window" ? windowBlock
            : modelData.type === "meta" ? metaBlock
            : modelData.type === "status" ? statusBlock : null
          onLoaded: item.block = modelData
        }
      }
    }
  }

  Component {
    id: labelBlock
    Text {
      property var block: ({})
      text: String(block.text || "")
      textFormat: Text.PlainText
      color: pane.foreground
      opacity: 0.5
      font.family: pane.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Component {
    id: heroBlock
    Text {
      property var block: ({})
      text: String(block.text || "")
      textFormat: Text.PlainText
      color: pane.accent
      font.family: block.mono ? Style.font.family : pane.fontFamily
      font.pixelSize: block.name ? Math.round(Style.font.display * 0.75) : Style.font.display
      font.weight: Font.DemiBold
      wrapMode: block.name ? Text.NoWrap : Text.WrapAnywhere
      maximumLineCount: block.name ? 1 : 3
      elide: block.name ? Text.ElideMiddle : Text.ElideRight
    }
  }

  Component {
    id: linesBlock
    Column {
      property var block: ({})
      spacing: Style.space(6)
      Repeater {
        model: block.items || []
        delegate: Row {
          required property var modelData
          spacing: Style.space(8)
          width: parent ? parent.width : 0
          Text {
            id: lineText
            text: String(modelData.text || "")
            textFormat: Text.PlainText
            color: pane.foreground
            font.family: block.mono ? Style.font.family : pane.fontFamily
            font.pixelSize: Style.font.subtitle
            elide: Text.ElideRight
            width: Math.min(implicitWidth, parent.width - noteText.width - Style.space(8))
          }
          Text {
            id: noteText
            text: String(modelData.note || "")
            visible: text.length > 0
            textFormat: Text.PlainText
            color: pane.foreground
            opacity: 0.42
            font.family: pane.fontFamily
            font.pixelSize: Style.font.caption
            anchors.baseline: lineText.baseline
          }
        }
      }
    }
  }

  Component {
    id: fieldsBlock
    Column {
      property var block: ({})
      spacing: Style.space(5)
      topPadding: Style.space(4)
      Repeater {
        model: block.items || []
        delegate: Row {
          required property var modelData
          spacing: Style.space(10)
          width: parent ? parent.width : 0
          Text {
            id: fieldLabel
            text: String(modelData.label || "")
            textFormat: Text.PlainText
            color: pane.foreground
            opacity: 0.45
            font.family: pane.fontFamily
            font.pixelSize: Style.font.caption
            width: Math.round(parent.width * 0.3)
            elide: Text.ElideRight
          }
          Text {
            text: String(modelData.value || "")
            textFormat: Text.PlainText
            color: pane.foreground
            font.family: modelData.mono ? Style.font.family : pane.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width - fieldLabel.width - parent.spacing
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
            anchors.baseline: fieldLabel.baseline
          }
        }
      }
    }
  }

  Component {
    id: textBlock
    Rectangle {
      property var block: ({})
      implicitHeight: excerpt.implicitHeight + Style.space(16)
      radius: Style.space(6)
      color: block.mono ? Util.alpha(pane.foreground, 0.05) : "transparent"
      Text {
        id: excerpt
        x: parent.block.mono ? Style.space(10) : 0
        y: parent.block.mono ? Style.space(8) : 0
        width: parent.width - x * 2
        text: String(parent.block.text || "")
        textFormat: Text.PlainText
        color: pane.foreground
        opacity: parent.block.mono ? 0.85 : 0.7
        font.family: parent.block.mono ? Style.font.family : pane.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: parent.block.mono ? Text.WrapAnywhere : Text.Wrap
        maximumLineCount: 40
        elide: Text.ElideRight
      }
    }
  }

  Component {
    id: imageBlock
    Item {
      property var block: ({})
      readonly property bool icon: block.icon === true
      // A missing app icon is not worth a message; the name below says enough.
      visible: !(icon && picture.status === Image.Error)
      implicitHeight: !visible ? 0 : icon ? Style.space(56)
        : (picture.status === Image.Ready && picture.implicitWidth > 0
          ? Math.min(Style.space(220), width * picture.implicitHeight / picture.implicitWidth)
          : Style.space(120))
      Image {
        id: picture
        anchors.left: parent.left
        width: parent.icon ? Style.space(56) : parent.width
        height: parent.height
        source: String(parent.block.source || "")
        fillMode: Image.PreserveAspectFit
        horizontalAlignment: Image.AlignLeft
        asynchronous: true
        // Decoding is bounded by the pane, not by the file.
        sourceSize.width: Math.round(pane.width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(Style.space(220) * Screen.devicePixelRatio)
      }
      Text {
        anchors.centerIn: parent
        visible: picture.status === Image.Error
        text: "Image could not be loaded"
        textFormat: Text.PlainText
        color: pane.foreground
        opacity: 0.4
        font.family: pane.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Component {
    id: windowBlock
    Rectangle {
      property var block: ({})
      readonly property real aspect: capture.hasContent && capture.sourceSize.width > 0
        ? capture.sourceSize.height / capture.sourceSize.width : 0.6
      implicitHeight: Math.min(Style.space(140), width * aspect)
      radius: Style.space(6)
      color: Util.alpha(pane.foreground, 0.05)
      clip: true
      ScreencopyView {
        id: capture
        anchors.fill: parent
        captureSource: parent.block.toplevel || null
        live: pane.live
        paintCursor: false
        constraintSize: Qt.size(width, height)
      }
      Text {
        anchors.centerIn: parent
        visible: !capture.hasContent
        text: "No preview"
        textFormat: Text.PlainText
        color: pane.foreground
        opacity: 0.4
        font.family: pane.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Component {
    id: metaBlock
    Text {
      property var block: ({})
      topPadding: Style.space(4)
      text: String(block.text || "")
      textFormat: Text.PlainText
      color: pane.foreground
      opacity: 0.45
      font.family: pane.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WrapAnywhere
      maximumLineCount: 4
      elide: Text.ElideRight
    }
  }

  Component {
    id: statusBlock
    Text {
      property var block: ({})
      text: String(block.text || "")
      textFormat: Text.PlainText
      color: pane.foreground
      opacity: 0.4
      font.family: pane.fontFamily
      font.pixelSize: Style.font.caption
      font.italic: true
    }
  }
}
