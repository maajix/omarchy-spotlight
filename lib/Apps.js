// Application matching and ranking, used for every app candidate - not just
// a fallback. Spotlight still asks the shell's own AppLibrary for entry
// name/subtext/icon/launch/hide-state when it is available (a plugin
// declaring the "menu" manifest kind gets it), but matching itself always
// runs through this file, never through AppLibrary.sortedEntries().
//
// That split is deliberate, not an oversight: AppLibrary's own matcher
// (services/AppSearch.js, upstream Omarchy) folds a desktop entry's raw
// `id` into its searchable text with no sanitisation, and a browser-
// installed web app's id is a generated string - <browser>-<32-char
// extension id>-<profile name> - that leaked into unrelated search results
// (see GENERATED_WEBAPP_ID_RE below). This file is a close port of that
// same matcher (MIT), with that one gap closed; expect its scoring to track
// AppSearch.js's closely but not necessarily exactly forever.

var FIELD_CHARS = 512
var SEARCH_CHARS = 2048
var KEYWORD_COUNT = 64
// A browser-installed web app's .desktop id is a generated identifier, not
// something a user would ever intentionally type: <browser>-<32-char
// extension id, base16 with a-p instead of 0-9a-f>-<browser profile
// directory name> ("Default", "Profile 1", ...). Found via a real bug
// report: three unrelated PWAs (installed under the "Default" Chrome
// profile) matched every search for the word "default", because that id
// was being folded into their searchable text below. The invariant is the
// 32-letter Chromium extension-id segment, not the "chrome-" prefix
// specifically - omarchy-launch-webapp installs the same shape of id for
// Brave/Edge/Opera/Vivaldi/Helium too. None of an id shaped like this is
// human-meaningful, so it is excluded wholesale rather than trimmed.
var GENERATED_WEBAPP_ID_RE = /^[a-z0-9]+-[a-p]{32}-.+$/i

function bounded(value, chars) {
  return String(value || "").slice(0, chars)
}

// The one place `entry.id` is read for anything other than search text - a
// hidden-entry lookup or a launch call needs the real id, unsanitized, so
// this is deliberately not used there.
function searchableId(entry) {
  var id = bounded(entry && entry.id, 256)
  return GENERATED_WEBAPP_ID_RE.test(id) ? "" : id
}

function entryName(entry) {
  return bounded((entry && entry.name) || (entry && entry.id), FIELD_CHARS)
}

function entrySubtext(entry) {
  return bounded(entry && entry.genericName, FIELD_CHARS)
}

function keywordText(entry) {
  try {
    if (entry && entry.keywords && typeof entry.keywords.length === "number") {
      var out = []
      for (var i = 0; i < entry.keywords.length && i < KEYWORD_COUNT; i++)
        out.push(bounded(entry.keywords[i], 128))
      return out.join(" ").slice(0, SEARCH_CHARS)
    }
  } catch (e) {
  }
  return ""
}

function entrySearchText(entry) {
  if (!entry) return ""
  return [
    bounded(entry.name, FIELD_CHARS),
    bounded(entry.genericName, FIELD_CHARS),
    bounded(entry.comment, FIELD_CHARS),
    keywordText(entry),
    searchableId(entry)
  ].join(" ").slice(0, SEARCH_CHARS).toLowerCase()
}

function wordText(value) {
  return String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
}

function words(value) {
  var values = wordText(value).split(/[^a-z0-9]+/)
  var result = []
  for (var i = 0; i < values.length; i++) {
    if (values[i]) result.push(values[i])
  }
  return result
}

function entryAcronym(entry) {
  var values = words([
    bounded(entry && entry.name, FIELD_CHARS),
    bounded(entry && entry.genericName, FIELD_CHARS),
    keywordText(entry),
    searchableId(entry)
  ].join(" ").slice(0, SEARCH_CHARS))
  var result = ""
  for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
  return result.slice(0, 256)
}

