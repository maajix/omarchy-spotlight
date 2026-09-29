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

function parse(text, defaultCurrency) {
  var s = String(text || "").trim()
  if (s.length > 512) return null
  // Word separators require a boundary; arrows and '=' also work without spaces.
  var split = s.match(/^(.*?)\s*(?:\b(?:to|in|as)\b|->|→|=)\s*(.*?)$/i)
  var quote = split ? code(split[2]) : defaultCode(defaultCurrency)
  if (!quote) return parseExpression(s, defaultCurrency)
  var left = split ? split[1].trim() : s
  var m = left.match(/^(-?\d+(?:[.,]\d+)?)\s*([a-z$€£]+)$/i)
  var amount, base
  if (m) {
    amount = Number(m[1].replace(",", "."))
    base = code(m[2])
    // A default target must not turn ordinary lowercase words ("cup", "try")
    // into currency lookups while someone is still typing a unit conversion.
    if (!split && /^[a-z]{3}$/i.test(m[2]) && m[2] !== m[2].toUpperCase()
        && !Object.prototype.hasOwnProperty.call(ALIASES, m[2].toLowerCase())) return null
    if (!split && /^(?:pound|pounds)$/i.test(m[2])) return null
  } else {
    m = left.match(/^(US\$|[$€£])\s*(-?\d+(?:[.,]\d+)?)$/i)
    if (!m) return parseExpression(s, defaultCurrency)
    amount = Number(m[2].replace(",", "."))
    base = code(m[1])
  }
  if (!base || !quote || !isFinite(amount)) return parseExpression(s, defaultCurrency)
  return { amount: amount, base: base, quote: quote, key: base + "/" + quote }
}

// Currency amounts carry a dimension; plain numbers can scale them. The
// expression parser accepts only arithmetic and known currency names.
function parseExpression(text, defaultCurrency) {
  var split = text.match(/^(.*?)\s*(?:\b(?:to|in|as)\b|->|→|=)\s*([a-z$€£]+)$/i)
  var source = split ? split[1].trim() : text
  var quote = split ? code(split[2]) : defaultCode(defaultCurrency)
  if (split && !quote) return null
  var tokens = [], bases = [], i = 0
  while (i < source.length) {
    var rest = source.slice(i), m
    if (/^\s/.test(rest)) { i++; continue }
    m = rest.match(/^(US\$|[$€£])\s*(-?\d+(?:[.,]\d+)?)/i)
    if (m) {
      var prefix = code(m[1])
      var prefixedValue = Number(m[2].replace(",", "."))
      if (!prefix || !isFinite(prefixedValue)) return null
      tokens.push({ type: "money", value: prefixedValue, base: prefix })
      bases.push(prefix); i += m[0].length; continue
    }
    m = rest.match(/^(\d+(?:[.,]\d+)?)(?:\s*([a-z$€£]+))?/i)
    if (m) {
      var value = Number(m[1].replace(",", "."))
      if (!isFinite(value)) return null
      if (m[2]) {
        var base = code(m[2])
        if (!base) return null
        // Inferred targets keep the shorthand rule: lowercase codes can be
        // ordinary words, even when the query contains arithmetic.
        if (!split && /^[a-z]{3}$/i.test(m[2]) && m[2] !== m[2].toUpperCase()
            && !Object.prototype.hasOwnProperty.call(ALIASES, m[2].toLowerCase())) return null
        if (!split && /^(?:pound|pounds)$/i.test(m[2])) return null
        tokens.push({ type: "money", value: value, base: base }); bases.push(base)
      } else tokens.push({ type: "number", value: value })
      i += m[0].length; continue
    }
    var op = rest.charAt(0)
    if ("+-*/()".indexOf(op) < 0) return null
    tokens.push({ type: op }); i++
  }
  if (tokens.length > 128 || !bases.length || tokens.length < 2
      || (tokens.length === 2 && (tokens[0].type === "+" || tokens[0].type === "-")))
    return null
  if (!quote) quote = bases[0]
  var pos = 0
  function expression() {
    var left = term()
    while (left && pos < tokens.length && (tokens[pos].type === "+" || tokens[pos].type === "-")) {
      var op = tokens[pos++].type, right = term()
      if (!right || left.money !== right.money) return null
      left = { op: op, left: left, right: right, money: left.money }
    }
    return left
  }
  function term() {
    var left = unary()
    while (left && pos < tokens.length && (tokens[pos].type === "*" || tokens[pos].type === "/")) {
      var op = tokens[pos++].type, right = unary()
      if (!right || (op === "*" && left.money && right.money)
          || (op === "/" && right.money)) return null
      left = { op: op, left: left, right: right, money: left.money || right.money }
    }
    return left
  }
  function unary() {
    var t = tokens[pos]
    if (t && (t.type === "+" || t.type === "-")) {
      pos++
      var child = unary()
      return child ? { op: t.type, child: child, money: child.money } : null
    }
    if (t && t.type === "(") {
      pos++
      var inner = expression()
      if (!inner || !tokens[pos] || tokens[pos++].type !== ")") return null
      return inner
    }
    if (t && (t.type === "money" || t.type === "number")) {
      pos++
      return { value: t.value, base: t.base, money: t.type === "money" }
    }
    return null
  }
  var tree = expression()
  if (!tree || !tree.money || pos !== tokens.length) return null
  var pairs = [], seen = {}
  for (var j = 0; j < bases.length; j++) {
    var pair = bases[j] + "/" + quote
    if (!Object.prototype.hasOwnProperty.call(seen, pair)) {
      seen[pair] = true; pairs.push({ base: bases[j], quote: quote, key: pair })
    }
  }
  return { expression: tree, source: source, quote: quote,
    base: bases[0], pairs: pairs, key: pairs.map(function(p) { return p.key }).sort().join("|") }
}

