const assert = require('node:assert/strict');
const comparison = require('../lib/Comparison.js');
const options = [
  { name: 'A', price: '10', summary: 'A longer summary.', recommended: false, facts: [{label: 'Memory', value: '32 GB'}, {label: 'Platform', value: 'Linux'}], pros: ['Long benefit', 'Second benefit'], cons: ['One tradeoff'], sourceUrl: '' },
  { name: 'B', price: '20', summary: 'Short.', recommended: true, facts: [{label: ' platform ', value: 'Windows'}, {label: 'Memory', value: '16 GB'}, {label: 'Bandwidth', value: '500 GB/s'}], pros: ['Short'], cons: ['First tradeoff', 'Second tradeoff'], sourceUrl: 'https://example.com' },
];
const cells = comparison.cells(options);
assert.equal(cells.length % options.length, 0);
const factRows = cells.filter(cell => cell.kind === 'fact');
assert.deepEqual(factRows.map(cell => cell.text), ['32 GB', '16 GB', 'Linux', 'Windows', '—', '500 GB/s']);
assert.deepEqual(cells.filter(cell => cell.kind === 'pros').map(cell => cell.text), ['Long benefit', 'Short', 'Second benefit', '']);
assert.deepEqual(cells.filter(cell => cell.kind === 'cons').map(cell => cell.text), ['One tradeoff', 'First tradeoff', '', 'Second tradeoff']);
assert.deepEqual(cells.filter(cell => cell.kind === 'section').map(cell => cell.text), ['Strengths', 'Strengths', 'Trade-offs', 'Trade-offs']);
assert.deepEqual(comparison.groups(options.concat(options)).map(group => group.length), [2, 2]);
console.log('Comparison row alignment checks passed');
