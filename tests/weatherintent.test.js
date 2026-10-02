const assert = require("node:assert/strict")
const test = require("node:test")
const WeatherIntent = require("../lib/WeatherIntent.js")

test("the saved weather location is used only for weather questions", () => {
  for (const query of ["What's the weather?", "Will it rain tomorrow?", "weather in Berlin", "rain forecast"])
    assert.equal(WeatherIntent.isWeather(query), true)
  for (const query of ["How do I install scp?", "find weather.png", "map of Tokyo"])
    assert.equal(WeatherIntent.isWeather(query), false)
})

test("ambiguous technical terms do not select the weather contract", () => {
  for (const query of ["what is the temperature parameter in LLM sampling?",
    "forecast accuracy for ARIMA models", "forecast for ARIMA models", "temperature in LLM sampling", "temperature", "forecast", "explain wind turbines",
    "CPU temperature in Linux", "sales forecast for tomorrow", "what is the temperature of a GPU?"])
    assert.equal(WeatherIntent.isWeather(query), false, query)
  for (const query of ["temperature in Berlin", "forecast tomorrow", "What is the temperature outside?",
    "Temperatur heute", "Wie ist die Temperatur in Berlin?"])
    assert.equal(WeatherIntent.isWeather(query), true, query)
})

test("rain instruments and programming questions stay general", () => {
  for (const query of ["rain gauge arduino code", "how does a rain gauge work?",
    "write a script for a rain sensor", "build a weather API", "Arduino rain forecast display"])
    assert.equal(WeatherIntent.isWeather(query), false, query)
  for (const query of ["Will it rain tomorrow?", "rain in Berlin", "rain forecast",
    "Is it raining outside?", "Regnet es morgen?", "weather in Berlin"])
    assert.equal(WeatherIntent.isWeather(query), true, query)
})
