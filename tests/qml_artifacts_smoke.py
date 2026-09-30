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
    image = directory / "preview.jpg"
    subprocess.run(["magick", "-size", "320x180", "gradient:#234b68-#9be4ef", str(image)], check=True, timeout=5)
    for fixture in fixtures:
        if fixture["type"] == "gallery":
            for entry in fixture["images"]: entry["previewUrl"] = image.as_uri()
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
  function button(item, text) {
    if (item.text === text && typeof item.clicked === "function") return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = button(children[i], text)
      if (found) return found
    }
    return null
  }
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
        property string lastOpen: ""
        property string lastCopy: ""
        property string lastAction: ""
        onImageActionRequested: function(identity, action) { lastAction = identity + ":" + action }
        onOpenRequested: function(url) { lastOpen = url }
        onCopyRequested: function(value) { lastCopy = value }
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
          var host = cards.itemAt(i)
          if (stage === 1 && host.artifact.type === "gallery") {
            if (host.lastAction) throw new Error("Gallery applied without a click")
            var save = root.button(host, "Save"), apply = root.button(host, "Apply")
            if (!save.enabled || !apply.enabled) throw new Error("Gallery preview did not load")
            save.clicked()
            if (host.lastAction !== host.artifact.images[0].id + ":save") throw new Error("Gallery save failed")
            apply.clicked()
            if (host.lastAction !== host.artifact.images[0].id + ":apply") throw new Error("Gallery apply failed")
            host.galleryBusy = true
            if (save.enabled || apply.enabled) throw new Error("Gallery actions allow overlapping requests")
          }
          if (stage === 0 && host.artifact.type === "diff") {
            root.button(host, "Copy proposed config").clicked()
            if (host.lastCopy !== host.artifact.files[0].after) throw new Error("Diff config copy failed")
            root.button(host, "Copy diff").clicked()
            if (host.lastCopy !== host.artifact.files[0].diff) throw new Error("Diff copy failed")
          }
          if (stage === 0 && host.artifact.type === "places") {
            if (host.lastOpen) throw new Error("Place card opened a link without a click")
            root.button(host, "View map ↗").clicked()
            if (host.lastOpen !== host.artifact.places[0].mapUrl) throw new Error("Place map link failed")
            root.button(host, "Copy address").clicked()
            if (host.lastCopy !== host.artifact.places[0].address) throw new Error("Place copy failed")
            root.button(host, "Source ↗").clicked()
            if (host.lastOpen !== host.artifact.places[0].sourceUrl) throw new Error("Place source failed")
          }
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
