// Offline unit conversion: "10 km to miles", "72f in c", "5 GiB to MB".
// Every family converts through one base unit; temperature is the exception
// and carries explicit to/from-base functions instead of a factor.

var FAMILIES = [
  {
    name: "length", base: "m",
    units: {
      m: 1, meter: 1, meters: 1, metre: 1, metres: 1,
      km: 1000, kilometer: 1000, kilometers: 1000, kilometre: 1000, kilometres: 1000,
      dm: 0.1, cm: 0.01, centimeter: 0.01, centimeters: 0.01,
      mm: 0.001, millimeter: 0.001, millimeters: 0.001,
      um: 1e-6, micron: 1e-6, nm: 1e-9,
      mi: 1609.344, mile: 1609.344, miles: 1609.344,
      yd: 0.9144, yard: 0.9144, yards: 0.9144,
      ft: 0.3048, foot: 0.3048, feet: 0.3048,
      in: 0.0254, inch: 0.0254, inches: 0.0254,
      nmi: 1852, ly: 9.4607304725808e15, au: 1.495978707e11
    }
  },
  {
    name: "mass", base: "kg",
    units: {
      kg: 1, kilo: 1, kilos: 1, kilogram: 1, kilograms: 1,
      g: 0.001, gram: 0.001, grams: 0.001,
      mg: 1e-6, ug: 1e-9,
      t: 1000, tonne: 1000, tonnes: 1000, ton: 1000,
      lb: 0.45359237, lbs: 0.45359237, pound: 0.45359237, pounds: 0.45359237,
      oz: 0.028349523125, ounce: 0.028349523125, ounces: 0.028349523125,
      st: 6.35029318, stone: 6.35029318
    }
  },
  {
    name: "data", base: "byte",
    units: {
      b: 1, byte: 1, bytes: 1,
      bit: 0.125, bits: 0.125,
      kb: 1e3, mb: 1e6, gb: 1e9, tb: 1e12, pb: 1e15,
      kib: 1024, mib: 1048576, gib: 1073741824, tib: 1099511627776, pib: 1125899906842624,
      kbit: 125, mbit: 125000, gbit: 125000000
    }
  },
  {
    name: "duration", base: "s",
    units: {
      ms: 0.001, s: 1, sec: 1, secs: 1, second: 1, seconds: 1,
      min: 60, mins: 60, minute: 60, minutes: 60,
      h: 3600, hr: 3600, hrs: 3600, hour: 3600, hours: 3600,
      d: 86400, day: 86400, days: 86400,
      week: 604800, weeks: 604800,
      month: 2629800, months: 2629800,
      year: 31557600, years: 31557600
    }
  },
  {
    name: "speed", base: "m/s",
    units: {
      "m/s": 1, mps: 1,
      "km/h": 0.2777777777777778, kmh: 0.2777777777777778, kph: 0.2777777777777778,
      mph: 0.44704, "mi/h": 0.44704,
      kn: 0.5144444444444445, knot: 0.5144444444444445, knots: 0.5144444444444445,
      "ft/s": 0.3048
    }
  },
  {
    name: "volume", base: "l",
    units: {
      l: 1, liter: 1, liters: 1, litre: 1, litres: 1,
      ml: 0.001, cl: 0.01, dl: 0.1,
      m3: 1000, cm3: 0.001,
      gal: 3.785411784, gallon: 3.785411784, gallons: 3.785411784,
      qt: 0.946352946, quart: 0.946352946, quarts: 0.946352946,
      pt: 0.473176473, pint: 0.473176473, pints: 0.473176473,
      cup: 0.2365882365, cups: 0.2365882365,
      floz: 0.0295735295625, "fl-oz": 0.0295735295625
    }
  },
  {
    name: "area", base: "m2",
    units: {
      m2: 1, sqm: 1, km2: 1e6, sqkm: 1e6, cm2: 1e-4,
      ha: 10000, hectare: 10000, hectares: 10000,
      acre: 4046.8564224, acres: 4046.8564224,
      sqft: 0.09290304, ft2: 0.09290304,
      sqmi: 2589988.110336, mi2: 2589988.110336
    }
  },
  {
    name: "temperature", base: "k",
    temperature: true,
    units: {
      c: { to: function(v) { return v + 273.15 },        from: function(k) { return k - 273.15 } },
      celsius: { to: function(v) { return v + 273.15 },  from: function(k) { return k - 273.15 } },
      f: { to: function(v) { return (v - 32) * 5 / 9 + 273.15 }, from: function(k) { return (k - 273.15) * 9 / 5 + 32 } },
      fahrenheit: { to: function(v) { return (v - 32) * 5 / 9 + 273.15 }, from: function(k) { return (k - 273.15) * 9 / 5 + 32 } },
      k: { to: function(v) { return v }, from: function(k) { return k } },
      kelvin: { to: function(v) { return v }, from: function(k) { return k } }
    }
  }
]

