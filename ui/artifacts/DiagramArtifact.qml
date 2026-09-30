import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"
import "../../lib/Diagram.js" as Diagram

ArtifactCard {
  id: diagramCard
  glyph: "󰕂"
  subtitle: artifact.note
  sourceUrl: artifact.sourceUrl
  retrievedAt: artifact.retrievedAt
  property int selectedEdge: 0
  onArtifactChanged: selectedEdge = 0
  readonly property var edge: artifact.edges[selectedEdge]
  function nodeLabel(id) { return artifact.nodes.filter(function(node) { return node.id === id })[0].label }
  function selectNext(delta) { selectedEdge = (selectedEdge + delta + artifact.edges.length) % artifact.edges.length }

  RowLayout {
    Layout.fillWidth: true
    ArtifactText {
      Layout.fillWidth: true
      text: "CONNECTION " + (diagramCard.selectedEdge + 1) + " OF " + diagramCard.artifact.edges.length
      color: diagramCard.mutedText
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
    }
    Pill {
      chrome: diagramCard.actionChrome
      text: "‹"
      Accessible.role: Accessible.Button
      Accessible.name: "Previous connection"
      onClicked: diagramCard.selectNext(-1)
    }
    Pill {
      chrome: diagramCard.actionChrome
      text: "›"
      Accessible.role: Accessible.Button
      Accessible.name: "Next connection"
      onClicked: diagramCard.selectNext(1)
    }
  }
  ColumnLayout {
    Layout.fillWidth: true
    spacing: 5
    ArtifactText {
      Layout.fillWidth: true
      visible: text !== ""
      text: diagramCard.edge.label
      font.weight: Font.DemiBold
    }
    ArtifactText {
      Layout.fillWidth: true
      text: diagramCard.nodeLabel(diagramCard.edge.from) + " → " + diagramCard.nodeLabel(diagramCard.edge.to)
      color: diagramCard.secondaryText
    }
  }

  Rectangle {
    id: board
    Layout.fillWidth: true
    readonly property var grid: Diagram.grid(diagramCard.artifact.nodes)
    implicitHeight: grid.rows.length * 96 + 12
    radius: 14
    color: "#18212e48"
    border.color: "#20ffffff"
    function geometry(id) {
      return Diagram.geometry(diagramCard.artifact.nodes.filter(function(node) { return node.id === id })[0], grid, width)
    }

    Canvas {
      id: links
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Connections {
        target: diagramCard
        function onSelectedEdgeChanged() { links.requestPaint() }
        function onArtifactChanged() { links.requestPaint() }
      }
      function draw(ctx, edge, selected) {
        var points = Diagram.route(board.geometry(edge.from), board.geometry(edge.to))
        ctx.globalAlpha = selected ? 1 : .18
        ctx.strokeStyle = selected ? "#b8e0ff" : "#93c9f5"
        ctx.lineWidth = selected ? 2.5 : 1.5
        ctx.beginPath(); ctx.moveTo(points[0][0], points[0][1])
        for (var i = 1; i < points.length - 1; i++) {
          var prev = points[i - 1], current = points[i], next = points[i + 1]
          var before = Math.hypot(current[0] - prev[0], current[1] - prev[1])
          var after = Math.hypot(next[0] - current[0], next[1] - current[1])
          var radius = Math.min(8, before / 2, after / 2)
          if (!radius) { ctx.lineTo(current[0], current[1]); continue }
          ctx.lineTo(current[0] + (prev[0] - current[0]) * radius / before,
            current[1] + (prev[1] - current[1]) * radius / before)
          ctx.quadraticCurveTo(current[0], current[1], current[0] + (next[0] - current[0]) * radius / after,
            current[1] + (next[1] - current[1]) * radius / after)
        }
        var end = points[points.length - 1], previous = points[points.length - 2]
        ctx.lineTo(end[0], end[1]); ctx.stroke()
        var angle = Math.atan2(end[1] - previous[1], end[0] - previous[0])
        ctx.fillStyle = ctx.strokeStyle
        ctx.beginPath(); ctx.moveTo(end[0], end[1])
        ctx.lineTo(end[0] - 8 * Math.cos(angle - .45), end[1] - 8 * Math.sin(angle - .45))
        ctx.lineTo(end[0] - 8 * Math.cos(angle + .45), end[1] - 8 * Math.sin(angle + .45))
        ctx.closePath(); ctx.fill()
      }
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.lineJoin = "round"
        diagramCard.artifact.edges.forEach(function(edge, index) {
          if (index !== diagramCard.selectedEdge) draw(ctx, edge, false)
        })
        draw(ctx, diagramCard.edge, true)
      }
    }

    Repeater {
      model: diagramCard.artifact.nodes
      delegate: Rectangle {
        id: node
        required property var modelData
        readonly property var position: board.geometry(modelData.id)
        readonly property bool selected: diagramCard.edge.from === modelData.id || diagramCard.edge.to === modelData.id
        x: position.x
        y: position.y
        width: position.w
        height: position.h
        radius: 12
        color: selected ? "#3e5e80" : "#2b4058"
        border.color: selected || activeFocus ? "#a6d6ff" : "#5c7796"
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: modelData.label + ": show outgoing connection"
        function selectOutgoing() {
          for (var i = 0; i < diagramCard.artifact.edges.length; i++) {
            if (diagramCard.artifact.edges[i].from === modelData.id) { diagramCard.selectedEdge = i; return }
          }
          for (var j = 0; j < diagramCard.artifact.edges.length; j++) {
            if (diagramCard.artifact.edges[j].to === modelData.id) { diagramCard.selectedEdge = j; return }
          }
        }
        Keys.onReturnPressed: selectOutgoing()
        Keys.onSpacePressed: selectOutgoing()
        ArtifactText {
          anchors { fill: parent; margins: 10 }
          text: node.modelData.label
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          font.weight: Font.Medium
          wrapMode: Text.Wrap
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { node.forceActiveFocus(); node.selectOutgoing() }
        }
      }
    }
  }

  Pill {
    chrome: diagramCard.actionChrome
    text: "Copy diagram"
    onClicked: diagramCard.copyRequested(diagramCard.artifact.edges.map(function(edge) {
      return diagramCard.nodeLabel(edge.from) + " → " + diagramCard.nodeLabel(edge.to) + (edge.label ? " · " + edge.label : "")
    }).join("\n"))
  }
}
