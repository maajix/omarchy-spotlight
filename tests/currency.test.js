const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const test = require("node:test")
const Currency = require("../lib/Currency.js")
const Query = require("../lib/Query.js")

const Units = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "../lib/Units.js"), "utf8"), Units)
const NOW = Date.parse("2026-09-22T12:00:00Z")
const reply = (extra = {}) => ({ ok: true, base: "USD", quote: "EUR", rate: 0.9234,
  date: "2026-09-21", fetchedAt: NOW / 1000, stale: false, ...extra })
const target = text => Currency.parse(text || "100 USD to EUR")

test("a chosen default expands shorthand while explicit targets take priority", () => {
  for (const text of ["23 USD", "23USD", "$23", "US$23", "23 dollars"]) {
    assert.deepEqual(Currency.parse(text, "eur"), target("23 USD to EUR"), text)
    assert.equal(Currency.parse(text), null)
  }
  assert.deepEqual(Currency.parse("23 USD to JPY", "EUR"), target("23 USD to JPY"))
  assert.deepEqual(Currency.parse("-23,5 GBP", "EUR"), target("-23.5 GBP to EUR"))
  assert.deepEqual(Currency.parse("0 USD", "EUR"), target("0 USD to EUR"))
  assert.deepEqual(Currency.parse("23 EUR", "EUR"), target("23 EUR to EUR"))
  for (const text of ["23", "23 km", "23 ¥", "23 USD to", "23 USD in", "23 USD ->",
    "23 USD =", "23 USD to nope", "23 USD tomorrow"]) assert.equal(Currency.parse(text, "EUR"), null, text)
  for (const value of ["", "ZZZ", "eurO", null, 123, "€", "constructor"]) {
    assert.equal(Currency.defaultCode(value), "")
    assert.equal(Currency.parse("23 USD", value), null)
  }
  assert.equal(Currency.defaultCode(" eur "), "EUR")
  for (const text of ["2 cup", "5 all", "3 try", "23 usd", "23usd", "10 pen",
    "10 pound", "10 pounds"]) {
    assert.equal(Currency.parse(text, "EUR"), null, text)
  }
})

test("currency codes and common aliases normalize to explicit pairs", () => {
  for (const text of ["100 USD to EUR", "100usd in eur", "$100 to euros", "US$100 as €",
    "100 dollars -> euro", "100 USD→EUR", "100$=€"]) {
    assert.deepEqual(Currency.parse(text), target(), text)
  }
  assert.equal(target("100 euros in pounds").quote, "GBP")
  assert.equal(target("£100 to yen").quote, "JPY")
  assert.equal(target("1 sterling to yuan").base, "GBP")
  assert.equal(target("-12,5 EUR to USD").amount, -12.5)
  assert.equal(target("€-12.5 to $").amount, -12.5)
  assert.equal(target("0 CHF to CAD").amount, 0)
  assert.equal(Currency.CODES.length, new Set(Currency.CODES).size)
  for (const code of Currency.CODES) assert.equal(target(`1 ${code} to USD`).base, code)
})

test("incomplete, ambiguous, historical and ordinary text stays offline", () => {
  for (const text of ["", "100 USD", "$100", "100 to EUR", "100 USD to", "100 USD to E",
    "100 USD to EUR tomorrow", "100 USD to EUR to GBP", "1 ¥ to USD", "1 EUR to ¥",
    "1 constructor to USD", "1 XXX to USD", "1 BTC to EUR", "1 DEM to EUR", "NaN USD to EUR",
    "Infinity USD to EUR", "1,000.50 USD to EUR", "1 000 USD to EUR", "usd to eur",
    "find usd to eur", "9".repeat(400) + " USD to EUR"]) assert.equal(Currency.parse(text), null, text)
})

