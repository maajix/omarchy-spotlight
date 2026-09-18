---
title: Development
description: Repository layout, the checks to run before committing, and how the plugin is loaded.
weight: 90
---

The source lives at [github.com/maajix/omarchy-spotlight](https://github.com/maajix/omarchy-spotlight) under the MIT license.

## Layout

```text
Spotlight.qml          UI and actions
SetupTour.qml          first-run shortcut setup
PillSwitch.qml         live toggle control
lib/                   parsers and ranking logic
bin/spotlight-helper   bounded interface to files and subprocesses
tests/                 JavaScript and Python checks
```

The QML files run inside `omarchy-shell`. The `lib/` modules are plain JavaScript with no dependencies, which is why they can be tested with Node directly. The helper is a single Python script.

## Checks

Useful checks before committing:

```bash
omarchy plugin validate .
python3 -m unittest discover -s tests -p '*_test.py'
for file in tests/*.test.js; do node "$file"; done
python3 -m py_compile bin/spotlight-helper
/usr/lib/qt6/bin/qmlformat -n Spotlight.qml SetupTour.qml PillSwitch.qml >/dev/null
for file in lib/*.js; do node --check "$file"; done
```

CI runs the manifest validation, the Python tests and the Node tests on every push and pull request.

## Working on a local checkout

Restart `omarchy-shell` after changing QML because the plugin stays loaded inside the shell. Changes to `lib/` and the helper are picked up when Spotlight next runs them.

Search for `spotlight settings` and choose **Open Spotlight Plugin Folder** to jump to the installed files.
