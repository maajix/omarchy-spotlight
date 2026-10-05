"""Exercise the shared AI settings in both real panels with Quickshell."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="spotlight-settings-") as directory:
    directory = Path(directory)
    (directory / "Commons").symlink_to("/usr/share/omarchy/shell/Commons")
    (directory / "ui").symlink_to(ROOT / "ui")
    (directory / "lib").symlink_to(ROOT / "lib")
    (directory / "shell.qml").write_text('''import Quickshell
import QtQuick
import QtQuick.Window
import "ui/panels"
ShellRoot {
  id: root
  function find(item, predicate) {
    if (predicate(item)) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = find(children[i], predicate)
      if (found) return found
    }
    return null
  }
  Window {
    width: 1400; height: 1000; visible: true
    SettingsPanel {
      id: settings
      settings: ({ searchEngine: "g", maxResults: 20, maxApps: 8, maxSuggestions: 4, aiEnabled: true, aiWebSearch: true, aiProvider: "claude", aiModel: "old", aiEffort: "high" })
      onChanged: function(patch) { settings.settings = Object.assign({}, settings.settings, patch) }
    }
    SetupTour { id: tour; x: 750 }
    Timer {
      interval: 300; running: true
      onTriggered: {
        try {
          tour.start(settings.settings, 3, false)
          for (var panel of [settings, tour]) {
            var web = root.find(panel, function(item) { return item.title === "AI web search" })
            if (!web || !web.checked) throw new Error("Saved web search is not checked")
            web.toggled()
            if (panel.draft.aiWebSearch !== false || web.checked) throw new Error("Web search did not turn off")
            var providerRow = root.find(panel, function(item) { return item.title === "AI provider" })
            var provider = root.find(providerRow, function(item) { return typeof item.currentLabel === "function" })
            provider.changed("codex")
            if (panel.draft.aiProvider !== "codex" || panel.draft.aiModel !== "" || panel.draft.aiEffort !== "")
              throw new Error("Provider switch did not reset model and effort")
            if (panel === tour) tour.draft = Object.assign({}, tour.draft, { aiEffort: "high" })
            else settings.settings = Object.assign({}, settings.settings, { aiEffort: "high" })
            var modelRow = root.find(panel, function(item) { return item.title === "AI model" })
            root.find(modelRow, function(item) { return typeof item.currentLabel === "function" }).changed("new")
            if (panel.draft.aiModel !== "new" || panel.draft.aiEffort !== "")
              throw new Error("Model switch did not reset effort")
          }
          console.log("SETTINGS_SMOKE_OK")
        } catch (error) { console.error(error) }
        Qt.quit()
      }
    }
  }
}
''')
    (directory / "runtime").mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
               QT_STYLE_OVERRIDE="Fusion", XDG_RUNTIME_DIR=str(directory / "runtime"))
    result = subprocess.run(["quickshell", "-p", str(directory / "shell.qml")],
                            env=env, capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "SETTINGS_SMOKE_OK" in output, output
    assert not any(error in output for error in ("Error:", "Unable to assign", "Binding loop")), output
    print("Settings and tour preserve web search and reset model/effort through the shared form")
