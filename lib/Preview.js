// The side pane next to the results. A preview is plain data: a list of
// blocks the pane knows how to paint, built from the selected row and, for
// rows that need more than the row carries, one helper reply.
//
//   need(row, ctx)        -> { key, args } or null: the helper call to make
//   build(row, ctx, data) -> { blocks } or null: what to paint
//   rich(row)             -> whether the row has a preview of its own
//
// `data` is { state: "loading" | "ready" | "error", reply } for the `need`
// whose key matches, or null. The QML side runs the call and repaints; it
// never interprets a block itself beyond its type.
//
// Block types:
//   { type: "label", text }                   small heading
//   { type: "hero", text, mono, name }        the answer, large; with `name`,
//                                             one shorter line for a title
//   { type: "lines", items: [{ text, note }], mono }
//   { type: "fields", items: [{ label, value, mono }] }
//   { type: "text", text, mono }              a preformatted excerpt
//   { type: "image", source, icon }           a local image, or an app icon
//   { type: "window", toplevel }              a live capture of a window
//   { type: "meta", text }                    the footnote under it all
//   { type: "status", text }                  loading or unavailable

var owned = Object.prototype.hasOwnProperty

// The pane's other-currency list: the user's default first, then these.
var PREVIEW_CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CHF"]
var MAX_CURRENCY_LINES = 4
// ISO 4217 currencies without minor units, shown without decimals.
var WHOLE_CURRENCIES = ["BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX",
                        "VND", "VUV", "XAF", "XOF", "XPF"]

function label(text) { return { type: "label", text: String(text) } }
function hero(text, mono) { return { type: "hero", text: String(text), mono: mono !== false } }
// A name rather than an answer: one line, smaller, shortened in the middle so
// a file keeps its extension.
function name(text) { return { type: "hero", text: String(text), mono: false, name: true } }
function meta(text) { return { type: "meta", text: String(text) } }
function status(text) { return { type: "status", text: String(text) } }
function fields(items) {
  var out = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (item && item.value !== undefined && item.value !== null && String(item.value) !== "")
      out.push({ label: String(item.label), value: String(item.value), mono: item.mono === true })
  }
  return out.length ? { type: "fields", items: out } : null
}
function lines(items, mono) { return { type: "lines", items: items, mono: mono !== false } }
function compact(blocks) { return blocks.filter(function(b) { return b !== null && b !== undefined }) }

// Money reads as money: two decimals, none for yen and the like, digits
// grouped with the same thin space the answer row uses.
function formatMoney(value, code) {
  if (!isFinite(value)) return ""
  var parts = Math.abs(value).toFixed(WHOLE_CURRENCIES.indexOf(code) >= 0 ? 0 : 2).split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ")
  return (value < 0 ? "-" : "") + parts.join(".") + " " + code
}

function previewQuotes(base, quote, preferred) {
  var list = []
  var candidates = (preferred ? [preferred] : []).concat(PREVIEW_CURRENCIES)
  for (var i = 0; i < candidates.length && list.length < MAX_CURRENCY_LINES; i++) {
    var code = candidates[i]
    if (code && code !== base && code !== quote && list.indexOf(code) < 0) list.push(code)
  }
  return list
}

// ------------------------------------------------------------- calculator

function integerBases(value) {
  if (!isFinite(value) || Math.floor(value) !== value || Math.abs(value) > Number.MAX_SAFE_INTEGER
      || Math.abs(value) < 2) return []
  var sign = value < 0 ? "-" : ""
  var abs = Math.abs(value)
  var out = [
    { text: sign + "0x" + abs.toString(16).toUpperCase(), note: "hex" },
    { text: sign + "0o" + abs.toString(8), note: "octal" }
  ]
  if (abs < 65536) out.push({ text: sign + "0b" + abs.toString(2), note: "binary" })
  return out
}

function calcPreview(row) {
  var p = row.payload || {}
  var value = Number(p.value)
  var items = integerBases(value)
  if (isFinite(value) && value !== 0 && (Math.abs(value) >= 1e6 || Math.abs(value) < 1e-3))
    items.push({ text: value.toExponential(6).replace(/\.?0+e/, "e"), note: "scientific" })
  return compact([
    label(row.subtitle),
    hero("= " + row.title),
    items.length ? lines(items) : null,
    meta("Calculator")
  ])
}

