// Natural-language time parsing for the reminder and calendar rows.
//
// parseWhen() finds the time phrases anywhere in a string and reports both the
// resolved Date and the query with those phrases taken out, so the caller can
// keep the remainder as the title/message. Everything resolves against an
// injected `now` so the behaviour is testable.

// Same rule as the other tables in lib/: these are indexed with words lifted
// out of the query, so they are only ever consulted for keys they own.
// Object.prototype is not a calendar.
var owned = Object.prototype.hasOwnProperty

function tableGet(table, key) {
  return owned.call(table, key) ? table[key] : undefined
}

var WEEKDAYS = {
  sunday: 0, sun: 0,
  monday: 1, mon: 1,
  tuesday: 2, tue: 2, tues: 2,
  wednesday: 3, wed: 3,
  thursday: 4, thu: 4, thur: 4, thurs: 4,
  friday: 5, fri: 5,
  saturday: 6, sat: 6
}

var MONTHS = {
  jan: 0, january: 0, feb: 1, february: 1, mar: 2, march: 2, apr: 3, april: 3,
  may: 4, jun: 5, june: 5, jul: 6, july: 6, aug: 7, august: 7,
  sep: 8, sept: 8, september: 8, oct: 9, october: 9, nov: 10, november: 10,
  dec: 11, december: 11
}

var MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var UNIT_MINUTES = {
  s: 1 / 60, sec: 1 / 60, secs: 1 / 60, second: 1 / 60, seconds: 1 / 60,
  m: 1, min: 1, mins: 1, minute: 1, minutes: 1,
  h: 60, hr: 60, hrs: 60, hour: 60, hours: 60,
  d: 1440, day: 1440, days: 1440,
  w: 10080, week: 10080, weeks: 10080
}

var WEEKDAY_ALTERNATION = "sunday|sun|monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat"

// Longest first, so "september" is never matched as "sep" with a stray tail.
var MONTH_ALTERNATION = Object.keys(MONTHS)
  .sort(function (a, b) { return b.length - a.length })
  .join("|")

// Every word that can anchor a day on its own.
var DAY_WORDS = "today|tonight|tomorrow|tmr|morgen|next\\s+week|next\\s+(?:"
  + WEEKDAY_ALTERNATION + ")|" + WEEKDAY_ALTERNATION

// "on"/"am" in front of a date belongs to the date, not to the title.
var LEAD = "(?:(?:on|am)\\s+)?"

// "25 september", "on 25th sep 2027", "dec 24". The month names are baked into
// the pattern rather than checked afterwards: matching any word here would let
// "room 5 with sarah" claim the slot and hide the real date further along.
var DATE_MONTH = new RegExp(
  "\\b" + LEAD + "(?:(\\d{1,2})(?:st|nd|rd|th)?\\.?\\s+(" + MONTH_ALTERNATION + ")"
  + "|(" + MONTH_ALTERNATION + ")\\s+(\\d{1,2})(?:st|nd|rd|th)?)(?:\\s+(\\d{4}))?\\b", "i")

// A clock directly after a date. Bare digits only count when something marks
// them as a time, so "25 sep 2027" keeps its year and "party 25 sep 3" is not
// three o'clock.
var CLOCK_TAIL = /^[\s,]*(?:(at|@|um)\s*)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i

function startOfDay(d) {
  var out = new Date(d.getTime())
  out.setHours(0, 0, 0, 0)
  return out
}

function addDays(d, n) {
  var out = new Date(d.getTime())
  out.setDate(out.getDate() + n)
  return out
}

// Next occurrence of `weekday`, strictly in the future. "next friday" on a
// Friday means the Friday a week out, which is what people mean by it.
function nextWeekday(now, weekday) {
  var delta = (weekday - now.getDay() + 7) % 7
  if (delta === 0) delta = 7
  return addDays(startOfDay(now), delta)
}

