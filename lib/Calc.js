// Arithmetic for the calculator row. A hand-written recursive-descent parser
// rather than eval(): this runs inside omarchy-shell, so a query string must
// never reach the JS evaluator.

var CONSTANTS = {
  pi: Math.PI,
  tau: Math.PI * 2,
  e: Math.E
}

var FUNCTIONS = {
  sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs,
  round: Math.round, floor: Math.floor, ceil: Math.ceil,
  sin: Math.sin, cos: Math.cos, tan: Math.tan,
  asin: Math.asin, acos: Math.acos, atan: Math.atan,
  ln: Math.log, log: function(x) { return Math.log(x) / Math.LN10 },
  log2: function(x) { return Math.log(x) / Math.LN2 },
  exp: Math.exp, sign: function(x) { return x < 0 ? -1 : (x > 0 ? 1 : 0) },
  min: Math.min, max: Math.max, pow: Math.pow, hypot: Math.hypot
}

var VARIADIC = { min: true, max: true, pow: true, hypot: true }

// An identifier in the query is matched by /[a-z_][a-z0-9_]*/, so `constructor`
// and `__proto__` are both things a user can type. Plain member access would
// find them on Object.prototype — `FUNCTIONS.__proto__` is an object with no
// .apply, which threw straight out of the keystroke handler — so every table
// lookup below goes through here and sees only keys the table owns.
var owned = Object.prototype.hasOwnProperty

function tableGet(table, name) {
  return owned.call(table, name) ? table[name] : undefined
}

// Percent forms get rewritten to plain arithmetic before tokenizing, because
// "%" means three different things depending on what sits next to it.
function normalize(src) {
  var s = String(src || "")
  // Grouping commas are allowed outside function calls; inside, commas always
  // separate arguments (max(1,234) must not become max(1234)).
  var calls = []
  s = s.replace(/([a-z_][a-z0-9_]*\s*)?\(|\)|\d+(?:,\d{3})+(?!\d)/gi, function(token, name) {
    if (token.slice(-1) === "(") calls.push(!!name || calls[calls.length - 1] === true)
    else if (token === ")") calls.pop()
    else if (!calls[calls.length - 1]) return token.replace(/,/g, "")
    return token
  })
  // "20% of 250" -> "(20/100)*(250)"
  s = s.replace(/(\d+(?:\.\d+)?)\s*%\s+of\s+/gi, "($1/100)*")
  // "250 + 10%" -> "(250)*(1+10/100)"; same for minus. Anchored so the left
  // side is the whole expression so far, which is what people mean by it.
  s = s.replace(/^\s*(.+?)\s*\+\s*(\d+(?:\.\d+)?)\s*%\s*$/i, "($1)*(1+$2/100)")
  s = s.replace(/^\s*(.+?)\s*-\s*(\d+(?:\.\d+)?)\s*%\s*$/i, "($1)*(1-$2/100)")
  // Any remaining bare "N%" is just N/100. "%" is always percent here;
  // remainder is spelled "mod", which the tokenizer handles as an operator.
  s = s.replace(/(\d+(?:\.\d+)?)\s*%/g, "($1/100)")
  s = s.replace(/\bx\b/gi, "*")
  s = s.replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-")
  return s
}

function tokenize(src) {
  var tokens = []
  var i = 0
  var s = src

  while (i < s.length) {
    var c = s.charAt(i)

    if (c === " " || c === "\t") { i++; continue }

    if (c >= "0" && c <= "9" || c === ".") {
      var start = i
      while (i < s.length && (s.charAt(i) >= "0" && s.charAt(i) <= "9" || s.charAt(i) === ".")) i++
      // Scientific notation: 1e6, 2.5e-3
      if (i < s.length && (s.charAt(i) === "e" || s.charAt(i) === "E")) {
        var save = i
        i++
        if (i < s.length && (s.charAt(i) === "+" || s.charAt(i) === "-")) i++
        if (i < s.length && s.charAt(i) >= "0" && s.charAt(i) <= "9") {
          while (i < s.length && s.charAt(i) >= "0" && s.charAt(i) <= "9") i++
        } else {
          i = save
        }
      }
      var num = Number(s.slice(start, i))
      if (!isFinite(num)) return null
      tokens.push({ t: "num", v: num })
      continue
    }

    if (/[a-z_]/i.test(c)) {
      var ns = i
      while (i < s.length && /[a-z0-9_]/i.test(s.charAt(i))) i++
      var word = s.slice(ns, i).toLowerCase()
      if (word === "mod") tokens.push({ t: "op", v: "mod" })
      else tokens.push({ t: "id", v: word })
      continue
    }

    if ("+-*/^()," .indexOf(c) >= 0) {
      // "//" and "**" are common typos for "/" and "^"
      if (c === "*" && s.charAt(i + 1) === "*") { tokens.push({ t: "op", v: "^" }); i += 2; continue }
      tokens.push({ t: c === "(" ? "lp" : (c === ")" ? "rp" : (c === "," ? "comma" : "op")), v: c })
      i++
      continue
    }

    return null
  }

  return tokens
}

