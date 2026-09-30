import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

ArtifactCard {
  id: diagramCard
  glyph: "󰕂"
  subtitle: artifact.note
  sourceUrl: artifact.sourceUrl
  retrievedAt: artifact.retrievedAt

  // ponytail: a bounded provider-arranged grid covers simple flows. Add a
  // graph-layout engine only if diagrams need more than three columns.
  Rectangle {
    id: board
    Layout.fillWidth: true
    readonly property int columns: 1 + Math.max.apply(null, diagramCard.artifact.nodes.map(function(node) { return node.column }))
    readonly property int rows: 1 + Math.max.apply(null, diagramCard.artifact.nodes.map(function(node) { return node.row }))
    readonly property real nodeWidth: (width - 40 - (columns - 1) * 44) / columns
    readonly property real nodeHeight: Style.space(70)
    readonly property real rowHeight: nodeHeight + Style.space(50)
    implicitHeight: rows * rowHeight + 4
    radius: 14
    color: "#18212e48"
    border.color: "#20ffffff"

    function geometry(id) {
      var node = diagramCard.artifact.nodes.filter(function(node) { return node.id === id })[0]
      return { x: 20 + node.column * (nodeWidth + 44), y: 24 + node.row * rowHeight,
        w: nodeWidth, h: nodeHeight, column: node.column, row: node.row }
    }

    Canvas {
      id: links
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.font = "11px sans-serif"
        ctx.lineJoin = "round"
        diagramCard.artifact.edges.forEach(function(edge) {
          var a = board.geometry(edge.from), b = board.geometry(edge.to), points
          if (a.column === b.column) {
            var down = a.row < b.row
            var ay = down ? a.y + a.h : a.y, by = down ? b.y : b.y + b.h
            if (Math.abs(a.row - b.row) === 1) {
              points = [[a.x + a.w / 2, ay], [b.x + b.w / 2, by]]
            } else {
              var outside = a.x + a.w + 16
              points = [[a.x + a.w, a.y + a.h / 2], [outside, a.y + a.h / 2],
                [outside, b.y + b.h / 2], [b.x + b.w, b.y + b.h / 2]]
            }
          } else {
            var right = a.column < b.column
            var ax = right ? a.x + a.w : a.x, bx = right ? b.x : b.x + b.w
            var middle = (ax + bx) / 2
            points = [[ax, a.y + a.h / 2], [middle, a.y + a.h / 2],
              [middle, b.y + b.h / 2], [bx, b.y + b.h / 2]]
          }
          ctx.strokeStyle = "#93c9f5"
          ctx.lineWidth = 1.5
          ctx.beginPath(); ctx.moveTo(points[0][0], points[0][1])
          points.slice(1).forEach(function(point) { ctx.lineTo(point[0], point[1]) })
          ctx.stroke()
          var end = points[points.length - 1], previous = points[points.length - 2]
          var angle = Math.atan2(end[1] - previous[1], end[0] - previous[0])
          ctx.fillStyle = "#93c9f5"
          ctx.beginPath(); ctx.moveTo(end[0], end[1])
          ctx.lineTo(end[0] - 7 * Math.cos(angle - .45), end[1] - 7 * Math.sin(angle - .45))
          ctx.lineTo(end[0] - 7 * Math.cos(angle + .45), end[1] - 7 * Math.sin(angle + .45))
          ctx.closePath(); ctx.fill()
          if (edge.label) {
            var mid = points[Math.floor(points.length / 2)]
            var x = points.length === 2 ? (points[0][0] + end[0]) / 2 : mid[0]
            var y = points.length === 2 ? (points[0][1] + end[1]) / 2 : (points[1][1] + points[2][1]) / 2
            var labelWidth = ctx.measureText(edge.label).width + 12
            ctx.fillStyle = "#263d57"
            ctx.fillRect(x - labelWidth / 2, y - 9, labelWidth, 18)
            ctx.fillStyle = "#c4d5e8"
            ctx.textAlign = "center"; ctx.textBaseline = "middle"
            ctx.fillText(edge.label, x, y)
          }
        })
      }
    }

    Repeater {
      model: diagramCard.artifact.nodes
      delegate: Rectangle {
        required property var modelData
        readonly property var position: board.geometry(modelData.id)
        x: position.x
        y: position.y
        width: position.w
        height: position.h
        radius: 12
        color: "#34506f"
        border.color: "#789dc7"
        Accessible.role: Accessible.StaticText
        Accessible.name: modelData.label
        ArtifactText {
          anchors { fill: parent; margins: 12 }
          text: parent.modelData.label
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          font.weight: Font.Medium
          wrapMode: Text.Wrap
        }
      }
    }
  }

  Pill {
    chrome: diagramCard.actionChrome
    text: "Copy diagram"
    onClicked: diagramCard.copyRequested(diagramCard.artifact.edges.map(function(edge) {
      function label(id) { return diagramCard.artifact.nodes.filter(function(node) { return node.id === id })[0].label }
      return label(edge.from) + " → " + label(edge.to) + (edge.label ? " · " + edge.label : "")
    }).join("\n"))
  }
}