function applyClock(day, hour, minute) {
  var out = new Date(day.getTime())
  out.setHours(hour, minute, 0, 0)
  return out
}

function normalizeHour(hour, meridiem) {
  if (!meridiem) return hour
  var h = hour % 12
  return meridiem === "pm" ? h + 12 : h
}

function dayAnchor(now, word) {
  if (!word) return null
  var w = String(word).toLowerCase().replace(/\s+/g, " ").trim()
  if (w === "today") return startOfDay(now)
  if (w === "tonight") return startOfDay(now)
  if (w === "tomorrow" || w === "tmr" || w === "morgen") return addDays(startOfDay(now), 1)
  // "next week" means the week that starts on Monday, not the same weekday
  // seven days out, which is what a plain +7 gives you on a Saturday.
  if (w === "next week") return nextWeekday(now, 1)
  if (w.indexOf("next ") === 0) w = w.slice(5).trim()
  var weekday = tableGet(WEEKDAYS, w)
  if (weekday !== undefined) return nextWeekday(now, weekday)
  return null
}

// `allDay` says no clock was given, so a calendar row should span the day.
// `floating` is its mirror: a clock with no day behind it, carrying the hour
// as written in `hour`/`minute`. Either one means the phrase is half an
// appointment and the other half may be elsewhere in the query.
// `strong` says the phrase cannot plausibly be an ordinary search, which is
// what lets parseEvent fire on a query that never said "meeting". A bare
// weekday is the one token common enough in file and app names to stay weak.
function found(at, index, length, now, allDay, weak) {
  return {
    at: at,
    from: index,
    to: index + length,
    label: labelFor(at, now, allDay),
    allDay: !!allDay,
    floating: false,
    strong: !weak
  }
}

// Blanks a span without moving anything, so an index taken from the result
// still points at the same character in the original query.
function blank(text, from, to) {
  return text.slice(0, from) + text.slice(from, to).replace(/\S/g, " ") + text.slice(to)
}

function labelFor(at, now, allDay) {
  var sameDay = startOfDay(at).getTime() === startOfDay(now).getTime()
  var tomorrow = startOfDay(at).getTime() === addDays(startOfDay(now), 1).getTime()
  var hh = ("0" + at.getHours()).slice(-2)
  var mm = ("0" + at.getMinutes()).slice(-2)
  var clock = allDay ? "" : " at " + hh + ":" + mm
  if (sameDay) return "today" + clock
  if (tomorrow) return "tomorrow" + clock
  var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  if (at.getTime() - now.getTime() < 7 * 86400000) return names[at.getDay()] + clock
  var date = at.getDate() + " " + MONTH_NAMES[at.getMonth()]
  if (at.getFullYear() !== now.getFullYear()) date += " " + at.getFullYear()
  return date + clock
}

// A clock sitting immediately after a matched date, or null.
function clockAfter(text, index) {
  var m = CLOCK_TAIL.exec(String(text).slice(index))
  if (!m) return null
  var meridiem = (m[4] || "").toLowerCase()
  if (!m[1] && !m[3] && !meridiem) return null
  var hour = normalizeHour(Number(m[2]), meridiem)
  var minute = m[3] ? Number(m[3]) : 0
  if (hour > 23 || minute > 59) return null
  return { hour: hour, minute: minute, length: m[0].length }
}

// Shared tail of the three date branches. A date with no year means the next
// one still to come; a date with no clock runs all day, and the 09:00 it still
// carries is what the reminder path needs to have a concrete moment at all.
function dated(text, m, now, year, month, day) {
  if (!(month >= 0 && month <= 11) || !(day >= 1 && day <= 31)) return null
  var end = m.index + m[0].length
  var clock = clockAfter(text, end)
  var at = new Date(year < 0 ? now.getFullYear() : year, month, day,
    clock ? clock.hour : 9, clock ? clock.minute : 0, 0, 0)
  if (at.getMonth() !== month) return null
  if (year < 0 && at.getTime() < now.getTime()) at.setFullYear(at.getFullYear() + 1)
  return found(at, m.index, (clock ? end + clock.length : end) - m.index, now, !clock)
}

