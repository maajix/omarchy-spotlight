const assert = require("node:assert/strict")
const test = require("node:test")
const Apps = require("../lib/Apps.js")
const fs = require("node:fs")
const path = require("node:path")
const source = fs.readFileSync(path.join(__dirname, "../Spotlight.qml"), "utf8")
const appEntries = source.match(/  function appEntries\(q\) \{([\s\S]*?)\n  \}/)
assert.ok(appEntries)
const runAppEntries = new Function("root", "DesktopEntries", "Apps", "q", appEntries[1])

test("the restricted plugin API supplies visibility while Spotlight matches the query", () => {
  const youtube = { id: "chrome-agimnkijcaahngcdmfeangaknmldooml-Default", name: "YouTube" }
  const firefox = { id: "firefox", name: "Firefox" }
  const hidden = { id: "hidden", name: "Hidden" }
  const desktop = { applications: { values: [hidden, youtube, firefox] } }
  let visible = [youtube, firefox]
  const root = {
    maxAppCandidates: 10,
    appHides: Apps.hiddenMap(["firefox"]),
    appLibrary: { sortedEntries(query) {
      assert.equal(query, "", "the shell must not match the user's query")
      return visible.map(entry => ({ entry, score: 999 }))
    } }
  }
  const search = q => runAppEntries(root, desktop, Apps, q)
  assert.deepEqual(search("").map(row => row.entry), [firefox, youtube])
  assert.deepEqual(search("hidden"), [])
  assert.deepEqual(search("default"), [])
  assert.deepEqual(search("yt").map(row => row.entry), [youtube])
  visible = [firefox]
  assert.deepEqual(search("youtube"), [], "visibility updates apply on the next search")
  visible = []
  assert.deepEqual(search(""), [], "an empty visible list must not expose raw desktop entries")
})

test("the shell path does not depend on direct DesktopEntries access", () => {
  const entry = { id: "firefox", name: "Firefox" }
  const root = { maxAppCandidates: 10, appLibrary: {
    sortedEntries: () => [{ entry, score: 0 }]
  } }
  const desktop = { get applications() { throw new Error("unavailable") } }
  assert.deepEqual(runAppEntries(root, desktop, Apps, "firefox").map(row => row.entry), [entry])
})

test("standalone app search retains packaged hides, noDisplay and result limits", () => {
  const entries = [
    { id: "hidden", name: "Hidden" },
    { id: "nodisplay", name: "Invisible", noDisplay: true },
    { id: "firefox", name: "Firefox" },
    { id: "terminal", name: "Terminal" }
  ]
  const root = { maxAppCandidates: 1, appLibrary: null, appHides: Apps.hiddenMap(["hidden"]) }
  const desktop = { applications: { values: entries } }
  assert.deepEqual(runAppEntries(root, desktop, Apps, "").map(row => row.entry.id), ["firefox"])
  assert.deepEqual(runAppEntries(root, desktop, Apps, "terminal").map(row => row.entry.id), ["terminal"])
  assert.deepEqual(runAppEntries(root, {}, Apps, ""), [])
})

test("application fields and result counts are bounded", () => {
  const entries = Array.from({ length: 50 }, (_, i) => ({
    id: `app-${i}`,
    name: "x".repeat(1000) + i,
    keywords: Array(100).fill("keyword")
  }))
  const rows = Apps.sortedEntries(entries, "", null, 7, 12)
  assert.equal(rows.length, 7)
  assert.equal(Apps.entryName(entries[0]).length, 512)
  assert.ok(Apps.entryAcronym(entries[0]).length <= 256)
})

test("hidden ids cannot pollute object prototypes", () => {
  const hidden = Apps.hiddenMap(["__proto__", "constructor"])
  assert.equal(Object.getPrototypeOf(hidden), null)
  assert.equal(hidden.__proto__, true)
  assert.equal(hidden.constructor, true)
  assert.equal({}.polluted, undefined)
})

test("a browser-installed web app's generated id does not leak into search text or acronym", () => {
  // Real bug: a Chrome PWA's .desktop id is
  // chrome-<32-char extension id>-<profile directory name>, e.g.
  // "chrome-agimnkijcaahngcdmfeangaknmldooml-Default" - every PWA installed
  // under the default Chrome profile was matching the search "default"
  // because entrySearchText() folded that generated id in as if it were a
  // meaningful, human-typed identifier.
  const youtube = { id: "chrome-agimnkijcaahngcdmfeangaknmldooml-Default", name: "YouTube" }
  const text = Apps.entrySearchText(youtube)
  assert.ok(!text.includes("default"), text)
  assert.ok(!text.includes("chrome-"), text)
  // entryAcronym folded the id in too ("ytcad" instead of "yt") - same fix.
  assert.equal(Apps.entryAcronym(youtube), "yt")

  // A profile other than "Default" must be excluded the same way - the
  // pattern is the generated id shape, not that one specific string.
  const profile1 = { id: "chrome-agimnkijcaahngcdmfeangaknmldooml-Profile 1", name: "YouTube" }
  assert.ok(!Apps.entrySearchText(profile1).includes("profile"))

  // omarchy-launch-webapp installs the same id shape for other Chromium-
  // based browsers - the invariant is the 32-letter extension id, not the
  // "chrome-" prefix.
  const brave = { id: "brave-agimnkijcaahngcdmfeangaknmldooml-Default", name: "YouTube" }
  assert.ok(!Apps.entrySearchText(brave).includes("default"))

  // A normal app's id is still searchable - only the generated webapp shape
  // is excluded, not entry.id in general.
  const firefox = { id: "firefox", name: "Firefox" }
  assert.ok(Apps.entrySearchText(firefox).includes("firefox"))
  const vscode = { id: "code", name: "Visual Studio Code" }
  assert.ok(Apps.entrySearchText(vscode).includes("code"))
})

test("a generated web app id does not win a match through score() either", () => {
  // Found by review: the first fix only closed entrySearchText() - termMatches()
  // and score() read entry.id raw, independent of entrySearchText(), so the
  // PWA still matched "default" with a high score even after that fix.
  const youtube = { id: "chrome-agimnkijcaahngcdmfeangaknmldooml-Default", name: "YouTube" }
  assert.equal(Apps.score(youtube, "default"), -1)
  // A real, human id is still a legitimate match.
  assert.ok(Apps.score({ id: "firefox", name: "Firefox" }, "firefox") > 0)
})

test("isHidden accepts a callback as well as a map", () => {
  const entries = [{ id: "hidden-app", name: "Hidden" }, { id: "shown-app", name: "Shown" }]
  const callback = (entry) => entry.id === "hidden-app"
  const rows = Apps.sortedEntries(entries, "", callback, 10, 10)
  assert.deepEqual(rows.map(r => r.entry.id), ["shown-app"])
})
