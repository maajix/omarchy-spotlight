# AI artifacts

Artifacts are optional visual cards beside an `ai:` answer. The provider returns
structured JSON, `bin/spotlight-helper` validates it, and
`ui/panels/AiPanel.qml` renders the approved data through
`ui/artifacts/ArtifactHost.qml`. The text answer remains visible if a card is
missing or invalid. Cards display information; they never execute commands.

## Choose the response shape

| Path | Use it when | Current example |
| --- | --- | --- |
| Optional `artifacts` array in `resources/ai-result.schema.json` | A card may help, but the answer is useful without one. | Map |
| Dedicated schema selected by `cmd_ai()` | The request needs a specific card or an explicit unavailable result. | Weather |

The generic schema currently describes **only map objects**. To add another
optional type, give the array item distinct closed object variants (for
example with `anyOf`); adding a type name to its enum alone would still require
map fields. A dedicated path also needs request detection in `Spotlight.qml`,
schema selection and prompt text in `cmd_ai()`, and conversion of its result
field into the `artifacts` list in `ai_result()`.

## Add a card

1. Define a small JSON object with a unique `type` in the appropriate schema
   under `resources/`. Include only data the card can actually show. Keep an
   explicit unavailable result for request-specific cards when the provider
   cannot get trustworthy data.
2. Add a validator in `bin/spotlight-helper` and register it in
   `ARTIFACT_VALIDATORS`. Treat every provider field as untrusted: bound text
   and array lengths, check numeric ranges and dates, restrict URLs, and return
   only validated fields. `ai_result()` drops an invalid card without dropping
   the text answer.
3. Add `<Type>Artifact.qml` under `ui/artifacts/`. It receives validated
   `artifact` data and a `SpotlightPalette` named `chrome`, reports its
   `implicitHeight`, and emits `openRequested(url)` for user-clicked links.
   Register the type once in `ArtifactHost.qml`; `AiPanel.qml` needs no change.
4. Tell the provider when to return this object in `cmd_ai()`. For an optional
   card, a short instruction in the shared prompt is enough. For a required
   card, also wire the request flag, schema, result field and unavailable case.
5. Add one valid and one invalid response to `tests/helper_test.py`. If the
   card needs local request detection, test that in `tests/` too. Update
   `SECURITY.md` for any new data flow or external link.

For a setting, add `artifactSettings.<type>` to the helper's settings defaults
and normalizer, then add its control to
`ui/panels/ArtifactSettingsPage.qml`. Pass only the setting needed for that
request from `Spotlight.qml`; avoid sending the full settings object to the
provider. Weather's saved location is an example.

This is a **source-level extension point**: adding a card currently means
editing the plugin and reloading the shell. Users cannot drop an arbitrary QML
file into a folder and have Spotlight load it automatically.

## Check the change

From the plugin root:

```bash
omarchy plugin validate .
python3 -m unittest discover -s tests -p '*_test.py'
/usr/lib/qt6/bin/qmlformat -n ui/artifacts/*.qml >/dev/null
```

Then ask for the card in Spotlight. Check the useful failure path too: an
unavailable or invalid card should leave a readable text answer. Reload the
Omarchy shell after changing QML if the running plugin does not pick it up.

## Existing cards

| Type | Validated data | Behavior |
| --- | --- | --- |
| `map` | Title, latitude, longitude, zoom | Static preview from MapMap; OpenStreetMap opens only after a click. |
| `weather` | Variant, location, HTTPS source, up to seven dated days | Current conditions, two-day rain comparison or forecast. |

Weather requires AI web search. The helper rejects cards with incomplete or
stale measurements and stamps the time Spotlight received the answer. The
source link comes from the provider: Spotlight validates its URL shape, but
cannot verify that the provider read the page. The optional default location
is sent only for locally recognized weather requests; an explicit place in the
question wins.

Map previews request a dark static image from `mapmap.ai` with the validated
coordinates and zoom. The image includes map attribution. If the service is
unavailable, the card still shows the coordinates and OpenStreetMap link.
