function split(value) {
  var parts = [], cursor = 0, match
  value = String(value || "").replace(/\r\n/g, "\n")

  function prose(source) {
    source = source.trim()
    if (!source) return
    source = source.replace(/([^\n])\n(?=#{1,6}[ \t])/g, "$1\n\n")
      .replace(/(^#{1,6}[^\n]*)\n(?=\S)/gm, "$1\n\n")
    source.split(/\n[ \t]*\n+/).forEach(function(block) {
      if (block.trim()) parts.push({ type: "markdown", text: block.trim() })
    })
  }

  var fence = /^```([^\n]*)\n([\s\S]*?)\n```[ \t]*(?=\n|$)/gm
  while ((match = fence.exec(value)) !== null) {
    prose(value.slice(cursor, match.index))
    parts.push({ type: "code", language: match[1].trim() || "code", text: match[2] })
    cursor = fence.lastIndex
  }
  prose(value.slice(cursor))
  return parts
}

function highlightInlineCode(value) {
  function brightLinks(source) {
    return source.replace(/\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)/g, function(_, label, url) {
      var safeLabel = label.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      url = url.replace(/&#33;/g, "!")
      var safeUrl = url.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;")
      return '<a href="' + safeUrl + '" style="color:#a6d2ff; text-decoration:underline">'
        + safeLabel + '</a>'
    })
  }
  var heading = /^#{1,6}[ \t]/.test(value) || /\n(?:=+|-+)[ \t]*$/.test(value)
  // Escape provider HTML and every image opener, including reference images.
  // Entities render as text; they cannot become Markdown image delimiters.
  return String(value).split(/(`[^`\n]+`)/g).map(function(part, index) {
    if (index % 2) {
      var code = part.slice(1, -1)
      if (heading) return code.replace(/[\\`*_\[\]<>!]/g, "\\$&")
      return '<span style="color:#a6d2ff">' + code.replace(/&/g, "&amp;")
        .replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/!/g, "&#33;") + '</span>'
    }
    return brightLinks(part.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/!/g, "&#33;"))
  }).join("")
}

if (typeof module !== "undefined") module.exports = { split: split, highlightInlineCode: highlightInlineCode }
