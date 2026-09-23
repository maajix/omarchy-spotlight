// Parses provider filters without stealing the existing web bangs. In
// particular, `w: firefox` is a window filter while `w firefox` remains a
// Wikipedia search.

var FILTERS = {
  a: "app", app: "app",
  w: "window", window: "window",
  f: "file", file: "file",
  action: "action", cmd: "action",
  cb: "clipboard", clipboard: "clipboard",
  web: "web", search: "web", url: "web",
  calc: "calc",
  unit: "unit", convert: "unit",
  reminder: "reminder",
  calendar: "calendar", event: "calendar",
  man: "tldr", tldr: "tldr"
}

var owned = Object.prototype.hasOwnProperty
var VIEWS = {
  ports: { title: "Listening ports", icon: "󰈀", field: "ports" },
  ssh: { title: "SSH hosts", icon: "󰌆", field: "hosts", command: "ssh-hosts" },
  docker: { title: "Docker containers", icon: "󰡨", field: "containers" },
  services: { title: "System and user services", icon: "󰒓", field: "services" },
  mounts: { title: "Mounted filesystems", icon: "󰋊", field: "mounts" },
  audio: { title: "Audio outputs and inputs", icon: "󰓃", field: "devices" },
  wifi: { title: "Wi-Fi networks", icon: "󰤨", field: "networks" },
  bluetooth: { title: "Paired Bluetooth devices", icon: "󰂯", field: "devices" }
}

function isView(name) { return owned.call(VIEWS, name) }
function viewDetails(name) { return isView(name) ? VIEWS[name] : null }

function viewCompletions(value) {
  var text = String(value || "").trim().toLowerCase()
  if (!/^[a-z]+:?$/.test(text)) return []
  var prefix = text.replace(/:$/, "")
  return Object.keys(VIEWS).filter(function(view) { return view.indexOf(prefix) === 0 })
}

// The default Enter target. Matching views sort first, so when the top row is
// a view this chooses between it and what follows: a view named exactly what
// was typed, then an app named exactly that, then, for a single matching
// view, an app whose name starts with the text. Several matching views defer
// to the first direct answer below them.
function firstSelectableIndex(rows, value) {
  var typed = String(value || "").trim().toLowerCase()
  var first = -1
  var exactApp = -1
  var prefixApp = -1
  var answer = -1
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (row.kind === "noop") continue
    if (first < 0) {
      if (row.kind !== "view") return i
      first = i
    }
    if (row.resultType === "app") {
      var title = String(row.title || "").toLowerCase()
      if (exactApp < 0 && title === typed) exactApp = i
      if (prefixApp < 0 && title.indexOf(typed) === 0) prefixApp = i
    }
    if (answer < 0 && (row.resultType === "intent" || row.resultType === "app"
        || row.resultType === "action")) answer = i
  }
  if (first < 0) return 0
  var completions = viewCompletions(typed)
  // Typing a view's whole name asks for the view: `docker` is the container
  // list, even with an app of the same name right below it.
  if (completions.length === 1 && completions[0] === typed) return first
  if (exactApp >= 0) return exactApp
  if (completions.length === 1) return prefixApp < 0 ? first : prefixApp
  return answer >= 0 ? answer : first
}

// What Tab writes for a row: a view's colon filter or an app's name.
function completionText(row) {
  if (!row) return ""
  if (row.kind === "view") return String((row.payload && row.payload.query) || "")
  if (row.kind === "app") return String(row.title || "")
  return ""
}

function parse(value) {
  var raw = String(value || "").trim()
  var match = raw.match(/^([a-z]+):\s*(.*)$/i)
  if (match) {
    var alias = match[1].toLowerCase()
    if (owned.call(FILTERS, alias) || isView(alias)) {
      var filtered = match[2].trim()
      return {
        raw: raw,
        text: filtered,
        filter: FILTERS[alias] || alias,
        empty: filtered.length === 0
      }
    }
  }

  // These space-separated forms predate colon filters (`man` and `tldr`
  // joined later) and remain exclusive provider choices.
  match = raw.match(/^(f|file|files|cb|clip|clipboard|man|tldr)\s+(\S.*)$/i)
  if (match) {
    var legacy = match[1].toLowerCase()
    return {
      raw: raw,
      text: match[2].trim(),
      filter: FILTERS[legacy] || (legacy === "files" ? "file" : "clipboard"),
      empty: false
    }
  }

  return { raw: raw, text: raw, filter: "", empty: false }
}

function contextKeys(query) {
  var text = String(query.text || "").toLowerCase().replace(/\s+/g, " ").trim().slice(0, 200)
  if (text.length < 2) return []
  var namespace = query.filter ? "filter:" + query.filter + ":" : "query:"
  var out = []
  var previous = ""
  for (var i = 2; i <= text.length && out.length < 127; i++) {
    var prefix = text.slice(0, i).trim()
    if (prefix.length >= 2 && prefix !== previous) {
      out.push(namespace + prefix)
      previous = prefix
    }
  }
  var full = namespace + text
  if (out[out.length - 1] !== full) out.push(full)
  return out
}

function contextKey(query) {
  var keys = contextKeys(query)
  return keys.length ? keys[keys.length - 1] : ""
}

if (typeof module !== "undefined") {
  module.exports = { parse: parse, viewCompletions: viewCompletions,
    firstSelectableIndex: firstSelectableIndex, completionText: completionText,
    VIEWS: VIEWS, isView: isView, viewDetails: viewDetails,
    contextKeys: contextKeys, contextKey: contextKey }
}
