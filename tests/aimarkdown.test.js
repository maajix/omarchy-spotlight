const assert = require("node:assert/strict")
const test = require("node:test")
const AiMarkdown = require("../lib/AiMarkdown.js")

test("AI markdown keeps lists and tables together but spaces paragraphs and headings", () => {
  const parts = AiMarkdown.split("Intro\n\n## Beispiele\n- eins\n- zwei\n\n## Optionen\n| A | B |\n|---|---|\n| x | y |\n\n```bash\nscp a b\n```\n\nEnde")
  assert.deepEqual(parts, [
    { type: "markdown", text: "Intro" },
    { type: "markdown", text: "## Beispiele" },
    { type: "markdown", text: "- eins\n- zwei" },
    { type: "markdown", text: "## Optionen" },
    { type: "markdown", text: "| A | B |\n|---|---|\n| x | y |" },
    { type: "code", language: "bash", text: "scp a b" },
    { type: "markdown", text: "Ende" }
  ])
})

test("inline commands keep surrounding typography and escape their content", () => {
  assert.equal(AiMarkdown.highlightInlineCode("Use `scp <a&b>` now"),
    'Use <span style="color:#a6d2ff">scp &lt;a&amp;b&gt;</span> now')
  assert.equal(AiMarkdown.highlightInlineCode("## Was ist `scp`?"), "## Was ist scp?")
})

test("markdown links get a readable color without changing their target", () => {
  assert.equal(AiMarkdown.highlightInlineCode("Quelle: [WetterOnline](https://example.org/a?x=1&y=2)"),
    'Quelle: <a href="https://example.org/a?x=1&amp;y=2" style="color:#a6d2ff; text-decoration:underline">WetterOnline</a>')
})

test("provider images and HTML cannot trigger automatic requests", () => {
  for (const input of [
    '![x](https://example.org/a "title")', '![x](<https://example.org/a>)',
    '![x](HTTPS://example.org/a)', '![x][ref]\n\n[ref]: https://example.org/a',
    '![x][]', '![x]', String.raw`\![x](https://example.org/a)`,
    '`![x](https://example.org/a)`', '<img src="https://example.org/a">',
    '<IMG SRC="file:///etc/passwd">', '## `![x](https://example.org/a)`'
  ]) {
    const output = AiMarkdown.highlightInlineCode(input)
    assert.doesNotMatch(output, /!\[|<img/i, input)
  }
})
