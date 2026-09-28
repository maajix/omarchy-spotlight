const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
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

test("fromPlugins builds summon entries for active interactive plugins", () => {
  const plugins = {
    "test.service": {
      id: "test.service",
      name: "Background Worker",
      kinds: ["service"]
    },
    "test.disabled": {
      id: "test.disabled",
      name: "Disabled Plugin",
      kinds: ["panel"]
    },
    "test.bar.notmounted": {
      id: "test.bar.notmounted",
      name: "Not In Bar",
      kinds: ["bar-widget"]
    },
    "test.panel": {
      id: "test.panel",
      name: "My Panel",
      description: "Custom overlay panel",
      kinds: ["panel"],
      icon: "rocket"
    },
    "test.bar": {
      id: "test.bar",
      name: "My Widget",
      description: "Custom bar widget",
      kinds: ["bar-widget"],
      icon: "assets/icon.svg",
      __sourceDir: "/home/user/.config/omarchy/plugins/test.bar",
      aliases: ["widget", "test"]
    },
    "test.known": {
      id: "test.known",
      name: "Curated Plugin",
      kinds: ["overlay"]
    }
  }

  const enabled = new Set(["test.panel", "test.bar", "test.known"])
  const inBar = new Set(["test.bar"])
  const known = { "test.known": true }

  const entries = Commands.fromPlugins(plugins, {
    ignoreId: "test.service",
    knownIds: known,
    isEnabled: id => enabled.has(id),
    inBar: id => inBar.has(id)
  })

  assert.equal(entries.length, 2)
  const [panel, widget] = entries

  assert.equal(panel.id, "test.panel")
  assert.equal(panel.kind, "summon")
  assert.equal(panel.title, "My Panel")
  assert.equal(panel.icon, "rocket")
  assert.equal(panel.image, "")

  assert.equal(widget.id, "test.bar")
  assert.equal(widget.kind, "summon")
  assert.equal(widget.title, "My Widget")
  assert.equal(widget.icon, "")
  assert.equal(widget.image, "file:///home/user/.config/omarchy/plugins/test.bar/assets/icon.svg")
  assert.ok(widget.keywords.includes("widget"))
  assert.ok(widget.keywords.includes("test"))
})

