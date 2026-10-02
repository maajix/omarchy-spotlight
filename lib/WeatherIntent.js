// ponytail: keyword matching can miss unusual weather phrasing; the AI asks
// for a place then. Add intent classification only if real prompts demand it.
function isWeather(text) {
  var query = String(text || "").replace(/\b(?:wetter|weather|regen|rain)\.[a-z0-9]{1,8}\b/gi, "")
  var explicit = /(?:^|[^A-Za-zÀ-ÖØ-öø-ÿ])(?:wetter|weather|regen|regnet|regnen|rain|raining|schnee|snow|sonnig|sunny)(?=$|[^A-Za-zÀ-ÖØ-öø-ÿ])/i.test(query)
  if (explicit) return true
  if (/\b(?:llms?|sampling|parameters?|models?|arima|cpu|gpu|sales|stocks?|finance)\b/i.test(query)) return false
  // ponytail: ambiguous terms need a place/time cue; unusual phrasing stays general.
  return /^(?:(?:what(?:'s| is)|how is|show(?: me)?|wie ist|zeig(?: mir)?)\s+)?(?:(?:the|die|der)\s+)?(?:temperature|temperatur|forecast|vorhersage|wind)(?:\s+(?:in|for|für|at)\s+[^?]+|\s+(?:today|tomorrow|tonight|outside|here|heute|morgen|draußen|hier))[?.!]*$/i.test(query.trim())
}

if (typeof module !== "undefined") module.exports = { isWeather: isWeather }
