import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"
import "../../lib/ArtifactChart.js" as ChartMath

ArtifactCard {
  id: chartCard
  subtitle: artifact.note
  sourceUrl: artifact.sourceUrl
  retrievedAt: artifact.retrievedAt
  glyph: "󰄧"
  readonly property var colors: ["#8acaff", "#c0afff", "#8ae1cd", "#ffd09b", "#f9a8cb", "#e5df89", "#91b6aa", "#a9b6cc"]
  property int selected: -1
  readonly property bool donut: artifact.variant === "donut"
  readonly property var scale: ChartMath.extent(artifact.series)
  readonly property real total: artifact.series[0].values.reduce(function(a, b) { return a + b }, 0)
  readonly property int headlineIndex: selected < 0 ? artifact.labels.length - 1 : selected

  function valueText(value) { return ChartMath.format(value) + (artifact.unit ? " " + artifact.unit : "") }
  function pick(x, y) {
    if (donut) {
      var angle = Math.atan2(y - plot.height / 2, x - plot.width / 2) + Math.PI / 2
      if (angle < 0) angle += Math.PI * 2
      var sum = 0
      for (var i = 0; i < artifact.labels.length; i++) {
        sum += artifact.series[0].values[i] / total * Math.PI * 2
        if (angle <= sum) return i
      }
      return artifact.labels.length - 1
    }
    var ratio = Math.max(0, Math.min(1, (x - 52) / Math.max(1, plot.width - 66)))
    return artifact.variant === "bar" ? Math.min(artifact.labels.length - 1, Math.floor(ratio * artifact.labels.length))
      : Math.round(ratio * (artifact.labels.length - 1))
  }

  RowLayout {
    Layout.fillWidth: true
    visible: !chartCard.donut
    spacing: 10
    ArtifactText {
      text: ChartMath.format(chartCard.artifact.series[0].values[chartCard.headlineIndex])
      font.pixelSize: 42
      font.weight: Font.Light
      color: "#ffffff"
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 3
      ArtifactText {
        Layout.fillWidth: true
        text: chartCard.artifact.unit || chartCard.artifact.series[0].label
        font.weight: Font.Medium
      }
      ArtifactText {
        Layout.fillWidth: true
        text: chartCard.artifact.labels[chartCard.headlineIndex]
          + (chartCard.artifact.unit ? " · " + chartCard.artifact.series[0].label : "")
        color: chartCard.secondaryText
        font.pixelSize: Style.font.body
      }
    }
  }

  Rectangle {
    id: plot
    Layout.fillWidth: true
    implicitHeight: 236
    radius: 14
    color: "#18212e48"
    border.color: "#20ffffff"
    activeFocusOnTab: true
    Accessible.role: Accessible.Chart
    Accessible.name: chartCard.artifact.title
    Keys.onLeftPressed: chartCard.selected = Math.max(0, chartCard.selected - 1)
    Keys.onRightPressed: chartCard.selected = Math.min(chartCard.artifact.labels.length - 1, chartCard.selected + 1)

    Canvas {
      id: graph
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Connections { target: chartCard; function onSelectedChanged() { graph.requestPaint() } }
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var data = chartCard.artifact, count = data.labels.length
        if (chartCard.donut) {
          var radius = Math.min(width, height) / 2 - 20, angle = -Math.PI / 2
          ctx.lineWidth = 24
          ctx.lineCap = "round"
          data.series[0].values.forEach(function(value, index) {
            var next = angle + value / chartCard.total * Math.PI * 2
            if (value > 0) {
              ctx.strokeStyle = chartCard.colors[index]
              ctx.globalAlpha = chartCard.selected < 0 || chartCard.selected === index ? 1 : 0.4
              ctx.beginPath()
              ctx.arc(width / 2, height / 2, radius, angle + 0.025, Math.max(angle + 0.025, next - 0.025))
              ctx.stroke()
            }
            angle = next
          })
          return
        }
        var left = 52, right = width - 14, top = 12, bottom = height - 38
        var range = chartCard.scale.high - chartCard.scale.low
        function y(value) { return bottom - (value - chartCard.scale.low) / range * (bottom - top) }
        ctx.font = "12px sans-serif"
        ctx.textBaseline = "middle"
        for (var tick = 0; tick <= 4; tick++) {
          var value = chartCard.scale.low + range * tick / 4, row = y(value)
          ctx.strokeStyle = "#20ffffff"
          ctx.lineWidth = 1
          ctx.beginPath(); ctx.moveTo(left, row); ctx.lineTo(right, row); ctx.stroke()
          ctx.fillStyle = "#a5bdd7"
          ctx.textAlign = "right"
          ctx.fillText(ChartMath.format(value), left - 9, row)
        }
        var step = (right - left) / (data.variant === "bar" ? count : count - 1)
        data.series.forEach(function(entry, seriesIndex) {
          ctx.strokeStyle = chartCard.colors[seriesIndex]
          ctx.fillStyle = chartCard.colors[seriesIndex]
          ctx.lineWidth = 2.5
          if (data.variant === "bar") {
            var barWidth = step * 0.68 / data.series.length
            entry.values.forEach(function(value, index) {
              var x = left + index * step + step * 0.16 + seriesIndex * barWidth
              ctx.globalAlpha = chartCard.selected < 0 || chartCard.selected === index ? 1 : 0.45
              var w = Math.max(1, barWidth - 4), h = Math.max(1, Math.abs(y(value) - y(0)))
              var by = Math.min(y(value), y(0)), r = Math.min(5, w / 2, h / 2)
              ctx.beginPath()
              ctx.moveTo(x + r, by)
              ctx.lineTo(x + w - r, by); ctx.quadraticCurveTo(x + w, by, x + w, by + r)
              ctx.lineTo(x + w, by + h - r); ctx.quadraticCurveTo(x + w, by + h, x + w - r, by + h)
              ctx.lineTo(x + r, by + h); ctx.quadraticCurveTo(x, by + h, x, by + h - r)
              ctx.lineTo(x, by + r); ctx.quadraticCurveTo(x, by, x + r, by)
              ctx.closePath(); ctx.fill()
            })
          } else {
            if (seriesIndex === 0) {
              var wash = ctx.createLinearGradient(0, top, 0, bottom)
              wash.addColorStop(0, "rgba(138,202,255,0.24)")
              wash.addColorStop(1, "rgba(138,202,255,0.02)")
              ctx.fillStyle = wash
              ctx.beginPath(); ctx.moveTo(left, y(0))
              entry.values.forEach(function(value, index) { ctx.lineTo(left + index * step, y(value)) })
              ctx.lineTo(left + (count - 1) * step, y(0)); ctx.closePath(); ctx.fill()
              ctx.fillStyle = chartCard.colors[seriesIndex]
            }
            ctx.lineWidth = 3
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.beginPath()
            entry.values.forEach(function(value, index) {
              if (index === 0) ctx.moveTo(left, y(value))
              else ctx.lineTo(left + index * step, y(value))
            })
            ctx.stroke()
            entry.values.forEach(function(value, index) {
              ctx.beginPath(); ctx.arc(left + index * step, y(value), chartCard.selected === index ? 5 : 3, 0, Math.PI * 2); ctx.fill()
            })
          }
          ctx.globalAlpha = 1
        })
        ctx.fillStyle = "#a5bdd7"
        ctx.textAlign = "center"
        data.labels.forEach(function(label, index) {
          if (count > 8 && index !== count - 1 && index % Math.ceil(count / 6) !== 0) return
          var x = left + (data.variant === "bar" ? index + 0.5 : index) * step
          ctx.fillText(label.length > 10 ? label.slice(0, 9) + "…" : label, x, height - 15)
        })
      }
    }

    ColumnLayout {
      anchors.centerIn: parent
      visible: chartCard.donut
      spacing: 3
      ArtifactText {
        Layout.alignment: Qt.AlignHCenter
        text: chartCard.selected < 0 ? chartCard.valueText(chartCard.total)
          : chartCard.valueText(chartCard.artifact.series[0].values[chartCard.selected])
        font.pixelSize: 34
        font.weight: Font.Light
      }
      ArtifactText {
        Layout.alignment: Qt.AlignHCenter
        text: chartCard.selected < 0 ? "Total" : Math.round(chartCard.artifact.series[0].values[chartCard.selected] / chartCard.total * 100) + "%"
        color: chartCard.secondaryText
      }
    }
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onPositionChanged: function(mouse) { chartCard.selected = chartCard.pick(mouse.x, mouse.y) }
      onExited: chartCard.selected = -1
      onClicked: function(mouse) { plot.forceActiveFocus(); chartCard.selected = chartCard.pick(mouse.x, mouse.y) }
    }
  }

  Flow {
    Layout.fillWidth: true
    spacing: 16
    Repeater {
      model: chartCard.donut ? chartCard.artifact.labels : chartCard.artifact.series
      delegate: Row {
        required property var modelData
        required property int index
        spacing: 6
        Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: chartCard.colors[parent.index] }
        ArtifactText {
          text: chartCard.donut ? modelData + " · " + chartCard.valueText(chartCard.artifact.series[0].values[index]) : modelData.label
          font.pixelSize: Style.font.caption + 1
        }
      }
    }
  }

  ArtifactText {
    Layout.fillWidth: true
    text: chartCard.selected < 0 ? "Hover or use ← → for exact values"
      : chartCard.artifact.labels[chartCard.selected] + "  ·  " + chartCard.artifact.series.map(function(entry) {
        return entry.label + ": " + String(entry.values[chartCard.selected]) + (chartCard.artifact.unit ? " " + chartCard.artifact.unit : "")
      }).join("   ·   ")
    color: chartCard.selected < 0 ? chartCard.mutedText : "#d8ecff"
    font.pixelSize: Style.font.body
  }
}
