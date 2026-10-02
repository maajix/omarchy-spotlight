# AI artifacts

Artifacts are optional visual cards beside an `ai:` answer. The provider returns
structured JSON, `bin/spotlight-helper` validates it, and
`ui/panels/AiPanel.qml` renders the approved data through
`ui/artifacts/ArtifactHost.qml`. The text answer remains visible if a card is
missing or invalid. Provider output never executes commands. Gallery Save and
Apply buttons invoke fixed helper actions only after a user click.

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
5. Add one valid and one invalid response to `tests/artifacts_test.py`. If the
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

## Configuration diff previews

`diff` contains 1–3 files with display-only `path` labels and exact `before` /
`after` strings. Each string is capped at 6,000 characters, 120 lines and 300
characters per line. The helper uses Python's `difflib.unified_diff` to build
context hunks, line numbers and addition/removal counts. New files and empty
proposed contents are supported; equal contents show No changes.

Copy proposed config copies the complete `after` text, not only the visible
hunks. Copy diff copies the unified diff. Paths are never opened, configs are
never read or written, and no apply action is available. When the user has not
supplied a starting configuration, the provider must label it illustrative.

## Image galleries and explicit actions

`gallery` contains a title, provenance note and 1–8 images, each with `title`,
`description`, `credit`, a direct HTTPS `imageUrl` and HTTPS attribution/license
`sourceUrl`. Prefer a CDN's bounded image size rather than a full-resolution
original. The provider must find actual URLs using web search or use URLs
explicitly supplied by the user; unavailable results must not be invented.
The provider aims for six distinct images unless the user requests a count;
explicit counts are respected up to eight. A shortfall or larger requested
count is explained in the answer. Previews fit the entire image into a 4:3
frame, preserving portrait artwork without cropping.

After validation, `local_gallery()` uses `lib/gallery_images.py` to fetch each
image. DNS resolution must yield only public IPs, and curl pins the connection
to a checked IP while verifying TLS for the original hostname. Port 443 only;
no redirects, proxies, curl configuration or credentials. Each download is
capped at 8 MiB with an eight-second network deadline. Only PNG/JPEG inputs up
to 32 megapixels and 12,000 pixels per edge are decoded. Native JPEG
downsampling keeps large camera images within the preview size. ImageMagick
has a 256 MiB pixel-cache limit, disables disk/map caches and limits threads/time,
strips metadata and emits a JPEG up
to 2,560 × 1,440. Quickshell receives only the sanitized local preview. Missing
tools, invalid images and failed downloads show per-image unavailable states.

The private cache under `~/.cache/omarchy-spotlight/gallery` retains the newest
16 previews (at most 128 MiB), enough for two full galleries. `id` and `previewUrl` are helper-owned, never
provider fields. Expired previews require another request. Save writes the
sanitized image to `~/Pictures/Spotlight/<hash>.jpg`; it never overwrites an
existing changed file. Apply saves the same image and calls the fixed native
`omarchy theme bg set` command. Neither occurs on generation or card reopening.
Review the source license before reuse; downloading a preview grants no rights.

`GalleryArtifact` emits `imageActionRequested(id, action)`; `ArtifactHost`
forwards it to `AiPanel`, which runs the existing helper command with `gallery`
and a validated `save`/`apply` action. Actions accept only a content hash, never
a provider path or command. The panel allows one action at a time and stores
bounded status outside delegates so closing Spotlight does not discard it.
For another actionable artifact, use the same signal/validated helper pattern
and document exactly which user click authorizes the operation.

## Place recommendations

`places` contains 1–4 venues with name, category, address, hours, summary,
a nullable 0–5 rating, rating source and optional HTTPS source URL. Unknown
ratings remain `null`; current hours/ratings require verification through AI
web search or explicitly supplied data. The provider explains provenance in
`note`; Spotlight validates structure but cannot prove the provider read a page.

The helper generates an OpenStreetMap search link from the validated venue
name and address. The card makes no automatic map/image requests; View map
and Source open the browser only after a click. Copy address copies only the
address. For nearby recommendations, specify a location in the prompt; the
weather default is not sent for venue requests.

## Local system dashboards

The provider returns only `{ "type": "dashboard", "title": "System snapshot",
"focus": "all" }`. Focus can also be `cpu`, `memory`, `storage` or `services`.
`cmd_ai()` enriches the validated selector after the provider finishes, using
`lib/system_metrics.py` and the existing service collector. Provider-supplied
measurements are discarded. The snapshot is not included in the AI prompt.

CPU is sampled over 200 ms from `/proc/stat`; memory uses `MemAvailable` from
`/proc/meminfo`. Filesystem usage comes from `statvfs`, with duplicate
filesystems merged using `findmnt`'s UUID (including Btrfs subvolumes that share
one pool), falling back to the filesystem ID when a UUID is unavailable. Storage requests also run `du` for direct home folders,
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
| `diff` | Title, provenance note and 1–3 display-labelled before/after files | Read-only unified hunks, old/new line numbers, change counts and explicit copy actions. |
| `gallery` | Title, note and 1–8 attributed direct HTTPS PNG/JPEG images | Full-image local previews, source links, explicit Save and Apply wallpaper actions. Six images by default; explicit counts respected up to eight. |
| `places` | Title, note and 1–4 venues with address, hours, summary, nullable rating/rating source and optional HTTPS source | Venue cards, explicit map/source links and copy address; unavailable ratings stay unavailable. |
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