// Canonical spelling for the result line, so "10 km to miles" answers in "mi".
var DISPLAY = {
  meter: "m", meters: "m", metre: "m", metres: "m",
  kilometer: "km", kilometers: "km", kilometre: "km", kilometres: "km",
  centimeter: "cm", centimeters: "cm", millimeter: "mm", millimeters: "mm",
  mile: "mi", miles: "mi", yard: "yd", yards: "yd",
  foot: "ft", feet: "ft", inch: "in", inches: "in",
  kilo: "kg", kilos: "kg", kilogram: "kg", kilograms: "kg",
  gram: "g", grams: "g", tonne: "t", tonnes: "t", ton: "t",
  lbs: "lb", pound: "lb", pounds: "lb", ounce: "oz", ounces: "oz",
  stone: "st", byte: "B", bytes: "B", b: "B",
  bit: "bit", bits: "bit",
  kb: "kB", mb: "MB", gb: "GB", tb: "TB", pb: "PB",
  kib: "KiB", mib: "MiB", gib: "GiB", tib: "TiB", pib: "PiB",
  sec: "s", secs: "s", second: "s", seconds: "s",
  mins: "min", minute: "min", minutes: "min",
  hr: "h", hrs: "h", hour: "h", hours: "h",
  day: "d", days: "d", weeks: "week", months: "month", years: "year",
  mps: "m/s", kmh: "km/h", kph: "km/h", knot: "kn", knots: "kn",
  liter: "l", liters: "l", litre: "l", litres: "l",
  gallon: "gal", gallons: "gal", quart: "qt", quarts: "qt",
  pint: "pt", pints: "pt", cups: "cup", "fl-oz": "fl oz", floz: "fl oz",
  celsius: "°C", c: "°C", fahrenheit: "°F", f: "°F", kelvin: "K", k: "K",
  hectare: "ha", hectares: "ha", acres: "acre",
  sqm: "m²", m2: "m²", km2: "km²", sqkm: "km²", cm2: "cm²",
  sqft: "ft²", ft2: "ft²", sqmi: "mi²", mi2: "mi²", m3: "m³", cm3: "cm³"
}

// Unit names come straight out of the query, so the tables are consulted only
// for keys they own — otherwise "1 constructor to m" finds an inherited
// function where a conversion should be.
var owned = Object.prototype.hasOwnProperty

function unitEntry(family, unit) {
  return owned.call(family.units, unit) ? family.units[unit] : undefined
}

function findFamily(unit) {
  for (var i = 0; i < FAMILIES.length; i++) {
    if (unitEntry(FAMILIES[i], unit) !== undefined) return FAMILIES[i]
  }
  return null
}

function display(unit) {
  return owned.call(DISPLAY, unit) ? DISPLAY[unit] : unit
}

function formatNumber(n) {
  if (!isFinite(n)) return ""
  var abs = Math.abs(n)
  if (abs > 0 && abs < 0.000001) return String(Number(n.toPrecision(6)))
  var digits = abs >= 100 ? 2 : (abs >= 1 ? 4 : 6)
  var rounded = Number(n.toFixed(digits))
  var parts = String(rounded).split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ")
  return parts.join(".")
}

// The units a conversion is also shown in, beside the answer. Each list runs
// from the most to the least everyday; related() skips the two already on
// screen and any value too large or too small to read at a glance.
var RELATED = {
  length: ["m", "km", "cm", "mm", "mi", "yd", "ft", "in"],
  mass: ["kg", "g", "lb", "oz", "st", "t"],
  data: ["b", "kb", "mb", "gb", "tb", "kib", "mib", "gib", "bit"],
  duration: ["s", "min", "h", "d", "week", "ms"],
  speed: ["km/h", "m/s", "mph", "kn", "ft/s"],
  volume: ["l", "ml", "gal", "qt", "pt", "cup", "floz"],
  area: ["m2", "km2", "ha", "acre", "sqft", "sqmi"],
  temperature: ["c", "f", "k"]
}

// A conversion from convert() -> up to `limit` lines of { text }.
function related(conversion, limit) {
  if (!conversion || !owned.call(RELATED, conversion.family)) return []
  var family = null
  for (var i = 0; i < FAMILIES.length; i++) if (FAMILIES[i].name === conversion.family) family = FAMILIES[i]
  var shown = [display(conversion.from), display(conversion.to)]
  var out = []
  var keys = RELATED[conversion.family]
  for (var j = 0; j < keys.length && out.length < (limit || 5); j++) {
    var unit = unitEntry(family, keys[j])
    var label = display(keys[j])
    if (unit === undefined || shown.indexOf(label) >= 0) continue
    var value = family.temperature ? unit.from(conversion.base) : conversion.base / unit
    var abs = Math.abs(value)
    if (!isFinite(value) || (!family.temperature && abs !== 0 && (abs < 0.01 || abs >= 1e6))) continue
    out.push({ text: formatNumber(value) + " " + label })
  }
  return out
}

// "10 km to mi" / "72f in c" / "5 gib -> mb"  ->  { text, value } or null
function convert(src) {
  var s = String(src || "").trim().toLowerCase()
  if (!s) return null

  var m = s.match(/^(-?\d+(?:[.,]\d+)?)\s*([a-z°µ][a-z0-9°µ/²³-]*)\s*(?:to|in|as|->|→|=)\s*([a-z°µ][a-z0-9°µ/²³-]*)$/)
  if (!m) return null

  var amount = Number(m[1].replace(",", "."))
  if (!isFinite(amount)) return null

  var from = m[2].replace(/^°/, "").replace(/²/, "2").replace(/³/, "3").replace(/µ/, "u")
  var to = m[3].replace(/^°/, "").replace(/²/, "2").replace(/³/, "3").replace(/µ/, "u")

  var fromFamily = findFamily(from)
  var toFamily = findFamily(to)
  if (!fromFamily || !toFamily || fromFamily !== toFamily) return null

  var fromUnit = unitEntry(fromFamily, from)
  var toUnit = unitEntry(toFamily, to)
  var base = fromFamily.temperature ? fromUnit.to(amount) : amount * fromUnit
  var out = fromFamily.temperature ? toUnit.from(base) : base / toUnit
  if (!isFinite(out)) return null

  return {
    value: out,
    text: formatNumber(out) + " " + display(to),
    detail: formatNumber(amount) + " " + display(from) + " = " + formatNumber(out) + " " + display(to),
    family: fromFamily.name,
    base: base, from: from, to: to
  }
}