// Returns { at, label, allDay, strong, rest } or null. `rest` is the query
// with every matched phrase removed.
function parseWhen(text, now) {
  var s = String(text || "")
  if (!s.trim()) return null
  now = now || new Date()

  var first = firstPhrase(s, now)
  if (!first) return null

  // A day and a clock can arrive as two separate phrases: "in 3w at 15pm" and
  // "at 3pm tomorrow" each name both, and no single span covers them. When the
  // first phrase left one half open, look for the other half once more in what
  // is left of the query.
  var second = (first.allDay || first.floating)
    ? firstPhrase(blank(s, first.from, first.to), now) : null
  var merged = second ? mergeDayAndClock(first, second, now) : null
  if (merged && merged.at.getTime() <= now.getTime()) merged = null

  var when = merged || first
  var rest = blank(s, first.from, first.to)
  if (merged) rest = blank(rest, second.from, second.to)
  when.rest = rest.replace(/\s+/g, " ").trim()
  return when
}

// Two half-appointments describing one moment: take the day from the phrase
// that names a day and the clock from the phrase that names a clock.
function mergeDayAndClock(first, second, now) {
  var day = first.allDay ? first : (second.allDay ? second : null)
  var clock = first.floating ? first : (second.floating ? second : null)
  if (!day || !clock || day === clock) return null
  var at = applyClock(startOfDay(day.at), clock.hour, clock.minute)
  return {
    at: at,
    label: labelFor(at, now, false),
    allDay: false,
    floating: false,
    strong: day.strong || clock.strong
  }
}