test("amount edits reuse requests and calculate from the latest amount", () => {
  const session = Currency.createSession()
  assert.equal(Currency.select(session, target(), NOW), true)
  const request = Currency.begin(session)
  assert.equal(Currency.select(session, target("200 USD to EUR"), NOW), false)
  assert.equal(Currency.begin(session), null)
  assert.equal(Currency.accept(session, request, reply(), NOW), true)
  const result = Currency.result(session.target, Currency.entry(session, "USD/EUR"), NOW, Units.formatNumber)
  assert.equal(result.text, "184.68 EUR")
  assert.equal(result.copy, "184.68")
  assert.match(result.detail, /^200 USD = 184.68 EUR · Frankfurter · 2026-09-21$/)
  assert.equal(Currency.select(session, target("999 USD to EUR"), NOW + 1000), false)
})

test("changing away and back rejects old replies, including after closing", () => {
  const session = Currency.createSession()
  Currency.select(session, target(), NOW)
  const old = Currency.begin(session)
  Currency.select(session, target("1 EUR to JPY"), NOW)
  Currency.select(session, target(), NOW)
  const current = Currency.begin(session)
  assert.equal(Currency.accept(session, old, reply(), NOW), false)
  assert.equal(session.request, current)
  Currency.cancel(session)
  assert.equal(Currency.accept(session, current, reply(), NOW), false)
  assert.equal(Currency.select(session, target(), NOW), true)
  assert.notEqual(Currency.begin(session).generation, current.generation)
})

test("24-hour expiry and failed-refresh cooldown preserve the dated cached rate", () => {
  const session = Currency.createSession()
  Currency.select(session, target(), NOW)
  Currency.accept(session, Currency.begin(session), reply(), NOW)
  assert.equal(Currency.select(session, target(), NOW + Currency.TTL - 1), false)
  const later = NOW + Currency.TTL
  assert.equal(Currency.select(session, target(), later), true)
  Currency.accept(session, Currency.begin(session), null, later)
  const cached = Currency.entry(session, "USD/EUR")
  assert.match(Currency.result(target(), cached, later, Units.formatNumber).detail,
    /2026-09-21 · Cached · refresh unavailable$/)
  assert.equal(Currency.select(session, target(), later + Currency.RETRY - 1), false)
  assert.equal(Currency.select(session, target(), later + Currency.RETRY), true)
  Currency.cancel(session)
  assert.equal(Currency.select(session, target(), later + 1000), false)
})

test("QML-copied request tokens are accepted once and cannot replace a later retry", () => {
  const session = Currency.createSession()
  Currency.select(session, target(), NOW)
  const first = JSON.parse(JSON.stringify(Currency.begin(session)))
  assert.equal(Currency.accept(session, first, null, NOW), true)
  Currency.select(session, target(), NOW + Currency.RETRY)
  const next = JSON.parse(JSON.stringify(Currency.begin(session)))
  assert.equal(Currency.accept(session, first, reply(), NOW + Currency.RETRY), false)
  assert.equal(Currency.accept(session, next, reply(), NOW + Currency.RETRY), true)
  assert.equal(Currency.accept(session, next, reply(), NOW + Currency.RETRY), false)
})

test("cold failures and malformed replies are unavailable with a retry cooldown", () => {
  for (const value of [null, { ok: false }, reply({ rate: -1 }), reply({ rate: Infinity }),
    reply({ rate: "1" }), reply({ base: "GBP" }), reply({ fetchedAt: NOW / 1000 + 1 })]) {
    const session = Currency.createSession()
    Currency.select(session, target(), NOW)
    Currency.accept(session, Currency.begin(session), value, NOW)
    const cached = Currency.entry(session, "USD/EUR")
    assert.equal(Currency.result(target(), cached, NOW, Units.formatNumber), null)
    assert.equal(Currency.select(session, target(), NOW + 1), false)
    assert.equal(Currency.select(session, target(), NOW + Currency.RETRY), true)
  }
})

test("identity conversions are local and clipboard text has no grouping or code", () => {
  const session = Currency.createSession()
  const identity = target("12345.67 euros to EUR")
  assert.equal(Currency.select(session, identity, NOW), false)
  const result = Currency.result(identity, null, NOW, Units.formatNumber)
  assert.equal(result.text, "12 345.67 EUR")
  assert.equal(result.copy, "12345.67")
  assert.doesNotMatch(result.detail, /Frankfurter/)
})

