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
  const root = { opened: true, query: "", currencySession: Currency.createSession(),
    row: spec => spec, rebuild() {}, stopCurrencyProcess() { this.stops++ }, stops: 0 }
  const timer = { running: false, stop() { this.running = false }, restart() { this.running = true } }
  const context = vm.createContext({ root, currencyDebounce: timer, Currency, Query, Units,
    Date: { now: () => NOW }, Calc: { evaluate: () => null },
    NaturalTime: { parseReminder: () => null, parseEvent: () => null },
    Web: { detectUrl: () => "" }, Fuzzy: { MATCH_EXACT: 100 } })
  for (const name of ["intentRows", "updateCurrency", "loadCurrency"]) {
    const source = qml.match(new RegExp("  function " + name + "\\([^]*?\\n  }"))[0]
    vm.runInContext(source, context)
    root[name] = context[name]
  }
  return { root, timer }
}

test("QML filters, unit precedence, loading rows and copy payloads", () => {
  const { root, timer } = overlay()
  for (const query of ["100 USD to EUR", "unit: 100 USD to EUR", "convert: $100 to €"]) {
    root.query = query
    root.updateCurrency()
    const parsed = Query.parse(query)
    const rows = root.intentRows(parsed.text, parsed.filter)
    assert.equal(rows[0].kind, "noop")
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
