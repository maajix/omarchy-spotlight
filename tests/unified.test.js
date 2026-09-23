const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const Commands = require("../lib/Commands.js")
const Fuzzy = require("../lib/Fuzzy.js")

const qml = fs.readFileSync(path.join(__dirname, "..", "Spotlight.qml"), "utf8")

test("the displayed model is one globally ranked, capped list with provider sections", () => {
  assert.match(qml, /next = root\.globallyRank\(next, parsed\.text\)/)
  assert.match(qml, /Util\.clamp\(root\.settings\.maxResults, 8, root\.maxGlobalResults\)/)
  assert.match(qml, /var limit = target\.implicit\s*\? Math\.min\(root\.maxUnifiedFileRows/)
  assert.match(qml, /rowSection: root\.resultSection\(r\)/)
  assert.match(qml, /section\.property: "rowSection"/)
  for (const label of ["Applications", "Windows", "Commands", "Files", "Clipboard", "Web", "Reminders"])
    assert.ok(qml.includes(`return "${label}"`))
})

test("empty input is a per-section digest and empty filters show only a hint", () => {
  assert.match(qml, /if \(parsed\.empty\) \{\s*next\.push\(root\.filterHintRow\(parsed\)\)/)
  assert.match(qml, /else if \(!q\) \{\s*push\(root\.idleRows\(\)\)/)
  assert.match(qml, /var fallback = root\.appRows\("", false\)/)
  // Each source is ranked and capped on its own, so the longest one cannot
  // crowd the others out of the digest the way an uncapped app list did.
  assert.match(qml, /root\.idleSlice\(root\.appRows\("", true\), root\.idleAppRows\)/)
  assert.match(qml, /\.concat\(root\.idleSlice\(root\.commandRows\("", true, true\), root\.idleCommandRows\)\)/)
  assert.match(qml, /\.concat\(root\.idleSlice\(root\.learnedFileRows\(\), root\.idleFileRows\)\)/)
  assert.match(qml, /\.concat\(root\.idleSlice\(root\.windowRows\("", true\), root\.idleWindowRows\)\)/)
  assert.match(qml, /if \(!learned \|\| !Frecency\.hasItem\(root\.usage, fallback\[i\]\.stableId\)\) apps\.push\(fallback\[i\]\)/)
  assert.match(qml, /readonly property int idleAppRows: 5/)
  assert.match(qml, /readonly property int idleWindowRows: 2/)
  assert.match(qml, /readonly property int idleCommandRows: 1/)
  assert.match(qml, /readonly property int idleFileRows: 2/)
})

// The digest concatenates its sections in order and then hands the whole list
// back to the same global ranking every query uses. The order only survives
// that because Ranking sorts by result type before it sorts by score.
test("global ranking keeps the digest's section order", () => {
  const Ranking = require("../lib/Ranking.js")
  const row = (resultType, title) => ({
    resultType, title, textMatch: Fuzzy.MATCH_RESIDUAL,
    recencyBonus: 0, frequencyBonus: 0, contextBonus: 0
  })
  const shuffled = [
    row("window", "Brave"), row("file", "notes.md"),
    row("action", "Clipboard History"), row("app", "Ghostty")
  ]
  assert.deepEqual(
    Ranking.rank(shuffled, 50).map(r => r.resultType),
    ["app", "action", "file", "window"]
  )
  // A big learning bonus may reorder rows inside a section, never across one.
  const boosted = [row("window", "Brave"), row("app", "Ghostty")]
  boosted[0].contextBonus = 110
  assert.deepEqual(Ranking.rank(boosted, 50).map(r => r.resultType), ["app", "window"])
})

test("one character starts only explicitly filtered file and clipboard providers", () => {
  assert.match(qml, /var searchable = parsed\.text\.length >= 2/)
  assert.match(qml, /fileSearchAlways && s\.length >= 2/)
  assert.match(qml, /clipboardSearchAlways && parsed\.text\.length >= 2/)
})

test("spotlight settings finds all four local maintenance actions", () => {
  const rows = Fuzzy.rank(Commands.commands(), "spotlight settings", 20)
    .filter(row => row.key.startsWith("spotlight."))
  assert.deepEqual(rows.map(row => row.title).sort(), [
    "Spotlight Settings",
    "Open Spotlight Data Folder",
    "Open Spotlight Plugin Folder",
    "Reset Spotlight Learning"
  ].sort())
  assert.equal(rows.find(row => row.key === "spotlight.reset").confirm, true)
})

test("every asynchronous query result is rejected after the query changes", () => {
  assert.match(qml, /function loadSuggestions\(raw, forQuery\) \{\s*if \(forQuery !== String\(root\.query/)
  assert.match(qml, /function loadFiles\(raw, forQuery\) \{\s*if \(forQuery !== String\(root\.query/)
  assert.match(qml, /function loadClipboard\(raw, forQuery\) \{\s*if \(forQuery !== String\(root\.query/)
  assert.match(qml, /var restored = root\.pinnedKey \? root\.indexOfKey\(root\.pinnedKey\) : -1/)
  assert.match(qml, /root\.selectedIndex = restored >= 0 \? restored : root\.firstSelectableIndex\(\)/)
})
