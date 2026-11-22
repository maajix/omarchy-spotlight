const assert = require("node:assert/strict")
const test = require("node:test")
const AiOptions = require("../lib/AiOptions.js")

test("model and effort menus follow the selected provider and model", () => {
  const catalogs = {
    claude: [{ id: "claude-opus-5-5", name: "Opus 5.5", efforts: ["low", "high"] }],
    codex: [{ id: "gpt-6-sol", name: "GPT-6 Sol", efforts: ["medium", "ultra"] }],
    opencode: [{ id: "opencode/deepseek-v4.1-flash-free", name: "opencode/deepseek-v4.1-flash-free", efforts: [] }]
  }
  assert.deepEqual(AiOptions.models(catalogs, "claude").map(x => x.value), ["", "claude-opus-5-5"])
  assert.deepEqual(AiOptions.models(catalogs, "codex").map(x => x.value), ["", "gpt-6-sol"])
  assert.deepEqual(AiOptions.models(catalogs, "opencode").map(x => x.value), ["", "opencode/deepseek-v4.1-flash-free"])
  assert.deepEqual(AiOptions.efforts(catalogs, "codex", "gpt-6-sol").map(x => x.value), ["", "medium", "ultra"])
  assert.deepEqual(AiOptions.efforts(catalogs, "claude", "").map(x => x.value), [""])
  assert.deepEqual(AiOptions.efforts(catalogs, "opencode", "opencode/deepseek-v4.1-flash-free").map(x => x.value), [""])
})

test("provider names normalize and have display labels", () => {
  for (const value of ["claude", "codex", "opencode"])
    assert.equal(AiOptions.provider(value), value)
  assert.equal(AiOptions.provider("bogus"), "claude")
  assert.equal(AiOptions.provider(""), "claude")
  assert.equal(AiOptions.label("claude"), "Claude")
  assert.equal(AiOptions.label("codex"), "Codex")
  assert.equal(AiOptions.label("opencode"), "OpenCode")
  assert.equal(AiOptions.label("bogus"), "Claude")
})