function parse(tokens) {
  var pos = 0

  function peek() { return pos < tokens.length ? tokens[pos] : null }
  function next() { return tokens[pos++] }

  function expression() {
    var left = term()
    if (left === null) return null
    while (true) {
      var t = peek()
      if (!t || t.t !== "op" || (t.v !== "+" && t.v !== "-")) break
      next()
      var right = term()
      if (right === null) return null
      left = t.v === "+" ? left + right : left - right
    }
    return left
  }

  function term() {
    var left = power()
    if (left === null) return null
    while (true) {
      var t = peek()
      if (!t || t.t !== "op" || (t.v !== "*" && t.v !== "/" && t.v !== "mod")) break
      next()
      var right = power()
      if (right === null) return null
      if (right === 0 && (t.v === "/" || t.v === "mod")) return null
      if (t.v === "*") left = left * right
      else if (t.v === "/") left = left / right
      else left = left % right
    }
    return left
  }

  function power() {
    var base = unary()
    if (base === null) return null
    var t = peek()
    if (t && t.t === "op" && t.v === "^") {
      next()
      var exp = power()          // right-associative
      if (exp === null) return null
      return Math.pow(base, exp)
    }
    return base
  }

  function unary() {
    var t = peek()
    if (t && t.t === "op" && (t.v === "-" || t.v === "+")) {
      next()
      var v = unary()
      if (v === null) return null
      return t.v === "-" ? -v : v
    }
    return primary()
  }

  function primary() {
    var t = next()
    if (!t) return null

    if (t.t === "num") return t.v

    if (t.t === "lp") {
      var v = expression()
      if (v === null) return null
      var close = next()
      if (!close || close.t !== "rp") return null
      return v
    }

    if (t.t === "id") {
      var fn = tableGet(FUNCTIONS, t.v)
      var nt = peek()
      if (fn && nt && nt.t === "lp") {
        next()
        var args = []
        if (peek() && peek().t === "rp") {
          next()
        } else {
          while (true) {
            var a = expression()
            if (a === null) return null
            args.push(a)
            var sep = next()
            if (!sep) return null
            if (sep.t === "rp") break
            if (sep.t !== "comma") return null
          }
        }
        var variadic = tableGet(VARIADIC, t.v) === true
        if (!variadic && args.length !== 1) return null
        if (variadic && args.length < 1) return null
        var out = fn.apply(null, args)
        return isFinite(out) ? out : null
      }
      var constant = tableGet(CONSTANTS, t.v)
      if (constant !== undefined) return constant
      return null
    }

    return null
  }

  var value = expression()
  if (value === null || pos !== tokens.length) return null
  return value
}

// A bare number is not worth a calculator row; an expression is. "=" forces it.
function looksLikeExpression(src) {
  var s = String(src || "").trim()
  if (!s) return false
  if (s.charAt(0) === "=") return true
  var hasConstant = /\b(pi|tau|e)\b/i.test(s)
  if (!/\d/.test(s) && !hasConstant) return false
  if (!/[-+*/^%()]|\b(mod|x|sqrt|cbrt|abs|round|floor|ceil|sin|cos|tan|asin|acos|atan|ln|log2|log|exp|sign|min|max|pow|hypot|pi|tau)\b/i.test(s)) return false
  // Reject things that are clearly not maths: version numbers, times, dates,
  // paths, and any word that isn't a known function or constant.
  if (/^\d{1,2}:\d{2}/.test(s)) return false
  if (/^v?\d+\.\d+\.\d+/.test(s)) return false
  if (/[/\\]\w*[a-z]{3,}/i.test(s) && !/^[\d\s.+\-*/^%()]+$/.test(s)) return false
  var words = s.toLowerCase().match(/[a-z_][a-z0-9_]*/g) || []
  for (var i = 0; i < words.length; i++) {
    if (!tableGet(FUNCTIONS, words[i]) && tableGet(CONSTANTS, words[i]) === undefined
        && words[i] !== "of" && words[i] !== "x" && words[i] !== "mod") return false
  }
  return true
}

function format(n) {
  if (!isFinite(n)) return ""
  if (Math.abs(n) >= 1e15 || (n !== 0 && Math.abs(n) < 1e-9)) return String(Number(n.toPrecision(10)))
  var rounded = Number(n.toFixed(10))
  var s = String(rounded)
  // Thousands separators, integer part only.
  var parts = s.split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ")
  return parts.join(".")
}

// -> { value, text } or null
function evaluate(src) {
  var raw = String(src || "").trim()
  if (!looksLikeExpression(raw)) return null
  if (raw.charAt(0) === "=") raw = raw.slice(1)
  var tokens = tokenize(normalize(raw))
  if (!tokens || tokens.length === 0) return null
  var value = parse(tokens)
  if (value === null || !isFinite(value)) return null
  return { value: value, text: format(value) }
}