test("session cache stays bounded, including failed requests", () => {
  const session = Currency.createSession()
  for (const code of Currency.CODES) {
    if (code === "USD") continue
    Currency.select(session, target(`1 USD to ${code}`), NOW)
    Currency.accept(session, Currency.begin(session), null, NOW)
  }
  assert.equal(session.entries.length, Currency.KEEP)
  assert.ok(Currency.entry(session, session.target.key))
  assert.equal(Currency.select(session, session.target, NOW + 1), false)
})

// Execute the actual QML provider methods with a timer/process stand-in. This
// tests routing and row payloads, rather than merely matching implementation text.
function overlay() {
  const qml = fs.readFileSync(path.join(__dirname, "../Spotlight.qml"), "utf8")
  const root = { opened: true, query: "", settings: { defaultCurrency: "", currencyRates: true },
    settingsWrites: { pending: {}, active: {} },
    currencySession: Currency.createSession(), helperReply: JSON.parse,
    row: spec => spec, rebuild() { this.rebuilds++ }, rebuilds: 0,
    rows: [], indexOfKey(key) { return this.rows.findIndex(row => row.key === key) },
    bumpUsage() {}, dismiss() { this.opened = false; this.pendingCurrency = null },
    copyCalls: [],
    stopCurrencyProcess() { this.stops++ }, stops: 0 }
  const timer = { running: false, stop() { this.running = false }, restart() { this.running = true } }
  const context = vm.createContext({ root, currencyDebounce: timer,
    suggestDebounce: { stop() {} }, suggestProc: { running: false }, Currency, Query, Units,
    Util: { clamp: (v, min, max) => Math.min(max, Math.max(min, v)),
      execArgv: argv => root.copyCalls.push(argv) },
    Date: { now: () => NOW }, Calc: { evaluate: () => null },
    NaturalTime: { parseReminder: () => null, parseEvent: () => null },
    Web: { detectUrl: () => "", canonicalEngine: key => key }, Fuzzy: { MATCH_EXACT: 100 } })
  for (const name of ["currencyQuery", "intentRows", "updateCurrency", "loadCurrency",
    "loadSettings", "setupPending", "loadSuggestions", "activate"]) {
    const source = qml.match(new RegExp("  function " + name + "\\([^]*?\\n  }"))[0]
    vm.runInContext(source, context)
    root[name] = context[name]
  }
  return { root, timer }
}

test("settings arriving after query starts shorthand and suppress late suggestions", () => {
  const { root, timer } = overlay()
  root.query = "23 USD"
  root.updateCurrency()
  assert.equal(timer.running, false)
  root.suggestionRows = ["old suggestion"]
  root.loadSettings(JSON.stringify({ ok: true, settings: { defaultCurrency: "EUR", setupCompleted: true } }))
  assert.equal(timer.running, true)
  assert.equal(root.currencySession.target.quote, "EUR")
  assert.equal(root.suggestionRows.length, 0)
  root.loadSuggestions(JSON.stringify({ ok: true, suggestions: ["23 usd today"] }), root.query)
  assert.equal(root.suggestionRows.length, 0)
  const old = Currency.begin(root.currencySession)
  root.loadSettings(JSON.stringify({ ok: true, settings: { defaultCurrency: "JPY", setupCompleted: true } }))
  assert.equal(root.currencySession.target.quote, "JPY")
  assert.equal(Currency.accept(root.currencySession, old, reply(), NOW), false)
  root.loadSettings(JSON.stringify({ ok: true, settings: { defaultCurrency: "", setupCompleted: true } }))
  assert.equal(root.currencySession.target, null)
  assert.equal(timer.running, false)
  assert.equal(root.intentRows(root.query, "unit").length, 0)
})

