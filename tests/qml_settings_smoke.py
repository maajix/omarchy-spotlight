"""Exercise settings tabs, scrolling, edits, and the shared AI form with Quickshell."""
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
  function shown(item) {
    for (var current = item; current; current = current.parent)
      if (!current.visible) return false
    return true
  }
  function row(title) { return find(settings, function(item) { return item.title === title }) }
  function inView(item) {
    var flick = find(settings, function(item) { return typeof item.contentY === "number" })
    var top = item.mapToItem(flick, 0, 0).y
    if (!shown(item) || top < -0.5 || top + item.height > flick.height + 0.5)
      throw new Error("Focused row is outside the scroll viewport: " + item.title)
  }
  Window {
    width: 1400; height: 1000; visible: true
    SettingsPanel {
      id: settings
      availableHeight: 540
      settings: ({ searchEngine: "g", maxResults: 20, maxApps: 8, maxSuggestions: 4, verticalPosition: 50, horizontalPosition: 50, aiEnabled: true, aiWebSearch: true, aiProvider: "claude", aiModel: "old", aiEffort: "high" })
      onChanged: function(patch) { settings.settings = Object.assign({}, settings.settings, patch) }
    }
    SetupTour { id: tour; x: 750 }
    Timer {
      property int phase: 0
      interval: 300; running: true; repeat: true
      onTriggered: {
        try {
          if (phase === 1) {
            root.find(root.row("AI provider"), function(item) { return typeof item.currentLabel === "function" }).forceActiveFocus()
            phase++
            return
          }
          if (phase === 2) {
            root.inView(root.row("AI provider"))
            root.find(root.row("Weather default location"), function(item) { return item.placeholderText === "City, region" }).forceActiveFocus()
            phase++
            return
          }
          if (phase === 3) {
            root.inView(root.row("Weather default location"))
            var location = root.find(root.row("Weather default location"), function(item) { return item.placeholderText === "City, region" })
            location.text = " Tokyo "
            settings.showTab("search")
            if (settings.draft.artifactSettings.weather.defaultLocation !== "Tokyo")
              throw new Error("Leaving AI did not commit the weather location")
            settings.showTab("ai")
            location.text = "Oslo"
            settings.finish()
            if (settings.draft.artifactSettings.weather.defaultLocation !== "Oslo")
              throw new Error("Closing settings did not commit the weather location")
            settings.open()
            if (settings.activeTab !== "general") throw new Error("Reopening did not reset the tab")
            console.log("SETTINGS_SMOKE_OK")
            Qt.quit()
            return
          }
          var pages = [
            { key: "general", label: "General", rows: ["Open Spotlight", "Setup and data"] },
            { key: "search", label: "Search", rows: ["Files and folders", "Clipboard history", "Learn from your choices",
              "Search suggestions", "Search suggestions shown", "Web search engine", "Currency rates", "Default currency",
              "Results shown", "Applications shown"] },
            { key: "appearance", label: "Appearance", rows: ["Vertical position", "Horizontal position", "Preview pane",
              "Reduce motion"] },
            { key: "ai", label: "AI", rows: ["Ask AI", "AI provider", "AI model", "Thinking level", "AI web search", "Weather default location"] }
          ]
          for (var page of pages) {
            var tab = root.find(settings, function(item) { return item.text === page.label && typeof item.clicked === "function" })
            if (!tab || tab.mapToItem(settings, 0, 0).x + tab.width > settings.width)
              throw new Error("Tab is missing or outside the panel: " + page.label)
            tab.clicked()
            if (settings.activeTab !== page.key || !tab.selected) throw new Error("Tab did not select: " + page.label)
            for (var other of pages) {
              for (var title of other.rows) {
                var setting = root.row(title)
                if (!setting || root.shown(setting) !== (page.key === other.key))
                  throw new Error("Setting is missing or in the wrong tab: " + title)
              }
            }
          }
          settings.showTab("appearance")
          for (var axis of [["Vertical position", "verticalPosition"], ["Horizontal position", "horizontalPosition"]]) {
            var positionRow = root.row(axis[0])
            var position = root.find(positionRow, function(item) { return typeof item.apply === "function" })
            if (!position || position.value !== 50 || position.step !== 5)
              throw new Error(axis[0] + " did not load its default")
            for (var value of [25, 0, -5, 100, 105, 50]) {
              position.apply(value)
              if (settings.draft[axis[1]] !== Math.max(0, Math.min(100, value))
                  || position.value !== settings.draft[axis[1]])
                throw new Error(axis[0] + " did not update or stay in bounds")
            }
          }
          var motion = root.find(settings, function(item) { return item.title === "Reduce motion" })
          if (!motion || motion.checked) throw new Error("Reduce motion default is wrong")
          motion.toggled()
          if (!settings.draft.reduceMotion || !motion.checked) throw new Error("Reduce motion did not persist")
          settings.showTab("ai")
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
          phase++
        } catch (error) { console.error(error); Qt.quit() }
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
    print("Four tabs group every setting; focused AI/weather rows stay visible; weather edits survive tab switches and closing; shared AI behavior passes")
