// Shared numeric scale for chart cards and their local-data counterparts.
function extent(series) {
  var low = 0, high = 0
  series.forEach(function(entry) {
    entry.values.forEach(function(value) { low = Math.min(low, value); high = Math.max(high, value) })
  })
  if (low === high) high = low + 1
  return { low: low, high: high }
}

function format(value) {
  var magnitude = Math.abs(value)
  if (magnitude >= 1e9) return +(value / 1e9).toFixed(1) + "B"
  if (magnitude >= 1e6) return +(value / 1e6).toFixed(1) + "M"
  if (magnitude >= 1e3) return +(value / 1e3).toFixed(1) + "k"
  return String(+value.toFixed(2))
}

if (typeof module !== "undefined") module.exports = { extent: extent, format: format }
