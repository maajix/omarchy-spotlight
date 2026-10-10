const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const test = require("node:test")
const Calc = vm.createContext({})
const Units = vm.createContext({})
vm.runInContext(fs.readFileSync(require.resolve("../lib/Calc.js"), "utf8"), Calc)
vm.runInContext(fs.readFileSync(require.resolve("../lib/Units.js"), "utf8"), Units)

test("grouping commas do not swallow function arguments", () => {
  for (const [query, expected] of [
    ["max(1,234)", 234], ["min(1,234)", 1], ["pow(2,100)", 2 ** 100],
    ["max(1,min(234,567))", 234], ["max((1),234)", 234],
    ["1,234 + 5", 1239], ["(1,234) + 5", 1239],
    ["1,234,567 + max(1,234)", 1234801], ["1,000 + 10%", 1100]
  ]) assert.equal(Calc.evaluate(query).value, expected, query)
})

test("small nonzero conversions remain nonzero when displayed and copied", () => {
  for (const query of ["1 byte to GB", "1 nm to m", "-1 nm to m"]) {
    const result = Units.convert(query)
    assert.equal(Number(result.text.split(" ")[0]), result.value, query)
  }
  assert.equal(Units.formatNumber(0), "0")
  assert.equal(Units.formatNumber(0.000001), "0.000001")
})

test("conversions list related units in a readable range, never the two on screen", () => {
  const related = query => Array.from(Units.related(Units.convert(query), 5), r => r.text)
  assert.deepEqual(related("2000 m in km"), ["200 000 cm", "1.2427 mi", "2 187.23 yd", "6 561.68 ft", "78 740.16 in"])
  assert.deepEqual(related("5 gib to mb"), ["5.3687 GB", "5 120 MiB"])
  assert.deepEqual(related("72f in c"), ["295.37 K"])
  assert.deepEqual(Array.from(Units.related(null, 5)), [])
})
