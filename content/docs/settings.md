---
title: Settings
description: The optional settings file, its valid ranges, and the frosted-glass layer rule.
weight: 60
---

Spotlight works without a configuration file. Optional settings live at `~/.config/omarchy/spotlight.json` and are re-read every time Spotlight opens.

Search for `spotlight settings` to create or edit the file, open Spotlight's data directory, reset learning, rerun the setup tour, or change the shortcut. Creating the settings file never overwrites an existing one.

## The settings file

```json
{
  "webSuggestions": false,
  "searchEngine": "g",
  "fileSearch": true,
  "fileSearchAlways": true,
  "clipboardSearch": true,
  "clipboardSearchAlways": true,
  "learningEnabled": true,
  "maxResults": 20,
  "maxApps": 8,
  "maxSuggestions": 4,
  "setupCompleted": true
}
```

| Key | Meaning |
| --- | --- |
| `webSuggestions` | Fetch live suggestions from Google while typing. Off by default. |
| `searchEngine` | The bang key used for plain web searches. Any supported bang works. |
| `fileSearch` | Enable the file provider at all. |
| `fileSearchAlways` | Include files in mixed searches from two characters onward. With this off, use `f:` or a path. |
| `clipboardSearch` | Enable the clipboard provider at all. |
| `clipboardSearchAlways` | Include clipboard history in mixed searches. With this off, use `cb:`. |
| `learningEnabled` | Rank by recency, frequency and query context. Stored locally. |
| `maxResults` | Total rows shown. |
| `maxApps` | Application rows shown. |
| `maxSuggestions` | Web suggestion rows shown. |
| `setupCompleted` | Set by the tour. Delete it to see the tour again, or rerun it from `spotlight settings`. |

The numeric limits are validated before use:

```text
maxApps          3–24
maxSuggestions   0–8
maxResults       8–50
```

With the `Always` options enabled, file and clipboard results join mixed searches from two characters onward. Set the provider option itself to `false` to disable it completely.

## Optional frosted glass

Spotlight is translucent by default. For background blur, enable Hyprland blur and add a layer rule in `~/.config/hypr/looknfeel.lua`:

```lua
hl.config({
  decoration = {
    blur = {
      enabled = true,
      size = 8,
      passes = 3,
      brightness = 0.8,
      contrast = 0.9,
      new_optimizations = true
    },
  },
})

hl.layer_rule({
  match = { namespace = "omarchy-spotlight" },
  blur = true,
  ignore_alpha = 0.4,
})
```

Keep `ignore_alpha`: Spotlight uses a fullscreen surface, and the threshold limits blur to the card. Reload with `hyprctl reload`.

## Theme

Spotlight reads the active Omarchy theme, so colors follow whatever you pick in the theme switcher. There is nothing to configure.
