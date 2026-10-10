"""Exercise the production presentation animation and close lifecycle in Qt."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "Spotlight.qml").read_text()
motion = source[source.index("  property real presentationProgress:"):
                source.index("  property string query:")]
functions = "\n".join(re.search(
    r"^  function " + name + r"\([^)]*\) \{\n[\s\S]*?^  \}", source, re.M)[0]
    for name in ("close", "finishClose"))
visible = re.search(r"    visible: root.opened \|\|[^\n]+", source)[0]
focus_cleared = re.search(r"      onCleared: ([^\n]+)", source)[1]

with tempfile.TemporaryDirectory(prefix="spotlight-animation-") as directory:
    directory = Path(directory)
    (directory / "shell.qml").write_text('''import QtQuick
import QtQuick.Window
import Quickshell
ShellRoot {
  Window {
    id: root
    visible: true
    width: 400; height: 200
    property bool opened: false
    property var settings: ({reduceMotion: false})
    property bool settingsActive: false
    property string armedKey: ""
    property int cleanups: 0
    property int saves: 0
    function leaveSettingsPanel() { settingsActive = false }
    function stopQueryWork() { cleanups++ }
    function flushSettings() { saves++ }
    function dismiss() { close() }
    function check(ok, message) { if (!ok) throw new Error(message) }
''' + motion + functions + "\n    function focusCleared() { " + focus_cleared + " }\n" + '''
    Item {
      id: panel
      property bool focusPrimed: false
      width: 400; height: 200
''' + visible + '''
      Rectangle { anchors.fill: parent; color: "#333333"; opacity: root.presentationProgress }
    }
    Timer {
      interval: 20; repeat: true; running: true
      property int frame: 0
      property int cleanupsBefore: 0
      property real beforeReverse: 0
      onTriggered: {
        try {
          frame++
          root.check(root.presentationProgress >= 0 && root.presentationProgress <= 1, "Motion overshot")
          if (frame === 1) root.opened = true
          if (frame === 4) {
            root.check(panel.visible && root.presentationProgress > 0 && root.presentationProgress < 1,
              "Opening did not interpolate")
            beforeReverse = root.presentationProgress
            root.close()
            root.check(Math.abs(root.presentationProgress - beforeReverse) < 0.001, "Close jumped")
            root.check(panel.visible, "Closing unmapped the panel too early")
          }
          if (frame === 6) {
            beforeReverse = root.presentationProgress
            root.opened = true
            root.focusCleared()
            root.check(root.opened, "A stale focus-grab event dismissed the reopening panel")
            root.check(Math.abs(root.presentationProgress - beforeReverse) < 0.001, "Reopen jumped")
            cleanupsBefore = root.cleanups
          }
          if (frame === 20) {
            root.check(root.presentationProgress === 1 && panel.visible, "Reopen did not settle")
            root.check(root.cleanups === cleanupsBefore, "Interrupted close cleared the new session")
            root.settingsActive = true
            panel.focusPrimed = true
            root.focusCleared()
            root.close()
            root.check(root.saves === 1, "Settings did not flush once on dismissal")
            root.check(root.settingsActive && root.cleanups === cleanupsBefore, "Exit cleared visible content")
          }
          if (frame === 30) {
            root.check(!panel.visible && !root.settingsActive, "Close did not finish")
            root.check(root.cleanups > cleanupsBefore, "Close left query work running")
            root.settings = {reduceMotion: true}
            root.opened = true
            root.check(root.presentationProgress === 1, "Reduced motion animated opening")
            root.close()
            root.check(root.presentationProgress === 0 && !panel.visible, "Reduced motion animated closing")
            root.opened = true
            root.settings = {reduceMotion: false}
            root.close()
          }
          if (frame === 32) root.settings = {reduceMotion: true}
          if (frame === 44) {
            root.check(!panel.visible, "Changing motion preference left a closing panel mapped")
            console.log("ANIMATION_SMOKE_OK"); Qt.quit()
          }
        } catch (error) { console.error(error); Qt.quit() }
      }
    }
  }
}
''')
    (directory / "runtime").mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
               XDG_RUNTIME_DIR=str(directory / "runtime"))
    result = subprocess.run(["quickshell", "-p", str(directory / "shell.qml")],
                            env=env, capture_output=True, text=True, timeout=5)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "ANIMATION_SMOKE_OK" in output, output
    assert not any(error in output for error in ("Error:", "Unable to assign", "Binding loop")), output
    print("Opening, interrupted closing, reopening, cleanup and reduced motion passed in Qt")
