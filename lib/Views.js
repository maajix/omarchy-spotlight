// Rows and actions for the colon views (`ports:`, `ssh:`, ...). Query.VIEWS
// holds each view's title, icon and helper field; this file holds how its
// entries are matched, shown and acted on. The QML side only adds row
// defaults and runs the step an action returns.

var owned = Object.prototype.hasOwnProperty
var HOST_RE = /^(?:[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}@)?[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$/
// An exact port number beats every text match; a loose abbreviation stays
// below every direct match so endpoint coincidences never outrank a name.
var EXACT_SCORE = 1100
var ABBREVIATION_SCORE = 100

function copy(text) { return { copy: String(text) } }

function portTitle(p) { return p.process || "Port " + p.port }

var SPECS = {
  ports: {
    noun: "listening ports",
    abbreviation: true,
    exact: function(p, q) { return q === String(p.port) },
    candidate: function(p) {
      return { title: portTitle(p), subtitle: p.endpoint + " " + p.protocol,
               keywords: String(p.pid || "") }
    },
    row: function(p) {
      return { key: "port:" + p.protocol + ":" + p.endpoint + ":" + (p.pid || ""),
               title: portTitle(p), subtitle: p.endpoint + (p.pid ? " · PID " + p.pid : ""),
               accessory: p.protocol,
               primaryLabel: p.url ? "Open URL" : "Copy endpoint", secondaryLabel: "Copy endpoint",
               payload: { endpoint: p.endpoint, url: p.url } }
    },
    // UDP listeners have no URL, so Enter copies them too.
    action: function(p, secondary) { return secondary || !p.url ? copy(p.endpoint) : { url: p.url } }
  },

  ssh: {
    noun: "SSH hosts",
    empty: "No saved SSH hosts · type a hostname",
    exact: function(h, q) { return q === String(h.name).toLowerCase() },
    candidate: function(h) { return { title: h.name } },
    row: function(h) {
      return { key: "ssh:" + h.name, title: h.name,
               subtitle: (h.source === "known_hosts" ? "Known host" : "Saved host") + " · ssh " + h.name,
               accessory: "SSH", primaryLabel: "Connect", secondaryLabel: "Copy command",
               payload: { host: h.name } }
    },
    // A typed host that is not itself saved; never one ssh could read as an option.
    fallback: function(q) {
      if (!HOST_RE.test(q)) return null
      return { key: "ssh.direct:" + q, title: "Connect to " + q, subtitle: "ssh " + q,
               accessory: "SSH", primaryLabel: "Connect", secondaryLabel: "Copy command",
               payload: { host: q } }
    },
    // Hold only on ssh's own failures (255), not after a normal logout.
    action: function(p, secondary) {
      return secondary ? copy("ssh " + p.host) : { terminal: ["ssh", String(p.host)], holdIf: 255 }
    }
  },

  docker: {
    noun: "containers",
    error: "Docker unavailable · check daemon access",
    candidate: function(c) {
      return { title: c.name, subtitle: c.image + " " + c.status + " " + c.ports, keywords: c.id }
    },
    row: function(c) {
      return { key: "docker:" + c.id, title: c.name || c.id.slice(0, 12),
               subtitle: c.image + " · " + c.status + (c.ports ? " · " + c.ports : ""),
               accessory: c.state, primaryLabel: "Follow logs", secondaryLabel: "Copy ID",
               payload: { id: c.id } }
    },
    action: function(p, secondary) {
      return secondary ? copy(p.id)
        : { terminal: ["docker", "logs", "--follow", "--tail", "100", String(p.id)] }
    }
  },

  services: {
    noun: "services",
    empty: "No loaded services",
    candidate: function(s) {
      return { title: s.name, subtitle: s.description + " " + s.active + " " + s.sub,
               keywords: s.scope }
    },
    row: function(s) {
      return { key: "service:" + s.scope + ":" + s.name, title: s.name.replace(/\.service$/, ""),
               subtitle: s.active + " / " + s.sub + (s.description ? " · " + s.description : ""),
               accessory: s.scope, primaryLabel: "Follow logs", secondaryLabel: "Copy unit name",
               payload: { name: s.name, scope: s.scope } }
    },
    action: function(p, secondary) {
      return secondary ? copy(p.name)
        : { terminal: ["journalctl", p.scope === "user" ? "--user" : "--system", "--follow",
                       "--lines", "100", "--no-pager", "--unit=" + String(p.name)] }
    }
  },

  mounts: {
    noun: "mounts",
    candidate: function(m) { return { title: m.target, subtitle: m.source + " " + m.fstype } },
    row: function(m) {
      return { key: "mount:" + m.target, title: m.target, subtitle: m.source,
               accessory: m.fstype, primaryLabel: "Open mount", secondaryLabel: "Copy path",
               payload: { target: m.target } }
    },
    action: function(p, secondary) { return secondary ? copy(p.target) : { path: String(p.target) } }
  },

  audio: {
    noun: "audio devices",
    group: function(d) { return d.kind === "output" ? 0 : 1 },
    candidate: function(d) {
      return { title: d.description, subtitle: d.name, keywords: d.kind + " "
               + (d.kind === "output" ? "speaker headphones" : "microphone mic") }
    },
    row: function(d) {
      var output = d.kind === "output"
      return { key: "audio:" + d.kind + ":" + d.name, title: d.description || d.name,
               subtitle: (d.default ? "Default" : "Available") + (d.volume ? " · " + d.volume : "")
                 + (d.muted ? " · Muted" : ""),
               section: output ? "Audio outputs" : "Audio inputs",
               accessory: output ? "Output" : "Input", icon: output ? "" : "󰍬",
               primaryLabel: d.default ? "Current default" : "Set as default",
               payload: { kind: d.kind, name: d.name, id: d.id, current: d.default } }
    },
    // Omarchy's setters also move the streams already playing, like its audio panel.
    action: function(p) {
      if ((p.kind !== "output" && p.kind !== "input") || p.current) return null
      var output = p.kind === "output"
      if (!p.id) return { argv: ["pactl", output ? "set-default-sink" : "set-default-source", String(p.name)] }
      return { argv: [output ? "omarchy-audio-output-set-default" : "omarchy-audio-input-set-default",
                      String(p.id), String(p.name)] }
    }
  },

  wifi: {
    noun: "Wi-Fi networks",
    manage: { title: "Manage Wi-Fi…", empty: "No Wi-Fi networks · open Network panel",
              argv: ["omarchy-shell", "omarchy.network", "show"] },
    candidate: function(n) { return { title: n.ssid, subtitle: n.security } },
    row: function(n) {
      return { key: "wifi:" + n.ssid, title: n.ssid,
               subtitle: (n.connected ? "Connected" : "Available") + " · " + n.signal
                 + "% signal · " + (n.security || "Open"),
               accessory: n.connected ? "Connected" : "Wi-Fi",
               primaryLabel: n.connected || n.ssid.charAt(0) === "-" ? "Manage network" : "Connect",
               payload: { ssid: n.ssid, connected: n.connected } }
    },
    // nmcli would read an SSID that starts with "-" as an option.
    action: function(p) {
      return p.connected || String(p.ssid).charAt(0) === "-"
        ? { argv: ["omarchy-shell", "omarchy.network", "show"] }
        : { terminal: ["nmcli", "--ask", "device", "wifi", "connect", String(p.ssid)] }
    }
  },

  bluetooth: {
    noun: "Bluetooth devices",
    manage: { title: "Pair another device…", empty: "No paired devices · open Bluetooth panel",
              argv: ["omarchy-shell", "omarchy.bluetooth", "show"] },
    candidate: function(d) { return { title: d.name, subtitle: d.address } },
    row: function(d) {
      return { key: "bluetooth:" + d.address, title: d.name,
               subtitle: d.connected ? "Connected" : "Paired", accessory: "Bluetooth",
               primaryLabel: d.connected ? "Disconnect" : "Connect",
               // Dropping a device in use takes a second Enter.
               confirm: d.connected === true,
               payload: { address: d.address, connected: d.connected } }
    },
    action: function(p) {
      return { argv: ["omarchy-bluetooth-device", p.connected ? "disconnect" : "connect",
                      String(p.address)] }
    }
  }
}

function subsequence(query, text) {
  var at = 0
  for (var i = 0; i < text.length && at < query.length; i++)
    if (text.charAt(i) === query.charAt(at)) at++
  return at === query.length
}

// Group (audio outputs first), then match score, then helper order.
function rank(spec, entries, query, match) {
  var scored = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    var exact = !!(query && spec.exact && spec.exact(entry, query))
    var score = exact ? EXACT_SCORE : 0
    if (query && !exact) {
      var candidate = spec.candidate(entry)
      var found = match(candidate, query)
      score = found ? found.score
        : spec.abbreviation && !/\s/.test(query)
          && subsequence(query, String(candidate.title).toLowerCase()) ? ABBREVIATION_SCORE : -1
    }
    if (score >= 0)
      scored.push({ entry: entry, score: score, exact: exact,
                    group: spec.group ? spec.group(entry) : 0, order: i })
  }
  scored.sort(function(a, b) { return a.group - b.group || b.score - a.score || a.order - b.order })
  return scored
}

