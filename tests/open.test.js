const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")

const source = fs.readFileSync(path.join(__dirname, "../Spotlight.qml"), "utf8")
const openPath = source.match(/  function openPath\(path\) \{([\s\S]*?)\n  \}/)
assert.ok(openPath)
const runOpenPath = new Function("Util", "console", "path", openPath[1])

function recorder() {
  const calls = { argv: [], warnings: [] }
  const util = { execArgv(argv) { calls.argv.push(argv) } }
  const log = { warn(...args) { calls.warnings.push(args.join(" ")) } }
  return { calls, open: target => runOpenPath(util, log, target) }
}

test("files and folders open through gio, detached", () => {
  const { calls, open } = recorder()
  open("/home/user/Projects")
  open("/home/user/notes.md")
  assert.deepEqual(calls.argv, [
    ["gio", "open", "/home/user/Projects"],
    ["gio", "open", "/home/user/notes.md"]
  ])
  assert.deepEqual(calls.warnings, [])
})

test("an empty path is refused", () => {
  const { calls, open } = recorder()
  open("")
  open(undefined)
  assert.deepEqual(calls.argv, [])
  assert.equal(calls.warnings.length, 2)
})

// A Process child keeps pipes whose read ends Quickshell has closed, and gio
// hands them to the app it starts: an app that writes to stdout or stderr at
// startup then dies of SIGPIPE while gio exits 0.
test("no attached Process runs gio", () => {
  assert.doesNotMatch(source, /command\s*=\s*\[\s*"gio"/)
  assert.doesNotMatch(source, /id:\s*openProc\b/)
})
