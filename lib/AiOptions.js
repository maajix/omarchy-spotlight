function models(catalogs, provider) {
  var entries = catalogs && catalogs[provider] || []
  return [{ value: "", label: "CLI default" }].concat(entries.map(function(item) {
    return { value: item.id, label: item.name }
  }))
}

function efforts(catalogs, provider, model) {
  var entries = catalogs && catalogs[provider] || []
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].id === model)
      return [{ value: "", label: "Model default" }].concat(entries[i].efforts.map(function(level) {
        return { value: level, label: level.charAt(0).toUpperCase() + level.slice(1) }
      }))
  }
  return [{ value: "", label: "Model default" }]
}

if (typeof module !== "undefined") module.exports = { models: models, efforts: efforts }
