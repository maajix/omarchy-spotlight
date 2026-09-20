---
title: Privacy and security
description: What touches the network, what is stored, and how the helper is hardened.
weight: 70
---

Spotlight has no telemetry, analytics, or background network service. Almost everything happens locally.

## Network access

| Network access | When it happens |
| --- | --- |
| `suggestqueries.google.com` | While typing, only when `webSuggestions` is enabled |
| Your browser | After you activate a web search, URL, or calendar result |
| tldr-pages (GitHub) | First lookup of a command not yet in `~/.cache/tldr`, via the `tldr` client |

Live web suggestions are disabled by default. Normal web searches do not send the query anywhere until you activate the result.

## Learning data

Learning is optional and stays in `~/.local/state/omarchy/spotlight-usage.json`. It stores bounded selection counts, timestamps, stable IDs, file paths, and normalized query prefixes. Older entries decay and the file is capped in size.

Disable it with `"learningEnabled": false`, or remove the data with **Reset Spotlight Learning** from `spotlight settings`.

## The helper

`bin/spotlight-helper` is the boundary between the shell UI and your files and processes. It:

- bounds file and subprocess output
- validates persistent files and their ownership, and rejects symlinks
- uses private atomic writes
- applies subprocess deadlines and cleans up process groups

Clipboard previews sent to the shell are bounded to one line; the full selected value goes directly from the helper to `wl-copy`.

## Confirmations

Logout, restart and shutdown ask before they act.

## Reporting a vulnerability

Please do not open a public issue for an undisclosed vulnerability. Use GitHub's private reporting for the repository:

[github.com/maajix/omarchy-spotlight/security/advisories/new](https://github.com/maajix/omarchy-spotlight/security/advisories/new)

The full policy, including supported versions, disclosure process and safe harbor for good-faith research, is in [SECURITY.md](https://github.com/maajix/omarchy-spotlight/blob/main/SECURITY.md).
