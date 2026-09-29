const assert = require("node:assert/strict")
const test = require("node:test")
const WeatherIntent = require("../lib/WeatherIntent.js")

test("the saved weather location is used only for weather questions", () => {
  for (const query of ["What's the weather?", "Will it rain tomorrow?", "weather in Berlin", "rain forecast"])
    assert.equal(WeatherIntent.isWeather(query), true)
  for (const query of ["How do I install scp?", "find weather.png", "map of Tokyo"])
    assert.equal(WeatherIntent.isWeather(query), false)
})