function unitPreview(row) {
  var related = (row.payload && row.payload.related) || []
  var items = []
  for (var i = 0; i < related.length; i++) items.push({ text: "= " + related[i].text, note: "" })
  return compact([label(row.subtitle), hero("= " + row.title), items.length ? lines(items) : null,
                  meta("Unit conversion")])
}

// --------------------------------------------------------------- currency

function currencyNeed(row, ctx) {
  var p = row.payload || {}
  if (!p.base || !p.quote || p.expression) return null
  var quotes = previewQuotes(p.base, p.quote, ctx && ctx.defaultCurrency)
  if (!quotes.length) return null
  var args = ["currency-rates"]
  if (ctx && ctx.currencyRates === false) args.push("--cached-only")
  args.push(p.base, quotes.join(","))
  return { key: "rates:" + (ctx && ctx.currencyRates === false ? "cached:" : "") + p.base + ":" + quotes.join(","),
           args: args }
}

function currencyPreview(row, ctx, data) {
  var p = row.payload || {}
  var format = ctx && ctx.formatNumber ? ctx.formatNumber : String
  var converted = Number(p.amount) * Number(p.rate)
  var out = [label(p.source || row.subtitle),
             hero("= " + (isFinite(converted) ? formatMoney(converted, p.quote) : row.title))]
  if (!p.expression && data && data.state === "ready" && data.reply && data.reply.rates) {
    var items = []
    var rates = data.reply.rates
    for (var i = 0; i < rates.length; i++) {
      var r = rates[i]
      if (!r || !isFinite(r.rate)) continue
      items.push({ text: "= " + formatMoney(Number(p.amount) * r.rate, r.quote),
                   note: r.stale ? "cached" : "" })
    }
    if (items.length) out.push(lines(items))
  } else if (!p.expression && data && data.state === "loading") {
    out.push(status("Loading other currencies…"))
  }
  if (p.base && p.quote && isFinite(p.rate) && p.base !== p.quote)
    out.push(meta("1 " + p.base + " = " + format(Number(p.rate)) + " " + p.quote
      + " · European Central Bank" + (p.date ? ", " + p.date : "")))
  else if (p.date) out.push(meta("European Central Bank, " + p.date))
  return out
}

// ------------------------------------------------------------------ files

var IMAGE_RE = /\.(?:png|jpe?g|gif|webp|bmp|svg|avif|tiff?)$/i

function humanBytes(n) {
  n = Number(n)
  if (!isFinite(n) || n < 0) return ""
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  return (i === 0 ? String(n) : n.toFixed(n >= 100 ? 0 : 1)) + " " + units[i]
}

// Every segment encoded, so "#" and "?" in a name stay part of the path.
function fileUrl(path) {
  return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
}

function fileNeed(row) {
  var p = row.payload || {}
  return p.path ? { key: "file:" + p.path, args: ["preview-file", String(p.path)] } : null
}

function filePreview(row, ctx, data) {
  var p = row.payload || {}
  var out = [label(row.subtitle || p.dir || "")]
  var reply = data && data.state === "ready" ? data.reply : null
  if (!reply) {
    out.push(name(row.title))
    out.push(status(data && data.state === "error" ? "Preview unavailable" : "Loading preview…"))
    return out
  }
  if (reply.kind === "image") out.push({ type: "image", source: fileUrl(p.path) })
  out.push(name(row.title))
  if (reply.kind === "text" && reply.text) out.push({ type: "text", text: String(reply.text), mono: true })
  if (reply.kind === "hidden") out.push(status("Contents hidden for private files"))
  if (reply.kind === "binary") out.push(status("Binary file"))
  if (reply.kind === "dir" && reply.entries) {
    var items = []
    for (var i = 0; i < reply.entries.length; i++) {
      var e = reply.entries[i]
      items.push({ text: (e.isDir ? "󰉋  " : "󰈔  ") + e.name, note: "" })
    }
    if (items.length) out.push(lines(items, false))
    else out.push(status("Empty folder"))
  }
  var f = fields([
    { label: "Kind", value: reply.description || "" },
    { label: "Size", value: reply.kind === "dir"
        ? (reply.count === undefined ? "" : reply.count + (reply.more ? "+" : "") + " items")
        : humanBytes(reply.size) },
    { label: "Modified", value: reply.modified || "" },
    { label: "Lines", value: reply.lines ? reply.lines + (reply.truncated ? "+" : "") : "" }
  ])
  if (f) out.push(f)
  out.push(meta(String(p.path)))
  return out
}

