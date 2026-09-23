const assert = require("node:assert/strict")
const test = require("node:test")
const Commands = require("../lib/Commands.js")
const Queue = require("../lib/SettingsQueue.js")

test("settings result keeps the file editor as a secondary action", () => {
  const settings = Commands.commands().find(command => command.key === "spotlight.settings")
  assert.equal(settings.kind, "spotlight-settings")
  assert.equal(settings.secondaryLabel, "Edit spotlight.json")
})

test("a tour patch waits for the panel write and keeps the latest value", () => {
  let state = Queue.add(Queue.create(), { fileSearch: false })
  let next = Queue.take(state)
  assert.deepEqual(next.patch, { fileSearch: false })
  state = Queue.add(next.state, { fileSearch: true, maxResults: 30 })
  assert.equal(Queue.take(state).patch, null)
  state = Queue.settle(state, true)
  next = Queue.take(state)
  assert.deepEqual(next.patch, { fileSearch: true, maxResults: 30 })
  assert.deepEqual(Queue.settle(next.state, true), Queue.create())
})

test("a failed write stays pending until retry, with newer edits taking priority", () => {
  let state = Queue.add(Queue.create(), { fileSearch: false, maxApps: 10 })
  state = Queue.take(state).state
  state = Queue.add(state, { fileSearch: true })
  state = Queue.settle(state, false)
  assert.equal(state.failed, true)
  assert.deepEqual(state.pending, { fileSearch: true, maxApps: 10 })
  assert.equal(Queue.take(state).patch, null)
  // A later edit queues up but does not write over a file fixed by hand.
  state = Queue.add(state, { maxResults: 30 })
  assert.equal(state.failed, true)
  assert.equal(Queue.take(state).patch, null)
  state = Queue.retry(state)
  assert.deepEqual(Queue.take(state).patch, { fileSearch: true, maxApps: 10, maxResults: 30 })
})
