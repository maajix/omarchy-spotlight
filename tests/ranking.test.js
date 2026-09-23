const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const Frecency = require("../lib/Frecency.js")
const Fuzzy = require("../lib/Fuzzy.js")
const Query = require("../lib/Query.js")
const Ranking = require("../lib/Ranking.js")

test("text matches use the six shared tiers", () => {
  assert.equal(Fuzzy.match({ title: "Firefox" }, "firefox").tier, "exact")
  assert.equal(Fuzzy.match({ title: "Firefox Developer" }, "firefox").tier, "prefix")
  assert.equal(Fuzzy.match({ title: "Mozilla-Firefox" }, "firefox").tier, "word")
  assert.equal(Fuzzy.match({ title: "MyFirefox" }, "firefox").tier, "substring")
  assert.equal(Fuzzy.match({ title: "Browser", keywords: "firefox" }, "firefox").tier, "metadata")
  assert.equal(Fuzzy.match({ title: "Visual Studio Code" }, "vsc").tier, "metadata")
  assert.equal(Fuzzy.match({ title: "Fire Browser", keywords: "fox" }, "fire fox").tier, "residual")
})

test("the final formula applies every type weight and clamps bonuses to 200", () => {
  for (const [type, weight] of Object.entries(Ranking.TYPE_WEIGHTS)) {
    assert.equal(Ranking.score({ resultType: type, textMatch: 100 }), 100 * weight)
  }
  assert.equal(Ranking.score({
    resultType: "app", textMatch: 0,
    recencyBonus: 400, frequencyBonus: 500, contextBonus: 1100
  }), 200)
})

test("ties are deterministic and independent of provider arrival order", () => {
  const a = { key: "a", stableId: "app:a", title: "Same", resultType: "app", textMatch: 850 }
  const b = { key: "b", stableId: "app:b", title: "Same", resultType: "app", textMatch: 850 }
  assert.deepEqual(Ranking.rank([b, a], 2).map(row => row.key), ["a", "b"])
  assert.deepEqual(Ranking.rank([a, b], 2).map(row => row.key), ["a", "b"])
})

test("provider priority keeps actions ahead of a flood of file results", () => {
  const action = { key: "shutdown", title: "Shut Down", resultType: "action" }
  const files = Array.from({ length: 20 }, (_, i) => ({
    key: `file:${i}`, title: "shutdown.rs", resultType: "file"
  }))
  const rows = [action, ...files]
  for (const row of rows) row.textMatch = Fuzzy.score(row, "shut")

  assert.equal(Ranking.rank(rows, 20)[0].key, "shutdown")
})

test("view completion appears before apps, actions and files", () => {
  const view = { key: "view:docker", title: "docker:", resultType: "view", textMatch: Fuzzy.MATCH_EXACT }
  const app = { key: "app:lazydocker", title: "lazydocker", resultType: "app", textMatch: Fuzzy.MATCH_WORD }
  const action = { key: "action:docker", title: "Docker setup", resultType: "action", textMatch: Fuzzy.MATCH_WORD }
  const file = { key: "file:docker", title: "Dockerfile", resultType: "file", textMatch: Fuzzy.MATCH_EXACT }
  assert.deepEqual(Ranking.rank([file, view, action, app], 4).map(row => row.key), [view.key, app.key, action.key, file.key])
})

test("mixed results order apps, actions, files, then web", () => {
  const rows = [
    { key: "web", title: "Search", resultType: "web", textMatch: Fuzzy.MATCH_EXACT },
    { key: "file", title: "sleep", resultType: "file", textMatch: Fuzzy.MATCH_EXACT },
    { key: "action", title: "Stay Awake", resultType: "action", textMatch: Fuzzy.MATCH_METADATA },
    { key: "app", title: "Sleep Timer", resultType: "app", textMatch: Fuzzy.MATCH_METADATA }
  ]

  assert.deepEqual(Ranking.rank(rows, 4).map(row => row.key), [
    "app", "action", "file", "web"
  ])
})

