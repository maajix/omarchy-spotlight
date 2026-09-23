const assert = require("node:assert/strict")
const test = require("node:test")
const Web = require("../lib/Web.js")

test("a named target rewrites the DeepL language pair and drops the tail", () => {
  assert.equal(
    Web.searchUrl("what is this to german", "tr"),
    "https://www.deepl.com/translator#en/de/what%20is%20this"
  )
  assert.equal(
    Web.searchUrl("what is this in german", "tr"),
    "https://www.deepl.com/translator#en/de/what%20is%20this"
  )
  assert.equal(
    Web.searchUrl("qux into japanese", "tr"),
    "https://www.deepl.com/translator#en/ja/qux"
  )
})

test("the declared source is never the target, or DeepL swaps the pair back", () => {
  const url = Web.searchUrl("wie geht es dir to english", "tr")
  assert.equal(url, "https://www.deepl.com/translator#de/en/wie%20geht%20es%20dir")
  for (const name of ["german", "english", "french", "pt-br", "zh-hant"]) {
    const [source, target] = Web.searchUrl("x to " + name, "tr").split("#")[1].split("/")
    assert.notEqual(source, target)
  }
})

test("both fragment slots always name a language DeepL accepts", () => {
  // "-" and "auto" leave the source box empty, and an unknown code silently
  // falls back to English, so neither may ever reach the URL.
  const known = /^[a-z]{2}(-[a-z]{2,4})?$/
  for (const q of ["hello world", "hello to klingon", "x to german", "x to en"]) {
    const [source, target] = Web.searchUrl(q, "tr").split("#")[1].split("/")
    assert.match(source, known)
    assert.match(target, known)
  }
  // An unknown tail is text, not a language: it must survive into the query.
  assert.ok(Web.searchUrl("hello to klingon", "tr").endsWith("/hello%20to%20klingon"))
})

test("a trailing word that is not a language stays part of the text", () => {
  assert.equal(Web.translation("I want to go"), null)
  assert.equal(Web.translation("hello world"), null)
  assert.equal(
    Web.searchUrl("I want to go", "tr"),
    "https://www.deepl.com/translator#en/de/I%20want%20to%20go"
  )
})

test("the last target wins and matching ignores case", () => {
  assert.equal(Web.translation("von hier to spanish to GERMAN").code, "de")
  assert.equal(Web.translation("hola TO Spanish").name, "Spanish")
})

test("only the translator reads a target out of the query", () => {
  assert.equal(
    Web.searchUrl("what is this to german", "g"),
    "https://www.google.com/search?q=what%20is%20this%20to%20german"
  )
})

test("inherited property names are not languages or engines", () => {
  assert.equal(Web.translation("x to constructor"), null)
  assert.equal(Web.translation("x to toString"), null)
  assert.equal(Web.hasEngine("constructor"), false)
})

test("engineOptions lists every engine once, first key wins", () => {
  const options = Web.engineOptions()
  const google = options.filter((o) => o.label === "Google")
  assert.deepEqual(google, [{ value: "g", label: "Google" }])
  assert.ok(options.some((o) => o.value === "ddg" && o.label === "DuckDuckGo"))
  assert.ok(options.some((o) => o.value === "kagi" && o.label === "Kagi"))
  for (const o of options) assert.ok(Web.hasEngine(o.value))
})

test("canonicalEngine maps an alias to the key the settings menu lists", () => {
  assert.equal(Web.canonicalEngine("google"), "g")
  assert.equal(Web.canonicalEngine("gg"), "g")
  assert.equal(Web.canonicalEngine("ddg"), "ddg")
  assert.equal(Web.canonicalEngine("nope"), "g")
  assert.equal(Web.canonicalEngine(undefined), "g")
})

test("Kagi builds a search URL", () => {
  assert.equal(Web.searchUrl("linux desktop", "kagi"), "https://kagi.com/search?q=linux%20desktop")
})
