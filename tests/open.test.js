const assert = require("node:assert/strict")
const { spawnSync } = require("node:child_process")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const test = require("node:test")

const source = fs.readFileSync(path.join(__dirname, "../Spotlight.qml"), "utf8")
const openPath = source.match(/  function openPath\(path\) \{([\s\S]*?)\n  \}/)
assert.ok(openPath)
const runOpenPath = new Function("openProcessComponent", "root", "console", "path", openPath[1])

function recorder() {
  const calls = { launches: [], warnings: [] }
  const component = { createObject(_parent, properties) { calls.launches.push(properties) } }
  const log = { warn(...args) { calls.warnings.push(args.join(" ")) } }
  return { calls, open: target => runOpenPath(component, {}, log, target) }
}

test("files and folders get independent opener processes", () => {
  const { calls, open } = recorder()
  open("/home/user/Projects")
  open("/home/user/notes.md")
  assert.deepEqual(calls.launches.map(launch => launch.target), [
    "/home/user/Projects", "/home/user/notes.md"
  ])
  assert.deepEqual(calls.warnings, [])
})

test("an empty path is refused", () => {
  const { calls, open } = recorder()
  open("")
  open(undefined)
  assert.deepEqual(calls.launches, [])
  assert.equal(calls.warnings.length, 2)
})

test("gio receives a literal path and null stdio, and its exit code survives", t => {
  const bin = fs.mkdtempSync(path.join(os.tmpdir(), "spotlight-open-"))
  t.after(() => fs.rmSync(bin, { recursive: true, force: true }))
  fs.writeFileSync(path.join(bin, "gio"), `#!/bin/sh
[ "$#" -eq 3 ] && [ "$1" = open ] && [ "$2" = -- ] && [ "$3" = "$EXPECTED_PATH" ] || exit 90
for fd in 0 1 2; do
  [ "/proc/$$/fd/$fd" -ef /dev/null ] || exit 91
done
exit 37
`, { mode: 0o755 })

  const { calls, open } = recorder()
  const target = "--name with spaces 'and $(exit 1)'"
  open(target)
  const [shell, ...args] = calls.launches[0].command
  const result = spawnSync(shell, args, {
    env: { ...process.env, PATH: bin + path.delimiter + process.env.PATH, EXPECTED_PATH: target },
    stdio: "inherit",
    timeout: 5000
  })
  assert.ifError(result.error)
  assert.equal(result.status, 37)
})
