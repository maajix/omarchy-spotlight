// Compact empty provider rows/columns without changing their relative order.
function grid(nodes) {
  function values(key) {
    return nodes.map(function(node) { return node[key] }).filter(function(value, index, all) {
      return all.indexOf(value) === index
    }).sort(function(a, b) { return a - b })
  }
  return { columns: values("column"), rows: values("row") }
}

function geometry(node, grid, width) {
  var gap = 60, padding = 28
  var w = (width - padding * 2 - (grid.columns.length - 1) * gap) / grid.columns.length
  var column = grid.columns.indexOf(node.column), row = grid.rows.indexOf(node.row)
  return { x: padding + column * (w + gap), y: 18 + row * 96,
    w: w, h: 60, column: column, row: row }
}

// ponytail: orthogonal grid routes for at most ten nodes; highlight one
// connection at a time instead of adding a graph-layout dependency.
function route(a, b) {
  if (a.column === b.column) {
    var down = a.row < b.row, offset = down ? -8 : 8
    if (Math.abs(a.row - b.row) === 1) {
      return [[a.x + a.w / 2 + offset, down ? a.y + a.h : a.y],
        [b.x + b.w / 2 + offset, down ? b.y : b.y + b.h]]
    }
    var lane = a.x + a.w + (down ? 12 : 22)
    return [[a.x + a.w, a.y + a.h / 2 + offset], [lane, a.y + a.h / 2 + offset],
      [lane, b.y + b.h / 2 + offset], [b.x + b.w, b.y + b.h / 2 + offset]]
  }
  var right = a.column < b.column, offset = right ? -8 : 8
  var ax = right ? a.x + a.w : a.x, bx = right ? b.x : b.x + b.w
  var ay = a.y + a.h / 2 + offset, by = b.y + b.h / 2 + offset
  if (Math.abs(a.column - b.column) === 1) {
    var lane = (ax + bx) / 2 + offset
    return [[ax, ay], [lane, ay], [lane, by], [bx, by]]
  }
  var laneA = ax + (right ? 18 : -18), laneB = bx + (right ? -18 : 18)
  var corridor = a.y + a.h + (right ? 12 : 24)
  return [[ax, ay], [laneA, ay], [laneA, corridor], [laneB, corridor], [laneB, by], [bx, by]]
}

if (typeof module !== "undefined") module.exports = { grid: grid, geometry: geometry, route: route }