function pairs(target) {
  return target.pairs || [{ base: target.base, quote: target.quote, key: target.key }]
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

function nextPair(session, now) {
  if (!session.target) return null
  var required = pairs(session.target)
  for (var i = 0; i < required.length; i++) {
    var pair = required[i]
    if (pair.base === pair.quote) continue
    var cached = entry(session, pair.key)
    if (!cached || (!fresh(cached.rate, now) && now >= cached.retryAt)) return pair
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
  return !session.request && !!nextPair(session, now)
}

function begin(session, now) {
  if (!session.target || session.request) return null
  var pair = nextPair(session, now === undefined ? Date.now() : now)
  if (!pair) return null
  session.serial++
  session.request = { base: pair.base, quote: pair.quote, pairKey: pair.key,
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
  var pairKey = request.pairKey || request.key
  var cached = entry(session, pairKey)
  var rate = reply && reply.ok === true && validRate(reply, request, now) ? reply : null
  if (!rate && cached) rate = cached.rate
  var retryAt = !rate || !fresh(rate, now) ? now + RETRY : 0
  session.entries = session.entries.filter(function(e) { return e.key !== pairKey })
  session.entries.sort(function(a, b) { return b.storedAt - a.storedAt })
  // Keep the current answer even when its offline rate is the oldest one.
  session.entries = session.entries.slice(0, KEEP - 1)
  session.entries.push({ key: pairKey, rate: rate, retryAt: retryAt,
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
  if (target.expression) return expressionResult(target, cached, now, formatNumber)
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

function expressionResult(target, session, now, formatNumber) {
  if (!session) return null
  var stale = [], dates = []
  function evaluate(node) {
    if (node.op) {
      if (node.child) {
        var unaryValue = evaluate(node.child)
        return node.op === "-" ? -unaryValue : unaryValue
      }
      var a = evaluate(node.left), b = evaluate(node.right)
      if (node.op === "+") return a + b
      if (node.op === "-") return a - b
      if (node.op === "*") return a * b
      return b === 0 ? NaN : a / b
    }
    if (!node.money || node.base === target.quote) return node.value
    var cached = entry(session, node.base + "/" + target.quote)
    if (!cached || !cached.rate) return NaN
    if (dates.indexOf(cached.rate.date) < 0) dates.push(cached.rate.date)
    if (!fresh(cached.rate, now) && stale.indexOf(cached.retryAt > now
        ? "refresh unavailable" : "refreshing") < 0)
      stale.push(cached.retryAt > now ? "refresh unavailable" : "refreshing")
    return node.value * cached.rate.rate
  }
  var value = evaluate(target.expression)
  if (!isFinite(value)) return null
  var number = formatNumber(value), rendered = number + " " + target.quote
  var detail = target.source + " = " + rendered
  if (dates.length) detail += " · Frankfurter · " + dates.join(", ")
  if (stale.length) detail += " · Cached · " + stale.join(", ")
  return { text: rendered, detail: detail, copy: number.replace(/\s/g, "") }
}

if (typeof module !== "undefined") {
  module.exports = { CODES: CODES, TTL: TTL, RETRY: RETRY, KEEP: KEEP, parse: parse,
    defaultCode: defaultCode,
    createSession: createSession, entry: entry, select: select, begin: begin,
    accept: accept, cancel: cancel, result: result }
}
