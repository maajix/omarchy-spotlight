import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../../lib/AiOptions.js" as AiOptions

ColumnLayout {
  id: form
  spacing: Style.space(10)
  required property SpotlightPalette chrome
  required property Item bounds
  required property var draft
  required property var aiModels
  signal changed(var patch)

  SettingRow {
    chrome: form.chrome
    glyph: "󰚩"
    title: "Ask AI"
    description: "Send ai: queries to your selected CLI. Answers and commands stay in Spotlight; commands run only when you press Enter in a terminal."
    checked: form.draft.aiEnabled === true
    onToggled: form.changed({ aiEnabled: !form.draft.aiEnabled })
  }

  SettingRow {
    chrome: form.chrome
    glyph: "󰒊"
    switchable: false
    title: "AI provider"
    description: "Use an installed and signed-in Claude or Codex CLI. Queries are sent to that provider."
    trailing: ChoiceMenu {
      chrome: form.chrome
      bounds: form.bounds
      value: form.draft.aiProvider || "claude"
      options: [{ value: "claude", label: "Claude" }, { value: "codex", label: "Codex" }]
      onChanged: function(v) { form.changed({ aiProvider: v, aiModel: "", aiEffort: "" }) }
    }
  }

  SettingRow {
    chrome: form.chrome
    glyph: "󰘦"
    switchable: false
    title: "AI model"
    description: "Available models from the selected CLI's local catalog."
    trailing: ChoiceMenu {
      chrome: form.chrome
      bounds: form.bounds
      value: form.draft.aiModel || ""
      options: AiOptions.models(form.aiModels, form.draft.aiProvider || "claude")
      onChanged: function(v) { form.changed({ aiModel: v, aiEffort: "" }) }
    }
  }

  SettingRow {
    chrome: form.chrome
    glyph: "󰞌"
    switchable: false
    title: "Thinking level"
    description: "Levels supported by the selected model; choose a model to set one."
    trailing: ChoiceMenu {
      chrome: form.chrome
      bounds: form.bounds
      value: form.draft.aiEffort || ""
      options: AiOptions.efforts(form.aiModels, form.draft.aiProvider || "claude", form.draft.aiModel || "")
      onChanged: function(v) { form.changed({ aiEffort: v }) }
    }
  }

  SettingRow {
    chrome: form.chrome
    glyph: "󰖟"
    title: "AI web search"
    description: "Allow the selected AI provider to search the web for current information."
    checked: form.draft.aiWebSearch === true
    onToggled: form.changed({ aiWebSearch: !form.draft.aiWebSearch })
  }
}
