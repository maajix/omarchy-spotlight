const assert = require('node:assert/strict');
const {grid, geometry, route} = require('../lib/Diagram.js');
const nodes = [{id: 'a', column: 0, row: 0}, {id: 'b', column: 0, row: 3},
  {id: 'c', column: 2, row: 3}, {id: 'd', column: 1, row: 5}];
const layout = grid(nodes);
assert.deepEqual(layout.rows, [0, 3, 5]);
const boxes = nodes.map(node => geometry(node, layout, 674));
assert.equal(boxes[1].y - boxes[0].y, 96, 'Unused rows must not leave empty vertical space');
for (const box of boxes) assert.ok(box.x >= 0 && box.x + box.w <= 674 && box.w > 150);
for (let i = 0; i < boxes.length; i++) for (let j = 0; j < boxes.length; j++) {
  if (i === j) continue;
  const points = route(boxes[i], boxes[j]);
  assert.ok(points.flat().every(Number.isFinite));
  assert.notDeepEqual(points, route(boxes[j], boxes[i]).reverse(), 'Replies need a separate route');
  for (const box of boxes) for (let k = 1; k < points.length; k++) {
    const [x, y] = points[k - 1], [nx, ny] = points[k];
    assert.ok(x === nx || y === ny, 'Routes must remain orthogonal');
    assert.ok(!(Math.max(x, nx) > box.x && Math.min(x, nx) < box.x + box.w
      && Math.max(y, ny) > box.y && Math.min(y, ny) < box.y + box.h), 'Connections must not pass through nodes');
  }
}
const fullGrid = [];
for (let column = 0; column < 3; column++) for (let row = 0; row < 6; row++) fullGrid.push({column, row});
const fullLayout = grid(fullGrid);
const fullBoxes = fullGrid.map(node => geometry(node, fullLayout, 674));
for (const from of fullBoxes) for (const to of fullBoxes) {
  if (from === to) continue;
  for (const [x, y] of route(from, to)) assert.ok(x >= 0 && x <= 674 && y >= 0 && y <= 6 * 96 + 12, 'Route must stay inside the board');
}
console.log('Diagram grid is compact; directed routes are distinct and avoid node interiors');
