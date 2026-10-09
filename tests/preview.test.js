const assert = require("node:assert/strict")
const test = require("node:test")
const Preview = require("../lib/Preview.js")

const ctx = { defaultCurrency: "EUR", currencyRates: true, formatNumber: n => String(Math.round(n * 100) / 100) }
const types = preview => preview.blocks.map(b => b.type)
const block = (preview, type) => preview.blocks.find(b => b.type === type)
const currency = { key: "currency", kind: "copy", title: "261.75 USD",
  payload: { amount: 234, base: "EUR", quote: "USD", rate: 1.1186, date: "2026-10-08", source: "234 EUR" } }

test("only rows with something to add count as rich; noop rows have no preview", () => {
  assert.equal(Preview.rich({ key: "calc", kind: "copy" }), true)
  assert.equal(Preview.rich({ key: "file:/a", kind: "file" }), true)
  assert.equal(Preview.rich({ key: "cmd:lock", kind: "shell" }), false)
  assert.equal(Preview.rich({ key: "currency", kind: "currency-wait" }), false)
  assert.equal(Preview.build({ key: "x", kind: "noop", title: "Loading…" }, ctx, null), null)
  // A plain row still gets a pane while a rich one is on screen with it.
  assert.deepEqual(types(Preview.build({ key: "cmd:lock", kind: "shell", title: "Lock", accessory: "Action" }, ctx)),
    ["label", "hero"])
})

test("currency asks for the other currencies once, default first, never base or quote", () => {
  assert.deepEqual(Preview.previewQuotes("EUR", "USD", "EUR"), ["GBP", "JPY", "CHF"])
  assert.deepEqual(Preview.previewQuotes("USD", "JPY", "NOK"), ["NOK", "EUR", "GBP", "CHF"])
  assert.deepEqual(Preview.need(currency, ctx), { key: "rates:EUR:GBP,JPY,CHF",
    args: ["currency-rates", "EUR", "GBP,JPY,CHF"] })
  // Rates turned off: the pane may use the cache but must not go online.
  assert.deepEqual(Preview.need(currency, Object.assign({}, ctx, { currencyRates: false })).args,
    ["currency-rates", "--cached-only", "EUR", "GBP,JPY,CHF"])
  assert.equal(Preview.need(Object.assign({}, currency, { payload: { expression: true } }), ctx), null)
})

test("currency preview mirrors the answer and converts the same amount", () => {
  const loading = Preview.build(currency, ctx, { state: "loading" })
  assert.deepEqual(types(loading), ["label", "hero", "status", "meta"])
  assert.equal(block(loading, "hero").text, "= 261.75 USD")
  assert.equal(block(Preview.build(Object.assign({}, currency, { payload: Object.assign({}, currency.payload,
    { amount: 20, rate: 1.1204 }) }), ctx, null), "hero").text, "= 22.41 USD")
  assert.equal(block(loading, "label").text, "234 EUR")
  assert.equal(block(loading, "meta").text, "1 EUR = 1.12 USD · European Central Bank, 2026-10-08")
  const ready = Preview.build(currency, ctx, { state: "ready", reply: { rates: [
    { quote: "GBP", rate: 0.85 }, { quote: "JPY", rate: 177, stale: true }, { quote: "CHF", rate: "x" }] } })
  assert.deepEqual(block(ready, "lines").items, [{ text: "= 198.90 GBP", note: "" },
    { text: "= 41 418 JPY", note: "cached" }])
})

test("currency expressions show each amount and its rate under the total", () => {
  const row = { key: "currency", kind: "copy", title: "294.57 EUR", payload: { expression: true, quote: "EUR",
    source: "200 EUR + 99 USD + 1100 JPY", rate: NaN, steps: [
      { amount: 200, base: "EUR", rate: 1, value: 200, date: "" },
      { amount: 99, base: "USD", rate: 0.8926, value: 88.3674, date: "2026-10-09" },
      { amount: 1100, base: "JPY", rate: 0.00564, value: 6.204, date: "2026-10-09" }] } }
  assert.equal(Preview.need(row, ctx), null)
  const preview = Preview.build(row, ctx, null)
  assert.deepEqual(types(preview), ["label", "hero", "lines", "meta"])
  assert.equal(block(preview, "hero").text, "= 294.57 EUR")
  assert.deepEqual(block(preview, "lines").items, [{ text: "200 EUR", note: "" },
    { text: "99 USD = 88.37 EUR", note: "× 0.89" }, { text: "1100 JPY = 6.20 EUR", note: "× 0.01" }])
  assert.equal(block(preview, "meta").text, "Rates: European Central Bank, 2026-10-09")
})

test("money rounds to the currency's minor unit", () => {
  assert.equal(Preview.formatMoney(16.94124, "GBP"), "16.94 GBP")
  assert.equal(Preview.formatMoney(3546.2, "JPY"), "3 546 JPY")
  assert.equal(Preview.formatMoney(1234567.891, "USD"), "1 234 567.89 USD")
  assert.equal(Preview.formatMoney(-0.5, "EUR"), "-0.50 EUR")
  assert.equal(Preview.formatMoney(NaN, "EUR"), "")
  assert.equal(Preview.formatMoney(0.001, "KWD"), "0.001 KWD")
  assert.equal(Preview.formatMoney(12.3456, "BHD"), "12.346 BHD")
  assert.equal(Preview.formatMoney(5, "constructor"), "5.00 constructor")
})

