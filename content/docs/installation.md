---
title: Installation
description: Add the plugin, bind the shortcut, and open Spotlight for the first time.
weight: 10
---

## Requirements

Spotlight targets **Omarchy 4 (Quattro)** and only uses components included with stock Omarchy.

| Package | Used for |
| --- | --- |
| `python3` | File and subprocess helper |
| `fd` | File search |
| `wl-clipboard` | Clipboard actions |
| `tldr` | Command help pages |

## Add the plugin

```bash
omarchy plugin add https://github.com/maajix/omarchy-spotlight.git --enable
```

Spotlight is also listed in the [Omarchy plugin marketplace](https://plugins.omarchy.org/plugin.html?id=io.github.maajix.spotlight).

## Open it

Press `Alt+Space` to open Spotlight.

That shortcut is set up on install: it is unbound on stock Omarchy, so Spotlight claims it on first run by writing one marked block to `~/.config/hypr/bindings.lua` and reloading Hyprland. If something on your system already holds `Alt+Space`, Spotlight leaves it alone and the first-run tour asks you to pick another one. The tour can change the shortcut at any time and can undo its own changes. Rerun it by searching for `spotlight settings`.

If the shortcut does not work, open Spotlight from a terminal instead:

```bash
omarchy-shell shell toggle io.github.maajix.spotlight '{}'
```

### Set the shortcut manually

Add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("ALT + SPACE", "Spotlight", "omarchy-shell shell toggle io.github.maajix.spotlight '{}'")
```

Then reload Hyprland:

```bash
hyprctl reload
```

Older Spotlight versions recommended `Ctrl+Space`, which conflicts with fcitx5 on fresh Omarchy installations.

### Open Spotlight with a query already filled in

The IPC payload accepts a query, so a shortcut can open a specific workflow:

```lua
o.bind("ALT + SHIFT + SPACE", "Spotlight reminder",
  "omarchy-shell shell toggle io.github.maajix.spotlight '{\"query\":\"remind me \"}'")
```

## Where things live

| Path | Purpose |
| --- | --- |
| `~/.config/omarchy/plugins/io.github.maajix.spotlight/` | The installed plugin |
| `~/.config/omarchy/spotlight.json` | Optional settings, created on demand |
| `~/.local/state/omarchy/spotlight-usage.json` | Optional learning data |