// -------------------------------------------------------------- clipboard

function clipNeed(row) {
  var p = row.payload || {}
  return isFinite(p.index) ? { key: "clip:" + p.index + ":" + p.title,
                              args: ["clipboard-preview", String(p.index), String(p.title || "")] }
    : null
}

function clipPreview(row, ctx, data) {
  var reply = data && data.state === "ready" ? data.reply : null
  var out = [label("Clipboard")]
  if (!reply) {
    out.push(status(data && data.state === "error" ? "Entry no longer in history" : "Loading entry…"))
    return out
  }
  out.push({ type: "text", text: String(reply.text || ""), mono: true })
  out.push(meta(reply.chars + " characters · " + reply.lines + (reply.lines === 1 ? " line" : " lines")
    + (reply.truncated ? " · excerpt" : "")))
  return out
}

// ------------------------------------------------------------- apps, windows

function appPreview(row) {
  var p = row.payload || {}
  var out = compact([
    p.icon ? { type: "image", source: String(p.icon), icon: true } : null,
    hero(row.title, false),
    p.comment ? { type: "text", text: String(p.comment), mono: false } : null,
    fields([
      { label: "Category", value: (p.categories || []).slice(0, 3).join(", ") },
      { label: "Runs", value: p.exec || "", mono: true },
      { label: "Desktop ID", value: p.appId || "", mono: true }
    ])
  ])
  return out
}

function windowPreview(row) {
  var p = row.payload || {}
  return compact([
    p.toplevel ? { type: "window", toplevel: p.toplevel } : null,
    name(row.title),
    fields([
      { label: "App", value: p.appId || row.subtitle },
      { label: "Workspace", value: p.workspace || "" },
      { label: "Monitor", value: p.monitor || "" },
      { label: "State", value: p.state || "" }
    ])
  ])
}

// ------------------------------------------------------------------ views
// Rows from Views.js already carry their entry; anything more comes from the
// helper's `preview-view`, which looks one entry up by its identity.

var VIEW_PREVIEWS = {
  ports: {
    need: function(p) { return p.pid ? ["process", String(p.pid)] : null },
    fields: function(p, r) {
      return [{ label: "Endpoint", value: p.endpoint, mono: true }, { label: "PID", value: p.pid },
              { label: "URL", value: p.url, mono: true },
              { label: "Command", value: r && r.command, mono: true },
              { label: "User", value: r && r.user }, { label: "Started", value: r && r.started }]
    }
  },
  ssh: {
    need: function(p) { return p.host ? ["ssh", String(p.host)] : null },
    fields: function(p, r) {
      return [{ label: "Host", value: p.host, mono: true }, { label: "HostName", value: r && r.hostname, mono: true },
              { label: "User", value: r && r.user }, { label: "Port", value: r && r.port },
              { label: "Identity", value: r && r.identity, mono: true },
              { label: "ProxyJump", value: r && r.proxyjump, mono: true }]
    }
  },
  docker: {
    need: function(p) { return p.id ? ["docker", String(p.id)] : null },
    fields: function(p, r) {
      return [{ label: "Image", value: r && r.image, mono: true }, { label: "Status", value: r && r.status },
              { label: "Ports", value: r && r.ports, mono: true },
              { label: "Started", value: r && r.started }, { label: "ID", value: String(p.id).slice(0, 12), mono: true }]
    },
    text: function(r) { return r && r.logs }
  },
  services: {
    need: function(p) { return p.name ? ["service", String(p.scope), String(p.name)] : null },
    fields: function(p, r) {
      return [{ label: "Unit", value: p.name, mono: true }, { label: "Scope", value: p.scope },
              { label: "State", value: r && r.state }, { label: "Since", value: r && r.since },
              { label: "Main PID", value: r && r.pid }, { label: "Memory", value: r && r.memory }]
    },
    text: function(r) { return r && r.logs }
  },
  mounts: {
    need: function(p) { return p.target ? ["mount", String(p.target)] : null },
    fields: function(p, r) {
      return [{ label: "Mounted at", value: p.target, mono: true },
              { label: "Used", value: r && r.size ? humanBytes(r.used) + " of " + humanBytes(r.size)
                + " (" + Math.round(100 * r.used / Math.max(1, r.size)) + "%)" : "" },
              { label: "Free", value: r && r.size ? humanBytes(r.free) : "" }]
    }
  },
  audio: {
    fields: function(p) {
      return [{ label: "Device", value: p.name, mono: true }, { label: "Kind", value: p.kind },
              { label: "Default", value: p.current ? "Yes" : "No" }]
    }
  },
  wifi: {
    fields: function(p) {
      return [{ label: "Network", value: p.ssid }, { label: "Signal", value: p.signal ? p.signal + "%" : "" },
              { label: "Security", value: p.security || "Open" },
              { label: "Status", value: p.connected ? "Connected" : "Available" }]
    }
  },
  bluetooth: {
    fields: function(p) {
      return [{ label: "Address", value: p.address, mono: true },
              { label: "Status", value: p.connected ? "Connected" : "Paired" }]
    }
  }
}

