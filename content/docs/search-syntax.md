---
title: Search syntax
description: Provider filters, bang prefixes, and how Spotlight reads an ambiguous query.
weight: 30
---

Most of the time, just type. Spotlight decides whether a query looks like an app name, a calculation, a path, a URL or a sentence, and shows the matching providers together.

## Filters

Use a filter when you want results from one provider only:

| Filter | Provider |
| --- | --- |
| `a:` or `app:` | Applications |
| `w:` or `window:` | Open windows |
| `f:` or `file:` | Files and folders |
| `action:` or `cmd:` | Omarchy and system actions |
| `cb:` or `clipboard:` | Clipboard history |
| `web:`, `search:`, or `url:` | Web |
| `calc:` | Calculator |
| `unit:` or `convert:` | Unit and currency converter |
| `reminder:` | Reminders |
| `calendar:` or `event:` | Calendar events |
| `man:` or `tldr:` | Command help from tldr pages |
| `ports:` | Local listening TCP and UDP ports |
| `ssh:` | Saved SSH aliases and visible hosts from `~/.ssh/known_hosts` |
| `docker:` | Running and stopped Docker containers |
| `services:` | Loaded user and system services |
| `mounts:` | Mounted real filesystems |
| `audio:` | Audio outputs and inputs |
| `wifi:` | Visible Wi-Fi networks |
| `bluetooth:` | Paired Bluetooth devices |

A filter without a query shows a hint instead of launching a broad search. The views from `ports:` to `bluetooth:` are the exception: they list their entries immediately, and typing after the colon narrows the list, as in `ports:22` or `ssh:prod`. Each view holds up to 200 entries (100 for `audio:`, `wifi:` and `bluetooth:`); when there were more, the section title says "partial list".

Typing the start of a view name shows the matching views above normal results, and Tab or Enter on a selected view fills in its colon filter (`moun` becomes `mounts:`). An app still gets the first Enter when its name is exactly what you typed, or when it starts with what you typed and only one view matches, so `port` selects Portal rather than `ports:`; press the down arrow to reach the view. A view's full name, such as `bluetooth`, selects the view unless an app has exactly that name.

Short forms without the colon work for the common providers: `f invoice` searches files, `cb ssh` searches the clipboard, and `man ssh` or `tldr ssh` shows the tldr examples for a command. A path such as `~/Downloads/` searches within that folder.

## Command help

`man <command>` and `tldr <command>` show every example from the command's tldr page as a row under its description, in page order. Enter copies the selected example; Shift+Enter opens a terminal with it on the prompt, unexecuted, so you can edit it before running. Multi-word pages work too: `tldr git commit`.

## Bangs

Bang prefixes send the query directly to a destination. Type the bang, a space, then the query:

| Bang | Destination | Bang | Destination |
| --- | --- | --- | --- |
| `g`, `gg`, `google` | Google | `ddg` | DuckDuckGo |
| `yt` | YouTube | `gh` | GitHub |
| `w` | Wikipedia | `wde` | German Wikipedia |
| `aw` | Arch Wiki | `aur` | AUR |
| `pkg` | Arch packages | `so` | Stack Overflow |
| `mdn` | MDN | `npm` | npm |
| `crates` | crates.io | `docker` | Docker Hub |
| `maps` | Google Maps | `tr` | DeepL |
| `img` | Google Images | `hn` | Hacker News |
| `omarchy` | Omarchy manual | `kagi` | Kagi |

The space-separated `w query` is the Wikipedia bang; `w:` is the window filter.

Translation accepts a language name or code at the end, such as `to german`, `in de`, or `into pt-br`:

```text
tr what is this to german
```

## URLs and web search

A query that looks like a domain, such as `example.com`, opens directly. Anything that matches no local provider offers a web search with your configured engine. Set `searchEngine` in the [settings](../settings/) to any bang key to change the default.

Live web suggestions while typing are off by default. Turn them on with `webSuggestions` if you want them, and read [what that sends](../privacy-and-security/) first.