// Row specs for one view: a status row until the list is ready, otherwise the
// matching entries plus at most one extra row (direct connect, manage, or an
// empty/no-match note). `view` is { state, entries, partial }.
function rows(name, details, view, q, match) {
  var spec = SPECS[name]
  var query = String(q || "").toLowerCase().trim()
  var suffix = view.partial ? " · partial list" : ""
  var section = details.title + suffix
  function note(key, title) {
    return { key: name + "." + key, kind: "noop", title: title, section: section,
             icon: details.icon, primaryLabel: "" }
  }
  if (view.state !== "ready") {
    var noun = spec.noun.charAt(0).toUpperCase() + spec.noun.slice(1)
    return [note("status", view.state === "error" ? spec.error || noun + " unavailable"
      : "Loading " + spec.noun + "…")]
  }

  var entries = view.entries || []
  var ranked = rank(spec, entries, query, match)
  var out = []
  var seen = {}
  for (var i = 0; i < ranked.length; i++) {
    var row = spec.row(ranked[i].entry)
    // Keys select and restore the cursor, so a repeated one would act on the wrong row.
    if (owned.call(seen, row.key)) continue
    seen[row.key] = true
    row.kind = name
    row.icon = row.icon || details.icon
    row.section = (row.section || details.title) + suffix
    out.push(row)
  }

  // A partial match must not hide the host that was typed (10.0.0.1 vs 10.0.0.12).
  var typedIsSaved = ranked.some(function(r) { return r.exact })
  var direct = query && spec.fallback && !typedIsSaved ? spec.fallback(String(q).trim()) : null
  if (direct) {
    direct.kind = name
    direct.icon = details.icon
    direct.section = section
    out.push(direct)
  } else if (!query && spec.manage) {
    out.push({ key: name + ".manage", kind: "shell", section: section, icon: details.icon,
               title: entries.length ? spec.manage.title : spec.manage.empty,
               primaryLabel: "Open panel", payload: { argv: spec.manage.argv } })
  } else if (!out.length) {
    out.push(note("none", query ? "No matching " + spec.noun
      : view.partial ? "Could not list all " + spec.noun : spec.empty || "No " + spec.noun))
  }
  return out
}

// The step Enter (or Shift+Enter) on a view row takes: { copy }, { url },
// { path }, { argv }, { terminal, holdIf }, or null to do nothing.
function action(name, payload, secondary) {
  return owned.call(SPECS, name) ? SPECS[name].action(payload || {}, secondary === true) : null
}

if (typeof module !== "undefined") module.exports = { SPECS: SPECS, rows: rows, action: action }