function viewNeed(row) {
  var spec = VIEW_PREVIEWS[row.kind]
  var args = spec && spec.need ? spec.need(row.payload || {}) : null
  return args ? { key: "view:" + args.join("\u0000"), args: ["preview-view"].concat(args) } : null
}

function viewPreview(row, ctx, data) {
  var spec = VIEW_PREVIEWS[row.kind]
  var p = row.payload || {}
  var reply = data && data.state === "ready" ? data.reply : null
  var out = [label(row.accessory || row.kind), name(row.title)]
  var f = fields(spec.fields(p, reply))
  if (f) out.push(f)
  var text = spec.text ? spec.text(reply) : ""
  if (text) out.push({ type: "text", text: String(text), mono: true })
  if (spec.need && spec.need(p) && data && data.state === "loading") out.push(status("Loading details…"))
  if (row.subtitle) out.push(meta(row.subtitle))
  return out
}

// ----------------------------------------------------------------- generic

function genericPreview(row) {
  return compact([
    row.accessory ? label(row.accessory) : null,
    name(row.title),
    row.subtitle ? { type: "text", text: row.subtitle, mono: false } : null
  ])
}

// --------------------------------------------------------------- dispatch

function specFor(row) {
  if (!row || row.kind === "noop") return null
  if (row.key === "calc") return { build: calcPreview }
  if (row.key === "unit") return { build: unitPreview }
  if (row.key === "currency" && row.kind === "copy") return { build: currencyPreview, need: currencyNeed }
  if (row.kind === "file") return { build: filePreview, need: fileNeed }
  if (row.kind === "clipcopy") return { build: clipPreview, need: clipNeed }
  if (row.kind === "app") return { build: appPreview }
  if (row.kind === "window") return { build: windowPreview }
  if (owned.call(VIEW_PREVIEWS, row.kind)) return { build: viewPreview, need: viewNeed }
  return null
}

function rich(row) { return specFor(row) !== null }

function need(row, ctx) {
  var spec = specFor(row)
  return spec && spec.need ? spec.need(row, ctx || {}) : null
}

function build(row, ctx, data) {
  if (!row || row.kind === "noop") return null
  var spec = specFor(row)
  var blocks = spec ? spec.build(row, ctx || {}, data || null) : genericPreview(row)
  return { blocks: compact(blocks) }
}

if (typeof module !== "undefined") {
  module.exports = { PREVIEW_CURRENCIES: PREVIEW_CURRENCIES, previewQuotes: previewQuotes,
    formatMoney: formatMoney,
    humanBytes: humanBytes, fileUrl: fileUrl, rich: rich, need: need, build: build }
}
