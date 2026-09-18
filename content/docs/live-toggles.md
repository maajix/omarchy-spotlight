---
title: Live toggles
description: Settings that show their real state as a switch and flip in place.
weight: 50
---

Settings that are on or off show their live state instead of a generic action label. `Enter` or a click flips the switch while Spotlight stays open, so you can toggle several things in a row.

## Global settings

These read a system-wide state:

- Bluetooth
- Wi-Fi
- Night light
- Speaker mute and microphone mute
- Do Not Disturb
- Stay Awake (inhibits idle and lock)
- The status bar
- The battery percentage next to the bar icon
- Touchpad and touchscreen
- Window gaps
- Square aspect ratio
- Screensaver
- Crash capture (notify when a program crashes)
- Suspend in the system menu

## Per-window and per-workspace

These read the focused window or the active workspace rather than a global setting:

- Window transparency
- Tiled fullscreen
- Workspace layout (scrolling instead of dwindle)

## When no switch appears

If a state cannot be read, Spotlight shows no switch rather than guessing. The action still runs on `Enter`; you just do not get a live indicator.

Typing the setting's name is enough: `bluetooth`, `wifi`, `night`, `mute`, `dnd`. The empty-query digest also lists the most common switches so they are one keystroke away.
