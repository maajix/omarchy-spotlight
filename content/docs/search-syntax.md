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
| `unit:` or `convert:` | Unit converter |
| `reminder:` | Reminders |
| `calendar:` or `event:` | Calendar events |
| `man:` or `tldr:` | Command help from tldr pages |

A filter without a query shows a hint instead of launching a broad search.

Short forms without the colon work for the common providers: `f invoice` searches files, `cb ssh` searches the clipboard, and `man ssh` or `tldr ssh` shows the tldr examples for a command. A path such as `~/Downloads/` searches within that folder.

## Command help

`man <command>` and `tldr <command>` show the examples from the command's tldr page as rows, in page order. Enter copies the selected example; Shift+Enter opens a terminal with it on the prompt, unexecuted, so you can edit it before running. Multi-word pages work too: `tldr git commit`.

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
| `omarchy` | Omarchy manual | | |

The space-separated `w query` is the Wikipedia bang; `w:` is the window filter.

Translation accepts a language name or code at the end, such as `to german`, `in de`, or `into pt-br`:

```text
tr what is this to german
```

## URLs and web search

A query that looks like a domain, such as `example.com`, opens directly. Anything that matches no local provider offers a web search with your configured engine. Set `searchEngine` in the [settings](../settings/) to any bang key to change the default.

Live web suggestions while typing are off by default. Turn them on with `webSuggestions` if you want them, and read [what that sends](../privacy-and-security/) first.
