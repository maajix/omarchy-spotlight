---
title: Update and remove
description: Keep Spotlight current, or take it off cleanly.
weight: 80
---

## Update

```bash
omarchy plugin update io.github.maajix.spotlight
```

Restart `omarchy-shell` afterwards if the update changed QML files, because the plugin stays loaded inside the shell.

## Remove

```bash
omarchy plugin remove io.github.maajix.spotlight
```

The setup tour can remove the shortcut it created before you uninstall: search for `spotlight settings` and choose the shortcut action. If you configured Spotlight manually, also remove its `o.bind(...)` entry from `~/.config/hypr/bindings.lua` and its layer rule from `~/.config/hypr/looknfeel.lua`, then run `hyprctl reload`.

Optional settings and learning data are left in place so reinstalling restores them. Delete them for a completely clean removal:

```bash
rm -f ~/.config/omarchy/spotlight.json
rm -f ~/.local/state/omarchy/spotlight-usage.json
```