function termMatches(entry, term) {
  if (!term) return true

  var name = entryName(entry).toLowerCase()
  var id = searchableId(entry).toLowerCase()
  var haystack = entrySearchText(entry)

  if (name.indexOf(term) >= 0) return true
  if (id.indexOf(term) >= 0) return true
  if (haystack.indexOf(term) >= 0) return true

  return term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0
}

function allTermsMatch(entry, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termMatches(entry, terms[i])) return false
  }
  return true
}

// -1 rejects the candidate. Higher is better.
function score(entry, query) {
  var q = bounded(query, FIELD_CHARS).trim().toLowerCase()
  if (!q) return 0
  if (!allTermsMatch(entry, q)) return -1

  var name = entryName(entry).toLowerCase()
  var id = searchableId(entry).toLowerCase()
  var haystack = entrySearchText(entry)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  if (directName === 0) return 10000 - name.length
  if (directId === 0) return 9500 - id.length
  if (directName > 0) return 8000 - directName * 10 - name.length
  if (directId > 0) return 7600 - directId * 10 - id.length

  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return 6000 - hayIndex

  var acronym = entryAcronym(entry)
  var acronymIndex = acronym.indexOf(q)
  if (acronymIndex === 0) return 5000 - acronym.length
  if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length

  return 4000 - name.length
}

var owned = Object.prototype.hasOwnProperty

// `hidden` is either a plain id->true map (the packaged launcher.hides
// projection, read through hasOwnProperty rather than plain lookup so an id
// of `constructor` cannot find a function on the prototype and hide a real
// entry) or a callback - `root.appLibrary.isHiddenEntry`, when the shell's
// own AppLibrary is the authority on hiding. The two sources are never
// merged: when the callback is passed, it already combines every hiding
// rule the shell knows about, and re-deriving that locally would either
// duplicate it or (worse) silently un-hide everything if the map form were
// used with an empty map instead.
function isHidden(hidden, entry) {
  if (typeof hidden === "function") return !!hidden(entry)
  var id = bounded(entry && entry.id, 256)
  return !!id && !!hidden && owned.call(hidden, id) && hidden[id] === true
}

// Returns [{entry, score}] — the same shape AppLibrary.sortedEntries returns,
// so the caller does not care which of the two produced it. Untyped: `values`
// is whatever DesktopEntries handed over.
function sortedEntries(values, query, hidden, resultLimit, scanLimit) {
  var q = bounded(query, FIELD_CHARS).trim()
  var rows = []
  var list = values || []
  var maxResults = Math.max(1, Math.min(2048, Number(resultLimit) || 512))
  var maxScan = Math.max(maxResults, Math.min(16384, Number(scanLimit) || 4096))

  for (var i = 0; i < list.length && i < maxScan; i++) {
    var entry = list[i]
    if (!entry || entry.noDisplay) continue
    if (isHidden(hidden, entry)) continue
    var name = entryName(entry)
    if (!name) continue
    var value = score(entry, q)
    if (value < 0) continue
    rows.push({ entry: entry, score: value, name: name.toLowerCase() })
  }

  rows.sort(function(a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.name < b.name) return -1
    if (a.name > b.name) return 1
    return 0
  })

  return rows.slice(0, maxResults)
}

// The id map the helper's read-hides projection turns into, built with a null
// prototype for the same reason Frecency's store is.
function hiddenMap(ids) {
  var next = Object.create(null)
  var list = ids || []
  for (var i = 0; i < list.length && i < 400; i++) {
    var id = bounded(list[i], 256)
    if (id) next[id] = true
  }
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    entryName: entryName,
    entrySubtext: entrySubtext,
    entryAcronym: entryAcronym,
    entrySearchText: entrySearchText,
    searchableId: searchableId,
    score: score,
    sortedEntries: sortedEntries,
    hiddenMap: hiddenMap
  }
}
