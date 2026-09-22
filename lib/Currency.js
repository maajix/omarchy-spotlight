// Active codes from https://frankfurter.dev/currencies/ (2026-09-22).
// A bundled catalog keeps incomplete queries and ordinary words offline.
var CODES = ("AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BHD BIF BMD BND BOB "
  + "BRL BSD BTN BWP BYN BZD CAD CDF CHF CLP CMD CNH CNY COP CRC CUP CVE CZK DJF DKK "
  + "DOP DZD EGP ERN ETB EUR FJD FKP GBP GEL GGP GHS GIP GMD GNF GTQ GYD HKD HNL "
  + "HTG HUF IDR ILS IMP INR IQD IRR ISK JEP JMD JOD JPY KES KGS KHR KMF KPW KRW "
  + "KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT MOP MRO MRU MUR "
  + "MVR MWK MXN MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG "
  + "QAR RON RSD RUB RWF SAR SBD SCR SDG SEK SGD SHP SLE SOS SRD SSP STN SVC SYP "
  + "SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX USD UYU UZS VES VND VUV WST "
  + "XAF XAG XAU XCD XCG XDR XOF XPD XPF XPT YER ZAR ZMW ZWG").split(" ")

var ALIASES = {
  "$": "USD", "us$": "USD", dollar: "USD", dollars: "USD",
  "€": "EUR", euro: "EUR", euros: "EUR",
  "£": "GBP", pound: "GBP", pounds: "GBP", sterling: "GBP",
  yen: "JPY", yuan: "CNY"
}
var TTL = 24 * 60 * 60 * 1000
var RETRY = 60 * 1000
var KEEP = 128

function code(text) {
  var s = String(text || "").trim().toLowerCase()
  if (Object.prototype.hasOwnProperty.call(ALIASES, s)) return ALIASES[s]
  var upper = s.toUpperCase()
  return CODES.indexOf(upper) >= 0 ? upper : ""
}

function defaultCode(value) {
  var upper = typeof value === "string" ? value.trim().toUpperCase() : ""
  return CODES.indexOf(upper) >= 0 ? upper : ""
}

function currencyOptions() {
  return [{ value: "", label: "None (explicit target)" }].concat(CODES.map(function(code) {
    return { value: code, label: code }
  }))
}

function parse(text, defaultCurrency) {
  var s = String(text || "").trim()
  if (s.length > 512) return null
  // Word separators require a boundary; arrows and '=' also work without spaces.
  var split = s.match(/^(.*?)\s*(?:\b(?:to|in|as)\b|->|→|=)\s*(.*?)$/i)
  var quote = split ? code(split[2]) : defaultCode(defaultCurrency)
  if (!quote) return null
  var left = split ? split[1].trim() : s
  var m = left.match(/^(-?\d+(?:[.,]\d+)?)\s*([a-z$€£]+)$/i)
  var amount, base
  if (m) {
    amount = Number(m[1].replace(",", "."))
    base = code(m[2])
  } else {
    m = left.match(/^(US\$|[$€£])\s*(-?\d+(?:[.,]\d+)?)$/i)
    if (!m) return null
    amount = Number(m[2].replace(",", "."))
    base = code(m[1])
  }
  if (!base || !quote || !isFinite(amount)) return null
  return { amount: amount, base: base, quote: quote, key: base + "/" + quote }
}

function validRate(rate, target, now) {
  return rate && rate.base === target.base && rate.quote === target.quote
    && typeof rate.rate === "number" && isFinite(rate.rate) && rate.rate > 0
    && typeof rate.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(rate.date)
    && typeof rate.fetchedAt === "number" && isFinite(rate.fetchedAt)
    && rate.fetchedAt > 0 && rate.fetchedAt * 1000 <= now
}

function fresh(rate, now) {
  return rate && now >= rate.fetchedAt * 1000 && now - rate.fetchedAt * 1000 < TTL
}

function createSession() {
  return { target: null, generation: 0, serial: 0, request: null, entries: [] }
}

function entry(session, key) {
  for (var i = 0; i < session.entries.length; i++) {
    if (session.entries[i].key === key) return session.entries[i]
  }
  return null
}

// Amount edits share a request; changing pair (even away and back) invalidates it.
function select(session, target, now) {
  var oldKey = session.target ? session.target.key : ""
  var key = target ? target.key : ""
  if (oldKey !== key) {
    session.generation++
    session.request = null
  }
  session.target = target
  if (!target || target.base === target.quote || session.request) return false
  var cached = entry(session, key)
  return !cached || (!fresh(cached.rate, now) && now >= cached.retryAt)
}

function begin(session) {
  if (!session.target || session.request) return null
  session.serial++
  session.request = { base: session.target.base, quote: session.target.quote,
    key: session.target.key, generation: session.generation, serial: session.serial }
  return session.request
}

function accept(session, request, reply, now) {
  // createObject can round-trip a JS object through QVariantMap. Compare
  // tokens by value, not object identity, across the QML process boundary.
  if (!request || !session.request || request.serial !== session.request.serial
      || request.generation !== session.generation
      || !session.target || request.key !== session.target.key) return false
  session.request = null
  var cached = entry(session, request.key)
  var rate = reply && reply.ok === true && validRate(reply, request, now) ? reply : null
  if (!rate && cached) rate = cached.rate
  var retryAt = !rate || !fresh(rate, now) ? now + RETRY : 0
  session.entries = session.entries.filter(function(e) { return e.key !== request.key })
  session.entries.sort(function(a, b) { return b.storedAt - a.storedAt })
  // Keep the current answer even when its offline rate is the oldest one.
  session.entries = session.entries.slice(0, KEEP - 1)
  session.entries.push({ key: request.key, rate: rate, retryAt: retryAt,
    storedAt: rate ? rate.fetchedAt * 1000 : now })
  return true
}

function cancel(session) {
  session.generation++
  session.request = null
  session.target = null
}

// Formatting uses the same adaptive precision as the offline unit converter.
function result(target, cached, now, formatNumber) {
  if (!target) return null
  var identity = target.base === target.quote
  var rate = identity ? 1 : (cached && cached.rate ? cached.rate.rate : NaN)
  var value = target.amount * rate
  if (!isFinite(value)) return null
  var number = formatNumber(value)
  var text = number + " " + target.quote
  var detail = formatNumber(target.amount) + " " + target.base + " = " + text
  if (!identity) {
    detail += " · Frankfurter · " + cached.rate.date
    if (!fresh(cached.rate, now)) {
      detail += cached.retryAt > now ? " · Cached · refresh unavailable" : " · Cached · refreshing"
    }
  }
  return { text: text, detail: detail, copy: number.replace(/\s/g, "") }
}

if (typeof module !== "undefined") {
  module.exports = { CODES: CODES, TTL: TTL, RETRY: RETRY, KEEP: KEEP, parse: parse,
    defaultCode: defaultCode, currencyOptions: currencyOptions,
    createSession: createSession, entry: entry, select: select, begin: begin,
    accept: accept, cancel: cancel, result: result }
}
