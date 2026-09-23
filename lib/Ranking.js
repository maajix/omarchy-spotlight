var TYPE_WEIGHTS = {
  intent: 1.05,
  app: 1.00,
  window: 0.98,
  file: 0.96,
  action: 0.94,
  clipboard: 0.92,
  web: 0.80
}

// Put matching views first; the default Enter target is chosen separately.
// A type that is not listed sorts last.
var TYPE_PRIORITY = {
  view: 0,
  intent: 1,
  app: 2,
  action: 3,
  file: 4,
  window: 5,
  clipboard: 6,
  web: 7
}

var owned = Object.prototype.hasOwnProperty

function clampBonus(value, maximum) {
  var number = Number(value) || 0
  return Math.max(0, Math.min(maximum, number))
}

function score(row) {
  var weight = owned.call(TYPE_WEIGHTS, row.resultType) ? TYPE_WEIGHTS[row.resultType] : 1
  return (Number(row.textMatch) || 0) * weight
    + clampBonus(row.recencyBonus, 40)
    + clampBonus(row.frequencyBonus, 50)
    + clampBonus(row.contextBonus, 110)
}

function rank(rows, limit) {
  var scored = []
  for (var i = 0; i < rows.length; i++) {
    scored.push({ row: rows[i], score: score(rows[i]), order: i })
  }
  scored.sort(function(a, b) {
    var ap = owned.call(TYPE_PRIORITY, a.row.resultType) ? TYPE_PRIORITY[a.row.resultType] : 99
    var bp = owned.call(TYPE_PRIORITY, b.row.resultType) ? TYPE_PRIORITY[b.row.resultType] : 99
    if (ap !== bp) return ap - bp
    if (b.score !== a.score) return b.score - a.score
    if (b.row.textMatch !== a.row.textMatch) return b.row.textMatch - a.row.textMatch
    if (a.row.resultType === b.row.resultType && isFinite(a.row.tieRank)
        && isFinite(b.row.tieRank) && a.row.tieRank !== b.row.tieRank)
      return a.row.tieRank - b.row.tieRank
    var at = String(a.row.title || "").toLowerCase()
    var bt = String(b.row.title || "").toLowerCase()
    if (at !== bt) return at < bt ? -1 : 1
    var ak = String(a.row.stableId || a.row.key || "")
    var bk = String(b.row.stableId || b.row.key || "")
    if (ak !== bk) return ak < bk ? -1 : 1
    return a.order - b.order
  })
  var out = []
  var max = Math.max(0, Number(limit) || rows.length)
  for (var j = 0; j < scored.length && out.length < max; j++) out.push(scored[j].row)
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    TYPE_WEIGHTS: TYPE_WEIGHTS, score: score, rank: rank
  }
}