test("unit conversions list the related units the row carries", () => {
  const row = { key: "unit", kind: "copy", title: "2 km", subtitle: "2 000 m = 2 km",
    payload: { related: [{ text: "1.2427 mi" }, { text: "6 561.68 ft" }] } }
  const preview = Preview.build(row, ctx)
  assert.deepEqual(types(preview), ["label", "hero", "lines", "meta"])
  assert.deepEqual(block(preview, "lines").items.map(i => i.text), ["= 1.2427 mi", "= 6 561.68 ft"])
  assert.deepEqual(types(Preview.build(Object.assign({}, row, { payload: {} }), ctx)), ["label", "hero", "meta"])
})

test("names are one middle-elided line; answers stay large", () => {
  const file = Preview.build({ key: "file:/a", kind: "file", title: "screenshot-2026-10-09_11-16-42.png",
    payload: { path: "/a" } }, ctx, { state: "loading" })
  assert.equal(block(file, "hero").name, true)
  assert.equal(block(Preview.build(currency, ctx, null), "hero").name, undefined)
})

test("calculator shows other bases for integers and scientific form for extremes", () => {
  const preview = Preview.build({ key: "calc", kind: "copy", title: "255", subtitle: "15*17",
    payload: { value: 255 } }, ctx)
  assert.deepEqual(block(preview, "lines").items.map(i => i.text), ["0xFF", "0o377", "0b11111111"])
  const tiny = Preview.build({ key: "calc", kind: "copy", title: "0.0001", payload: { value: 0.0001 } }, ctx)
  assert.deepEqual(block(tiny, "lines").items, [{ text: "1e-4", note: "scientific" }])
  assert.equal(block(Preview.build({ key: "calc", kind: "copy", title: "1", payload: { value: 1 } }, ctx), "lines"),
    undefined)
})

test("files ask the helper and keep private contents and odd names safe", () => {
  const row = { key: "file:/home/me/a #1?.png", kind: "file", title: "a #1?.png", subtitle: "/home/me",
    payload: { path: "/home/me/a #1?.png", dir: "/home/me" } }
  assert.deepEqual(Preview.need(row, ctx), { key: "file:/home/me/a #1?.png",
    args: ["preview-file", "/home/me/a #1?.png"] })
  const image = Preview.build(row, ctx, { state: "ready", reply: { kind: "image", size: 2048 } })
  assert.equal(block(image, "image").source, "file:///home/me/a%20%231%3F.png")
  const hidden = Preview.build(row, ctx, { state: "ready", reply: { kind: "hidden", size: 10 } })
  assert.equal(block(hidden, "text"), undefined)
  assert.equal(block(hidden, "status").text, "Contents hidden for private files")
  const failed = Preview.build(row, ctx, { state: "error" })
  assert.equal(block(failed, "status").text, "Preview unavailable")
  const dir = Preview.build(row, ctx, { state: "ready", reply: { kind: "dir", entries: [], count: 1000, more: true } })
  assert.equal(block(dir, "fields").items.find(i => i.label === "Size").value, "1000+ items")
})

test("clipboard previews only through the helper, keyed by index and title", () => {
  const row = { key: "clip:3", kind: "clipcopy", title: "abc", payload: { index: 3, title: "abc" } }
  assert.deepEqual(Preview.need(row, ctx).args, ["clipboard-preview", "3", "abc"])
  const shown = Preview.build(row, ctx, { state: "ready", reply: { text: "abc\ndef", chars: 7, lines: 2 } })
  assert.equal(block(shown, "text").text, "abc\ndef")
  assert.equal(block(shown, "meta").text, "7 characters · 2 lines")
})

test("views look one entry up by identity; payload-only views need no helper", () => {
  assert.deepEqual(Preview.need({ kind: "services", payload: { name: "a.service", scope: "user" } }, ctx).args,
    ["preview-view", "service", "user", "a.service"])
  assert.deepEqual(Preview.need({ kind: "ports", payload: { endpoint: "0.0.0.0:22", pid: 842 } }, ctx).args,
    ["preview-view", "process", "842"])
  assert.equal(Preview.need({ kind: "ports", payload: { endpoint: "[::]:5353", pid: "" } }, ctx), null)
  assert.equal(Preview.need({ kind: "wifi", payload: { ssid: "home" } }, ctx), null)
  const mount = Preview.build({ kind: "mounts", title: "/", payload: { target: "/" } }, ctx,
    { state: "ready", reply: { size: 1024 * 1024 * 1024, used: 512 * 1024 * 1024, free: 512 * 1024 * 1024 } })
  assert.equal(block(mount, "fields").items.find(i => i.label === "Used").value, "512 MB of 1.0 GB (50%)")
})

test("byte sizes read naturally", () => {
  assert.equal(Preview.humanBytes(0), "0 B")
  assert.equal(Preview.humanBytes(1536), "1.5 KB")
  assert.equal(Preview.humanBytes(250 * 1024 * 1024), "250 MB")
  assert.equal(Preview.humanBytes(-1), "")
})
