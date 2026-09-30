"""Compile and lay out all fixture cards using the installed Quickshell runtime.

Run: python3 tests/qml_artifacts_smoke.py
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
fixtures = json.loads((ROOT / "tests/artifact-fixtures.json").read_text())
with tempfile.TemporaryDirectory(prefix="spotlight-qml-check-") as directory:
    directory = Path(directory)
    (directory / "Commons").symlink_to("/usr/share/omarchy/shell/Commons")
    (directory / "ui").symlink_to(ROOT / "ui")
    (directory / "lib").symlink_to(ROOT / "lib")
    (directory / "shell.qml").write_text('''import Quickshell
import QtQuick
import QtQuick.Window
import "ui/artifacts"
import "ui/components"
import "ui/panels"
ShellRoot {
  id: root
  property SpotlightPalette chrome: SpotlightPalette {}
  function checklist(item) {
    if (typeof item.toggleItem === "function") return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = checklist(children[i])
      if (found) return found
    }
    return null
  }
  function checkComparisonRows(item, host, positions) {
    if (typeof item.selectNext === "function") {
      item.selectNext(-1)
      if (item.selectedEdge !== item.artifact.edges.length - 1) throw new Error("Diagram previous failed")
      item.selectNext(1)
      if (item.selectedEdge !== 0) throw new Error("Diagram next failed")
      item.selectNext(1)
      if (item.edge.from !== item.artifact.edges[1].from || item.edge.to !== item.artifact.edges[1].to) throw new Error("Diagram caption did not update")
      item.selectNext(-1)
    }
    var name = item.objectName || ""
    if (name.indexOf("comparison-cell-") === 0) {
      var parts = name.split("-")
      var key = parts.slice(0, -1).join("-")
      var y = item.mapToItem(host, 0, 0).y
      if (positions[key] !== undefined && Math.abs(positions[key] - y) > 0.5)
        throw new Error("Comparison row is misaligned: " + name)
      positions[key] = y
    }
    var children = item.children || []
    for (var i = 0; i < children.length; i++) checkComparisonRows(children[i], host, positions)
  }
  Window {
    width: 714
    height: 900
    visible: true
    Repeater {
      id: cards
      model: ''' + json.dumps(fixtures) + '''
      delegate: ArtifactHost {
        required property var modelData
        width: 714
        artifact: modelData
        chrome: root.chrome
      }
    }
    AiPanel {
      id: probe
      width: 714
      height: 700
      visible: false
      result: {"kind": "answer", "text": "", "commands": [], "artifacts": [{"type": "checklist", "id": "fixture-migration", "title": "Server migration", "note": "Suggested preparation. Check off tasks as you finish them.", "sourceUrl": "", "retrievedAt": "", "items": [{"title": "Verify backups", "description": "Create a fresh backup and test restoring a small file."}, {"title": "Plan the maintenance window", "description": "Notify users and record the expected downtime."}, {"title": "Prepare rollback", "description": "Keep the old server available until verification is complete."}]}]}
    }
    Timer {
      property int stage: 0
      property var saved: null
      interval: 100
      repeat: true
      running: true
      onTriggered: {
        for (var i = 0; i < cards.count; i++) {
          var height = cards.itemAt(i).implicitHeight
          if (!isFinite(height) || height <= 0) throw new Error("Card failed to lay out: " + i)
          if (["comparison", "diagram"].indexOf(cards.itemAt(i).artifact.type) >= 0)
            root.checkComparisonRows(cards.itemAt(i), cards.itemAt(i), {})
        }
        if (stage === 0) {
          var taskCard = root.checklist(probe)
          if (!taskCard) throw new Error("Checklist not rendered in AI panel")
          taskCard.toggleItem(0)
          if (taskCard.completed.indexOf(0) < 0 || taskCard.copyText().indexOf("[x]") < 0)
            throw new Error("Checklist toggle/copy failed")
          saved = probe.result
          probe.result = null // Spotlight closes and destroys its result delegates.
          stage = 1
        } else if (stage === 1) {
          if (root.checklist(probe)) throw new Error("Checklist delegate was not destroyed")
          probe.result = saved // Reopening restores the saved AI result.
          stage = 2
        } else {
          var restored = root.checklist(probe)
          if (!restored || restored.completed.indexOf(0) < 0) throw new Error("Checklist progress was lost on reopen")
          restored.toggleItem(0)
          if (restored.completed.length) throw new Error("Checklist uncheck failed")
          restored.toggleItem(1)
          restored.progressRequested([])
          if (restored.completed.length) throw new Error("Checklist reset failed")
          for (var n = 0; n < 40; n++) probe.setChecklistProgress("fixture-" + n, [0])
          if (Object.keys(probe.checklistProgress).length !== 32) throw new Error("Checklist state is unbounded")
          console.log("ARTIFACT_SMOKE_OK", cards.count)
          Qt.quit()
        }
      }
    }
  }
}
''')
    (directory / "runtime").mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
               QT_STYLE_OVERRIDE="Fusion", XDG_RUNTIME_DIR=str(directory / "runtime"))
    result = subprocess.run(["quickshell", "-p", str(directory / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    if (result.returncode or "ARTIFACT_SMOKE_OK" not in output
            or any(marker in output for marker in ("TypeError:", "ReferenceError:", "Unable to assign", "Invalid property", "Binding loop"))):
        raise SystemExit(output)
    print(f"Quickshell compiled and laid out {len(fixtures)} artifact fixtures")
