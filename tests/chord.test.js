const assert = require("node:assert/strict")
const test = require("node:test")
const Chord = require("../lib/Chord.js")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const META = 0x10000000, CTRL = 0x04000000, ALT = 0x08000000, SHIFT = 0x02000000
const KEY_K = 0x4b, KEY_SPACE = 0x20, KEY_F6 = 0x01000035, KEY_ESCAPE = 0x01000000

test("fromEvent spells chords in Hyprland order with one key", () => {
  assert.equal(Chord.fromEvent(KEY_K, SHIFT | META), "SUPER + SHIFT + K")
  assert.equal(Chord.fromEvent(KEY_SPACE, ALT), "ALT + SPACE")
  assert.equal(Chord.fromEvent(KEY_F6, CTRL | ALT), "CTRL + ALT + F6")
  assert.equal(Chord.fromEvent(0x31, META), "SUPER + 1")
})

test("fromEvent refuses bare keys, unknown keys and modifier-only presses", () => {
  assert.equal(Chord.fromEvent(KEY_SPACE, 0), "")
  assert.equal(Chord.fromEvent(KEY_ESCAPE, META), "")
  assert.equal(Chord.fromEvent(0x01000020, META), "")   // Qt.Key_Shift itself
  assert.equal(Chord.fromEvent(0x01000005, META), "")   // keypad Enter
})

test("normalize accepts both spellings and aliases", () => {
  assert.equal(Chord.normalize("SUPER SHIFT CTRL + SPACE"), "SUPER + CTRL + SHIFT + SPACE")
  assert.equal(Chord.normalize("shift+super+k"), "SUPER + SHIFT + K")
  assert.equal(Chord.normalize("Win + Control + Mod1 + F6"), "SUPER + CTRL + ALT + F6")
  assert.equal(Chord.normalize("PRINT"), "PRINT")
  assert.equal(Chord.normalize("SUPER + A + B"), "")
  assert.equal(Chord.normalize("constructor"), "CONSTRUCTOR")
  assert.equal(Chord.normalize(""), "")
})

test("mods is the modifier half of a canonical chord", () => {
  assert.equal(Chord.mods("SUPER + ALT + 9"), "SUPER + ALT")
  assert.equal(Chord.mods("ALT + SPACE"), "ALT")
  assert.equal(Chord.mods("PRINT"), "")
  assert.equal(Chord.mods(""), "")
  assert.equal(Chord.mods(null), "")
})

test("isKnown refuses a chord the bind table cannot speak for", () => {
  const bound = { "SUPER + SPACE": "Omarchy menu" }
  // The compositor reported binds under SUPER it would not name, so a SUPER
  // chord missing from the table is not evidence that it is free.
  assert.equal(Chord.isKnown("SUPER + 1", bound, ["SUPER"]), false)
  assert.equal(Chord.isKnown("SUPER + SPACE", bound, ["SUPER"]), false)
  assert.equal(Chord.isKnown("ALT + SPACE", bound, ["SUPER"]), true)
  assert.equal(Chord.isKnown("SUPER + ALT + K", bound, ["SUPER"]), true)
  assert.equal(Chord.isKnown("ALT + SPACE", bound, []), true)
  // No table at all is the older, coarser form of the same answer.
  assert.equal(Chord.isKnown("ALT + SPACE", null, []), false)
  assert.equal(Chord.isKnown("ALT + SPACE", undefined, []), false)
  // A helper too old to send the field built its table by the rule this
  // replaces, so a missing list is unknown rather than permission.
  assert.equal(Chord.isKnown("ALT + SPACE", bound, undefined), false)
  assert.equal(Chord.isKnown("ALT + SPACE", bound, null), false)
  assert.equal(Chord.isKnown("SUPER + K", bound, "SUPER"), false)
  assert.equal(Chord.isKnown("SUPER + K", bound, {}), false)
  assert.equal(Chord.isKnown("SUPER + K", bound, 3), false)
})

test("loadBinding only auto-binds when the helper explicitly knows the chord is free", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Spotlight.qml"), "utf8")
  const loadBinding = qml.match(/  function loadBinding\(reply\) \{[\s\S]*?\n  \}/)[0]
  const bound = { "SUPER + B": "Browser" }
  const cases = [
    [{ bound }, false],
    ...[null, "ALT", {}, 3].map(unknownMods => [{ bound, unknownMods }, false]),
    [{ bound, unknownMods: ["ALT"] }, false],
    [{ bound: null, unknownMods: [] }, false],
    [{ bound: { "ALT + SPACE": "" }, unknownMods: [] }, false],
    [{ bound, unknownMods: [] }, true],
    [{ bound, unknownMods: ["SUPER"] }, true],
  ]
  for (const [reply, shouldWrite] of cases) {
    const writes = []
    const root = {
      autoBindDone: false, settings: { setupCompleted: false },
      defaultChord: "ALT + SPACE", writeBinding: chord => writes.push(chord),
    }
    vm.runInNewContext(loadBinding + "\nloadBinding(reply)", { root, Chord, reply })
    assert.deepEqual(writes, shouldWrite ? ["ALT + SPACE"] : [], JSON.stringify(reply))
  }
})

test("the tour warns before replacing a binding even without a description", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "SetupTour.qml"), "utf8")
  for (const [boundChords, currentBinding, shouldReplace] of [
    [{ "ALT + SPACE": "" }, "", true],
    [{ "ALT + SPACE": "Launcher" }, "", true],
    [{}, "", false],
    [{ "ALT + SPACE": "" }, "ALT + SPACE", false],
  ]) {
    const context = vm.createContext({ selected: "ALT + SPACE", currentBinding, boundChords, step: 1 })
    // Evaluate the real QML properties in declaration order, through primaryText.
    const properties = qml.slice(qml.indexOf("  readonly property bool sameAsCurrent:"),
      qml.indexOf("  readonly property bool primaryEnabled:"))
    for (const match of properties.matchAll(/readonly property (?:bool|string) (\w+): ([\s\S]*?)(?=\n  readonly property|$)/g))
      context[match[1]] = vm.runInContext(match[2], context)
    assert.equal(context.primaryText === "Replace and set", shouldReplace)
    assert.equal(context.chordCaption.includes("Spotlight will take it over"), shouldReplace)
    if (shouldReplace) assert.notEqual(context.chordCaption, "Free to use.")
  }
})