test("unchanged settings avoid a second rebuild; disabled rates use local conversions", () => {
  const { root, timer } = overlay()
  root.query = "23 USD"
  root.loadSettings(JSON.stringify({ ok: true, settings: { defaultCurrency: "EUR", currencyRates: true } }))
  assert.equal(root.rebuilds, 1)
  assert.equal(timer.running, true)
  assert.equal(root.currencyQuery("2 cup"), null)
  root.loadSettings(JSON.stringify({ ok: true, settings: { defaultCurrency: "EUR", currencyRates: true } }))
  assert.equal(root.rebuilds, 1)
  const inFlight = Currency.begin(root.currencySession)
  root.loadSettings(JSON.stringify({ ok: true, settings: { defaultCurrency: "EUR", currencyRates: false } }))
  assert.equal(root.rebuilds, 2)
  assert.equal(Currency.accept(root.currencySession, inFlight, reply(), NOW), false)
  assert.ok(root.stops > 0)
  assert.equal(timer.running, true)
  assert.equal(root.currencySession.target.quote, "EUR")
  assert.equal(root.intentRows("23 USD", "unit")[0].kind, "currency-wait")
  assert.equal(root.intentRows("100 EUR to EUR", "unit")[0].kind, "copy")
})

test("shorthand works in conversion filters and retains numeric-only copy behavior", () => {
  const { root } = overlay()
  root.settings.defaultCurrency = "EUR"
  root.query = "convert: 23 USD"
  root.updateCurrency()
  const request = Currency.begin(root.currencySession)
  root.loadCurrency(JSON.stringify(reply()), request)
  const row = root.intentRows("23 USD", "unit")[0]
  assert.equal(row.title, "21.2382 EUR")
  assert.equal(row.payload.text, "21.2382")
  for (const query of ["23", "23 km", "web: 23 USD", "calc: 23 USD", "file: 23 USD",
    "convert: f 100 USD"]) {
    root.query = query
    root.updateCurrency()
    assert.equal(root.currencySession.target, null, query)
  }
  assert.equal(root.intentRows("f 100 USD", "unit").length, 0)
})

test("Enter on a loading rate copies the completed result", () => {
  const { root, timer } = overlay()
  root.query = "100 USD to EUR"
  root.updateCurrency()
  root.rows = root.intentRows(root.query, "unit")
  assert.equal(root.rows[0].primaryLabel, "Copy when ready")
  root.activate(0, false)
  assert.equal(root.pendingCurrency.key, "USD/EUR")
  assert.equal(root.copyCalls.length, 0)
  root.rebuild = function() { this.rows = this.intentRows(this.query, "unit") }
  const request = Currency.begin(root.currencySession)
  timer.stop()
  root.loadCurrency(JSON.stringify(reply()), request)
  assert.deepEqual(Array.from(root.copyCalls[0]), ["wl-copy", "--", "92.34"])
  assert.equal(root.opened, false)
})

test("QML filters, unit precedence, loading rows and copy payloads", () => {
  const { root, timer } = overlay()
  for (const query of ["100 USD to EUR", "unit: 100 USD to EUR", "convert: $100 to €"]) {
    root.query = query
    root.updateCurrency()
    const parsed = Query.parse(query)
    const rows = root.intentRows(parsed.text, parsed.filter)
    assert.equal(rows[0].kind, "currency-wait")
    assert.equal(rows[0].title, "Loading exchange rate…")
    assert.equal(timer.running, true)
  }
  const request = Currency.begin(root.currencySession)
  timer.stop()
  root.helperReply = JSON.parse
  root.loadCurrency(JSON.stringify(reply()), request)
  const row = root.intentRows("100 USD to EUR", "unit")[0]
  assert.equal(row.kind, "copy")
  assert.equal(row.payload.text, "92.34")
  assert.equal(row.section, "Conversions")
  for (const query of ["10 pounds to kg", "10 pounds to pounds", "10 km to miles", "web: 100 USD to EUR"]) {
    root.query = query
    root.updateCurrency()
    assert.equal(root.currencySession.target, null, query)
    assert.equal(timer.running, false)
  }
  assert.equal(root.intentRows("10 pounds to pounds", "unit")[0].key, "unit")
  root.query = "10 pounds to EUR"
  root.updateCurrency()
  assert.equal(root.currencySession.target.base, "GBP")
  root.opened = false
  root.updateCurrency()
  assert.equal(timer.running, false)
})
