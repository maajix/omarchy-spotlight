const assert = require("node:assert/strict")
const test = require("node:test")
const AiOptions = require("../lib/AiOptions.js")

test("model and effort menus follow the selected provider and model", () => {
  const catalogs = {
    claude: [{ id: "claude-opus-5-5", name: "Opus 5.5", efforts: ["low", "high"] }],
    codex: [{ id: "gpt-6-sol", name: "GPT-6 Sol", efforts: ["medium", "ultra"] }]
  }
  assert.deepEqual(AiOptions.models(catalogs, "claude").map(x => x.value), ["", "claude-opus-5-5"])
  assert.deepEqual(AiOptions.models(catalogs, "codex").map(x => x.value), ["", "gpt-6-sol"])
  assert.deepEqual(AiOptions.efforts(catalogs, "codex", "gpt-6-sol").map(x => x.value), ["", "medium", "ultra"])
  assert.deepEqual(AiOptions.efforts(catalogs, "claude", "").map(x => x.value), [""])
})
