const assert = require("node:assert/strict")
const test = require("node:test")
const fs = require("node:fs")
const Query = require("../lib/Query.js")
const source = fs.readFileSync(require("node:path").join(__dirname, "../Spotlight.qml"), "utf8")
function navigation() {
  const root = { opened: true, folderProcess: null, folderStack: [], folderRows: [], folderPath: "",
    folderIndex: 3, pinnedKey: "unchanged", navigatingResults: true, helperReply: JSON.parse, row: r => r,
    selectedRowKey: () => "file:/parent/child", rebuild() {} }
  for (const name of ["resetFolders", "loadFolder", "leaveFolder"]) {
    const match = source.match(new RegExp("  function " + name + "\\(([^)]*)\\) \\{([\\s\\S]*?)\\n  \\}"))
    assert.ok(match, name)
    root[name] = new Function("root", "return function(" + match[1] + ") {" + match[2] + "}")(root)
  }
  return root
}
test("folder descent and return preserve the parent selection and exact child path", () => {
  const root = navigation()
  const proc = { path: "/parent/child" }
  root.folderProcess = proc
  root.loadFolder(JSON.stringify({kind: "dir", entries: [
    { name: "display", path: "/parent/child/exact", isDir: true }
  ]}), proc)
  assert.equal(root.folderPath, proc.path)
  assert.equal(root.folderRows[0].payload.path, "/parent/child/exact")
  const rows = root.folderRows
  const nested = {path: "/parent/child/exact"}
  root.folderProcess = nested
  root.loadFolder(JSON.stringify({kind: "dir", entries: []}), nested)
  assert.equal(root.folderRows[0].title, "Empty folder")
  assert.equal(root.leaveFolder(), true)
  assert.equal(root.folderRows, rows)
  assert.equal(root.leaveFolder(), true)
  assert.equal(root.folderPath, "")
  assert.equal(root.folderIndex, 3)
  assert.equal(root.pinnedKey, "unchanged")
  assert.equal(root.leaveFolder(), false)
})
test("cancelled directory replies cannot reopen navigation", () => {
  const root = navigation()
  const proc = {path: "/old", running: true}
  root.folderProcess = proc
  root.resetFolders()
  root.loadFolder(JSON.stringify({kind: "dir", entries: []}), proc)
  assert.equal(proc.running, false)
  assert.equal(root.folderPath, "")
  assert.equal(root.folderStack.length, 0)
})
test("Tab completes folder names but does not complete regular files", () => {
  assert.equal(Query.completionText({kind: "file", accessory: "Folder", title: "yekintel"}), "yekintel")
  assert.equal(Query.completionText({kind: "file", accessory: "File", title: "file.txt"}), "")
})

// Exercise the production key handler; unaccepted events belong to TextInput.
function keyboard() {
  const root = navigation()
  Object.assign(root, {
    folderPath: "/parent", folderRows: Array.from({length: 12}, (_, i) => ({kind: "file", payload: {path: "/parent/" + i}})),
    folderIndex: 0, selectedIndex: 4, aiActive: false,
    select(delta) { this.selectedIndex += delta },
    enterFolder() { this.entered = true },
    leaveFolder() { this.left = true; return true },
    openPath(path) { this.openedPath = path }
  })
  const Qt = new Proxy({NoModifier: 0, ControlModifier: 1, ShiftModifier: 2}, {
    get: (values, key) => key in values ? values[key] : key
  })
  const match = source.match(/Keys.onPressed: function\(event\) \{([\s\S]*?)\n          \}/)
  assert.ok(match)
  const input = {text: "query", selectedText: ""}
  const press = new Function("root", "Qt", "typingGuard", "input",
    "return function(event) {" + match[1] + "}")(root, Qt, {restart() {}}, input)
  return {root, key(name, modifiers = 0, text = "") {
    const event = {key: Qt["Key_" + name], modifiers, text, accepted: false}
    press(event)
    return event
  }}
}

test("ineffective edits preserve folder navigation; real query resets clear it", () => {
  for (const name of ["Delete", "Backspace", "A"]) {
    const {root, key} = keyboard()
    assert.equal(key(name, name === "A" ? 1 : 0).accepted, false)
    assert.equal(root.navigatingResults, true)
    assert.equal(key("Right").accepted, true)
    assert.equal(root.entered, true)
    assert.equal(key("Left").accepted, true)
    assert.equal(root.left, true)
    root.resetFolders()
    assert.equal(root.navigatingResults, false)
    assert.equal(root.folderPath, "")
    assert.equal(key("Right").accepted, false)
  }
})

test("Ctrl+N/P and arrows move only the right selection and Enter opens it", () => {
  const {root, key} = keyboard()
  const pending = {running: true}
  root.folderProcess = pending
  assert.equal(key("N", 1, "n").accepted, true)
  assert.equal(root.folderIndex, 1)
  assert.equal(pending.running, false)
  assert.equal(key("Down").accepted, true)
  assert.equal(root.folderIndex, 2)
  key("P", 1, "p")
  key("Up")
  key("P", 1, "p")
  assert.equal(root.folderIndex, 0)
  key("PageDown")
  assert.equal(root.folderIndex, 8)
  key("PageDown")
  assert.equal(root.folderIndex, 11)
  key("Return")
  assert.equal(root.openedPath, "/parent/11")
  assert.equal(root.selectedIndex, 4)
  assert.equal(root.navigatingResults, true)
})

test("Ctrl+N/P retain their left-list behavior outside folder browsing", () => {
  const {root, key} = keyboard()
  root.folderPath = ""
  key("N", 1, "n")
  assert.equal(root.selectedIndex, 5)
  key("P", 1, "p")
  assert.equal(root.selectedIndex, 4)
  root.navigatingResults = false
  assert.equal(key("Left").accepted, false)
  assert.equal(key("Right").accepted, false)
})

test("the first Down after typing moves the left selection", () => {
  const {root, key} = keyboard()
  Object.assign(root, {folderPath: "", navigatingResults: false})
  assert.equal(key("Down").accepted, true)
  assert.equal(root.selectedIndex, 5)
  assert.equal(root.navigatingResults, true)
})

test("Left and Right stay caret keys unless they browse", () => {
  const {root, key} = keyboard()
  Object.assign(root, {folderPath: "", enterFolder() { return false }})
  assert.equal(key("Right").accepted, false)
  root.leaveFolder = () => false
  assert.equal(key("Left").accepted, false)
  assert.equal(root.navigatingResults, false)
  assert.equal(key("Right").accepted, false)
})

test("Right inside a folder is claimed even on a file entry", () => {
  const {root, key} = keyboard()
  root.enterFolder = () => false
  assert.equal(key("Right").accepted, true)
})

test("a new left selection ends folder browsing", () => {
  const match = source.match(/  onSelectedIndexChanged: \{([\s\S]*?)\n  \}/)
  assert.ok(match)
  const pending = {running: true}
  const root = {folderProcess: pending, folderStack: [{path: ""}], folderRows: [{}], folderPath: "/parent",
    navigatingResults: true, schedulePreview() { this.scheduled = true }}
  new Function("root", match[1])(root)
  assert.equal(pending.running, false)
  assert.equal(root.folderProcess, null)
  assert.equal(root.folderPath, "")
  assert.deepEqual(root.folderStack, [])
  assert.deepEqual(root.folderRows, [])
  assert.equal(root.navigatingResults, true)
  assert.equal(root.scheduled, true)
})
