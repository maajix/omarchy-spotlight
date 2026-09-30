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

The generic schema uses closed object variants in `artifacts.items.anyOf`.
Give each optional type its own variant and required fields; adding a type name
to an existing enum would still require that variant's fields. A dedicated path
also needs request detection in `Spotlight.qml`,
schema selection and prompt text in `cmd_ai()`, and conversion of its result
field into the `artifacts` list in `ai_result()`.

## Add a card

1. Define a small JSON object with a unique `type` in the appropriate schema
   under `resources/`. Include only data the card can actually show. Keep an
   explicit unavailable result for request-specific cards when the provider
   cannot get trustworthy data.
2. Add a validator in `lib/ai_artifacts.py` and register it in `VALIDATORS`.
   Existing map and weather validators live in `bin/spotlight-helper`.
   Treat every provider field as untrusted: bound text
   and array lengths, check numeric ranges and dates, restrict URLs, and return
   only validated fields. `ai_result()` drops an invalid card without dropping
   the text answer and returns a visible warning. Put the same length limits
   in the schema so providers generate data the validator can accept.
3. Add `<Type>Artifact.qml` under `ui/artifacts/`. Reuse `ArtifactCard` for the
   frame, title, source footer and content layout, and `ArtifactText` for
   consistent typography. The shared frame supplies the gradient and spacing;
   set `glyph` for a header icon and use its `actionChrome` for buttons.
   It receives validated
   `artifact` data and a `SpotlightPalette` named `chrome`, reports its
   `implicitHeight`, and emits `openRequested(url)` for user-clicked links.
   Emit `copyRequested(value)` for clipboard actions. Register the type once in
   `ArtifactHost.qml`; display-only cards need no `AiPanel.qml` change.
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

## Local system dashboards

The provider returns only `{ "type": "dashboard", "title": "System snapshot",
"focus": "all" }`. Focus can also be `cpu`, `memory`, `storage` or `services`.
`cmd_ai()` enriches the validated selector after the provider finishes, using
`lib/system_metrics.py` and the existing service collector. Provider-supplied
measurements are discarded. The snapshot is not included in the AI prompt.

CPU is sampled over 200 ms from `/proc/stat`; memory uses `MemAvailable` from
`/proc/meminfo`. Filesystem usage comes from `statvfs`, with duplicate
filesystems merged. Storage requests also run `du` for direct home folders,
without following symlinks or crossing filesystems. Its 64 KiB / three-second
bounds can produce a partial scan, explicitly labelled in the card. Folder
bars show allocated size relative to the largest returned folder, not a
complete breakdown of the filesystem. Service counts reuse the bounded
system/user service listing; incomplete listings remain labelled partial.
Unavailable measurements remain unavailable, never zero.

The card is a snapshot, not a background monitor. Submit another request for
fresh values. Copy snapshot exports the local data only after a click.

## Interactive checklist state

`ChecklistArtifact` receives `completed` (an array of zero-based task indices)
and emits `progressRequested(completed)`. `ArtifactHost` forwards that event to
`AiPanel`, which owns the state outside the card delegates. The helper derives
a stable ID from the validated title and tasks; providers cannot set progress.

The panel keeps the 32 most recently changed checklists in memory. Closing and
reopening Spotlight recreates the card with its saved checkmarks. Progress
resets when the shell restarts; no checklist data is written to disk or sent
to the AI. Reset clears the card's progress, and Copy includes `[x]` / `[ ]`
markers. Stateful cards should keep state outside delegates so hiding or
recreating a card does not discard it.

## Check the change

From the plugin root:

```bash
omarchy plugin validate .
python3 -m unittest discover -s tests -p '*_test.py'
python3 tests/qml_artifacts_smoke.py
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
| `palette` | Title, 2–8 named six-digit HEX colors | Copyable swatches and a small interface preview. |
| `chart` | Variant, category labels, 1–4 named numeric series, unit, provenance note, optional HTTPS source | Line and grouped bar charts, or a single-series donut; exact values on hover or with arrow keys. |
| `comparison` | 2–4 options with facts, pros, cons, price status and optional HTTPS sources | Rows share the tallest cell's height; facts match by label, missing values show `—`. At most one suggested pick and a copy action. |
| `timeline` | Title, provenance note, 1–12 chronological entries with when, title, description, status and optional HTTPS source | A connected itinerary or milestone list with planned/current/completed markers and a copy action. |
| `dashboard` | Provider-selected title/focus; helper-owned CPU, memory, filesystem, folder and service measurements | Local snapshot, unavailable/partial states and explicit copy. No metrics sent to AI. |
| `checklist` | Title, note, optional HTTPS source and 1–12 tasks with titles/descriptions | User-owned checkmarks, progress bar, reset and copy. State survives closing Spotlight within the current shell session. |
| `diagram` | Title, provenance note, optional source, 2–10 unique nodes and 1–16 directed connections | Native rounded nodes with compact grid spacing. Previous/next controls select a connection, highlight its directed route and show its full caption above the diagram. Clicking a node selects an outgoing connection. Up to three columns and six rows. No executable markup. |

Weather requires AI web search. The helper rejects invalid or stale
measurements and stamps the time Spotlight received the answer. A
forecast can contain fewer than seven verified days; the card shows its day
count. Days with only a verified high or low are supported; the missing value
shows `—`. Days with neither temperature are omitted. Missing or invalid
weather data produces an unavailable card with a
reason instead of silently omitting the widget. The
source link comes from the provider: Spotlight validates its URL shape, but
cannot verify that the provider read the page. The optional default location
is sent only for locally recognized weather requests; an explicit place in the
question wins.

Map previews request a dark static image from `mapmap.ai` with the validated
coordinates and zoom. The image includes map attribution. If the service is
unavailable, the card still shows the coordinates and OpenStreetMap link.

Charts accept up to 24 categories for lines, 12 for bars and 8 for donuts.
Each series must have one finite value per category. Donut values must be
nonnegative with a positive total. Use `sourceUrl: ""` for supplied or clearly
marked illustrative data; a real source gets a retrieval timestamp. Charts
do not collect local metrics or imply that example values are measurements.

Examples:

```text
ai: draw a bar chart of example sales: Jan 12, Feb 18, Mar 9, Apr 24
ai: draw a line chart of these example temperatures: Mon 12, Tue 15, Wed 14, Thu 18
ai: show a donut chart of this budget: Rent 900, Food 300, Transport 100, Savings 400 EUR
```
