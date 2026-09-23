const assert = require("node:assert/strict")
const test = require("node:test")
const Query = require("../lib/Query.js")

test("every colon alias selects exactly one provider", () => {
  const aliases = {
    a: "app", app: "app",
    w: "window", window: "window",
    f: "file", file: "file",
    action: "action", cmd: "action",
    cb: "clipboard", clipboard: "clipboard",
    web: "web", search: "web", url: "web",
    calc: "calc",
    unit: "unit", convert: "unit",
    reminder: "reminder",
    calendar: "calendar", event: "calendar",
    man: "tldr", tldr: "tldr",
    ports: "ports", ssh: "ssh", docker: "docker", services: "services", mounts: "mounts",
    audio: "audio", wifi: "wifi", bluetooth: "bluetooth"
  }

  for (const [alias, provider] of Object.entries(aliases)) {
    const parsed = Query.parse(`${alias}: needle`)
    assert.equal(parsed.filter, provider, alias)
    assert.equal(parsed.text, "needle", alias)
  }
})

test("empty filters are hints, not unscoped searches", () => {
  for (const alias of ["a", "window", "f", "cmd", "cb", "web", "calc", "unit", "reminder", "event", "man"]) {
    const parsed = Query.parse(`${alias}:`)
    assert.equal(parsed.empty, true, alias)
  }
  assert.deepEqual(
    { filter: Query.parse("ports:").filter, empty: Query.parse("ports:").empty },
    { filter: "ports", empty: true }
  )
  assert.equal(Query.parse("ports:22").text, "22")
  assert.equal(Query.parse("ssh:prod").text, "prod")
  assert.equal(Query.parse("docker:api").text, "api")
  assert.equal(Query.parse("services:ssh").text, "ssh")
  assert.equal(Query.parse("mounts:games").text, "games")
  assert.equal(Query.parse("audio:mic").text, "mic")
  assert.equal(Query.parse("wifi:home").text, "home")
  assert.equal(Query.parse("bluetooth:headphones").text, "headphones")
})

test("view prefixes offer completions without replacing filtered queries", () => {
  assert.deepEqual(Query.viewCompletions("port"), ["ports"])
  assert.deepEqual(Query.viewCompletions("s"), ["ssh", "services"])
  assert.deepEqual(Query.viewCompletions("dock:"), ["docker"])
  assert.deepEqual(Query.viewCompletions("moun"), ["mounts"])
  assert.deepEqual(Query.viewCompletions("aud"), ["audio"])
  assert.deepEqual(Query.viewCompletions("wif"), ["wifi"])
  assert.deepEqual(Query.viewCompletions("blue"), ["bluetooth"])
  assert.deepEqual(Query.viewCompletions("ports:22"), [])
  assert.deepEqual(Query.viewCompletions("hello world"), [])
  for (const name of ["ports", "ssh", "docker", "services", "mounts", "audio", "wifi", "bluetooth"]) {
    assert.equal(Query.parse(`${name}:`).filter, name)
    assert.ok(Query.viewDetails(name).title)
  }
})

test("default selection favors matching apps, then unique views", () => {
  const view = (name) => ({ kind: "view", resultType: "view", title: `${name}:` })
  const app = (name) => ({ kind: "app", resultType: "app", title: name })
  const action = { kind: "shell", resultType: "action", title: "Toggle Bluetooth" }
  assert.equal(Query.firstSelectableIndex([view("bluetooth"), action], "blue"), 0)
  assert.equal(Query.firstSelectableIndex([view("ports"), app("Portal")], "port"), 1)
  assert.equal(Query.firstSelectableIndex([view("docker"), app("Document Viewer")], "doc"), 1)
  assert.equal(Query.firstSelectableIndex([view("mounts"), app("Moonlight")], "mo"), 1)
  assert.equal(Query.firstSelectableIndex([view("services"), app("Settings")], "se"), 1)
  assert.equal(Query.firstSelectableIndex([view("docker"), app("Docker")], "do"), 1)
  assert.equal(Query.firstSelectableIndex([view("ports"), app("Portal")], "p"), 1)
  assert.equal(Query.firstSelectableIndex([view("ssh"), view("services"), app("Settings")], "s"), 2)
  assert.equal(Query.firstSelectableIndex([{ kind: "noop" }, view("wifi")], "wifi"), 1)
})

test("a full name picks its exact match: an app first, then the view", () => {
  const view = (name) => ({ kind: "view", resultType: "view", title: `${name}:` })
  const app = (name) => ({ kind: "app", resultType: "app", title: name })
  assert.equal(Query.firstSelectableIndex([view("docker"), app("Docker")], "docker"), 1)
  assert.equal(Query.firstSelectableIndex([view("docker"), app("Docker Desktop")], "docker"), 0)
  assert.equal(Query.firstSelectableIndex([view("bluetooth"), app("Bluetooth Manager")], "bluetooth"), 0)
  assert.equal(Query.firstSelectableIndex([view("audio"), app("Audio Recorder")], "Audio"), 0)
  // Rows that are not led by a view keep their own order.
  assert.equal(Query.firstSelectableIndex([app("Firefox"), view("ports")], "port"), 0)
  assert.equal(Query.firstSelectableIndex([], "port"), 0)
})

test("Tab completes the row Enter would act on", () => {
  const view = (name) => ({ kind: "view", resultType: "view", title: `${name}:`,
    payload: { query: `${name}:` } })
  const app = (name) => ({ kind: "app", resultType: "app", title: name })
  const tab = (rows, typed) => Query.completionText(rows[Query.firstSelectableIndex(rows, typed)])
  assert.equal(tab([view("ports"), app("Portal")], "port"), "Portal")
  assert.equal(tab([view("mounts"), app("Moonlight")], "moun"), "mounts:")
  assert.equal(tab([view("bluetooth"), app("Bluetooth Manager")], "bluetooth"), "bluetooth:")
  assert.equal(Query.completionText({ kind: "url", title: "Search" }), "")
  assert.equal(Query.completionText(undefined), "")
})

test("space-separated file, clipboard and tldr syntax is exclusive", () => {
  assert.deepEqual(
    { filter: Query.parse("f report").filter, text: Query.parse("f report").text },
    { filter: "file", text: "report" }
  )
  assert.deepEqual(
    { filter: Query.parse("cb ssh").filter, text: Query.parse("cb ssh").text },
    { filter: "clipboard", text: "ssh" }
  )
  assert.deepEqual(
    { filter: Query.parse("man scp").filter, text: Query.parse("man scp").text },
    { filter: "tldr", text: "scp" }
  )
  assert.equal(Query.parse("tldr git commit").text, "git commit")
  assert.equal(Query.parse("tldr: scp").filter, "tldr")
})

test("window colon filter does not steal the Wikipedia bang", () => {
  assert.equal(Query.parse("w: firefox").filter, "window")
  assert.equal(Query.parse("w firefox").filter, "")
  assert.equal(Query.parse("gh quickshell").filter, "")
})

test("query prefixes and colon filters use separate context namespaces", () => {
  assert.deepEqual(Query.contextKeys(Query.parse("Fire")), [
    "query:fi", "query:fir", "query:fire"
  ])
  assert.deepEqual(Query.contextKeys(Query.parse("app: Fire")), [
    "filter:app:fi", "filter:app:fir", "filter:app:fire"
  ])
  assert.equal(Query.contextKey(Query.parse("f report")), "filter:file:report")
  assert.deepEqual(Query.contextKeys(Query.parse("x")), [])
})