// The first time phrase in the string, or null.
function firstPhrase(s, now) {
  var m

  // "in 1h30", "in 2 hours and 15 minutes"
  m = s.match(/\bin\s+(\d+)\s*(?:h|hr|hrs|hour|hours)\s*(?:and\s+)?(\d+)\s*(?:m|min|mins|minute|minutes)?\b/i)
  if (m) {
    var mins = Number(m[1]) * 60 + Number(m[2])
    return found(new Date(now.getTime() + mins * 60000), m.index, m[0].length, now, false)
  }

  // "in 20m", "in 3 days"
  m = s.match(/\bin\s+(\d+(?:[.,]\d+)?)\s*(seconds|second|secs|sec|minutes|minute|mins|min|hours|hour|hrs|hr|days|day|weeks|week|s|m|h|d|w)\b/i)
  if (m) {
    var n = Number(String(m[1]).replace(",", "."))
    var unit = m[2].toLowerCase()
    var per = tableGet(UNIT_MINUTES, unit)
    if (isFinite(n) && per) {
      var at2 = new Date(now.getTime() + Math.round(n * per) * 60000)
      // "in 3 days" names a day, not a moment.
      return found(at2, m.index, m[0].length, now, per >= 1440)
    }
  }

  // "in an hour", "in a minute"
  m = s.match(/\bin\s+(?:a|an|one)\s+(minute|hour|day|week)\b/i)
  if (m) {
    var word1 = m[1].toLowerCase()
    var at3 = new Date(now.getTime() + (tableGet(UNIT_MINUTES, word1) || 0) * 60000)
    return found(at3, m.index, m[0].length, now, word1 === "day" || word1 === "week")
  }

  // Dates come before the clock branches. "25 september at 18:00" is a date
  // with a time on it, and matching only the "at 18:00" would quietly move the
  // event to today and leave "25 september" sitting in the title.

  // "2026-09-12", "2026-09-12 14:00"
  m = s.match(new RegExp("\\b" + LEAD + "(\\d{4})-(\\d{2})-(\\d{2})\\b", "i"))
  if (m) return dated(s, m, now, Number(m[1]), Number(m[2]) - 1, Number(m[3]))

  // "24.12.", "25.03.2027", "24.12. 18:00". The lookahead keeps a version
  // number like "3.12.1" from reading as the third of December.
  m = s.match(new RegExp("\\b" + LEAD + "(\\d{1,2})\\.(\\d{1,2})\\.(\\d{4}|\\d{2})?(?!\\d)", "i"))
  if (m && m[2]) {
    var dotYear = m[3] ? (m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3])) : -1
    return dated(s, m, now, dotYear, Number(m[2]) - 1, Number(m[1]))
  }

  // "25 september", "on 25 sep at 18:00", "dec 24 at 6pm", "1 mar 2027"
  m = s.match(DATE_MONTH)
  if (m) {
    var monthIndex = tableGet(MONTHS, String(m[2] || m[3]).toLowerCase())
    if (monthIndex !== undefined)
      return dated(s, m, now, m[5] ? Number(m[5]) : -1, monthIndex, Number(m[1] || m[4]))
  }

  // "at noon" / "at midnight", optionally with a day word
  m = s.match(new RegExp("\\b" + LEAD + "(?:(" + DAY_WORDS + ")\\s+)?(?:at|um)\\s+(noon|midday|midnight)\\b", "i"))
  if (m) {
    var anchorA = dayAnchor(now, m[1]) || startOfDay(now)
    var hourA = m[2].toLowerCase() === "midnight" ? 0 : 12
    var atA = applyClock(anchorA, hourA, 0)
    if (!m[1] && atA.getTime() <= now.getTime()) atA = addDays(atA, 1)
    var noon = found(atA, m.index, m[0].length, now, false)
    noon.floating = !m[1]
    noon.hour = hourA
    noon.minute = 0
    return noon
  }

  // "[tomorrow] at 15:30" / "at 3pm" / "friday at 9" / "morgen um 8"
  m = s.match(new RegExp("\\b" + LEAD + "(?:(" + DAY_WORDS + ")\\s+)?(?:at|um)\\s+(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?\\b", "i"))
  if (m) return fromClockMatch(m, now)

  // "tomorrow 15:30" / "friday 9am" — day word, no "at"
  m = s.match(new RegExp("\\b" + LEAD + "(" + DAY_WORDS + ")\\s+(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?\\b", "i"))
  if (m) return fromClockMatch(m, now)

  // Bare day word: "tomorrow", "next monday", "next week", "friday"
  m = s.match(new RegExp("\\b" + LEAD + "(" + DAY_WORDS + ")\\b", "i"))
  if (m) {
    var anchorB = dayAnchor(now, m[1])
    if (anchorB) {
      var word = String(m[1]).toLowerCase()
      var tonight = word === "tonight"
      var atB = applyClock(anchorB, tonight ? 20 : 9, 0)
      if (atB.getTime() <= now.getTime()) atB = new Date(now.getTime() + 3600000)
      return found(atB, m.index, m[0].length, now, !tonight,
        tableGet(WEEKDAYS, word) !== undefined)
    }
  }

  // Bare clock: "15:30", "3pm"
  m = s.match(/\b(\d{1,2}):(\d{2})\s*(am|pm)?\b/i)
  if (!m) m = s.match(/\b(\d{1,2})()\s*(am|pm)\b/i)
  if (m) {
    var hourC = normalizeHour(Number(m[1]), (m[3] || "").toLowerCase())
    var minuteC = m[2] ? Number(m[2]) : 0
    if (hourC > 23 || minuteC > 59) return null
    var atC = applyClock(startOfDay(now), hourC, minuteC)
    if (atC.getTime() <= now.getTime()) {
      if (!m[3] && hourC < 12) {
        atC = applyClock(startOfDay(now), hourC + 12, minuteC)
        if (atC.getTime() <= now.getTime()) atC = addDays(atC, 1)
      } else {
        atC = addDays(atC, 1)
      }
    }
    var bare = found(atC, m.index, m[0].length, now, false)
    bare.floating = true
    bare.hour = hourC
    bare.minute = minuteC
    return bare
  }

  // "in 20" with no unit — minutes is the only sane reading
  m = s.match(/\bin\s+(\d{1,4})\b/i)
  if (m) {
    var atD = new Date(now.getTime() + Number(m[1]) * 60000)
    return found(atD, m.index, m[0].length, now, false)
  }

  return null
}

