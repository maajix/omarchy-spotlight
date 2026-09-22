// Web search: bang prefixes, URL detection, and the always-available
// "search the web for …" fallback.

var ENGINES = {
  g:       { name: "Google",         url: "https://www.google.com/search?q=%s",                      icon: "󰊭" },
  gg:      { name: "Google",         url: "https://www.google.com/search?q=%s",                      icon: "󰊭" },
  google:  { name: "Google",         url: "https://www.google.com/search?q=%s",                      icon: "󰊭" },
  ddg:     { name: "DuckDuckGo",     url: "https://duckduckgo.com/?q=%s",                            icon: "󰇥" },
  kagi:    { name: "Kagi",           url: "https://kagi.com/search?q=%s",                            icon: "󰍉" },
  yt:      { name: "YouTube",        url: "https://www.youtube.com/results?search_query=%s",         icon: "󰗃" },
  gh:      { name: "GitHub",         url: "https://github.com/search?q=%s",                          icon: "󰊤" },
  w:       { name: "Wikipedia",      url: "https://en.wikipedia.org/w/index.php?search=%s",          icon: "󰖬" },
  wde:     { name: "Wikipedia (de)", url: "https://de.wikipedia.org/w/index.php?search=%s",          icon: "󰖬" },
  aw:      { name: "Arch Wiki",      url: "https://wiki.archlinux.org/index.php?search=%s",          icon: "󰣇" },
  aur:     { name: "AUR",            url: "https://aur.archlinux.org/packages?K=%s",                 icon: "󰣇" },
  pkg:     { name: "Arch packages",  url: "https://archlinux.org/packages/?q=%s",                    icon: "󰣇" },
  so:      { name: "Stack Overflow", url: "https://stackoverflow.com/search?q=%s",                   icon: "󰓌" },
  mdn:     { name: "MDN",            url: "https://developer.mozilla.org/en-US/search?q=%s",         icon: "󰖟" },
  npm:     { name: "npm",            url: "https://www.npmjs.com/search?q=%s",                       icon: "󰎙" },
  crates:  { name: "crates.io",      url: "https://crates.io/search?q=%s",                           icon: "󱘗" },
  docker:  { name: "Docker Hub",     url: "https://hub.docker.com/search?q=%s",                      icon: "󰡨" },
  maps:    { name: "Google Maps",    url: "https://www.google.com/maps/search/%s",                   icon: "󰗲" },
  // DeepL only fills the source box when both fragment slots name a real
  // language; "-" and "auto" make it drop the text. The source slot is only
  // a seed -- DeepL re-detects it -- so en/de is the no-target-named default
  // and translation() below rewrites the pair when the query names one.
  tr:      { name: "DeepL",          url: "https://www.deepl.com/translator#en/de/%s",               icon: "󰗊" },
  img:     { name: "Google Images",  url: "https://www.google.com/search?tbm=isch&q=%s",             icon: "󰋩" },
  hn:      { name: "Hacker News",    url: "https://hn.algolia.com/?q=%s",                            icon: "󰬛" },
  omarchy: { name: "Omarchy manual", url: "https://manuals.omamix.org/2/the-omarchy-manual?q=%s",    icon: "󰣇" }
}

var DEFAULT_ENGINE = "g"

// Every one of these tables is indexed with something the user typed, and
// `constructor` or `toString` are perfectly ordinary things to type. Reaching
// them through the prototype chain turns a search into an inherited function
// object, so the tables are only ever consulted for keys they actually own.
var owned = Object.prototype.hasOwnProperty

function hasEngine(key) {
  return typeof key === "string" && owned.call(ENGINES, key)
}

function lookupEngine(key) {
  if (hasEngine(key)) return ENGINES[key]
  return ENGINES[DEFAULT_ENGINE]
}

// -> [{ value, label }] for a settings dropdown: one row per engine name,
// the first key wins ("g" over "google").
function engineOptions() {
  var out = [], seen = {}
  for (var key in ENGINES) {
    if (!owned.call(ENGINES, key) || owned.call(seen, ENGINES[key].name)) continue
    seen[ENGINES[key].name] = true
    out.push({ value: key, label: ENGINES[key].name })
  }
  return out
}

// Bare hostnames worth opening directly. Anything else needs a scheme or a
// slash, so "node.js" stays a search rather than becoming a URL.
var COMMON_TLDS = /\.(com|org|net|io|dev|de|co|uk|eu|app|sh|gg|ai|me|info|xyz|to|tv|so|rs|it|fr|es|nl|ch|at|se|no|pl|cz|jp|cn|us|ca|au|in|br|edu|gov|mil|int|local|test)(\/|$|:)/i

function fill(template, query) {
  return template.replace("%s", encodeURIComponent(query))
}

