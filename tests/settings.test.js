const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const Commands = require("../lib/Commands.js")

const root = path.join(__dirname, "..")
const read = name => fs.readFileSync(path.join(root, name), "utf8")
const qml = read("Spotlight.qml")
const panel = read("SettingsPanel.qml")
const helper = read("bin/spotlight-helper")
const choiceMenu = read("ChoiceMenu.qml")
const settingRow = read("SettingRow.qml")

test("the settings result opens the panel and keeps the file on the secondary action", () => {
  assert.match(qml, /case "spotlight-settings":[\s\S]*?if \(secondary\) root\.editSettingsFile\(\)\s*\n\s*else root\.showSettingsPanel\(\)/)
  const settings = Commands.commands().find(c => c.key === "spotlight.settings")
  assert.equal(settings.kind, "spotlight-settings")
  assert.ok(settings.secondaryLabel.length > 0, "the file path needs a label of its own")
})

test("the panel replaces the search card, so no keystroke reaches the input", () => {
  assert.match(qml, /visible: !root\.tourActive && !root\.settingsActive/)
})

test("edits are coalesced into one patch and written by a single writer", () => {
  assert.match(qml, /function queueSetting\(key, value\) \{[\s\S]*?settingsWriteDebounce\.restart\(\)/)
  assert.match(qml, /function flushSettings\(\) \{[\s\S]*?if \(settingsWriteProc\.running\) \{\s*\n\s*settingsWriteDebounce\.restart\(\)/)
  // The helper merges spotlight.json without a lock because this file promises
  // it is the only writer; that promise is what the check above keeps.
  assert.match(helper, /no lock - Spotlight\.qml funnels every write through one/)
})

test("leaving the panel by any route flushes what the debounce still holds", () => {
  assert.match(qml, /function leaveSettingsPanel\(\) \{[\s\S]*?root\.flushSettings\(\)/)
  for (const fn of ["function close()", "function dismiss()"]) {
    const body = qml.slice(qml.indexOf(fn))
    assert.match(body.slice(0, 400), /root\.leaveSettingsPanel\(\)/, fn + " drops pending edits")
  }
})

test("every writable setting the helper knows is on the panel", () => {
  const known = helper
    .slice(helper.indexOf("def normalize_settings"), helper.indexOf("def normalize_usage"))
    .match(/out\["(\w+)"\] = /g)
    .map(m => m.slice(5, -5))
  const skipped = new Set(["setupCompleted"])
  for (const key of known) {
    if (skipped.has(key)) continue
    assert.match(panel, new RegExp('panel\\.(set|toggle)\\("' + key + '"'),
      key + " has no control in the settings panel")
  }
})

test("an unfinished currency code is never written", () => {
  assert.match(panel, /if \(valid\) panel\.set\("defaultCurrency"/)
})

test("clearing the learning data asks twice", () => {
  assert.match(panel, /if \(!panel\.resetArmed\) \{ panel\.resetArmed = true; return \}/)
})

test("a control reports a pick instead of writing over its own binding", () => {
  // Assigning the displayed value detaches the control from the draft it is
  // bound to, which is how the tour's currency field lost its binding.
  assert.doesNotMatch(choiceMenu, /menu\.value = /)
  assert.match(choiceMenu, /function pick\(\) \{[\s\S]*?menu\.changed\(o\.value\)/)
  assert.doesNotMatch(read("Stepper.qml"), /stepper\.value = /)
})

test("a focused row answers Enter and Space itself", () => {
  // Otherwise Return walks up to the panel, and the panel would close on a key
  // the user pressed at a row.
  assert.match(settingRow, /Keys\.onSpacePressed: row\.toggled\(\)/)
  assert.match(settingRow, /Keys\.onReturnPressed: row\.toggled\(\)/)
  assert.doesNotMatch(panel, /Qt\.Key_Return/)
})

test("every focusable row can scroll itself into view", () => {
  const ids = [...panel.matchAll(/^\s+id: (\w+Row)$/gm)].map(m => m[1])
  assert.ok(ids.length >= 10, "expected the focusable rows to be named")
  for (const id of ids)
    assert.match(panel, new RegExp("panel\\.ensureVisible\\(" + id + "\\)"),
      id + " never brings itself into view")
})

test("a rejected currency code does not outlive the panel", () => {
  assert.match(panel, /function finish\(\) \{[\s\S]*?panel\.currencyValid = true[\s\S]*?panel\.closed\(\)/)
  assert.match(panel, /onClicked: panel\.finish\(\)/)
})

test("the first-run tour cannot raise itself over the panel", () => {
  assert.match(qml, /root\.opened && !root\.tourActive && !root\.settingsActive/)
})
