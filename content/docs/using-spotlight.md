---
title: Using Spotlight
description: What to type, what comes back, and how to move through it.
weight: 20
---

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
| `gh quickshell` | Search GitHub |
| `tr what is this to german` | Translate into the named language |
| `example.com` | Open a URL directly |
| Anything else | Offer a web search |

Spotlight runs inside the existing `omarchy-shell` process, so there is no separate launcher or cold start. Late file and web results cannot steal the current selection while you type.

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

## The empty state

With no query, Spotlight shows a digest: recent and frequent items when learning is enabled, plus the live switches for common settings. Type to replace it with search results.

## Confirmations

Logout, restart and shutdown ask for confirmation before they act. Everything else runs immediately.