// -> { engine, key, query } or null
function bang(text) {
  var s = String(text || "")
  var m = s.match(/^([a-z]{1,8})\s+(\S.*)$/i)
  if (!m) return null
  var key = m[1].toLowerCase()
  if (!hasEngine(key)) return null
  return { engine: ENGINES[key], key: key, query: m[2].trim() }
}

// -> normalized URL string, or "" when the text is not a URL
function detectUrl(text) {
  var s = String(text || "").trim()
  if (!s || /\s/.test(s)) return ""

  if (/^(https?|ftp):\/\/\S+$/i.test(s)) return s
  if (/^(mailto|magnet|tel):\S+$/i.test(s)) return s
  if (/^[\w.+-]+@[\w-]+\.[a-z]{2,}$/i.test(s)) return "mailto:" + s

  // localhost and bare IPs, with or without a port
  if (/^localhost(:\d+)?(\/\S*)?$/i.test(s)) return "http://" + s
  if (/^(\d{1,3}\.){3}\d{1,3}(:\d+)?(\/\S*)?$/.test(s)) return "http://" + s

  if (/^www\./i.test(s)) return "https://" + s
  if (COMMON_TLDS.test(s) && /^[\w-]+(\.[\w-]+)+(:\d+)?(\/\S*)?$/.test(s)) return "https://" + s

  return ""
}

// [code, display name, extra words someone might type]. Every code was checked
// against the live translator: DeepL silently falls back to English for a code
// it does not know, so an unverified guess here would look like it worked.
// "th" is deliberately absent -- DeepL resolves it to a different language.
var LANGUAGES = [
  ["ar", "Arabic"],      ["bg", "Bulgarian"],  ["cs", "Czech"],
  ["da", "Danish"],      ["de", "German", "deutsch"],
  ["el", "Greek"],       ["en", "English"],    ["es", "Spanish"],
  ["et", "Estonian"],    ["fi", "Finnish"],    ["fr", "French"],
  ["he", "Hebrew"],      ["hu", "Hungarian"],  ["id", "Indonesian"],
  ["it", "Italian"],     ["ja", "Japanese"],   ["ka", "Georgian"],
  ["ko", "Korean"],      ["lt", "Lithuanian"], ["lv", "Latvian"],
  ["nb", "Norwegian", "no"],                   ["nl", "Dutch"],
  ["pl", "Polish"],      ["pt", "Portuguese"],
  ["pt-br", "Portuguese (Brazilian)", "brazilian"],
  ["ro", "Romanian"],    ["ru", "Russian"],    ["sk", "Slovak"],
  ["sl", "Slovenian"],   ["sv", "Swedish"],    ["tr", "Turkish"],
  ["uk", "Ukrainian"],   ["vi", "Vietnamese"], ["zh", "Chinese", "mandarin"],
  ["zh-hant", "Chinese (traditional)"]
]

var LANG_BY_WORD = {}
for (var li = 0; li < LANGUAGES.length; li++) {
  var row = LANGUAGES[li]
  LANG_BY_WORD[row[0]] = row
  LANG_BY_WORD[row[1].toLowerCase()] = row
  for (var lj = 2; lj < row.length; lj++) LANG_BY_WORD[row[lj]] = row
}

// "what is this to german" -> { text: "what is this", code: "de", name: "German" },
// and null when the tail names nothing translatable, so "I want to go" stays a
// whole-phrase translation. Greedy on purpose: the last "to" wins.
// -> { text, code, name } or null
function translation(text) {
  var m = String(text || "").match(/^(.*\S)\s+(?:to|in|into)\s+([a-z][a-z-]{1,11})$/i)
  if (!m) return null
  var word = m[2].toLowerCase()
  if (!owned.call(LANG_BY_WORD, word)) return null
  var row = LANG_BY_WORD[word]
  return { text: m[1], code: row[0], name: row[1] }
}

function searchUrl(query, engineKey) {
  var template = lookupEngine(engineKey).url
  var target = engineKey === "tr" ? translation(query) : null
  if (!target) return fill(template, query)
  // DeepL swaps the pair when the text it detects is already the target, so the
  // declared source only has to be some other real language.
  var source = target.code === "en" ? "de" : "en"
  return fill(template.replace(/#[a-z-]+\/[a-z-]+\//, "#" + source + "/" + target.code + "/"), target.text)
}

function engineName(engineKey) {
  return lookupEngine(engineKey).name
}

function engineIcon(engineKey) {
  return lookupEngine(engineKey).icon
}

// The autocomplete request itself lives in bin/spotlight-helper, which owns
// the endpoint, the response ceiling and the deadline. Nothing here reaches
// the network.

if (typeof module !== "undefined") {
  module.exports = {
    hasEngine: hasEngine,
    engineOptions: engineOptions,
    bang: bang,
    detectUrl: detectUrl,
    translation: translation,
    searchUrl: searchUrl,
    engineName: engineName,
    engineIcon: engineIcon
  }
}
