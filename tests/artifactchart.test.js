const assert = require('node:assert/strict');
const chart = require('../lib/ArtifactChart.js');

assert.deepEqual(chart.extent([{ values: [-2, 4] }, { values: [-8, 3] }]), { low: -8, high: 4 });
assert.deepEqual(chart.extent([{ values: [0, 0] }]), { low: 0, high: 1 });
assert.equal(chart.format(1536), '1.5k');
assert.equal(chart.format(-0.125), '-0.13');
console.log('Artifact chart scale checks passed');
