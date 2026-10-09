"""Check the real search card geometry: python3 tests/qml_position_smoke.py."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / "Spotlight.qml").read_text()
geometry = source.split("      id: card\n", 1)[1].split("      radius:", 1)[0]
dimensions = "\n".join(re.findall(
    r"^  readonly property int (?:maxCardHeight|searchHeight|footerHeight|hairline|listPadding|maxListHeight):[^\n]*(?:\n    [^\n]+)*",
    source, re.M))

with tempfile.TemporaryDirectory(prefix="spotlight-position-") as directory:
    directory = Path(directory)
    qml = '''import QtQuick
import Quickshell
ShellRoot {
  Item {
    id: root
    width: 1920; height: 580
    property bool tourActive: false
    property bool settingsActive: false
    property bool aiActive: false
    property int contentHeight: 456
    property var settings: ({ verticalPosition: 0 })
    ''' + dimensions + '''
    QtObject { id: displayModel; property int count: 10 }
    Item {
      id: panel
      anchors.fill: parent
      Rectangle {
        id: card
        ''' + geometry + '''
        Behavior on height { NumberAnimation { id: heightAnim; duration: 110 } }
      }
    }
    Timer {
      property int frame: 0
      property real top: -1
      property var positions: [0, 25, 50, 75, 100]
      property int positionIndex: 0
      interval: 16; repeat: true; running: true
      onTriggered: {
        try {
        if (top < 0) top = card.y
        if (Math.abs(card.y - top) > 0.5) throw new Error("Search card top moved")
        if (card.y < 0) throw new Error("Search card top is offscreen")
        if (!heightAnim.running && card.y + card.height > panel.height + 0.5)
          throw new Error("Search card bottom is offscreen")
        if (Math.abs(card.x - (panel.width - card.width) / 2) > 0.5)
          throw new Error("Search card is not horizontally centered")
        var position = root.settings.verticalPosition
        var defaultTop = Math.max(24, (panel.height - root.maxCardHeight) / 2)
        if (position === 50 && Math.abs(card.y - defaultTop) > 0.5)
          throw new Error("Default placement changed")
        if (position === 0 && Math.abs(card.y - 24) > 0.5)
          throw new Error("Top placement did not reach the screen margin")
        if (panel.height > root.maxCardHeight + 48) {
          if (position < 50 && card.y >= defaultTop)
            throw new Error("Higher placement did not move the card up")
          if (position > 50 && card.y <= defaultTop)
            throw new Error("Lower placement did not move the card down")
          if (position === 100 && Math.abs(card.y + root.maxCardHeight - (panel.height - 24)) > 0.5)
            throw new Error("Bottom placement did not leave room for the expanded card")
        }
        frame++
        if (frame === 1) root.contentHeight = 36
        if (frame === 10) { displayModel.count = 0; root.contentHeight = 0 }
        if (frame === 20) { displayModel.count = 10; root.contentHeight = 1000 }
        if (frame === 30) { root.height = 1080; top = -1 }
        if (frame === 40) { root.height = 540; top = -1 }
        if (frame === 44) root.aiActive = true
        if (frame === 52) root.aiActive = false
        if (frame === 54) root.contentHeight = 36
        if (frame === 60) {
          positionIndex++
          if (positionIndex === positions.length) { console.log("POSITION_SMOKE_OK"); Qt.quit() }
          else {
            root.settings = ({ verticalPosition: positions[positionIndex] })
            root.height = 580
            root.contentHeight = 456
            frame = 0
            top = -1
          }
        }
        } catch (error) { console.error(error); Qt.quit() }
      }
    }
  }
}
'''
    qml = re.sub(r"Style.space\((\d+)\)", r"\1", qml).replace("Style.spacing.hairline", "1")
    (directory / "shell.qml").write_text(qml)
    (directory / "runtime").mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
               XDG_RUNTIME_DIR=str(directory / "runtime"))
    result = subprocess.run(["quickshell", "-p", str(directory / "shell.qml")],
                            env=env, capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "POSITION_SMOKE_OK" in output, output
    assert not any(error in output for error in ("Error:", "Unable to assign", "Binding loop")), output
    print("All five placements kept the search field fixed and card onscreen at 580px, 1080p and 540px; 50% preserved the default")
