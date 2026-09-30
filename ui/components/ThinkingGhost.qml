import QtQuick

// Decorative dotted mascot. Paint once; floating and breathing animate its texture.
Item {
  id: ghost
  property color tint: "#9bd2ff"
  property real drift: 0
  property real breath: 1
  Accessible.ignored: true
  transform: Translate { y: ghost.drift }
  SequentialAnimation on drift {
    running: ghost.visible
    loops: Animation.Infinite
    NumberAnimation { to: -8; duration: 2400; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0; duration: 2400; easing.type: Easing.InOutSine }
  }
  SequentialAnimation on breath {
    running: ghost.visible
    loops: Animation.Infinite
    NumberAnimation { to: 0.65; duration: 2400; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 2400; easing.type: Easing.InOutSine }
  }
  onTintChanged: dots.requestPaint()
  Canvas {
    id: dots
    anchors.fill: parent
    opacity: ghost.breath
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.scale(width / 220, height / 240)
      ctx.fillStyle = ghost.tint
      for (var y = 25; y < 210; y += 5) {
        for (var x = 25; x < 200; x += 5) {
          var head = y <= 105 && Math.pow(x - 110, 2) + Math.pow(y - 105, 2) <= 6400
          var body = y > 105 && x >= 30 && x <= 190 && y <= 190 + 10 * Math.cos((x - 30) * Math.PI / 40)
          var eyes = Math.pow((x - 85) / 8, 2) + Math.pow((y - 107) / 13, 2) < 1
            || Math.pow((x - 135) / 8, 2) + Math.pow((y - 107) / 13, 2) < 1
          var mouth = Math.pow((x - 110) / 6, 2) + Math.pow((y - 139) / 4, 2) < 1
          if ((head || body) && !eyes && !mouth) {
            ctx.beginPath()
            ctx.arc(x, y, 1.05, 0, Math.PI * 2)
            ctx.fill()
          }
        }
      }
    }
  }
}
