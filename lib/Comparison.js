// A shared row per detail lets GridLayout size it to the tallest option.
function groups(options) {
  return options.length === 4 ? [options.slice(0, 2), options.slice(2)] : [options]
}

function cells(options) {
  var result = []
  function row(kind, values, label) {
    values.forEach(function(value) { result.push({ kind: kind, text: value, label: label || "" }) })
  }
  row("status", options.map(function(option) { return option.recommended ? "SUGGESTED PICK" : "OPTION" }))
  ;["name", "price", "summary"].forEach(function(key) {
    row(key, options.map(function(option) { return option[key] }))
  })
  var labels = []
  function key(label) { return label.trim().toLowerCase().replace(/\s+/g, " ") }
  options.forEach(function(option) {
    option.facts.forEach(function(fact) {
      if (!labels.some(function(label) { return key(label) === key(fact.label) })) labels.push(fact.label)
    })
  })
  labels.forEach(function(label) {
    row("fact", options.map(function(option) {
      var fact = option.facts.filter(function(item) { return key(item.label) === key(label) })[0]
      return fact ? fact.value : "—"
    }), label)
  })
  row("divider", options.map(function() { return "" }))
  ;["pros", "cons"].forEach(function(kind) {
    row("section", options.map(function() { return kind === "pros" ? "Strengths" : "Trade-offs" }))
    var count = Math.max.apply(null, options.map(function(option) { return option[kind].length }))
    for (var index = 0; index < count; index++) {
      row(kind, options.map(function(option) { return option[kind][index] || "" }))
    }
  })
  if (options.some(function(option) { return option.sourceUrl })) {
    row("source", options.map(function(option) { return option.sourceUrl }))
  }
  return result
}

if (typeof module !== "undefined") module.exports = { groups: groups, cells: cells }