// Shared tail of the two "day word + clock" branches.
function fromClockMatch(m, now) {
  var dayWord = m[1]
  var hour = Number(m[2])
  var minute = m[3] ? Number(m[3]) : 0
  var meridiem = (m[4] || "").toLowerCase()
  if (hour > 23 || minute > 59) return null

  var anchor = dayAnchor(now, dayWord)
  var explicitDay = anchor !== null && String(dayWord || "").toLowerCase() !== "today" && String(dayWord || "").toLowerCase() !== "tonight"
  if (!anchor) anchor = startOfDay(now)

  var at = applyClock(anchor, normalizeHour(hour, meridiem), minute)

  if (!explicitDay && at.getTime() <= now.getTime()) {
    // No day was named and the clock already passed. Prefer the pm reading of
    // a bare morning hour ("at 3" at 14:00 means 15:00), then roll to tomorrow.
    if (!meridiem && hour < 12) {
      at = applyClock(anchor, hour + 12, minute)
      if (at.getTime() <= now.getTime()) at = addDays(at, 1)
    } else {
      at = addDays(at, 1)
    }
  }

  var clocked = found(at, m.index, m[0].length, now, false)
  clocked.floating = !dayWord
  clocked.hour = normalizeHour(hour, meridiem)
  clocked.minute = minute
  return clocked
}

function cut(text, from, to) {
  return (String(text).slice(0, from) + " " + String(text).slice(to)).replace(/\s+/g, " ").trim()
}

function tidy(text) {
  return String(text || "")
    .replace(/^(?:to|that|about|for|:|-|–|,)\s+/i, "")
    .replace(/\s+(?:to|that|about|at|on|for)$/i, "")
    .replace(/^[\s:,-]+|[\s:,-]+$/g, "")
    .replace(/\s+/g, " ")
    .trim()
}

function titleCase(text) {
  var s = String(text || "").trim()
  if (!s) return s
  return s.charAt(0).toUpperCase() + s.slice(1)
}

function minutesUntil(at, now) {
  return Math.max(1, Math.ceil((at.getTime() - (now || new Date()).getTime()) / 60000))
}

var REMINDER_TRIGGER = /^(?:remind\s+me|remind|reminder|reminders|remember|erinner\s+mich|erinnere\s+mich)\b[\s:,]*/i

function isReminderQuery(text) {
  return REMINDER_TRIGGER.test(String(text || "").trim())
}

// -> { message, at, minutes, label } | { needsTime: true, message } | null
function parseReminder(text, now) {
  var s = String(text || "").trim()
  if (!isReminderQuery(s)) return null
  now = now || new Date()

  var body = s.replace(REMINDER_TRIGGER, "")
  var when = parseWhen(body, now)
  if (!when) return { needsTime: true, message: titleCase(tidy(body)) }

  var message = titleCase(tidy(when.rest))
  return {
    message: message,
    at: when.at,
    minutes: minutesUntil(when.at, now),
    label: when.label
  }
}

var EVENT_TRIGGER = /^(?:cal|calendar|event|meeting|appointment|appt|schedule|termin)\b[\s:,]*/i

var EVENT_NOUNS = {
  meeting: "Meeting", appointment: "Appointment", appt: "Appointment",
  event: "Event", termin: "Termin"
}

function isEventQuery(text) {
  return EVENT_TRIGGER.test(String(text || "").trim())
}

