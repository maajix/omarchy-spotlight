"""Lay out the preview pane for every block type with the installed Quickshell.

Run: python3 tests/qml_preview_smoke.py
Set SPOTLIGHT_PREVIEW_SHOTS=<dir> to also save a PNG of each preview.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHOTS = os.environ.get("SPOTLIGHT_PREVIEW_SHOTS", "")

# Preview.js builds the blocks, so the pane is checked against real output.
BUILD = r'''
const Preview = require(process.argv[1] + "/lib/Preview.js")
const Units = { formatNumber: n => String(Math.round(n * 100) / 100) }
const ctx = { defaultCurrency: "EUR", currencyRates: true, formatNumber: Units.formatNumber }
const ready = reply => ({ state: "ready", reply })
const cases = [
  ["currency", { key: "currency", kind: "copy", title: "209.04 EUR", subtitle: "",
    payload: { amount: 234, base: "USD", quote: "EUR", rate: 0.8933, date: "2026-10-09", source: "234 USD" } },
    ready({ rates: [{ quote: "GBP", rate: 0.756 }, { quote: "JPY", rate: 158.25, stale: true },
                    { quote: "CHF", rate: 0.832 }] })],
  ["calc", { key: "calc", kind: "copy", title: "1 024", subtitle: "2^10", payload: { value: 1024 } }, null],
  ["unit", { key: "unit", kind: "copy", title: "2 km", subtitle: "2 000 m = 2 km",
    payload: { related: [{ text: "1.2427 mi" }, { text: "2 187.23 yd" }] } }, null],
  ["file-long", { key: "file:/p/s.png", kind: "file", title: "screenshot-2026-10-09_11-16-42-with-a-long-tail.png",
    subtitle: "/p", payload: { path: "/p/s.png", dir: "/p" } },
    ready({ kind: "binary", size: 1048576, modified: "2026-10-09 11:16", description: "image/png" })],
  ["file-text", { key: "file:/tmp/notes.md", kind: "file", title: "notes.md", subtitle: "/tmp",
    payload: { path: "/tmp/notes.md", dir: "/tmp" } },
    ready({ kind: "text", text: "# Notes\n\n- one\n- two\n" + "x".repeat(200), size: 2048,
            modified: "2026-10-09 11:20", lines: 40, truncated: true, description: "Markdown" })],
  ["file-dir", { key: "file:/tmp", kind: "file", title: "tmp", subtitle: "/",
    payload: { path: "/tmp", dir: "/" } },
    ready({ kind: "dir", entries: [{ name: "a", isDir: true }, { name: "b.txt", isDir: false }],
            count: 2, modified: "2026-10-09 11:20", description: "Folder" })],
  ["file-loading", { key: "file:/tmp/x", kind: "file", title: "x", subtitle: "/tmp",
    payload: { path: "/tmp/x", dir: "/tmp" } }, { state: "loading" }],
  ["clipboard", { key: "clip:0", kind: "clipcopy", title: "token", payload: { index: 0, title: "token" } },
    ready({ text: "line one\nline two", chars: 17, lines: 2, truncated: false })],
  ["app", { key: "app:firefox", kind: "app", title: "Firefox", subtitle: "Web browser",
    payload: { appId: "firefox", comment: "Browse the World Wide Web", exec: "firefox %u",
               categories: ["Network", "WebBrowser"] } }, null],
  ["service", { key: "service:user:a", kind: "services", title: "pipewire", subtitle: "active / running",
    accessory: "user", payload: { name: "pipewire.service", scope: "user" } },
    ready({ state: "active (running)", since: "2026-10-09 09:00", pid: "1234", memory: "12.0 MB",
            logs: "Oct 09 09:00 started" })],
  ["generic", { key: "cmd:x", kind: "shell", title: "Lock screen", subtitle: "omarchy system lock",
    accessory: "Action" }, null]
]
console.log(JSON.stringify(cases.map(([name, row, data]) => ({ name, preview: Preview.build(row, ctx, data) }))))
'''

previews = json.loads(subprocess.run(["node", "-e", BUILD, str(ROOT)], check=True,
                                     capture_output=True, text=True, timeout=10).stdout)

with tempfile.TemporaryDirectory(prefix="spotlight-preview-") as directory:
    directory = Path(directory)
    (directory / "Commons").symlink_to("/usr/share/omarchy/shell/Commons")
    (directory / "ui").symlink_to(ROOT / "ui")
    (directory / "shell.qml").write_text('''import Quickshell
import QtQuick
import QtQuick.Window
import qs.Commons
import "ui/panels"
ShellRoot {
  Window {
    id: smokeWindow
    width: 400
    height: 460
    visible: true
    color: Color.menu.background
    PreviewPane {
      id: pane
      anchors.fill: parent
      foreground: Color.menu.text
      gutter: 11
    }
    function findItem(item, name) {
      if (item.objectName === name) return item
      var children = item.children || []
      for (var i = 0; i < children.length; i++) {
        var found = findItem(children[i], name)
        if (found) return found
      }
      return null
    }
    Timer {
      property var cases: ''' + json.dumps(previews) + '''
      property string shots: ''' + json.dumps(SHOTS) + '''
      property int index: -1
      // Checks run one tick after a preview is set, and the next preview waits
      // for the tick after that, so a saved shot shows the case it is named after.
      property bool checked: true
      interval: 150
      repeat: true
      running: true
      onTriggered: {
        try {
          if (!checked) {
            var column = smokeWindow.findItem(pane, "preview-blocks")
            if (!column) throw new Error("Missing preview block container")
            if (!(column.implicitHeight > 0)) throw new Error("Preview failed to lay out: " + cases[index].name)
            var shown = 0
            for (var i = 0; i < column.children.length; i++) {
              var loader = column.children[i]
              if (loader.item) {
                if (!(loader.item.implicitHeight > 0) && loader.item.visible)
                  throw new Error("Empty block in " + cases[index].name)
                shown++
              }
            }
            if (shown !== cases[index].preview.blocks.length)
              throw new Error("Unpainted block in " + cases[index].name)
            if (shots) {
              var name = cases[index].name
              pane.grabToImage(function(result) { result.saveToFile(shots + "/" + name + ".png") })
            }
            checked = true
            return
          }
          index++
          if (index >= cases.length) {
            console.log("PREVIEW_SMOKE_OK", cases.length)
            Qt.quit()
            return
          }
          pane.preview = cases[index].preview
          checked = false
        } catch (error) { console.error(error); Qt.quit() }
      }
    }
  }
}
''')
    (directory / "runtime").mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
               XDG_RUNTIME_DIR=str(directory / "runtime"))
    result = subprocess.run(["quickshell", "-p", str(directory / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    if (result.returncode or "PREVIEW_SMOKE_OK" not in output
            or any(marker in output for marker in ("TypeError:", "ReferenceError:", "Error:",
                                                   "Unable to assign", "Invalid property", "Binding loop"))):
        raise SystemExit(output)
    print(f"Quickshell laid out {len(previews)} preview panes")
