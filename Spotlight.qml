import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "lib/Calc.js" as Calc
import "lib/Units.js" as Units
import "lib/Currency.js" as Currency
import "lib/NaturalTime.js" as NaturalTime
import "lib/Web.js" as Web
import "lib/Fuzzy.js" as Fuzzy
import "lib/Frecency.js" as Frecency
import "lib/Commands.js" as Commands
import "lib/Apps.js" as Apps
import "lib/FileRank.js" as FileRank
import "lib/Query.js" as Query
import "lib/Ranking.js" as Ranking
import "lib/Chord.js" as Chord

// Spotlight — a Raycast-shaped command palette for Omarchy.
//
// One overlay, many providers. Each provider turns the query into rows; the
// rows are plain data carrying a `kind`, and activate() is the only place that
// turns a kind into an effect. Nothing from the query is ever evaluated: the
// calculator has its own parser and every command runs through an argv vector.
Item {
  id: root

  // ------------------------------------------------------------- injected
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  onShellChanged: {
    root.refreshHides()
    root.refreshMenuCommands()
  }
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "majix.spotlight"
  // The shell's own application library, when the host hands one over.
  //
  // Omarchy 4.0.3 gates it behind a manifest kind of "menu" — which this
  // manifest now declares — but the manifest that gate reads has been through
  // an Instantiator model by the time it arrives, and a QVariantMap round trip
  // leaves `kinds` an array that no longer answers to Array.isArray. The
  // check inside manifestHasKind() therefore cannot pass for any third-party
  // plugin, whatever it declares. Applications come from DesktopEntries
  // instead while that holds; the moment the host starts handing the library
  // over again, every path below switches back to it on its own.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginFolder: decodeURIComponent(
    String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, ""))

  // Spotlight is `keepLoaded`, so it lives inside the long-running
  // omarchy-shell process rather than being torn down with the overlay.
  // Nothing it reads may therefore be open-ended: a file, a process output or
  // a network response that is unbounded at the point of reading stays
  // resident for the life of the session. Every one of those crossings goes
  // through bin/spotlight-helper, which caps the bytes, imposes its own
  // wall-clock deadline with a process-group teardown, and hands back a
  // normalised, count-limited projection. No FileView, no raw subprocess.
  readonly property string helper: decodeURIComponent(
    String(Qt.resolvedUrl("bin/spotlight-helper")).replace(/^file:\/\//, ""))

  function helperArgv(args) {
    return ["python3", root.helper].concat(args)
  }

  // Every helper call answers with a single JSON object carrying an `ok` flag.
  // A refusal is not an error path here — the caller keeps its defaults, which
  // is what failing closed looks like for a launcher.
  function helperReply(raw) {
    try {
      var text = String(raw || "")
      if (text.length > root.maxHelperPayloadChars) return null
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object" && parsed.ok === true) return parsed
    } catch (e) {
    }
    return null
  }

  // ------------------------------------------------------------- state
  property bool opened: false
  property string query: ""
  property int selectedIndex: 0
  property bool cursorActive: true

  // Rows currently on screen, as plain JS objects. displayModel mirrors only
  // the display fields; the payload stays here and is read back by index, so
  // ListModel never has to hold a nested object.
  property var rows: []

  // Async provider caches. Each is refreshed by its own Process and triggers a
  // rebuild when it lands, so a slow provider never blocks the fast ones.
  property var suggestionRows: []
  property string suggestionFor: ""
  property var fileRows: []
  property string fileFor: ""
  property var reminderRows: []
  property var clipboardRows: []
  property string clipboardFor: ""
  property var tldrPage: null
  property var currencySession: Currency.createSession()
  property var currencyProcess: null

  // Destructive commands need a second Enter. Holds the row key that is armed.
  property string armedKey: ""

  // The row the user deliberately put the cursor on — arrow keys, or a pointer
  // that actually moved. Empty means "whatever is top right now", and that is
  // the rule that makes Enter safe while async rows are still landing: a late
  // rebuild can reshuffle the list without the cursor ever drifting off the
  // best answer onto a web suggestion.
  property string pinnedKey: ""

  // Desktop ids Omarchy keeps out of its own launcher. AppLibrary applies this
  // list itself, so it is read only when the fallback source is the one
  // building the list.
  property var appHides: Apps.hiddenMap([])

  // The real Omarchy root-menu tree, projected by the helper into rows
  // shaped exactly like Commands.js's own entries - commandRows() below
  // merges the two without needing to know one came from a different
  // source.
  property var menuCommands: []

  // Live state of every toggle the helper could actually read, as
  // { stateId: bool }. An id the probe could not answer is absent rather than
  // false, and an absent id draws no switch: a missing state is unknown, and
  // a switch that is confidently wrong is worse than no switch at all.
  property var toggleStates: ({})

  // Versioned learning store: stable items plus query-local contexts. The
  // helper validates and bounds it before it reaches this long-lived process.
  property var usage: Frecency.emptyStore()

  // Hard ceilings on everything the model will hold, applied where the rows
  // are built rather than after. maxApps is a user setting, so it is clamped
  // rather than trusted; the rest bound lists that arrive from outside.
  readonly property int maxAppRows: 24
  // The helper returns at most 400 hits; the shared global cap shows at most
  // 50 after ranking.
  readonly property int maxFileRows: 50
  readonly property int maxUnifiedFileRows: 4
  // Must match bin/spotlight-helper's file-search limits: the helper first
  // truncates the pattern to 256 characters, then AND-filters on its first
  // 8 terms. FileRank must score that same bounded pattern; otherwise text
  // fd never required can either collapse candidates to the residual tier
  // or favor an incidental match.
  readonly property int filePatternChars: 256
  readonly property int fileMaxTerms: 8
  readonly property int maxClipboardRows: 50
  readonly property int maxReminderRows: 50
  readonly property int maxQueryChars: 512
  readonly property int maxPayloadChars: 4096
  readonly property int maxHelperPayloadChars: 524288
  readonly property int maxAppCandidates: 512
  readonly property int maxWindowCandidates: 256
  readonly property int maxGlobalResults: 50

  // The empty query is a digest, not a search: every source is capped on its
  // own so the longest one cannot crowd the others off the list. Ranking.rank
  // already orders the sections by result type.
  readonly property int idleAppRows: 5
  readonly property int idleWindowRows: 2
  readonly property int idleCommandRows: 1
  readonly property int idleFileRows: 2
  readonly property int maxTitleChars: 512
  readonly property int maxSubtitleChars: 1024

  property var settings: ({
    webSuggestions: false,
    searchEngine: "g",
    fileSearch: true,
    fileSearchAlways: true,
    clipboardSearch: true,
    clipboardSearchAlways: true,
    learningEnabled: true,
    maxResults: 20,
    maxApps: 8,
    maxSuggestions: 4,
    // true until the helper answers, so the tour never flashes before the
    // first-run flag has actually been read.
    setupCompleted: true
  })

  // ------------------------------------------------------------- tour
  // The setup tour replaces the search card inside the same PanelWindow.
  // Spotlight.qml does all of the tour's I/O; SetupTour.qml only paints.
  property bool tourActive: false
  property string bindingState: ""
  property var tourBinding: ({ current: "", previous: "", managed: false,
                              bound: {}, unknownMods: [] })
  // Written on first run so a fresh install has a working shortcut before the
  // tour is ever opened. The tour can still change it.
  readonly property string defaultChord: "ALT + SPACE"
  property bool autoBindDone: false

  // ------------------------------------------------------------- theme
  // Shares the [menu] surface tokens, so any theme that styles the Omarchy
  // menu styles this too. The card is deliberately translucent: the frost is
  // Hyprland's, applied to this layer's namespace.
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.accent
  // Frosted glass needs something left to frost: at 0.86 the card is opaque
  // and Hyprland's blur has no visible effect. 0.62 keeps text contrast while
  // letting the blurred wallpaper through as colour and shape.
  readonly property color glassBackground: Util.alpha(Color.menu.background, 0.62)
  readonly property color glassBorder: Util.alpha(Color.foreground, 0.09)
  readonly property color glassSheen: Util.alpha("#ffffff", 0.07)
  readonly property color scrim: Util.alpha(Color.menu.scrim, 0.25)
  readonly property color selectedBackground: Util.alpha(Color.foreground, 0.12)
  readonly property color selectedText: Color.menu.selectedText
  readonly property color dividerColor: Util.alpha(Color.foreground, 0.06)
  readonly property string fontFamily: Style.font.menuFamily

  // One left rail at `gutter`. The search glyph and every row icon align to
  // it; a row is inset by `listPadding` and carries
  // the remainder internally, so the rail survives the inset.
  readonly property int gutter: Style.space(21)
  readonly property int listPadding: Style.space(10)
  readonly property int rowInset: gutter - listPadding

  readonly property int cardRadius: Style.space(12)
  readonly property int rowRadius: Style.space(8)
  readonly property int searchHeight: Style.space(56)
  readonly property int rowHeight: Style.space(36)
  readonly property int sectionHeight: Style.space(24)
  readonly property int footerHeight: Style.space(36)
  // Sized so the full empty-query digest lands above the fold: 5 apps, 1
  // command, 2 files and 2 windows at rowHeight, plus their four section
  // headings at sectionHeight. A query may still scroll.
  readonly property int maxListHeight: Style.space(456)
  readonly property int hairline: Style.spacing.hairline

  // Between heading (16) and display (24): a hero input that is still an
  // input. Scales with the user's font size rather than being pinned to 18px.
  readonly property int searchFontSize: Math.round(Style.font.baseSize * 1.5)

  // Fixing the top edge at the position the *fully expanded* panel would need
  // to sit centred means the panel grows downward into the middle of the
  // screen instead of shoving the search field around as results arrive.
  readonly property int maxCardHeight: searchHeight + hairline
    + listPadding * 2 + maxListHeight + hairline + footerHeight

  // ------------------------------------------------------------- lifecycle
  // The payload may carry {"query": "..."} so a keybind can summon Spotlight
  // already primed, e.g. bound to open straight into "remind me ".
  function open(payloadJson) {
    var initial = ""
    try {
      var rawPayload = String(payloadJson || "{}")
      if (rawPayload.length > root.maxPayloadChars) rawPayload = "{}"
      var payload = JSON.parse(rawPayload)
      if (payload && typeof payload.query === "string")
        initial = payload.query.slice(0, root.maxQueryChars)
    } catch (e) {
      initial = ""
    }

    root.opened = true
    root.tourActive = false
    root.armedKey = ""
    root.rows = []
    root.pinnedKey = ""
    input.text = initial
    input.cursorPosition = input.text.length
    root.selectedIndex = 0
    root.cursorActive = true
    root.suggestionRows = []
    root.suggestionFor = ""
    root.fileRows = []
    root.fileFor = ""
    root.clipboardRows = []
    root.clipboardFor = ""
    root.tldrPage = null
    // The panel appears under wherever the pointer already is. Hold the cursor
    // for the same beat a keystroke would, so opening over a row does not hand
    // it the selection before the first character is typed.
    typingGuard.restart()
    if (root.appLibrary) root.appLibrary.refreshIcons()
    // Settings are re-read on every open rather than watched. A watcher on a
    // predictable path is a standing invitation to whatever can write it; one
    // bounded read when the user asks for the launcher costs nothing and picks
    // up an edit just as promptly.
    root.refreshSettings()
    root.refreshReminders()
    root.refreshToggleStates()
    root.updateCurrency()
    root.rebuild()
    pointerGate.reset()
    if (root.settings.setupCompleted === false || (tour.started && !tour.singleStep)) root.resumeTour()
    Qt.callLater(function() {
      if (root.tourActive) tour.focusStep()
      else input.forceActiveFocus()
      resultList.positionViewAtBeginning()
    })
  }

  function close() {
    root.opened = false
    root.armedKey = ""
    root.stopQueryWork()
  }

  // Nothing that was started for a query outlives the overlay it was typed
  // into: the debounces stop, the readers are terminated, and the rows they
  // were filling are dropped rather than left resident.
  function stopQueryWork() {
    Currency.cancel(root.currencySession)
    currencyDebounce.stop()
    root.stopCurrencyProcess()
    suggestDebounce.stop()
    fileDebounce.stop()
    clipboardDebounce.stop()
    tldrDebounce.stop()
    suggestProc.running = false
    fileProc.running = false
    clipboardProc.running = false
    tldrProc.running = false
    root.clipboardRows = []
    root.clipboardFor = ""
    root.tldrPage = null
  }

  function refreshSettings() {
    settingsProc.running = false
    settingsProc.command = root.helperArgv(["read-settings"])
    settingsProc.running = true
  }

  function refreshUsage() {
    usageReadProc.running = false
    usageReadProc.command = root.helperArgv(["read-usage"])
    usageReadProc.running = true
  }

  // Read once, when the host injects its shell: the file is packaged and only
  // an Omarchy update changes it, which restarts the shell anyway.
  function refreshHides() {
    if (!root.shell || root.shell.appLibrary) return
    hidesProc.running = false
    hidesProc.command = root.helperArgv(["read-hides"])
    hidesProc.running = true
  }

  function loadHides(raw) {
    var reply = root.helperReply(raw)
    root.appHides = Apps.hiddenMap(reply ? reply.hides : null)
  }

  // Read once, when the host injects its shell: the tree is either packaged
  // (an Omarchy update restarts the shell anyway) or the user's own
  // extension file, which changes rarely enough that re-reading on every
  // open - the way settings does - would be evaluating dozens of `when`
  // conditions for no reason most of the time.
  function refreshMenuCommands() {
    if (!root.shell) return
    menuCommandsProc.running = false
    menuCommandsProc.command = root.helperArgv(["read-menu-commands"])
    menuCommandsProc.running = true
  }

  function loadMenuCommands(raw) {
    var reply = root.helperReply(raw)
    var list = (reply && Array.isArray(reply.commands)) ? reply.commands : []
    // The menu tree carries actions the catalogue already curates, only under
    // the menu's own wording, so the merged list showed both. The catalogue
    // copy wins: it is the one with the hand-written subtitle, the keywords
    // and, for a toggle, the state the switch reads.
    var known = {}
    var catalogue = Commands.commands()
    for (var k = 0; k < catalogue.length; k++) {
      var id = Commands.argvId(catalogue[k].argv)
      if (id) known[id] = true
    }
    var out = []
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (!c || !Array.isArray(c.argv) || c.argv.length === 0) continue
      var argv = []
      for (var j = 0; j < c.argv.length; j++) argv.push(String(c.argv[j]))
      if (known[Commands.argvId(argv)]) continue
      out.push({
        key: String(c.key || ""),
        title: String(c.title || "").slice(0, root.maxTitleChars),
        subtitle: String(c.subtitle || "").slice(0, root.maxSubtitleChars),
        icon: String(c.icon || "󰣇"),
        kind: "shell",
        argv: argv,
        keywords: String(c.keywords || "")
      })
    }
    root.menuCommands = out
  }

  function refreshReminders() {
    remindersProc.running = false
    remindersProc.command = root.helperArgv(["reminders"])
    remindersProc.running = true
  }

  function refreshToggleStates() {
    toggleStatesProc.running = false
    toggleStatesProc.command = root.helperArgv(["toggle-states"])
    toggleStatesProc.running = true
  }

  function loadToggleStates(raw) {
    var reply = root.helperReply(raw)
    var states = (reply && reply.states && typeof reply.states === "object") ? reply.states : {}
    var out = ({})
    for (var id in states)
      if (states[id] === true || states[id] === false) out[id] = states[id]
    root.toggleStates = out
  }

  // The label under the cursor names what Enter will do, so a toggle row says
  // which way it is about to go rather than a generic "Run".
  function primaryLabelFor(r) {
    var id = (r && r.payload) ? r.payload.stateId : ""
    if (id && root.toggleStates[id] !== undefined)
      return root.toggleStates[id] === true ? "Turn off" : "Turn on"
    return r ? r.primaryLabel : ""
  }

  // Escape and successful activations go through here so the shell's
  // openPanelIds stays in step — otherwise the next toggle would try to hide
  // an overlay that is already gone.
  function dismiss() {
    root.opened = false
    root.armedKey = ""
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    // The current shortcut pressed while the recorder step is up: show it as
    // "already your shortcut" instead of closing the tour.
    if (root.opened && root.tourActive && tour.step === 1) {
      tour.selected = root.tourBinding.current
      return
    }
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Re-raise an unfinished tour at the step the user left; fresh start otherwise.
  function resumeTour() {
    if (tour.started && !tour.singleStep) {
      root.tourActive = true
      root.readBinding()
      tour.focusStep()
    } else root.showTour(0, false)
  }

  // ------------------------------------------------------------- tour
  function showTour(step, single) {
    input.text = ""
    root.armedKey = ""
    root.bindingState = ""
    root.tourActive = true
    tour.start(root.settings, step, single)
    root.readBinding()
  }

  // `patch` holds the settings keys to persist; {} means the tour was only
  // looked at (single-step Done, or Esc on the shortcut chooser).
  function finishTour(patch) {
    root.tourActive = false
    if (Object.keys(patch || {}).length > 0) {
      settingsWriteProc.running = false
      settingsWriteProc.stdinEnabled = true
      settingsWriteProc.command = root.helperArgv(["write-settings"])
      settingsWriteProc.running = true
      settingsWriteProc.write(JSON.stringify(patch))
      settingsWriteProc.stdinEnabled = false
    }
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function readBinding() {
    bindingProc.running = false
    bindingProc.action = "read"
    bindingProc.command = root.helperArgv(["read-binding"])
    bindingProc.running = true
  }

  function writeBinding(chord) {
    root.bindingState = "busy"
    bindingProc.running = false
    bindingProc.action = "write"
    bindingProc.command = root.helperArgv(["write-binding", chord])
    bindingProc.running = true
  }

  function revertBinding() {
    root.bindingState = "busy"
    bindingProc.running = false
    bindingProc.action = "revert"
    bindingProc.command = root.helperArgv(["revert-binding"])
    bindingProc.running = true
  }

  // Chords arrive in two spellings (bindings.lua and the keybindings menu),
  // so every one is canonicalized before the tour compares them.
  function loadBinding(reply) {
    var bound = {}
    var raw = (reply && reply.bound && typeof reply.bound === "object") ? reply.bound : {}
    for (var key in raw) {
      if (!Object.prototype.hasOwnProperty.call(raw, key)) continue
      var chord = Chord.normalize(key)
      if (chord && !Object.prototype.hasOwnProperty.call(bound, chord))
        bound[chord] = String(raw[key]).slice(0, 80)
    }
    var unknownMods = (reply && Array.isArray(reply.unknownMods)) ? reply.unknownMods : null
    root.tourBinding = {
      current: Chord.normalize(reply && reply.current ? reply.current : ""),
      previous: Chord.normalize(reply && reply.previous ? reply.previous : ""),
      managed: !!(reply && reply.managed === true),
      bound: bound,
      unknownMods: unknownMods
    }
    // First run only: claim the recommended chord when Spotlight has no
    // shortcut and nothing else holds it. Absence from `bound` only means
    // free where the table can speak: a helper that could not read the live
    // keybindings answers bound: null, and one that read them but could not
    // name every bind under a modifier set lists it in unknownMods. Either
    // way nothing is taken.
    if (!root.autoBindDone && root.settings.setupCompleted === false) {
      root.autoBindDone = true
      if (root.tourBinding.current === ""
          && Chord.isKnown(root.defaultChord, reply && reply.bound, unknownMods)
          && !Object.prototype.hasOwnProperty.call(bound, root.defaultChord))
        root.writeBinding(root.defaultChord)
    }
  }

  // ------------------------------------------------------------- usage
  function bumpUsage(row) {
    if (!root.settings.learningEnabled || !row || !row.stableId) return
    if (row.resultType !== "app" && row.resultType !== "window"
        && row.resultType !== "file" && row.resultType !== "action") return
    var now = Date.now()
    var contexts = Query.contextKeys(Query.parse(root.query))
    var next = Frecency.bump(root.usage, row.stableId, contexts, row.learningMeta, now)
    root.usage = next
    root.persistUsage(JSON.stringify(next))
  }

  function loadUsage(raw) {
    var reply = root.helperReply(raw)
    // adopt() rebuilds the store as a null-prototype map. The helper has
    // already dropped anything that is not one of our own keys, and this is
    // the second half of the same guarantee: on an ordinary object a key of
    // `__proto__` is an assignment to the prototype rather than an entry, so
    // one such line in the file would quietly reshape every lookup after it.
    root.usage = Frecency.adopt(reply ? reply.usage : null, Date.now())
  }

  // Writes go through the helper too: a locked, atomic 0600 replacement inside
  // a directory it has verified it owns. Only one write is ever in flight, and
  // a bump that lands during one is folded into the next.
  property string pendingUsage: ""

  function persistUsage(json) {
    root.pendingUsage = json
    root.flushUsage()
  }

  function flushUsage() {
    if (usageWriteProc.running || !root.pendingUsage) return
    var payload = root.pendingUsage
    root.pendingUsage = ""
    usageWriteProc.stdinEnabled = true
    usageWriteProc.command = root.helperArgv(["write-usage"])
    usageWriteProc.running = true
    usageWriteProc.write(payload)
    usageWriteProc.stdinEnabled = false
  }

  // Settings arrive already type-checked and clamped. The one thing the helper
  // cannot judge is whether the engine key names an engine that exists, so
  // that is settled here against the table that will be asked for it.
  function loadSettings(raw) {
    var reply = root.helperReply(raw)
    var parsed = (reply && reply.settings) ? reply.settings : {}
    root.settings = {
      webSuggestions: parsed.webSuggestions === true,
      searchEngine: Web.hasEngine(parsed.searchEngine) ? parsed.searchEngine : "g",
      fileSearch: parsed.fileSearch !== false,
      fileSearchAlways: parsed.fileSearchAlways !== false,
      clipboardSearch: parsed.clipboardSearch !== false,
      clipboardSearchAlways: parsed.clipboardSearchAlways !== false,
      learningEnabled: parsed.learningEnabled !== false,
      maxResults: isFinite(parsed.maxResults)
        ? Util.clamp(parsed.maxResults, 8, root.maxGlobalResults) : 20,
      maxApps: isFinite(parsed.maxApps)
        ? Util.clamp(parsed.maxApps, 3, root.maxAppRows) : 8,
      maxSuggestions: isFinite(parsed.maxSuggestions)
        ? Util.clamp(parsed.maxSuggestions, 0, 8) : 4,
      setupCompleted: parsed.setupCompleted !== false
    }
    // First run: the flag usually lands after open() has already drawn the
    // search card, so the tour is raised from here as well.
    if (root.opened && !root.tourActive && root.settings.setupCompleted === false)
      root.resumeTour()
    // resumeTour has just read the binding when the launcher is open; only
    // a closed launcher needs a read of its own.
    if (root.settings.setupCompleted === false && !root.autoBindDone && !root.tourActive)
      root.readBinding()
  }

  // ------------------------------------------------------------- providers
  function row(spec) {
    return {
      key: String(spec.key || "").slice(0, 2048),
      kind: String(spec.kind || "noop").slice(0, 32),
      title: String(spec.title || "").slice(0, root.maxTitleChars),
      subtitle: String(spec.subtitle || "").slice(0, root.maxSubtitleChars),
      section: String(spec.section || "").slice(0, root.maxTitleChars),
      accessory: String(spec.accessory || "").slice(0, 128),
      icon: String(spec.icon || "").slice(0, 128),
      image: String(spec.image || "").slice(0, 2048),
      mono: spec.mono === true,
      primaryLabel: spec.primaryLabel || "Open",
      secondaryLabel: spec.secondaryLabel || "",
      confirm: spec.confirm === true,
      keywords: String(spec.keywords || "").slice(0, 2048),
      matchText: String(spec.matchText || ""),
      resultType: String(spec.resultType || "intent"),
      stableId: String(spec.stableId || "").slice(0, 512),
      textMatch: isFinite(spec.textMatch) ? Number(spec.textMatch) : -1,
      recencyBonus: 0,
      frequencyBonus: 0,
      contextBonus: 0,
      tieRank: isFinite(spec.tieRank) ? Number(spec.tieRank) : NaN,
      learningMeta: spec.learningMeta || null,
      payload: spec.payload || ({})
    }
  }

  // Calculator, unit conversion, reminders, calendar, URLs and bangs. These
  // are the rows that answer the query directly, so they sort above search.
  function intentRows(q, filter) {
    var out = []

    var calc = (!filter || filter === "calc") ? Calc.evaluate(q) : null
    if (calc) {
      out.push(root.row({
        key: "calc", kind: "copy",
        title: calc.text, subtitle: q.replace(/^=/, "").trim(),
        accessory: "Calculator", icon: "󰃬", mono: true,
        primaryLabel: "Copy result",
        payload: { text: calc.text.replace(/\s/g, "") }
      }))
    }

    var unit = (!filter || filter === "unit") ? Units.convert(q) : null
    if (unit) {
      out.push(root.row({
        key: "unit", kind: "copy",
        title: unit.text, subtitle: unit.detail,
        accessory: "Conversion", icon: "󰑤", mono: true,
        primaryLabel: "Copy result",
        payload: { text: unit.text.replace(/\s/g, "") }
      }))
    }

    var currency = (!unit && (!filter || filter === "unit")) ? Currency.parse(q) : null
    if (currency) {
      var cached = Currency.entry(root.currencySession, currency.key)
      var converted = Currency.result(currency, cached, Date.now(), Units.formatNumber)
      var waiting = currencyDebounce.running || root.currencySession.request !== null
      out.push(root.row({
        key: "currency", kind: converted ? "copy" : "noop",
        title: converted ? converted.text : (waiting ? "Loading exchange rate…" : "Exchange rate unavailable"),
        subtitle: converted ? converted.detail : currency.base + " → " + currency.quote + " · Frankfurter",
        accessory: "Currency", section: "Conversions", icon: "󰑤", mono: true,
        primaryLabel: converted ? "Copy result" : "",
        payload: converted ? { text: converted.copy } : ({})
      }))
    }

    var reminderText = filter === "reminder" ? "reminder " + q : q
    var reminder = (!filter || filter === "reminder")
      ? NaturalTime.parseReminder(reminderText) : null
    if (reminder && !reminder.needsTime && reminder.message) {
      out.push(root.row({
        key: "reminder.create", kind: "reminder",
        title: reminder.message,
        subtitle: "Notify " + reminder.label + " · in " + NaturalTime.formatDuration(reminder.minutes),
        accessory: "Reminder", icon: "󰢌",
        primaryLabel: "Set reminder",
        payload: { minutes: reminder.minutes, message: reminder.message }
      }))
    } else if (reminder && reminder.needsTime) {
      out.push(root.row({
        key: "reminder.hint", kind: "noop",
        title: reminder.message || "Set a reminder",
        subtitle: "Add a time — “in 20m”, “at 15:30”, “tomorrow at 9”",
        accessory: "Needs a time", icon: "󰢌",
        primaryLabel: ""
      }))
    }

    var eventText = filter === "calendar" ? "event " + q : q
    var event = (!filter || filter === "calendar") ? NaturalTime.parseEvent(eventText) : null
    if (event) {
      out.push(root.row({
        key: "event.create", kind: "event",
        title: event.title,
        subtitle: event.label + " · " + (event.allDay ? "All day" : NaturalTime.formatDuration(event.durationMinutes)),
        accessory: "Calendar", icon: "󰸗",
        primaryLabel: "Add to Google Calendar",
        secondaryLabel: "Save .ics file",
        payload: {
          title: event.title,
          allDay: event.allDay === true,
          // An all-day event travels as a plain date on both sides; DTEND and
          // the Google range are exclusive, which is why end is the next day.
          start: event.allDay ? NaturalTime.toDateBasic(event.start) : NaturalTime.toUtcBasic(event.start),
          end: event.allDay ? NaturalTime.toDateBasic(event.end) : NaturalTime.toUtcBasic(event.end),
          stamp: NaturalTime.toUtcBasic(event.start)
        }
      }))
    }

    var url = (!filter || filter === "web") ? Web.detectUrl(q) : ""
    if (url) {
      out.push(root.row({
        key: "url.open", kind: "url",
        title: url.replace(/^https?:\/\//, ""), subtitle: url,
        accessory: "Web", icon: "󰖟",
        primaryLabel: "Open in browser",
        payload: { url: url }
      }))
    }

    for (var i = 0; i < out.length; i++) out[i].textMatch = Fuzzy.MATCH_EXACT
    return out
  }

  // A bare bang is a prefix, not a sigil — "gh quickshell" is a GitHub search.
  // That makes it a trap for any application whose name starts with an engine
  // key and carries a space, "docker desktop" being the obvious one, so the
  // bang row is built here and pushed below the applications rather than
  // taking the cursor off them.
  function bangRows(q) {
    var bang = Web.bang(q)
    if (!bang) return []
    // "tr … to german" drops the target off the end of the query, so the row has
    // to show what is actually going to be translated and where it is going.
    var target = bang.key === "tr" ? Web.translation(bang.query) : null
    var text = target ? target.text : bang.query
    var label = target ? "Translate to " + target.name : "Search " + bang.engine.name
    return [root.row({
      key: "bang." + bang.key, kind: "url",
      title: text, subtitle: label,
      accessory: "Web", icon: bang.engine.icon,
      primaryLabel: label,
      matchText: text,
      resultType: "web",
      payload: { url: Web.searchUrl(bang.query, bang.key) }
    })]
  }

  // Matching always runs through Apps.js, with or without an AppLibrary -
  // AppLibrary.sortedEntries() folds a desktop entry's raw, unsanitised id
  // into its own search text (services/AppSearch.js, upstream Omarchy), and
  // a browser-installed web app's id is a generated, meaningless string
  // that leaked into unrelated results (see lib/Apps.js's header for the
  // real bug this traces back to). AppLibrary is still the sole authority
  // on which entries are hidden, though - isHiddenEntry combines two
  // separate hiding rules Spotlight has no other way to read, so it is
  // passed through as a callback rather than re-derived here. Without an
  // AppLibrary, root.appHides (this plugin's own packaged-hides read) is
  // the only hiding source there is.
  function appEntries(q) {
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { return [] }
    var hidden = root.appLibrary
      ? function(entry) { return root.appLibrary.isHiddenEntry(entry) }
      : root.appHides
    return Apps.sortedEntries(values, q, hidden,
      root.maxAppCandidates, root.maxAppCandidates * 8)
  }

  function appName(entry) {
    return root.appLibrary ? root.appLibrary.entryName(entry) : Apps.entryName(entry)
  }

  function appSubtext(entry) {
    return root.appLibrary ? root.appLibrary.entrySubtext(entry) : Apps.entrySubtext(entry)
  }

  // AppLibrary keeps its own index of icons installed after the shell started,
  // because this process's themed-icon cache never re-scans. Without it, the
  // themed lookup is what there is, and an app installed since login falls
  // back to the generic icon rather than showing none.
  function appIcon(icon) {
    if (root.appLibrary) return root.appLibrary.iconSource(icon)
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  // The launch Omarchy itself performs, minus its OSD: gtk-launch resolves the
  // desktop id — including ids with spaces and ones UWSM rejects — and
  // uwsm-app puts the app under app-graphical.slice rather than leaving it a
  // child of the shell's own unit.
  function launchApp(appId, name) {
    if (root.appLibrary) {
      root.appLibrary.launch(appId, name)
      return
    }
    var id = String(appId || "")
    if (!id) return
    Util.execArgv(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
  }

  function appRows(q, learnedOnly) {
    var entries = root.appEntries(q)
    var limit = q ? Util.clamp(root.settings.maxApps, 3, root.maxAppRows) : root.maxAppCandidates
    var out = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i].entry
      var key = "app:" + String(entry.id || "")
      if (learnedOnly && !Frecency.hasItem(root.usage, key)) continue
      out.push(root.row({
        key: key,
        kind: "app",
        title: root.appName(entry),
        subtitle: root.appSubtext(entry),
        accessory: "App",
        image: root.appIcon(entry.icon),
        primaryLabel: "Open",
        keywords: Apps.entrySearchText(entry),
        resultType: "app",
        stableId: key,
        payload: { appId: String(entry.id || ""), name: root.appName(entry) }
      }))
      if (out.length >= limit) break
    }
    return out
  }

  // Open windows, so "switch to that Slack window" is one query away.
  function windowRows(q, learnedOnly) {
    var candidates = []
    var values = []
    try { values = ToplevelManager.toplevels.values || [] } catch (e) { return [] }

    for (var i = 0; i < values.length && i < root.maxWindowCandidates; i++) {
      var t = values[i]
      if (!t) continue
      var title = String(t.title || "").slice(0, root.maxTitleChars)
      var appId = String(t.appId || "").slice(0, 256)
      if (!title && !appId) continue
      var stableId = appId ? "window:" + appId : ""
      if (learnedOnly && !Frecency.hasItem(root.usage, stableId)) continue
      candidates.push({
        title: title || appId,
        subtitle: appId,
        keywords: "window switch focus " + appId,
        stableId: stableId,
        toplevel: t
      })
    }

    var ranked = Fuzzy.rank(candidates, q, root.maxGlobalResults)
    var out = []
    for (var j = 0; j < ranked.length; j++) {
      out.push(root.row({
        key: "win:" + ranked[j].subtitle + ":" + ranked[j].title,
        kind: "window",
        title: ranked[j].title, subtitle: ranked[j].subtitle,
        accessory: "Window", icon: "󰖯",
        primaryLabel: "Focus window",
        secondaryLabel: "Close window",
        keywords: ranked[j].keywords,
        resultType: "window",
        stableId: ranked[j].stableId,
        payload: { toplevel: ranked[j].toplevel }
      }))
    }
    return out
  }

  function commandRows(q, actionsOnly, learnedOnly) {
    var catalogue = Commands.commands().concat(Commands.quicklinks()).concat(root.menuCommands)
    if (actionsOnly) catalogue = catalogue.filter(function(c) { return c.kind !== "url" })
    if (learnedOnly) catalogue = catalogue.filter(function(c) {
      return c.kind !== "url" && Frecency.hasItem(root.usage, "action:" + c.key)
    })
    var ranked = Fuzzy.rank(catalogue, q, root.maxAppCandidates)

    var out = []
    for (var j = 0; j < ranked.length && j < root.maxAppCandidates; j++) {
      var c = ranked[j]
      var isWeb = c.kind === "url"
      out.push(root.row({
        key: "cmd:" + c.key,
        kind: c.kind,
        title: c.title, subtitle: c.subtitle,
        accessory: isWeb ? "Web" : "Action",
        icon: c.icon,
        primaryLabel: isWeb ? "Open in browser" : "Run",
        confirm: c.confirm === true,
        keywords: c.keywords,
        resultType: isWeb ? "web" : "action",
        stableId: isWeb ? "" : "action:" + c.key,
        payload: {
          argv: c.argv || [], id: c.id || "", url: c.url || "",
          stateId: c.state || ""
        }
      }))
    }
    return out
  }

  // A tldr page keeps its own order: every row scores as an exact match, so
  // ranking falls through to tieRank, which is the position on the page.
  function tldrResultRows() {
    var page = root.tldrPage
    if (!page) return []
    var out = []
    function push(spec) {
      spec.accessory = "tldr"
      spec.section = spec.section || "Command help"
      spec.textMatch = Fuzzy.MATCH_EXACT
      spec.tieRank = out.length
      out.push(root.row(spec))
    }
    if (page.found !== true) {
      push({ key: "tldr.none", kind: "noop", icon: "󰋼", primaryLabel: "",
             title: "No tldr page for “" + page.page + "”" })
      return out
    }
    push({ key: "tldr.head", kind: "noop", icon: "󰋼", primaryLabel: "",
           title: page.title, subtitle: page.description })
    var examples = page.examples
    for (var i = 0; i < examples.length; i++) {
      // Each example sits under its own description heading, so the row is the command alone.
      push({ key: "tldr.ex:" + i, kind: "copy", icon: "󰆍", mono: true,
             section: examples[i].description, title: examples[i].command,
             primaryLabel: "Copy command", secondaryLabel: "Open in terminal",
             payload: { text: examples[i].command } })
    }
    if (page.url) push({ key: "tldr.url", kind: "url", icon: "󰖟", section: "More information",
                         title: page.url, payload: { url: String(page.url) } })
    return out
  }

  function clipboardSearchTarget(q) {
    if (!root.settings.clipboardSearch) return null
    var parsed = Query.parse(q)
    if (parsed.filter === "clipboard")
      return parsed.empty ? null : { pattern: parsed.text, explicit: true }
    if (parsed.filter) return null
    if (root.settings.clipboardSearchAlways && parsed.text.length >= 2)
      return { pattern: parsed.text, explicit: false }
    return null
  }

  // Only the one-line titles are held here. A clipboard history is the last
  // thing that should be resident in a process that outlives the query — it is
  // where tokens and passwords end up — so the bodies stay on disk and the
  // helper pipes the chosen one straight into wl-copy without it ever crossing
  // back into the shell.
  function clipboardResultRows(q) {
    var target = root.clipboardSearchTarget(q)
    if (!target || root.clipboardFor !== String(q || "").trim()) return []
    var ranked = Fuzzy.rank(root.clipboardRows, target.pattern, root.maxClipboardRows)
    var out = []
    for (var i = 0; i < ranked.length; i++) {
      out.push(root.row({
        key: "clip:" + ranked[i].index,
        kind: "clipcopy",
        title: ranked[i].title, subtitle: "",
        accessory: "Clipboard", icon: "󰅌", mono: true,
        primaryLabel: "Copy to clipboard",
        matchText: target.pattern,
        resultType: "clipboard",
        payload: { index: ranked[i].index, title: ranked[i].title }
      }))
    }
    return out
  }

  function reminderListRows(q) {
    if (!/^reminders?$/i.test(String(q || "").trim())) return []
    if (root.reminderRows.length === 0) {
      return [root.row({
        key: "reminder.none", kind: "noop",
        title: "No active reminders", subtitle: "Try “remind me in 20m to …”",
        accessory: "", icon: "󰢌", primaryLabel: "",
        textMatch: Fuzzy.MATCH_EXACT
      })]
    }
    var out = []
    for (var i = 0; i < root.reminderRows.length && i < root.maxReminderRows; i++) {
      var r = root.reminderRows[i]
      out.push(root.row({
        key: "reminder.active." + i,
        kind: "noop",
        title: String(r.label || ""),
        subtitle: "in " + String(r.remaining || "") + " · at " + String(r.atTime || ""),
        accessory: "Reminder", icon: "󰔟", primaryLabel: "",
        textMatch: Fuzzy.MATCH_EXACT
      }))
    }
    out.push(root.row({
      key: "reminder.clear", kind: "shell",
      title: "Clear all reminders", subtitle: root.reminderRows.length + " active",
      accessory: "Action", icon: "󰩹",
      primaryLabel: "Clear", resultType: "action", stableId: "action:reminder.clear",
      payload: { argv: ["omarchy", "reminder", "clear"] }
    }))
    return out
  }

  function fileResultRows(q) {
    // Results arrive asynchronously. Do not show the previous file query while
    // the helper is still answering the current one.
    if (root.fileFor !== String(q || "").trim() || root.fileRows.length === 0) return []
    var target = root.fileSearchTarget(q)
    if (!target) return []
    var limit = target.implicit
      ? Math.min(root.maxUnifiedFileRows, Math.max(1, Math.floor(root.settings.maxResults / 2)))
      : root.maxFileRows
    var out = []
    for (var i = 0; i < root.fileRows.length && i < limit; i++) {
      var f = root.fileRows[i]
      out.push(root.row({
        key: "file:" + f.path,
        kind: "file",
        title: f.name, subtitle: f.dir,
        accessory: f.isDir ? "Folder" : "File",
        icon: f.isDir ? "󰉋" : "󰈔",
        primaryLabel: "Open",
        secondaryLabel: "Open folder",
        matchText: target.pattern,
        resultType: "file",
        stableId: f.id ? "file:" + f.id : "",
        tieRank: i,
        learningMeta: { path: f.path, name: f.name, dir: f.dir, isDir: f.isDir },
        payload: { path: f.path, dir: f.dir }
      }))
    }
    return out
  }

  function learnedFileRows() {
    var out = []
    var items = root.usage && root.usage.items ? root.usage.items : ({})
    var ids = Object.keys(items)
    for (var i = 0; i < ids.length; i++) {
      var entry = items[ids[i]]
      var f = entry && entry.meta
      if (ids[i].indexOf("file:") !== 0 || !f || !f.path) continue
      out.push(root.row({
        key: "idle:" + ids[i], kind: "file",
        title: f.name, subtitle: f.dir,
        accessory: f.isDir ? "Folder" : "File",
        icon: f.isDir ? "󰉋" : "󰈔",
        primaryLabel: "Open", secondaryLabel: "Open folder",
        resultType: "file", stableId: ids[i], textMatch: 0,
        learningMeta: f, payload: { path: f.path, dir: f.dir }
      }))
    }
    return out
  }

  // Ranks one source on its own and keeps the head, so a cap selects the best
  // rows of that section rather than whichever ones the catalogue listed first.
  function idleSlice(list, limit) {
    return root.globallyRank(list, "").slice(0, limit)
  }

  function idleRows() {
    var fallback = root.appRows("", false)
    var learned = root.settings.learningEnabled && root.usage && root.usage.items
      && Object.keys(root.usage.items).length > 0
    var apps = learned ? root.idleSlice(root.appRows("", true), root.idleAppRows) : []
    // Top up from the catalogue until the section is full, so a fresh install
    // still opens on a usable list rather than an empty one.
    for (var i = 0; i < fallback.length && apps.length < root.idleAppRows; i++) {
      if (!learned || !Frecency.hasItem(root.usage, fallback[i].stableId)) apps.push(fallback[i])
    }
    if (!learned) return apps
    return apps
      .concat(root.idleSlice(root.commandRows("", true, true), root.idleCommandRows))
      .concat(root.idleSlice(root.learnedFileRows(), root.idleFileRows))
      .concat(root.idleSlice(root.windowRows("", true), root.idleWindowRows))
  }

  function suggestionResultRows(q) {
    if (root.suggestionRows.length === 0) return []
    var needle = Query.parse(q).text
    var engine = String(root.settings.searchEngine || "g")
    var out = []
    for (var i = 0; i < root.suggestionRows.length; i++) {
      var s = root.suggestionRows[i]
      out.push(root.row({
        key: "sugg:" + s,
        kind: "url",
        title: s, subtitle: "",
        accessory: "Web",
        icon: Web.engineIcon(engine),
        primaryLabel: "Search " + Web.engineName(engine),
        matchText: needle,
        resultType: "web",
        payload: { url: Web.searchUrl(s, engine) }
      }))
    }
    return out
  }

  function webFallbackRows(q) {
    if (!q) return []
    if (Web.detectUrl(q)) return []
    var engine = String(root.settings.searchEngine || "g")
    return [root.row({
      key: "web.fallback", kind: "url",
      title: "Search " + Web.engineName(engine) + " for “" + q + "”",
      subtitle: "",
      accessory: "Web",
      icon: Web.engineIcon(engine),
      primaryLabel: "Search " + Web.engineName(engine),
      resultType: "web",
      textMatch: Fuzzy.MATCH_RESIDUAL,
      payload: { url: Web.searchUrl(q, engine) }
    })]
  }

  function filterHintRow(parsed) {
    return root.row({
      key: "filter.hint", kind: "noop",
      title: "Type a search after “" + parsed.raw + "”",
      subtitle: "This filter searches " + parsed.filter + " results only",
      accessory: "Hint", icon: "󰋼", primaryLabel: "",
      textMatch: Fuzzy.MATCH_EXACT
    })
  }

  function globallyRank(list, q) {
    var now = Date.now()
    var context = Query.contextKey(Query.parse(root.query))
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (row.textMatch < 0) {
        var matched = Fuzzy.score(row, row.matchText || q)
        row.textMatch = matched >= 0 ? matched : Fuzzy.MATCH_RESIDUAL
      }
      var bonus = Frecency.bonuses(root.usage, row.stableId, context, now,
        root.settings.learningEnabled)
      row.recencyBonus = bonus.recency
      row.frequencyBonus = bonus.frequency
      row.contextBonus = bonus.context
    }
    var limit = Util.clamp(root.settings.maxResults, 8, root.maxGlobalResults)
    return Ranking.rank(list, limit)
  }

  function resultSection(row) {
    if (!row || row.key === "filter.hint") return ""
    if (row.section) return row.section
    if (row.resultType === "app") return "Applications"
    if (row.resultType === "window") return "Windows"
    if (row.resultType === "action") return "Commands"
    if (row.resultType === "file") return "Files"
    if (row.resultType === "clipboard") return "Clipboard"
    if (row.resultType === "web") return "Web"
    if (row.kind === "event") return "Calendar"
    if (row.key.indexOf("reminder.") === 0) return "Reminders"
    if (row.key === "calc") return "Calculator"
    if (row.key === "unit") return "Conversions"
    if (row.kind === "url") return "Direct links"
    return "Results"
  }

  // ------------------------------------------------------------- assembly
  function rebuild() {
    var q = String(root.query || "").trim()
    var parsed = Query.parse(q)

    var next = []
    function push(list) { for (var i = 0; i < list.length; i++) next.push(list[i]) }

    if (parsed.empty) {
      next.push(root.filterHintRow(parsed))
    } else if (parsed.filter) {
      var searchable = parsed.text.length >= 2
      if (parsed.filter === "app" && searchable) push(root.appRows(parsed.text))
      else if (parsed.filter === "window" && searchable) push(root.windowRows(parsed.text))
      else if (parsed.filter === "file") push(root.fileResultRows(q))
      else if (parsed.filter === "action" && searchable) push(root.commandRows(parsed.text, true))
      else if (parsed.filter === "clipboard") push(root.clipboardResultRows(q))
      else if (parsed.filter === "tldr") push(root.tldrResultRows())
      else if (parsed.filter === "web") {
        push(root.intentRows(parsed.text, "web"))
        push(root.bangRows(parsed.text))
        push(root.suggestionResultRows(q))
        push(root.webFallbackRows(parsed.text))
      } else if (parsed.filter === "calc" || parsed.filter === "unit"
          || parsed.filter === "reminder" || parsed.filter === "calendar") {
        push(root.intentRows(parsed.text, parsed.filter))
      }
    } else if (!q) {
      push(root.idleRows())
    } else {
      push(root.intentRows(q, ""))
      push(root.reminderListRows(q))
      if (q.length >= 2) {
        push(root.appRows(q))
        push(root.windowRows(q))
        push(root.commandRows(q, false))
        push(root.fileResultRows(q))
        push(root.clipboardResultRows(q))
      }
      push(root.bangRows(q))
      push(root.suggestionResultRows(q))
      push(root.webFallbackRows(q))
    }

    next = root.globallyRank(next, parsed.text)
    root.rows = next

    displayModel.clear()
    for (var j = 0; j < next.length; j++) {
      var r = next[j]
      displayModel.append({
        rowIndex: j,
        rowTitle: r.title,
        rowSubtitle: r.subtitle,
        rowAccessory: r.accessory,
        rowIcon: r.icon,
        rowImage: r.image,
        rowMono: r.mono,
        rowSection: root.resultSection(r),
        rowState: (r.payload && r.payload.stateId) ? r.payload.stateId : "",
        selectable: r.kind !== "noop"
      })
    }

    // A deliberate cursor is restored by key, so an async refresh cannot move
    // it. Everything else follows the top row on every single rebuild: a key
    // that outlives the query it was built for — the web-search fallback, a
    // suggestion still on screen while its replacement is in flight — must
    // never inherit the cursor and turn the next Enter into a web search.
    var restored = root.pinnedKey ? root.indexOfKey(root.pinnedKey) : -1
    if (root.pinnedKey && restored < 0) root.pinnedKey = ""
    root.selectedIndex = restored >= 0 ? restored : root.firstSelectableIndex()
    root.cursorActive = next.length > 0
    pointerGate.reset()
    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function selectedRowKey() {
    var r = root.rows[root.selectedIndex]
    return r ? r.key : ""
  }

  function indexOfKey(key) {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].key === key) return i
    return -1
  }

  function firstSelectableIndex() {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].kind !== "noop") return i
    return 0
  }

  function selectedRow() {
    return root.rows[root.selectedIndex] || null
  }

  // Only a pointer that actually moved may move the cursor, and not while the
  // keyboard is still mid-thought. The card animates its height as rows
  // arrive, so a pointer resting anywhere over the list has rows sliding under
  // it on every keystroke; hover winning that race is how "stea" ends up
  // selecting a web suggestion instead of Steam.
  function selectFromPointer(index, item, mouse) {
    if (typingGuard.running) return
    if (!root.rows[index] || root.rows[index].kind === "noop") return
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
    root.pinnedKey = root.selectedRowKey()
    root.armedKey = ""
  }

  // Steps over "noop" rows (hints, reminder listings) so the cursor only ever
  // rests somewhere Enter means something.
  function select(delta) {
    var count = root.rows.length
    if (count === 0) return
    var index = root.selectedIndex
    for (var step = 0; step < count; step++) {
      index = (index + delta + count) % count
      if (root.rows[index] && root.rows[index].kind !== "noop") break
    }
    root.selectedIndex = index
    root.pinnedKey = root.selectedRowKey()
    root.cursorActive = true
    root.armedKey = ""
    pointerGate.reset()
    resultList.positionViewAtIndex(index, ListView.Contain)
  }

  function selectPage(delta) {
    var count = root.rows.length
    if (count === 0) return
    var visible = Math.max(1, Math.floor(resultList.height / root.rowHeight))
    var index = Math.max(0, Math.min(count - 1, root.selectedIndex + delta * visible))
    while (index >= 0 && index < count && root.rows[index] && root.rows[index].kind === "noop")
      index += delta > 0 ? 1 : -1
    if (index < 0 || index >= count) index = delta > 0 ? count - 1 : 0
    root.selectedIndex = index
    root.pinnedKey = root.selectedRowKey()
    root.cursorActive = true
    root.armedKey = ""
    pointerGate.reset()
    resultList.positionViewAtIndex(index, ListView.Contain)
  }

  // ------------------------------------------------------------- actions
  function openUrl(url) {
    if (!url) return
    Util.execArgv(["omarchy-launch-browser", String(url)])
  }

  function openPath(path) {
    var target = String(path || "")
    if (!target) {
      console.warn("spotlight: refusing to open an empty path")
      return
    }
    if (openProc.running) {
      console.warn("spotlight: file opener is already running; skipped:", target)
      return
    }
    openProc.target = target
    openProc.command = ["gio", "open", target]
    openProc.running = true
  }

  // Enter comes through here rather than going straight at selectedIndex.
  // With no deliberate cursor the intent is always "the best row for what I
  // typed", and resolving that at the keystroke closes the window between a
  // rebuild landing and the cursor settling onto it.
  // The path a Ctrl+C would copy, or "" when the selected row has none. A
  // folder copies as its own path, not its parent's.
  function copyPathTarget() {
    var r = root.selectedRow()
    return (r && r.resultType === "file" && r.payload && r.payload.path)
      ? String(r.payload.path) : ""
  }

  function copySelectedPath() {
    var path = root.copyPathTarget()
    if (path === "") return
    root.dismiss()
    // wl-copy over argv, never a shell string: the path is user data.
    Util.execArgv(["wl-copy", "--", path])
  }

  function activateSelection(secondary) {
    root.activate(root.pinnedKey ? root.selectedIndex : root.firstSelectableIndex(), secondary)
  }

  // The switch moves immediately and the probe confirms it after the detached
  // command has had time to finish.
  function flipToggle(r) {
    var id = r.payload.stateId
    var on = root.toggleStates[id] === true
    var argv = r.payload.argv
    if (!Array.isArray(argv) || argv.length === 0) return
    Util.execArgv(argv)
    var next = ({})
    for (var k in root.toggleStates) next[k] = root.toggleStates[k]
    next[id] = !on
    root.toggleStates = next
    toggleReconcile.restart()
  }

  function activate(index, secondary) {
    var r = root.rows[index]
    if (!r || r.kind === "noop") return

    // One confirmation for the rows that end the session.
    if (r.confirm && !secondary && root.armedKey !== r.key) {
      root.armedKey = r.key
      return
    }
    root.armedKey = ""
    if (!secondary && r.kind !== "spotlight-reset") root.bumpUsage(r)

    switch (r.kind) {
    case "app":
      root.dismiss()
      root.launchApp(r.payload.appId, r.payload.name)
      break

    case "shell":
      // A toggle row keeps the panel open: its switch is the only feedback the
      // press produces, and closing over it would hide exactly that.
      if (r.payload.stateId && root.toggleStates[r.payload.stateId] !== undefined) {
        root.flipToggle(r)
        break
      }
      root.dismiss()
      // execArgv, not execDetached: the catalogue holds argv vectors rather
      // than command lines, so nothing here is ever re-tokenized by a shell.
      if (Array.isArray(r.payload.argv) && r.payload.argv.length > 0)
        Util.execArgv(r.payload.argv)
      break

    case "url":
      root.dismiss()
      root.openUrl(r.payload.url)
      break

    case "summon":
      root.dismiss()
      if (root.shell && typeof root.shell.summon === "function")
        root.shell.summon(r.payload.id, "{}")
      break

    case "copy":
      root.dismiss()
      // wl-copy over argv, never a shell string: the text is user data.
      // Shift+Enter, on rows that offer it, puts the text on a terminal prompt
      // unexecuted: bash gets it as $1 and the rc file moves it onto readline.
      if (secondary && r.secondaryLabel)
        Util.execArgv(["omarchy-launch-terminal", "bash", "--rcfile",
          root.pluginFolder + "/bin/spotlight-prefill.bash", "-s", "--", String(r.payload.text || "")])
      else Util.execArgv(["wl-copy", "--", String(r.payload.text || "")])
      break

    case "clipcopy":
      root.dismiss()
      // The body was never loaded, so the helper is told which entry to copy
      // rather than what to copy. It re-reads the history under the same
      // bounds, re-identifies the row by the title the user actually saw — the
      // list may have shifted since — and pipes it to wl-copy itself.
      clipCopyProc.running = false
      clipCopyProc.command = root.helperArgv([
        "clipboard-copy", String(r.payload.index), String(r.payload.title || "")])
      clipCopyProc.running = true
      break

    case "reminder":
      root.dismiss()
      Util.execArgv(["omarchy-reminder", String(r.payload.minutes), String(r.payload.message || "")])
      break

    case "event":
      root.dismiss()
      if (secondary) root.saveIcs(r.payload)
      else root.openUrl("https://calendar.google.com/calendar/render?action=TEMPLATE"
        + "&text=" + encodeURIComponent(r.payload.title)
        + "&dates=" + r.payload.start + "/" + r.payload.end)
      break

    case "window":
      root.dismiss()
      try {
        if (secondary) r.payload.toplevel.close()
        else r.payload.toplevel.activate()
      } catch (e) {
        console.warn("spotlight: window action failed:", e)
      }
      break

    case "file":
      root.dismiss()
      if (secondary) root.openPath(r.payload.dir)
      else root.openPath(r.payload.path)
      break

    case "spotlight-settings":
      root.dismiss()
      maintenanceProc.running = false
      maintenanceProc.action = "settings"
      maintenanceProc.command = root.helperArgv(["ensure-settings"])
      maintenanceProc.running = true
      break

    case "spotlight-plugin":
      root.dismiss()
      root.openPath(root.pluginFolder)
      break

    case "spotlight-tour":
      root.showTour(0, false)
      break

    case "spotlight-shortcut":
      root.showTour(1, true)
      break

    case "spotlight-data":
      root.dismiss()
      maintenanceProc.running = false
      maintenanceProc.action = "data"
      maintenanceProc.command = root.helperArgv(["ensure-data"])
      maintenanceProc.running = true
      break

    case "spotlight-reset":
      root.dismiss()
      root.pendingUsage = ""
      usageReadProc.running = false
      usageWriteProc.running = false
      maintenanceProc.running = false
      maintenanceProc.action = "reset"
      maintenanceProc.command = root.helperArgv(["reset-usage"])
      maintenanceProc.running = true
      break
    }
  }

  // Writes the event as an .ics next to the user's downloads and hands it to
  // the desktop.
  //
  // The path is predictable, which is the whole problem with writing one: a
  // shell redirect follows whatever symlink is already sitting at that name,
  // so anything able to drop a file in ~/Downloads first picks the target. The
  // helper creates the file O_EXCL|O_NOFOLLOW relative to a directory
  // descriptor it has verified it owns, so an existing name — symlink or not —
  // is stepped over rather than written through, and it reports back the path
  // it actually used.
  function saveIcs(payload) {
    var stamp = String(payload.stamp || payload.start).replace(/[^0-9TZ]/g, "").slice(0, 32)
    if (!stamp) return
    // DTSTAMP is always an instant; only the event's own bounds go date-only.
    var dateOnly = payload.allDay ? ";VALUE=DATE" : ""
    var ics = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Omarchy//Spotlight//EN",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:spotlight-" + stamp + "@omarchy",
      "DTSTAMP:" + stamp,
      "DTSTART" + dateOnly + ":" + payload.start,
      "DTEND" + dateOnly + ":" + payload.end,
      "SUMMARY:" + String(payload.title).replace(/([,;\\])/g, "\\$1").slice(0, 400),
      "END:VEVENT",
      "END:VCALENDAR",
      ""
    ].join("\r\n")

    icsProc.running = false
    icsProc.stdinEnabled = true
    icsProc.command = root.helperArgv(["write-ics", stamp])
    icsProc.running = true
    icsProc.write(ics)
    icsProc.stdinEnabled = false
  }

  // ------------------------------------------------------------- async data
  function loadSuggestions(raw, forQuery) {
    if (forQuery !== String(root.query || "").trim()) return
    var reply = root.helperReply(raw)
    var list = (reply && Array.isArray(reply.suggestions)) ? reply.suggestions : []
    var limit = Util.clamp(root.settings.maxSuggestions, 0, 8)
    var lower = forQuery.toLowerCase()
    var out = []
    var seen = Object.create(null)
    for (var i = 0; i < list.length && out.length < limit; i++) {
      var text = String(list[i] || "").trim()
      if (!text) continue
      var k = text.toLowerCase()
      if (k === lower || seen[k]) continue
      seen[k] = true
      out.push(text)
    }
    root.suggestionRows = out
    root.suggestionFor = forQuery
    root.rebuild()
  }

  function fileSearchTarget(q) {
    var s = String(q || "").trim()
    var parsed = Query.parse(s)
    if (parsed.filter === "file")
      return parsed.empty ? null : { pattern: parsed.text, dir: root.home, explicit: true }
    if (parsed.filter) return null
    if (/^~\//.test(s) || /^\//.test(s)) {
      var slash = s.lastIndexOf("/")
      var dir = s.slice(0, slash + 1).replace(/^~/, root.home)
      var pattern = s.slice(slash + 1)
      return { pattern: pattern || ".", dir: dir, explicit: false }
    }
    // With no keyword and no path, files are still one provider among many —
    // that is the whole point of fileSearchAlways — so this match is neither
    // explicit (it does not scope the results to files only) nor treated like
    // one for the web-suggestions guard below (it did not ask for files, it
    // just also got them).
    if (root.settings.fileSearchAlways && s.length >= 2) {
      return { pattern: s, dir: root.home, explicit: false, implicit: true }
    }
    return null
  }

  function loadFiles(raw, forQuery) {
    if (forQuery !== String(root.query || "").trim()) return
    var reply = root.helperReply(raw)
    var list = (reply && Array.isArray(reply.files)) ? reply.files : []
    var target = root.fileSearchTarget(forQuery)
    var candidates = []
    for (var i = 0; i < list.length; i++) {
      var f = list[i]
      if (!f || !f.path) continue
      candidates.push({
        id: String(f.id || ""),
        path: String(f.path),
        name: String(f.name || ""),
        dir: String(f.dir || "/"),
        isDir: f.isDir === true
      })
    }
    // Apply the helper's character cutoff before its term cutoff so ranking
    // uses exactly the portion of the pattern fd filtered on.
    var ranked = target
      ? FileRank.rank(candidates, target.pattern.slice(0, root.filePatternChars), target.dir, root.fileMaxTerms)
      : candidates
    var out = ranked.slice(0, root.maxFileRows)
    root.fileRows = out
    root.fileFor = forQuery
    root.rebuild()
  }

  function loadReminders(raw) {
    var reply = root.helperReply(raw)
    var list = (reply && Array.isArray(reply.reminders)) ? reply.reminders : []
    var out = []
    for (var i = 0; i < list.length && out.length < root.maxReminderRows; i++) {
      var r = list[i]
      if (!r) continue
      out.push({
        label: String(r.label || ""),
        remaining: String(r.remaining || ""),
        atTime: String(r.atTime || "")
      })
    }
    root.reminderRows = out
    if (root.opened) root.rebuild()
  }

  function loadClipboard(raw, forQuery) {
    if (forQuery !== String(root.query || "").trim()) return
    var reply = root.helperReply(raw)
    var list = (reply && Array.isArray(reply.items)) ? reply.items : []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      if (!item || typeof item.title !== "string" || !item.title) continue
      out.push({ index: Util.clamp(item.index, 0, 1000), title: item.title })
    }
    root.clipboardRows = out
    root.clipboardFor = forQuery
    if (root.opened) root.rebuild()
  }

  function loadTldr(raw, forQuery) {
    if (forQuery !== String(root.query || "").trim()) return
    root.tldrPage = root.helperReply(raw)
    if (root.opened) root.rebuild()
  }

  function stopCurrencyProcess() {
    var proc = root.currencyProcess
    root.currencyProcess = null
    if (proc) proc.running = false
  }

  function updateCurrency() {
    var parsed = Query.parse(root.query)
    var target = root.opened && (!parsed.filter || parsed.filter === "unit")
      && !Units.convert(parsed.text) ? Currency.parse(parsed.text) : null
    var generation = root.currencySession.generation
    var lookup = Currency.select(root.currencySession, target, Date.now())
    if (generation !== root.currencySession.generation) root.stopCurrencyProcess()
    currencyDebounce.stop()
    if (lookup) currencyDebounce.restart()
  }

  function loadCurrency(raw, request) {
    if (!root.opened) return
    if (Currency.accept(root.currencySession, request, root.helperReply(raw), Date.now())) root.rebuild()
  }

  // Query changes fan out to the async providers on a short debounce so a
  // fast typist does not spawn a process per keystroke.
  onQueryChanged: {
    root.armedKey = ""
    // A new query invalidates a deliberate cursor: the row it named may not
    // even be in the list any more.
    root.pinnedKey = ""
    typingGuard.restart()

    var q = String(root.query || "").trim()
    var parsed = Query.parse(q)
    root.updateCurrency()

    // The clipboard list is fetched while a clipboard query is on screen and
    // dropped the moment it is not, so the titles are resident for the length
    // of the query rather than the length of the session.
    var clipboardTarget = root.clipboardSearchTarget(q)
    if (clipboardTarget) {
      clipboardDebounce.forQuery = q
      clipboardDebounce.restart()
    } else {
      clipboardDebounce.stop()
      if (root.clipboardRows.length > 0) root.clipboardRows = []
      root.clipboardFor = ""
    }

    // Any query change drops the page; loadTldr only stores a reply for the current query.
    root.tldrPage = null
    if (parsed.filter === "tldr" && parsed.text) {
      tldrDebounce.forQuery = q
      tldrDebounce.text = parsed.text
      tldrDebounce.restart()
    } else tldrDebounce.stop()

    var target = root.settings.fileSearch ? root.fileSearchTarget(q) : null
    if (target && target.pattern.length >= 1) {
      fileDebounce.pattern = target.pattern
      fileDebounce.dir = target.dir
      fileDebounce.forQuery = q
      fileDebounce.restart()
    } else {
      fileDebounce.stop()
      if (root.fileRows.length > 0) { root.fileRows = []; root.fileFor = "" }
    }

    // A fileSearchAlways match is passive — the query never asked for files,
    // it just also got them — so unlike an explicit "f " prefix or a typed
    // path, it must not be the thing that silences web suggestions too.
    var suggestionText = parsed.filter === "web" ? parsed.text : q
    var fileSuggestGuard = root.fileSearchTarget(q)
    var wantSuggestions = root.settings.webSuggestions && suggestionText.length >= 2
      && (!parsed.filter || parsed.filter === "web")
      && !Web.detectUrl(suggestionText) && !Web.bang(suggestionText) && !Calc.evaluate(suggestionText)
      && !Currency.parse(suggestionText)
      && !NaturalTime.isReminderQuery(suggestionText) && !NaturalTime.isEventQuery(suggestionText)
      && !(fileSuggestGuard && !fileSuggestGuard.implicit)
    if (wantSuggestions) {
      suggestDebounce.forQuery = q
      suggestDebounce.pattern = suggestionText
      suggestDebounce.restart()
      // Suggestions go stale the moment the query stops being a continuation
      // of the one that fetched them. Keeping the ones the new query still
      // narrows is what stops the list collapsing on every keystroke; dropping
      // the rest is what stops "stea" offering what "ste" asked for.
      if (root.suggestionFor && q.indexOf(root.suggestionFor) !== 0) {
        root.suggestionRows = []
        root.suggestionFor = ""
      }
    } else {
      suggestDebounce.stop()
      if (root.suggestionRows.length > 0) { root.suggestionRows = []; root.suggestionFor = "" }
    }

    // Last, so the rows show the caches this pass just invalidated rather than
    // the ones it is about to.
    root.rebuild()
  }

  // A keystroke owns the cursor for a moment afterwards: long enough to cover
  // the card's height animation and the hover events it generates as rows
  // slide under a stationary pointer, short enough that reaching for the mouse
  // straight after typing still works.
  Timer {
    id: typingGuard
    interval: 400
  }

  Timer {
    id: currencyDebounce
    interval: 250
    onTriggered: {
      if (!root.opened) return
      var request = Currency.begin(root.currencySession)
      if (!request) return
      var proc = currencyProcessComponent.createObject(root, { request: request })
      if (!proc) {
        root.loadCurrency("", request)
        return
      }
      root.currencyProcess = proc
      proc.running = true
    }
  }

  // Each run owns an immutable request token. A cancelled process can finish
  // collecting stdout after a replacement starts without adopting its token.
  Component {
    id: currencyProcessComponent
    Process {
      id: currencyRun
      required property var request
      property bool delivered: false
      command: root.helperArgv(["currency-rate", request.base, request.quote])
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          currencyRun.delivered = true
          root.loadCurrency(text, currencyRun.request)
        }
      }
      onExited: {
        Qt.callLater(function() {
          if (!currencyRun.delivered) root.loadCurrency("", currencyRun.request)
          if (root.currencyProcess === currencyRun) root.currencyProcess = null
          currencyRun.destroy()
        })
      }
    }
  }

  Timer {
    id: suggestDebounce
    interval: 220
    property string forQuery: ""
    property string pattern: ""
    onTriggered: {
      suggestProc.running = false
      suggestProc.forQuery = suggestDebounce.forQuery
      suggestProc.command = root.helperArgv(["suggest", suggestDebounce.pattern])
      suggestProc.running = true
    }
  }

  // The helper builds the endpoint itself and reads it under a byte ceiling
  // and timeout, so neither a slow endpoint nor an oversized response can fill
  // the shell process.
  Process {
    id: suggestProc
    property string forQuery: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadSuggestions(text, suggestProc.forQuery)
    }
  }

  Timer {
    id: fileDebounce
    interval: 160
    property string pattern: ""
    property string dir: ""
    property string forQuery: ""
    onTriggered: {
      fileProc.running = false
      fileProc.forQuery = fileDebounce.forQuery
      fileProc.command = root.helperArgv(["files", fileDebounce.dir, fileDebounce.pattern])
      fileProc.running = true
    }
  }

  // fd is bounded by --max-results, but a result count is not a time bound:
  // a deep or slow tree can keep it walking long after the query is stale.
  // The helper holds an independent wall-clock deadline over it and tears the
  // whole process group down when it expires.
  Process {
    id: fileProc
    property string forQuery: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadFiles(text, fileProc.forQuery)
    }
  }

  Timer {
    id: clipboardDebounce
    interval: 160
    property string forQuery: ""
    onTriggered: {
      clipboardProc.running = false
      clipboardProc.forQuery = clipboardDebounce.forQuery
      clipboardProc.command = root.helperArgv(["read-clipboard"])
      clipboardProc.running = true
    }
  }

  Process {
    id: clipboardProc
    property string forQuery: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadClipboard(text, clipboardProc.forQuery)
    }
  }

  Timer {
    id: tldrDebounce
    interval: 160
    property string text: ""
    property string forQuery: ""
    onTriggered: {
      tldrProc.running = false
      tldrProc.forQuery = tldrDebounce.forQuery
      tldrProc.command = root.helperArgv(["tldr", tldrDebounce.text])
      tldrProc.running = true
    }
  }

  Process {
    id: tldrProc
    property string forQuery: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadTldr(text, tldrProc.forQuery)
    }
  }

  Process { id: clipCopyProc }

  Process {
    id: remindersProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadReminders(text)
    }
  }

  Process {
    id: toggleStatesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadToggleStates(text)
    }
  }

  // One late confirmation pass, not a poll. Night Light's cold start retries
  // for up to two seconds, so probing earlier can capture an intermediate state.
  Timer {
    id: toggleReconcile
    interval: 2500
    onTriggered: root.refreshToggleStates()
  }

  Process {
    id: settingsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadSettings(text)
    }
  }

  Process {
    id: hidesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadHides(text)
    }
  }

  Process {
    id: menuCommandsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadMenuCommands(text)
    }
  }

  Process {
    id: usageReadProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadUsage(text)
    }
  }

  Process {
    id: usageWriteProc
    onExited: root.flushUsage()
  }

  Process {
    id: icsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = root.helperReply(text)
        if (reply && reply.path) root.openPath(reply.path)
      }
    }
  }

  Process {
    id: openProc
    property string target: ""
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("spotlight: gio open failed for", target, "with exit code", exitCode)
    }
  }

  Process {
    id: maintenanceProc
    property string action: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = root.helperReply(text)
        if (!reply) return
        if (maintenanceProc.action === "settings" && reply.path)
          Util.execArgv(["omarchy", "launch", "editor", String(reply.path)])
        else if (maintenanceProc.action === "data" && reply.path)
          root.openPath(reply.path)
        else if (maintenanceProc.action === "reset" && reply.reset === true)
          root.usage = Frecency.emptyStore()
      }
    }
  }

  // Separate from maintenanceProc: a failed write must surface as an error
  // state instead of being swallowed, and a settings write must never cancel
  // an in-flight binding write.
  Process {
    id: bindingProc
    property string action: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = root.helperReply(text)
        if (bindingProc.action === "read") {
          root.loadBinding(reply)
        } else if (!reply) {
          root.bindingState = "error"
        } else {
          bindingReloadProc.action = bindingProc.action
          bindingReloadProc.command = ["hyprctl", "reload"]
          bindingReloadProc.running = true
        }
      }
    }
  }

  Process {
    id: bindingReloadProc
    property string action: ""
    onExited: function(exitCode) {
      root.bindingState = exitCode === 0
        ? (bindingReloadProc.action === "write" ? "ok" : "reverted")
        : "reloadError"
      root.readBinding()
    }
  }

  Process {
    id: settingsWriteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.helperReply(text)) root.loadSettings(text)
    }
  }

  Component.onCompleted: {
    if (root.appLibrary) root.appLibrary.refreshIcons()
    root.refreshSettings()
    root.refreshUsage()
  }

  // Unloading the plugin must not leave a reader behind. Each helper run has
  // its own deadline as a backstop, but the processes are terminated here so
  // teardown does not depend on one.
  Component.onDestruction: {
    root.stopQueryWork()
    clipCopyProc.running = false
    remindersProc.running = false
    settingsProc.running = false
    hidesProc.running = false
    menuCommandsProc.running = false
    usageReadProc.running = false
    usageWriteProc.running = false
    icsProc.running = false
    maintenanceProc.running = false
    bindingProc.running = false
    bindingReloadProc.running = false
    settingsWriteProc.running = false
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.opened) root.rebuild() }
  }

  ListModel { id: displayModel }

  // A stationary pointer must not own the selection. Without this, opening
  // Spotlight with the cursor anywhere over the list hands the highlight to
  // whatever row happens to land under it, so Enter runs the wrong thing.
  PointerMoveGate {
    id: pointerGate
    referenceItem: pointerFrame
  }

  // ------------------------------------------------------------- surface
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    // The Hyprland layer rule that frosts this surface matches on this
    // namespace. Renaming it silently turns the glass off.
    WlrLayershell.namespace: "omarchy-spotlight"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive grabs the compositor's own keyboard input wholesale, so a
    // bind like SUPER+arrow to move focus between windows goes dead while
    // this is open and the overlay never yields. OnDemand still gets typing
    // and Hyprland still focuses it the moment it maps (this window is only
    // ever mapped fresh - `visible` follows `opened` directly, never staying
    // mapped through a fade-out - which is the case Hyprland does grant
    // OnDemand focus for), so nothing here needs the Exclusive-then-OnDemand
    // prime a surface that stays mapped across a close would.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    // Anything that moves focus elsewhere - the compositor's own focus
    // bind, alt-tab, a click on another output - must dismiss the launcher,
    // the way losing focus dismisses Spotlight on macOS. Exclusive used to
    // make this unreachable by construction; OnDemand makes it possible, but
    // needs two different watchers, because Hyprland tracks "who has
    // keyboard input" and "which window is active" separately and neither
    // alone covers every way focus moves:
    //
    // - HyprlandFocusGrab.cleared fires on a click outside `windows`, or
    //   another grab starting (e.g. opening a different Omarchy panel) - per
    //   the hyprland-focus-grab-v1 protocol, that's the whole list. It does
    //   NOT fire for a pure keyboard movefocus (SUPER+arrow): movefocus only
    //   updates Hyprland's *active window* bookkeeping, it does not revoke
    //   keyboard input from an on_demand layer surface, so nothing a grab
    //   watches actually happens (confirmed against Hyprland's own
    //   Actions::moveFocus, and hyprwm/Hyprland#8293/discussion #12663).
    // - Hyprland.activeToplevelChanged is what movefocus *does* touch, so it
    //   is the second watcher below, catching exactly the gap the grab
    //   leaves open.
    // - Switching to a workspace with no windows on it is a third gap on its
    //   own: activeToplevel simply goes to null, and that transition does
    //   not reliably fire activeToplevelChanged (confirmed live - switching
    //   to an empty workspace left the overlay open). Hyprland's own
    //   focused-workspace tracking changes unconditionally on any workspace
    //   switch, windows or not, so it is the third watcher, for exactly the
    //   case the other two both miss.
    HyprlandFocusGrab {
      active: root.opened
      windows: [panel]
      onCleared: if (root.opened) root.dismiss()
    }

    Connections {
      target: Hyprland
      function onActiveToplevelChanged() {
        if (root.opened) root.dismiss()
      }
      function onFocusedWorkspaceChanged() {
        if (root.opened) root.dismiss()
      }
    }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    // A screen-fixed frame for the pointer gate to measure against. The card
    // is the wrong reference: it animates its height and stays centred, so it
    // slides under a stationary pointer on every rebuild and every row that
    // maps into it reads as deliberate movement.
    Item {
      id: pointerFrame
      anchors.fill: parent
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      id: card
      // Hidden items cannot hold focus, which is what keeps keystrokes away
      // from the search input while the tour is up.
      visible: !root.tourActive

      readonly property int listHeight: Math.min(root.maxListHeight, root.contentHeight)
      readonly property bool hasResults: displayModel.count > 0

      width: Math.min(Style.space(750), panel.width - Style.space(48))
      height: root.searchHeight
        + (hasResults ? root.hairline + root.listPadding * 2 + listHeight : 0)
        + root.hairline + root.footerHeight
      // Centred at whatever height it currently is, not just when full. The
      // height Behavior below drives y with it, so the panel grows and
      // shrinks symmetrically about the middle of the screen instead of
      // sitting high whenever a query returns only a few rows.
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter

      radius: root.cardRadius
      color: root.glassBackground
      border.width: root.hairline
      border.color: root.glassBorder
      antialiasing: true

      Behavior on height {
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
      }

      // Swallow clicks so they don't reach the dismiss MouseArea behind.
      MouseArea { anchors.fill: parent; onClicked: {} }

      // ------------------------------------------------------- search row
      Item {
        id: searchRow
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: root.searchHeight

        Text {
          id: searchGlyph
          text: "󰍉"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: root.searchFontSize
          anchors.left: parent.left
          anchors.leftMargin: root.gutter
          anchors.verticalCenter: parent.verticalCenter
        }

        TextInput {
          id: input
          anchors.left: searchGlyph.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: root.gutter
          anchors.verticalCenter: parent.verticalCenter

          color: root.foreground
          selectionColor: Util.alpha(root.accent, 0.35)
          selectedTextColor: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.searchFontSize
          // A query is a line someone typed, and every provider fans out from
          // it — the web fallback interpolates it into a row title, the file
          // search hands it to fd. Bounding it here bounds all of them.
          maximumLength: root.maxQueryChars
          clip: true
          focus: true
          activeFocusOnTab: false
          selectByMouse: true
          inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

          onTextChanged: root.query = text

          Text {
            anchors.fill: parent
            visible: input.text.length === 0
            text: "Search for apps and commands…"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.38
            font.family: input.font.family
            font.pixelSize: input.font.pixelSize
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          // BeforeItem so navigation and activation win over text editing;
          // anything not handled here falls through to normal typing, which
          // keeps Ctrl+V, selection and caret movement intact.
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            typingGuard.restart()
            if (event.key === Qt.Key_Escape) {
              if (input.text.length > 0) input.text = ""
              else root.dismiss()
              event.accepted = true
            } else if (event.key === Qt.Key_Down
                || (event.key === Qt.Key_N && event.modifiers === Qt.ControlModifier)) {
              root.select(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up
                || (event.key === Qt.Key_P && event.modifiers === Qt.ControlModifier)) {
              root.select(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
              root.selectPage(1)
              event.accepted = true
            } else if (event.key === Qt.Key_PageUp) {
              root.selectPage(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              var secondary = (event.modifiers & Qt.ShiftModifier) || (event.modifiers & Qt.ControlModifier)
              root.activateSelection(secondary ? true : false)
              event.accepted = true
            } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)
                && input.selectedText.length === 0 && root.copyPathTarget() !== "") {
              // Ctrl+C on a file result copies its path, the way Cmd+C does in
              // Spotlight. Only when nothing is selected in the query: with a
              // selection this is an ordinary copy and has to stay one.
              root.copySelectedPath()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
              // Tab completes the query with the selected row's title, the way
              // a shell completes a path — handy for narrowing an app search.
              var sel = root.selectedRow()
              if (sel && sel.kind === "app") input.text = sel.title
              event.accepted = true
            }
          }
        }
      }

      // Both dividers stop where a row's highlight stops, so the list reads as
      // one column with two rules across it rather than as three stacked bands.
      Rectangle {
        id: searchDivider
        anchors { top: searchRow.bottom; left: parent.left; right: parent.right }
        anchors.leftMargin: root.listPadding
        anchors.rightMargin: root.listPadding
        height: root.hairline
        color: root.dividerColor
        visible: card.hasResults
      }

      // ------------------------------------------------------- results
      Item {
        anchors {
          top: searchDivider.bottom
          left: parent.left
          right: parent.right
        }
        anchors.topMargin: root.listPadding
        anchors.bottomMargin: root.listPadding
        height: card.listHeight
        visible: card.hasResults

        ListView {
          id: resultList
          anchors.fill: parent
          model: displayModel
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: root.selectedIndex
          highlightMoveDuration: 0
          section.property: "rowSection"
          section.delegate: Item {
            required property string section

            width: resultList.width
            height: section.length > 0 ? root.sectionHeight : 0

            Text {
              text: parent.section
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.left: parent.left
              anchors.leftMargin: root.gutter
              anchors.right: parent.right
              anchors.rightMargin: root.gutter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(3)
            }
          }

          // The delegate root spans the full view width and is left where the
          // view puts it: a vertical ListView positions its delegates itself
          // and overwrites any `x` set here, which would push the whole inset
          // to one side. The padding belongs on the surface inside instead.
          delegate: Item {
            id: resultRow
            required property int index
            required property int rowIndex
            required property string rowTitle
            required property string rowSubtitle
            required property string rowAccessory
            required property string rowIcon
            required property string rowImage
            required property bool rowMono
            required property string rowState
            required property bool selectable

            readonly property bool hasCursor: root.cursorActive && resultRow.index === root.selectedIndex
            readonly property bool showSwitch: resultRow.rowState.length > 0
              && root.toggleStates[resultRow.rowState] !== undefined
            readonly property bool armed: root.armedKey.length > 0
              && root.rows[resultRow.rowIndex]
              && root.rows[resultRow.rowIndex].key === root.armedKey

            width: ListView.view.width
            height: root.rowHeight

            Rectangle {
              id: rowSurface
              anchors.fill: parent
              anchors.leftMargin: root.listPadding
              anchors.rightMargin: root.listPadding
              radius: root.rowRadius
              color: resultRow.armed
                ? Util.alpha(Color.urgent, 0.22)
                : (resultRow.hasCursor ? root.selectedBackground : "transparent")
            }

            Image {
              id: rowImageItem
              visible: resultRow.rowImage.length > 0
              source: resultRow.rowImage
              width: Style.space(20)
              height: Style.space(20)
              fillMode: Image.PreserveAspectFit
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              asynchronous: true
              anchors.left: rowSurface.left
              anchors.leftMargin: root.rowInset
              anchors.verticalCenter: rowSurface.verticalCenter
            }

            Text {
              id: rowGlyph
              visible: resultRow.rowImage.length === 0
              text: resultRow.rowIcon
              textFormat: Text.PlainText
              color: resultRow.hasCursor ? root.selectedText : root.foreground
              opacity: resultRow.hasCursor ? 1 : 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              width: Style.space(20)
              horizontalAlignment: Text.AlignHCenter
              anchors.left: rowSurface.left
              anchors.leftMargin: root.rowInset
              anchors.verticalCenter: rowSurface.verticalCenter
            }

            PillSwitch {
              id: rowSwitch
              visible: resultRow.showSwitch && !resultRow.armed
              checked: root.toggleStates[resultRow.rowState] === true
              accent: root.accent
              foreground: root.foreground
              anchors.right: rowSurface.right
              anchors.rightMargin: root.rowInset
              anchors.verticalCenter: rowSurface.verticalCenter
            }

            Text {
              id: accessoryText
              // The switch replaces the "Action" label rather than crowding it.
              visible: !rowSwitch.visible
              text: resultRow.armed ? "Press ↵ again to confirm" : resultRow.rowAccessory
              textFormat: Text.PlainText
              color: resultRow.armed ? Color.urgent : root.foreground
              opacity: resultRow.armed ? 1 : 0.38
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.right: rowSurface.right
              anchors.rightMargin: root.rowInset
              anchors.verticalCenter: rowSurface.verticalCenter
            }

            Row {
              anchors.left: rowGlyph.right
              anchors.leftMargin: Style.space(10)
              anchors.right: rowSwitch.visible ? rowSwitch.left : accessoryText.left
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: rowSurface.verticalCenter
              spacing: Style.space(8)

              Text {
                id: titleText
                text: resultRow.rowTitle
                textFormat: Text.PlainText
                color: resultRow.hasCursor ? root.selectedText : root.foreground
                opacity: resultRow.selectable ? 1 : 0.75
                font.family: resultRow.rowMono ? Style.font.family : root.fontFamily
                font.pixelSize: Style.font.title
                font.weight: resultRow.hasCursor ? Font.Medium : Font.Normal
                elide: Text.ElideRight
                width: Math.min(implicitWidth, parent.width)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: resultRow.rowSubtitle
                textFormat: Text.PlainText
                visible: resultRow.rowSubtitle.length > 0 && parent.width - titleText.width > Style.space(60)
                color: root.foreground
                opacity: 0.42
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                width: Math.max(0, parent.width - titleText.width - Style.space(10))
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            // Fills the visible surface, not the delegate: the click target
            // should be exactly what the highlight shows.
            MouseArea {
              id: rowMouse
              anchors.fill: rowSurface
              hoverEnabled: true
              cursorShape: resultRow.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
              onEntered: root.selectFromPointer(resultRow.index, resultRow, {
                x: rowMouse.mouseX,
                y: rowMouse.mouseY
              })
              onPositionChanged: function(mouse) {
                root.selectFromPointer(resultRow.index, resultRow, mouse)
              }
              onClicked: function(mouse) {
                if (!resultRow.selectable) return
                root.cursorActive = true
                root.selectedIndex = resultRow.index
                root.activate(resultRow.index, (mouse.modifiers & Qt.ShiftModifier) ? true : false)
              }
            }
          }
        }
      }

      // ------------------------------------------------------- footer
      Rectangle {
        anchors { bottom: footer.top; left: parent.left; right: parent.right }
        anchors.leftMargin: root.listPadding
        anchors.rightMargin: root.listPadding
        height: root.hairline
        color: root.dividerColor
      }

      Item {
        id: footer
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        anchors.bottomMargin: root.hairline
        height: root.footerHeight

        Text {
          text: "󰣇  Omarchy"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.35
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.left: parent.left
          // The mark sits inside the rail the rows use, so it reads as a corner
          // signature, but not so far out that it crowds the rounded corner.
          anchors.leftMargin: Style.space(15)
          anchors.verticalCenter: parent.verticalCenter
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: root.gutter
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(14)

          Text {
            readonly property var sel: root.selectedRow()
            text: sel && sel.primaryLabel ? "↵  " + root.primaryLabelFor(sel) : ""
            visible: text.length > 0
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            readonly property var sel: root.selectedRow()
            text: sel && sel.secondaryLabel ? "⇧↵  " + sel.secondaryLabel : ""
            visible: text.length > 0
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            text: root.copyPathTarget() !== "" ? "⌃C  Copy path" : ""
            visible: text.length > 0
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    SetupTour {
      id: tour
      visible: root.tourActive
      anchors.centerIn: parent
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      surface: root.glassBackground
      surfaceBorder: root.glassBorder
      sheen: root.glassSheen
      hairline: root.hairline
      surfaceRadius: root.cardRadius
      rowRadius: root.rowRadius
      currentBinding: root.tourBinding.current
      previousBinding: root.tourBinding.previous
      bindingManaged: root.tourBinding.managed
      boundChords: root.tourBinding.bound
      bindingState: root.bindingState
      onBindingRequested: function(chord) { root.writeBinding(chord) }
      onRevertRequested: root.revertBinding()
      onFinished: function(patch) { root.finishTour(patch) }
    }
  }

  // Total height the result list wants. Driving the card
  // height off this is what gives the panel the Raycast grow/shrink feel.
  readonly property int contentHeight: {
    if (displayModel.count === 0) return 0
    var height = root.rows.length * root.rowHeight
    var previous = ""
    for (var i = 0; i < root.rows.length; i++) {
      var section = root.resultSection(root.rows[i])
      if (section && section !== previous) height += root.sectionHeight
      previous = section
    }
    return height
  }
}
