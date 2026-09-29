const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const NaturalTime = require("../lib/NaturalTime.js")

// Saturday, 19 September 2026, 10:00 local.
const NOW = new Date(2026, 8, 19, 10, 0, 0)

const stamp = d => [
  d.getFullYear(), "-", ("0" + (d.getMonth() + 1)).slice(-2), "-", ("0" + d.getDate()).slice(-2),
  " ", ("0" + d.getHours()).slice(-2), ":", ("0" + d.getMinutes()).slice(-2)
].join("")

const event = text => NaturalTime.parseEvent(text, NOW)

test("a date phrase makes an event without a trigger word", () => {
  const cases = [
    ["birthday party with sam on 25 september at 6pm", "Birthday party with sam", "2026-09-25 18:00", false],
    ["bring ian to station next week at 15:00", "Bring ian to station", "2026-09-21 15:00", false],
    ["birthday party 25.03.2027", "Birthday party", "2027-03-25 09:00", true],
    ["standup 01 mar", "Standup", "2027-03-01 09:00", true],
    ["dentist next monday at 10", "Dentist", "2026-09-21 10:00", false],
    ["lunch with tom on friday at 13:00", "Lunch with tom", "2026-09-25 13:00", false],
    ["party in 3 days", "Party", "2026-09-22 10:00", true],
    ["team offsite 2027-01-15", "Team offsite", "2027-01-15 09:00", true]
  ]
  for (const [text, title, start, allDay] of cases) {
    const e = event(text)
    assert.ok(e, text)
    assert.equal(e.title, title, text)
    assert.equal(stamp(e.start), start, text)
    assert.equal(e.allDay, allDay, text)
  }
})

// The clock branches used to run first, so "25 september at 18:00" matched
// only the "at 18:00" and booked the party for today.
test("a date with a time beats the bare clock hiding inside it", () => {
  assert.equal(stamp(event("birthday party with sam on 25 september at 18 pm").start), "2026-09-25 18:00")
  assert.equal(stamp(event("event dec 24 at 18:00").start), "2026-12-24 18:00")
  assert.equal(stamp(event("release 24.12. 18:00").start), "2026-12-24 18:00")
})

test("a date with no clock runs all day and ends the next day", () => {
  const e = event("birthday party 25.03.2027")
  assert.equal(e.allDay, true)
  assert.equal(NaturalTime.toDateBasic(e.start), "20270325")
  assert.equal(NaturalTime.toDateBasic(e.end), "20270326")
  assert.equal(e.label, "25 Mar 2027")
  // An explicit duration is a time span, so it is not an all-day event.
  assert.equal(event("birthday party 25.03.2027 for 2h").allDay, false)
})

// parseWhen used to stop at the first phrase, so "in 3w" was the whole answer
// and "at 15pm" stayed in the title with the event left running all day.
test("a day and a clock written as two phrases describe one moment", () => {
  const cases = [
    ["birthday party in 3w at 15pm", "Birthday party", "2026-10-10 15:00"],
    ["birthday party at 3pm tomorrow", "Birthday party", "2026-09-20 15:00"],
    ["standup in 3 days at 9:30", "Standup", "2026-09-22 09:30"],
    ["lunch at 13:00 next monday", "Lunch", "2026-09-21 13:00"],
    ["party at noon tomorrow", "Party", "2026-09-20 12:00"]
  ]
  for (const [text, title, start] of cases) {
    const e = event(text)
    assert.ok(e, text)
    assert.equal(e.title, title, text)
    assert.equal(stamp(e.start), start, text)
    assert.equal(e.allDay, false, text)
  }
})

// A clock standing alone rolls past an hour that has already gone by. Once a
// day phrase turns up the literal hour is what was meant, so late in the
// evening "in 3 days at 9:30" must not become half past nine at night.
test("merging a clock onto a day keeps the hour as written", () => {
  const late = new Date(2026, 8, 19, 22, 0, 0)
  assert.equal(stamp(NaturalTime.parseEvent("standup in 3 days at 9:30", late).start), "2026-09-22 09:30")
  assert.equal(stamp(NaturalTime.parseEvent("lunch at 13:00 next monday", late).start), "2026-09-21 13:00")
  // A clock on its own still rolls forward.
  assert.equal(stamp(NaturalTime.parseEvent("meeting at 9", late).start), "2026-09-20 21:00")
})

test("the trigger word is the title when the query is nothing but a date", () => {
  assert.equal(event("meeting 25 sep").title, "Meeting")
  assert.equal(event("meeting next monday").title, "Meeting")
  assert.equal(event("cal 25 sep").title, "Event")
  // Without a trigger there is no title to fall back on.
  assert.equal(event("25 sep"), null)
})

test("an ordinary search is not an event", () => {
  for (const text of ["firefox", "python 3.12.1", "monday-notes.md", "budget 2026",
                      "note friday ideas", "remind me tomorrow at 9"])
    assert.equal(event(text), null, text)
})

test("the reminder path keeps its own reading of the same phrases", () => {
  const r = NaturalTime.parseReminder("remind me to call bob in 20m", NOW)
  assert.equal(r.message, "Call bob")
  assert.equal(r.minutes, 20)
  // An all-day phrase still has to resolve to one concrete moment here.
  assert.equal(stamp(NaturalTime.parseReminder("remind me on 25 september", NOW).at), "2026-09-25 09:00")
  assert.equal(NaturalTime.parseReminder("remind me to water plants", NOW).needsTime, true)
})

test("the calendar row carries the all-day dates through to both exports", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Spotlight.qml"), "utf8")
  assert.match(qml, /allDay: event\.allDay === true/)
  assert.match(qml, /event\.allDay \? NaturalTime\.toDateBasic\(event\.start\)/)
  assert.match(qml, /var dateOnly = payload\.allDay \? ";VALUE=DATE" : ""/)
  assert.match(qml, /"DTSTART" \+ dateOnly \+ ":" \+ payload\.start/)
  assert.match(qml, /"DTSTAMP:" \+ stamp/)
})