test("repeated Firefox selection for fi moves it ahead of Figma", () => {
  const now = 1000000000
  const parsed = Query.parse("fi")
  let store = Frecency.emptyStore()
  for (let i = 0; i < 3; i++)
    store = Frecency.bump(store, "app:firefox", Query.contextKeys(parsed), null, now + i)

  const rows = [
    { key: "figma", stableId: "app:figma", title: "Figma", resultType: "app", textMatch: Fuzzy.MATCH_PREFIX },
    { key: "firefox", stableId: "app:firefox", title: "Firefox", resultType: "app", textMatch: Fuzzy.MATCH_PREFIX }
  ]
  for (const row of rows) {
    const bonus = Frecency.bonuses(store, row.stableId, Query.contextKey(parsed), now + 3, true)
    row.recencyBonus = bonus.recency
    row.frequencyBonus = bonus.frequency
    row.contextBonus = bonus.context
  }
  assert.equal(Ranking.rank(rows, 2)[0].key, "firefox")
})

test("maximum personalization cannot beat an exact hit with a substring hit of the same type", () => {
  const exact = { key: "exact", title: "Exact", resultType: "app", textMatch: Fuzzy.MATCH_EXACT }
  const weak = {
    key: "weak", title: "Weak", resultType: "app", textMatch: Fuzzy.MATCH_SUBSTRING,
    recencyBonus: 40, frequencyBonus: 50, contextBonus: 110
  }
  assert.equal(Ranking.rank([weak, exact], 2)[0].key, "exact")
})

test("real usage can move a neighboring prefix tier above an unused exact tier", () => {
  const now = 2000000
  let store = Frecency.emptyStore()
  for (let i = 0; i < 3; i++)
    store = Frecency.bump(store, "app:used", ["query:fi"], null, now + i)
  const bonus = Frecency.bonuses(store, "app:used", "query:fi", now + 3, true)
  const rows = [
    { key: "exact", title: "Exact", resultType: "app", textMatch: Fuzzy.MATCH_EXACT },
    {
      key: "used", stableId: "app:used", title: "Used", resultType: "app",
      textMatch: Fuzzy.MATCH_PREFIX, recencyBonus: bonus.recency,
      frequencyBonus: bonus.frequency, contextBonus: bonus.context
    }
  ]
  assert.equal(Ranking.rank(rows, 2)[0].key, "used")
})

test("learning can be disabled without deleting stored data", () => {
  const store = Frecency.bump(Frecency.emptyStore(), "app:firefox", ["query:fi"], null, 1000)
  assert.equal(Frecency.hasItem(store, "app:firefox"), true)
  assert.deepEqual(Frecency.bonuses(store, "app:firefox", "query:fi", 1001, false), {
    recency: 0, frequency: 0, context: 0
  })
})

test("the in-memory store enforces item, file, context and hit limits", () => {
  assert.equal(Frecency.utf8Bytes("a😀"), 5)
  const parsed = { version: 2, items: {}, contexts: {} }
  const appIds = []
  for (let i = 0; i < 300; i++) {
    const id = `app:${"x".repeat(220)}${i}`
    appIds.push(id)
    parsed.items[id] = { count: 1, last: i }
  }
  for (let i = 0; i < 120; i++) {
    parsed.items[`file:${String(i).padStart(64, "0")}`] = {
      count: 1, last: i, meta: { path: `/tmp/${i}` }
    }
  }
  for (let c = 0; c < 140; c++) {
    const hits = {}
    for (let i = 0; i < 10; i++) hits[appIds[i]] = { count: 1, last: c }
    parsed.contexts[`query:q${c}`] = hits
  }
  const store = Frecency.adopt(parsed, 10000)
  assert.equal(Object.keys(store.items).length, 400)
  assert.equal(Object.keys(store.items).filter(id => id.startsWith("file:")).length, 100)
  assert.ok(Object.keys(store.contexts).length <= 128)
  assert.ok(Object.values(store.contexts).every(hits => Object.keys(hits).length <= 8))
  assert.ok(Frecency.utf8Bytes(JSON.stringify(store)) <= 200000)
})

test("V1 app and command counts migrate to stable V2 ids", () => {
  const store = Frecency.adopt({
    "app:firefox": { count: 2, last: 10 },
    "cmd:theme.pick": { count: 3, last: 20 },
    "bang.gh": { count: 4, last: 30 }
  }, 40)
  assert.equal(store.version, 2)
  assert.equal(store.items["app:firefox"].count, 2)
  assert.equal(store.items["action:theme.pick"].count, 3)
  assert.equal(store.items["bang.gh"], undefined)
})

test("only primary activations reach the learning call", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Spotlight.qml"), "utf8")
  assert.match(qml, /if \(!secondary\) root\.bumpUsage\(r\)/)
})
