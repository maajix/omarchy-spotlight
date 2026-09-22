# Spotlight

**A fast, local-first command palette for Omarchy.**

Launch apps, jump to open windows, find files, search your clipboard, run Omarchy commands, calculate, convert units, create reminders and calendar events, or search the web, all from one input.

[View Spotlight in the Omarchy Plugin Marketplace](https://plugins.omarchy.org/plugin.html?id=io.github.maajix.spotlight)

![Spotlight showing mixed local search results](preview.png)

## Install

```bash
omarchy plugin add https://github.com/maajix/omarchy-spotlight.git --enable
```

Press `Alt+Space` to open Spotlight.

That shortcut is set up on install: it is unbound on stock Omarchy, so Spotlight claims it on first run by writing one marked block to `~/.config/hypr/bindings.lua` and reloading Hyprland. If something on your system already holds `Alt+Space`, Spotlight leaves it alone and the first-run tour asks you to pick another one. The tour can change the shortcut at any time and can undo its own changes.

If the shortcut does not work, open Spotlight from a terminal instead:

```bash
omarchy-shell shell toggle io.github.maajix.spotlight '{}'
```

<details>
<summary>Set the shortcut manually</summary>

Add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("ALT + SPACE", "Spotlight", "omarchy-shell shell toggle io.github.maajix.spotlight '{}'")
```

Then reload Hyprland:

```bash
hyprctl reload
```

Older Spotlight versions recommended `Ctrl+Space`, which conflicts with fcitx5 on fresh Omarchy installations.

</details>

## Try it

From two characters onward, Spotlight searches enabled local providers together and ranks their results in one list.

| Type | Result |
| --- | --- |
| `chrom` | Applications, open windows, files, and other local matches |
| `screenshot` | Omarchy and system actions |
| `bluetooth` | Show its live state; Enter flips the switch without closing Spotlight |
| `wifi` | The same for Wi-Fi, night light, mute, Do Not Disturb, and other settings |
| `12*7+3` | Calculate; Enter copies the result |
| `20% of 250` | Calculate percentages |
| `10 km to miles` | Convert units offline |
| `remind me in 20m to check the oven` | Create an `omarchy reminder` |
| `reminders` | Show or clear pending reminders |
| `meeting with sarah tomorrow at 14:00 for 90min` | Open a calendar event; Shift+Enter creates an `.ics` file |
| `f invoice` | Search files and folders |
| `~/Downloads/` | Search within a path |
| `cb ssh` | Search clipboard history; Enter copies the full item |
| `man ssh` or `tldr ssh` | Show tldr examples for a command, each under its description; Enter copies one, Shift+Enter opens it in a terminal without running it |
| `gh quickshell` | Search GitHub |
| `tr what is this to german` | Translate into the named language |
| `example.com` | Open a URL directly |
| Anything else | Offer a web search |

Spotlight runs inside the existing `omarchy-shell` process, so there is no separate launcher or cold start. Late file and web results also cannot steal the current selection while you type.

## Features

- Unified search across apps, windows, actions, files, clipboard history, and the web
- Live toggle switches for common system settings
- Offline calculations, percentages, common math functions, and unit conversions
- Natural-language reminders and calendar events
- Bang searches for common sites and package registries
- Keyboard-first navigation with a stable selection as results arrive
- Optional local learning based on recency, frequency, and query context
- Theme-aware UI with an optional frosted-glass effect
- Confirmation before logout, restart, or shutdown
- No telemetry or analytics

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `↑` `↓` or `Ctrl+P` `Ctrl+N` | Move through results |
| `PageUp` `PageDown` | Move one screen |
| `Enter` | Run the primary action shown in the footer |
| `Shift+Enter` or `Ctrl+Enter` | Run the secondary action, when available |
| `Tab` | Complete the query with the selected app name |
| `Esc` | Clear the query; close Spotlight when already empty |

The search field is a normal text input, so selection, caret movement, and shortcuts such as `Ctrl+V` work as expected.

Settings that are on or off show their live state instead of a generic action label. This covers Bluetooth, Wi-Fi, night light, speaker and microphone mute, Do Not Disturb, Stay Awake, the status bar, the battery percentage, touchpad and touchscreen, window gaps, the square aspect ratio, the screensaver, crash capture, and suspend in the system menu. Window transparency, tiled fullscreen, and the workspace layout show a switch too, read from the focused window or the active workspace rather than from a global setting. `Enter` or a click flips the switch while Spotlight stays open. If a state cannot be read, Spotlight shows no switch rather than guessing.

## Search syntax

Most of the time, just type. Use a filter when you want results from one provider only:

| Filter | Provider |
| --- | --- |
| `a:` or `app:` | Applications |
| `w:` or `window:` | Open windows |
| `f:` or `file:` | Files and folders |
| `action:` or `cmd:` | Omarchy and system actions |
| `cb:` or `clipboard:` | Clipboard history |
| `web:`, `search:`, or `url:` | Web |
| `calc:` | Calculator |
| `unit:` or `convert:` | Unit converter |
| `reminder:` | Reminders |
| `calendar:` or `event:` | Calendar events |
| `man:` or `tldr:` | Command help from tldr pages |

A filter without a query shows a hint instead of launching a broad search.

Bang prefixes send the query directly to a destination:

```text
g       Google             ddg     DuckDuckGo
kagi    Kagi
yt      YouTube            gh      GitHub
w       Wikipedia          wde     German Wikipedia
aw      ArchWiki           aur     AUR
pkg     Arch packages      so      Stack Overflow
mdn     MDN                npm     npm
crates  crates.io          docker  Docker Hub
maps    Maps               tr      Translate
img     Images             hn      Hacker News
omarchy Omarchy
```

The space-separated `w query` is the Wikipedia bang; `w:` is the window filter. Translation accepts a language name or code at the end, such as `to german`, `in de`, or `into pt-br`.

<details>
<summary>Open Spotlight with a query already filled in</summary>

The IPC payload accepts a query, so a shortcut can open a specific workflow:

```lua
o.bind("ALT + SHIFT + SPACE", "Spotlight reminder",
  "omarchy-shell shell toggle io.github.maajix.spotlight '{\"query\":\"remind me \"}'")
```

</details>

## Settings

Spotlight works without a configuration file. Optional settings live at `~/.config/omarchy/spotlight.json` and are re-read every time Spotlight opens:

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

Search for `spotlight settings` to create or edit the file, open Spotlight's data directory, reset learning, rerun the setup tour, or change the shortcut. Creating the settings file never overwrites an existing one.

`searchEngine` accepts any supported bang key. The numeric limits are validated before use:

```text
maxApps          3–24
maxSuggestions   0–8
maxResults        8–50
```

With the `Always` options enabled, file and clipboard results join mixed searches from two characters onward. Set the provider option itself to `false` to disable it completely.

### Optional frosted glass

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

## Privacy and security

Spotlight has no telemetry, analytics, or background network service. Almost everything happens locally.

| Network access | When it happens |
| --- | --- |
| `kagi.com/api/autosuggest` | While typing, only when `webSuggestions` is enabled and `searchEngine` is `kagi` |
| `suggestqueries.google.com` | While typing, only when `webSuggestions` is enabled with any other search engine |
| Your browser | After you activate a web search, URL, or calendar result |
| tldr-pages (GitHub) | First lookup of a command not yet in `~/.cache/tldr`, via the `tldr` client |

Live web suggestions are disabled by default. Normal web searches do not send the query anywhere until you activate the result.

Learning is optional and stays in `~/.local/state/omarchy/spotlight-usage.json`. It stores bounded selection counts, timestamps, stable IDs, file paths, and normalized query prefixes. Disable it with `"learningEnabled": false`, or remove it with **Reset Spotlight Learning**.

The helper bounds file and subprocess output, validates persistent files and ownership, rejects symlinks, uses private atomic writes, applies subprocess deadlines, and cleans up process groups. Clipboard previews sent to the shell are bounded to one line; the full selected value goes directly from the helper to `wl-copy`.

## Requirements

Spotlight targets **Omarchy 4 (Quattro)** and only uses components included with stock Omarchy:

| Package | Used for |
| --- | --- |
| `python3` | File and subprocess helper |
| `fd` | File search |
| `wl-clipboard` | Clipboard actions |
| `tldr` | Command help pages |

## Update and remove

Update through Omarchy:

```bash
omarchy plugin update io.github.maajix.spotlight
```

Remove the plugin:

```bash
omarchy plugin remove io.github.maajix.spotlight
```

The setup tour can remove the shortcut it created before you uninstall. If you configured Spotlight manually, also remove its `o.bind(...)` entry from `~/.config/hypr/bindings.lua` and its layer rule from `~/.config/hypr/looknfeel.lua`, then run `hyprctl reload`.

Optional settings and learning data are left in place so reinstalling restores them. Delete them for a completely clean removal:

```bash
rm -f ~/.config/omarchy/spotlight.json
rm -f ~/.local/state/omarchy/spotlight-usage.json
```

## Development

```text
Spotlight.qml          UI and actions
SetupTour.qml          first-run shortcut setup
PillSwitch.qml         live toggle control
lib/                   parsers and ranking logic
bin/spotlight-helper   bounded interface to files and subprocesses
tests/                 JavaScript and Python checks
```

Useful checks before committing:

```bash
omarchy plugin validate .
python3 -m unittest discover -s tests -p '*_test.py'
for file in tests/*.test.js; do node "$file"; done
python3 -m py_compile bin/spotlight-helper
/usr/lib/qt6/bin/qmlformat -n Spotlight.qml SetupTour.qml PillSwitch.qml >/dev/null
for file in lib/*.js; do node --check "$file"; done
```

Restart `omarchy-shell` after changing QML because the plugin stays loaded inside the shell.

## License

MIT, see [LICENSE](LICENSE).

Spotlight is not affiliated with Apple or Raycast.
