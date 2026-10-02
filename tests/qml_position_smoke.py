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
        frame++
        if (frame === 1) root.contentHeight = 36
        if (frame === 10) { displayModel.count = 0; root.contentHeight = 0 }
        if (frame === 20) { displayModel.count = 10; root.contentHeight = 1000 }
        if (frame === 30) { root.height = 1080; top = -1 }
        if (frame === 32) { root.height = 540; top = -1 }
        if (frame === 36) root.aiActive = true
        if (frame === 44) root.aiActive = false
        if (frame === 46) root.contentHeight = 36
        if (frame === 50) { console.log("POSITION_SMOKE_OK"); Qt.quit() }
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
                            env=env, capture_output=True, text=True, timeout=5)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "POSITION_SMOKE_OK" in output, output
    assert not any(error in output for error in ("Error:", "Unable to assign", "Binding loop")), output
    print("Search card top stayed fixed and settled bottom stayed onscreen on 580px, 1080p and 540px screens")
