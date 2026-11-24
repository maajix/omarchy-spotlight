# Spotlight

**A fast, local-first command palette for Omarchy.**

Launch apps, switch windows, find files, search your clipboard and control your desktop from one input. Calculate, convert currencies, create reminders, search the web or ask AI without leaving Spotlight.

[Website](https://maajix.github.io/omarchy-spotlight/) · [Documentation](https://maajix.github.io/omarchy-spotlight/docs/) · [Plugin marketplace](https://plugins.omarchy.org/plugin.html?id=io.github.maajix.spotlight)

![Spotlight showing mixed local search results](preview.png)

## Install

Requires **Omarchy 4 (Quattro)**. Core features use tools already included with Omarchy.

```bash
omarchy plugin add https://github.com/maajix/omarchy-spotlight.git --enable
```

On first run, Spotlight sets up **Alt+Space** when Hyprland reports that it is free and Spotlight has no shortcut yet. The setup tour appears on first open and lets you pick a different shortcut. Search for `spotlight settings` to change sources, behavior or the shortcut later.

Settings are grouped into **General** (shortcut and data), **Search** (sources, results, web and currency), **Appearance**, and **AI** (provider and artifact settings, including weather location).

Under **Appearance**, **Vertical position** moves the launcher from 0% (top) to 100% (bottom). **Horizontal position** moves it from 0% (left) to 100% (right). Both default to 50%. The search field stays in place as results arrive, and screen margins keep the launcher visible.

If the shortcut does not open Spotlight:

```bash
omarchy-shell shell toggle io.github.maajix.spotlight '{}'
```

## Try it

| Type | What happens |
| --- | --- |
| `chrom` | Find apps, windows and matching local results |
| `f invoice` or `cb ssh` | Search files or clipboard history |
| `night light` | Show a live toggle and switch it in place |
| `12*7+3` or `100 USD to EUR` | Calculate or convert currencies |
| `remind me in 20m to check the oven` | Create a reminder |
| `ports:` or `ssh:` | Browse a system view |
| `gh quickshell` | Search GitHub |
| `action: change theme` | Find Omarchy's theme picker. Search for **Change Background** or **Change Font** to open those pickers. |
| A Spotify Jam invite link | Choose **Open Spotify Jam** to join in the desktop app. [Supported links](https://maajix.github.io/omarchy-spotlight/docs/?p=web-search#spotify-jam) |
| `ai: explain how DNS works` | Ask AI for an answer, with a visual card when available |

Use **↑ / ↓** to select a result, **Enter** for its main action and **Shift+Enter** for its secondary action. **Esc** clears the query, then closes Spotlight.

A preview pane beside the list shows more about the selected result, such as other currencies, the start of a file or a live window thumbnail. It appears when there is enough room and Ask AI is closed. Use **Preview pane** under **Appearance** in Spotlight Settings to control it. [Preview pane and requirements](https://maajix.github.io/omarchy-spotlight/docs/?p=how-search-works#preview-pane)

After moving to a folder result with **↑ / ↓**, press **→** to move the selection into its right-hand preview. The search results on the left stay in place. Use **↑ / ↓** to select entries and **←** to return one folder level, or back to the left-hand results. **Enter** opens the selected entry externally; **Tab** completes a folder name. Typing starts a new search, and **Esc** returns from browsing to the original search. The current folder path appears above the right-hand entries; listings are limited to 1,000 entries.

## Ask AI

Enable **Ask AI** in Spotlight Settings and choose an installed, signed-in **Claude or Codex CLI**. Submit questions with `ai:` and Enter. Answers can include copyable code and commands, maps, weather, charts, palettes, timelines and other visual cards. Requests stay available when you close and reopen Spotlight. Clearing the search discards the saved AI session and cancels any pending answer.

AI and AI web search are opt-in. Generated commands are shown for you to review and copy. [AI setup and usage](https://maajix.github.io/omarchy-spotlight/docs/?p=ask-ai) · [All twelve artifact types](https://maajix.github.io/omarchy-spotlight/docs/?p=ai-artifacts)

## Documentation

The website holds the full reference:

- [Quickstart](https://maajix.github.io/omarchy-spotlight/docs/?p=quickstart), [search syntax](https://maajix.github.io/omarchy-spotlight/docs/?p=search-syntax) and [keyboard shortcuts](https://maajix.github.io/omarchy-spotlight/docs/?p=keyboard-shortcuts)
- [Settings](https://maajix.github.io/omarchy-spotlight/docs/?p=settings) and [settings reference](https://maajix.github.io/omarchy-spotlight/docs/?p=settings-reference)
- [Update and remove](https://maajix.github.io/omarchy-spotlight/docs/?p=installation#update), [troubleshooting](https://maajix.github.io/omarchy-spotlight/docs/?p=troubleshooting) and [changelog](https://maajix.github.io/omarchy-spotlight/docs/?p=changelog)
- [Development guide](https://maajix.github.io/omarchy-spotlight/docs/?p=development), [test commands](tests/README.md) and [artifact contributions](docs/artifacts.md)

Spotlight runs inside `omarchy-shell` with no separate launcher process. Ordinary search and ranking stay local; the plugin has no telemetry or analytics. [Privacy and security](https://maajix.github.io/omarchy-spotlight/docs/?p=privacy-security) explains network access and local storage. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

MIT, see [LICENSE](LICENSE). Spotlight is not affiliated with Apple or Raycast.
