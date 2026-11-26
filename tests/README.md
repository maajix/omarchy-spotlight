# Spotlight tests

Run these commands from the plugin root. CI uses Python 3.14 and Node.js 24.

## Automated checks

```bash
python3 -m unittest discover -s tests -p '*_test.py'
node --test
```

- Python tests cover the helper, including file and folder access, system views, AI responses and artifact validation.
- Node tests cover query parsing, ranking, previews, folder navigation and launch arguments. Run a single file with `node --test tests/open.test.js`.

CI also validates the manifest and checks the committed diff for whitespace errors. On Omarchy, `omarchy plugin validate .` validates the local plugin. [CI workflow](../.github/workflows/ci.yml)

## Quickshell smoke tests

These scripts exercise QML offscreen. They need Quickshell. The artifact, preview and settings scripts use Omarchy's shell files at `/usr/share/omarchy/shell`. The artifact script also uses ImageMagick's `magick` to generate test images.

| Script | Checks |
| --- | --- |
| `qml_animation_smoke.py` | Open and close animation, including reduced motion |
| `qml_artifacts_smoke.py` | Layout of the fixture AI cards |
| `qml_position_smoke.py` | Launcher placement and stable geometry as results change |
| `qml_preview_smoke.py` | Layout for each preview block type |
| `qml_settings_smoke.py` | Settings tabs, scrolling and edits |

The preview smoke fixture can fail with a `Color.menu` binding error on Qt 6.12. The fixture still uses an unqualified shell palette reference.

```bash
(
  for file in tests/qml_*_smoke.py; do
    python3 "$file" || exit 1
  done
)
```

Run the relevant smoke test after changing QML. [Development guide](https://maajix.github.io/omarchy-spotlight/docs/?p=development#qml-smoke-tests)
