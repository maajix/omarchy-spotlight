// ponytail: keyword matching can miss unusual weather phrasing; the AI asks
// for a place then. Add intent classification only if real prompts demand it.
function isWeather(text) {
  var query = String(text || "").replace(/\b(?:wetter|weather|regen|rain)\.[a-z0-9]{1,8}\b/gi, "")
  return /(?:^|[^A-Za-zÀ-ÖØ-öø-ÿ])(?:wetter|weather|regen|regnet|regnen|rain|raining|vorhersage|forecast|temperatur|temperature|schnee|snow|sonnig|sunny|wind|wärme|kälte)(?=$|[^A-Za-zÀ-ÖØ-öø-ÿ])/i.test(query)
}

if (typeof module !== "undefined") module.exports = { isWeather: isWeather }