// -> { title, start, end, label, durationMinutes, allDay } | null
function parseEvent(text, now) {
  var s = String(text || "").trim()
  if (!s) return null
  now = now || new Date()

  var triggerMatch = s.match(EVENT_TRIGGER)
  var triggerWord = triggerMatch ? triggerMatch[0].replace(/[\s:,]+$/, "").toLowerCase() : ""
  var body = triggerMatch ? s.replace(EVENT_TRIGGER, "") : s
  // "remind me tomorrow at 9" already has its own row; it is not also an event.
  if (!triggerMatch && isReminderQuery(s)) return null

  // Pull an explicit duration out first so "for 2 hours" is never mistaken
  // for a start time.
  var durationMinutes = 0
  var dm = body.match(/\bfor\s+(\d+(?:[.,]\d+)?)\s*(minutes|minute|mins|min|hours|hour|hrs|hr|m|h)\b/i)
  if (dm) {
    var per = tableGet(UNIT_MINUTES, dm[2].toLowerCase())
    var n = Number(String(dm[1]).replace(",", "."))
    if (per && isFinite(n)) durationMinutes = Math.max(5, Math.round(n * per))
    body = cut(body, dm.index, dm.index + dm[0].length)
  }

  var when = parseWhen(body, now)

  // "meeting …" says what the query is. Without that word the date phrase is
  // the only evidence, so it has to be one no ordinary search would contain.
  if (!triggerMatch && !(when && when.strong)) return null

  var start
  var rest = body
  var allDay = false
  if (when) {
    start = when.at
    rest = when.rest
    allDay = when.allDay && !durationMinutes
  } else {
    // Next full hour is the least surprising default.
    start = new Date(now.getTime())
    start.setMinutes(0, 0, 0)
    start.setHours(start.getHours() + 1)
  }
  if (!durationMinutes) durationMinutes = allDay ? 1440 : 60

  var title = tidy(rest)
  // "meeting with sarah" reads better than "With sarah": when the remainder
  // opens with a preposition, the trigger word was part of the name.
  var noun = tableGet(EVENT_NOUNS, triggerWord)
  if (noun && /^(with|w\/|re|about|für|fuer)\b/i.test(title))
    title = noun + " " + title
  title = titleCase(title)
  // "meeting 25 sep" is all date and no title; the trigger word is the title.
  if (!title && triggerMatch) title = noun || "Event"
  if (!title) return null

  return {
    title: title,
    start: start,
    end: new Date(start.getTime() + durationMinutes * 60000),
    durationMinutes: durationMinutes,
    allDay: allDay,
    label: when ? when.label : labelFor(start, now, false)
  }
}

function pad(n) { return ("0" + n).slice(-2) }

// Google Calendar and iCalendar both take UTC basic format.
function toUtcBasic(d) {
  return d.getUTCFullYear() + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate())
    + "T" + pad(d.getUTCHours()) + pad(d.getUTCMinutes()) + pad(d.getUTCSeconds()) + "Z"
}

// An all-day event is a date, not an instant: 25 March is 20260325 in the
// user's own calendar, and UTC would shift it a day for half the planet.
function toDateBasic(d) {
  return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate())
}

function formatDuration(minutes) {
  var m = Math.max(1, Math.round(minutes))
  if (m < 60) return m + " min"
  var h = Math.floor(m / 60)
  var rest = m % 60
  if (m < 1440) return rest ? h + "h " + rest + "m" : h + "h"
  var d = Math.floor(m / 1440)
  var hRest = Math.floor((m % 1440) / 60)
  return hRest ? d + "d " + hRest + "h" : d + "d"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseWhen: parseWhen,
    parseReminder: parseReminder, isReminderQuery: isReminderQuery,
    parseEvent: parseEvent, isEventQuery: isEventQuery,
    toUtcBasic: toUtcBasic, toDateBasic: toDateBasic,
    formatDuration: formatDuration
  }
}
