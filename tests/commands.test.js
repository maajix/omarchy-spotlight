const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")
const Commands = require("../lib/Commands.js")

const helper = fs.readFileSync(path.join(__dirname, "..", "bin", "spotlight-helper"), "utf8")
const qml = fs.readFileSync(path.join(__dirname, "..", "Spotlight.qml"), "utf8")
const entries = Commands.commands().concat(Commands.quicklinks())

test("a catalogue key names exactly one entry", () => {
  const seen = new Set()
  for (const c of entries) {
    assert.equal(typeof c.key, "string")
    assert.ok(c.key.length > 0)
    assert.ok(!seen.has(c.key), "duplicate key " + c.key)
    seen.add(c.key)
  }
})

test("every shell entry carries a runnable argv vector", () => {
  for (const c of entries.filter(e => e.kind === "shell")) {
    assert.ok(Array.isArray(c.argv), c.key + " has no argv")
    assert.ok(c.argv.length > 0, c.key + " has an empty argv")
    for (const token of c.argv) assert.equal(typeof token, "string")
  }
})

test("every state id is one the helper knows how to probe", () => {
  const stateful = entries.filter(c => c.state)
  assert.ok(stateful.length > 0)
  for (const c of stateful) {
    assert.equal(c.kind, "shell", c.key + " is not a shell entry")
    assert.match(helper, new RegExp('"' + c.state + '":'), "helper cannot probe " + c.state)
  }
})

test("toggle interaction needs a known state and leaves Space to the search field", () => {
  assert.match(qml,
    /if \(r\.payload\.stateId && root\.toggleStates\[r\.payload\.stateId\] !== undefined\)/)
  assert.doesNotMatch(qml, /event\.key === Qt\.Key_Space/)
  assert.match(qml, /id: toggleReconcile\s+interval: 2500/)
})

test("argvId collapses the menu spelling of a command onto the catalogue one", () => {
  assert.equal(Commands.argvId(["omarchy", "toggle", "nightlight"]), "omarchy-toggle-nightlight")
  assert.equal(Commands.argvId(["omarchy-toggle-nightlight"]), "omarchy-toggle-nightlight")
  assert.equal(Commands.argvId(["omarchy-audio-output-volume", "mute-toggle"]),
    Commands.argvId(["omarchy", "audio", "output", "volume", "mute-toggle"]))
  assert.equal(Commands.argvId(null), "")
  assert.equal(Commands.argvId([]), "")
})

test("fromPlugins keeps curated entries, skips itself and deduplicates plugin IDs", () => {
  const plugins = [
    { id: "test.panel", name: "Zebra Panel" },
    { id: "test.menu", name: "Alpha Menu" },
    { id: "test.panel", name: "Duplicate" },
    { id: "omarchy.emojis", name: "Curated" },
    { id: "io.github.maajix.spotlight", name: "Spotlight" },
    { id: "constructor", name: "Prototype Name" }
  ]
  const entries = Commands.fromPlugins(plugins, "io.github.maajix.spotlight")
  assert.deepEqual(entries.map(c => c.id), ["test.menu", "constructor", "test.panel"])
  const panel = entries[2]
  assert.equal(panel.kind, "summon")
  assert.equal(panel.icon, "🧩")
  assert.equal(panel.image, undefined)
  assert.ok(panel.keywords.includes("test panel"))
  assert.deepEqual(Commands.fromPlugins(null), [])
  assert.deepEqual(Commands.fromPlugins({}), [])
})

test("QML discovers and launches plugins without a host registry or cross-plugin API", () => {
  const pluginsProc = { running: false }, pluginSummonProc = { running: false }
  let rebuilds = 0, dismissed = false
  const root = {
    // This is the installed third-party facade: no pluginRegistry property,
    // and cross-plugin calls are forbidden.
    shell: { summon: () => assert.fail("scoped summon used"),
      toggle: () => assert.fail("scoped toggle used") },
    pluginId: "io.github.maajix.spotlight", opened: true,
    pluginCommands: [{ id: "old.plugin" }], menuCommands: [],
    maxHelperPayloadChars: 524288, maxAppCandidates: 512, usage: {},
    helperArgv: args => ["python3", "/helper"].concat(args),
    rebuild: () => { rebuilds++ }, row: r => r,
    bumpUsage: () => {}, dismiss: () => { dismissed = true }
  }
  const context = vm.createContext({ root, pluginsProc, pluginSummonProc, Commands,
    Fuzzy: require("../lib/Fuzzy.js"), Frecency: require("../lib/Frecency.js"),
    Query: require("../lib/Query.js") })
  for (const name of ["helperReply", "refreshPluginCommands", "loadPluginCommands", "commandRows", "activate"]) {
    const source = qml.match(new RegExp("  function " + name + "\\([^]*?\n  \\}"))[0]
    vm.runInContext(source, context)
    root[name] = context[name]
  }
  root.refreshPluginCommands()
  assert.equal(root.pluginCommands.length, 0)
  assert.equal(pluginsProc.running, true)
  assert.deepEqual(Array.from(pluginsProc.command), ["python3", "/helper", "read-plugins"])
  root.loadPluginCommands(JSON.stringify({ ok: true, plugins: [
    { id: "test.panel", name: "My Panel" }, { id: root.pluginId, name: "Spotlight" }
  ] }))
  assert.equal(rebuilds, 1)
  root.rows = root.commandRows("my panel", false, false)
  assert.equal(root.rows.length, 1)
  assert.equal(root.rows[0].accessory, "Plugin")
  assert.equal(root.rows[0].primaryLabel, "Open")
  root.activate(0, false)
  assert.equal(dismissed, true)
  assert.equal(pluginSummonProc.running, true)
  assert.deepEqual(Array.from(pluginSummonProc.command),
    ["python3", "/helper", "summon-plugin", "test.panel"])
  root.loadPluginCommands('{"ok":false,"error":"offline"}')
  assert.equal(root.pluginCommands.length, 0)
  root.loadPluginCommands("not JSON")
  assert.equal(root.pluginCommands.length, 0)
})
