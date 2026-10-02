// Run the real QML lifecycle functions with process/UI boundaries replaced.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require.resolve('../Spotlight.qml'), 'utf8');
const notifications = [];
const noop = () => {};
const root = {
  opened: true, aiActive: false, aiBusy: false, aiGeneration: 0, aiQuery: '',
  aiResult: null, aiError: '', aiProgress: '', aiReadPosition: 0, aiProcess: null,
  query: '', maxPayloadChars: 2048, maxQueryChars: 512, maxHelperPayloadChars: 262144,
  pluginId: 'io.github.maajix.spotlight', appLibrary: null,
  settings: {aiEnabled: true, aiProvider: 'codex', aiModel: '', aiEffort: '', aiWebSearch: false},
  clipboardRows: [], fileRows: [], suggestionRows: [],
  currencySession: require('../lib/Currency.js').createSession(),
  setupPending: () => false, clipboardSearchTarget: () => null, fileSearchTarget: () => null,
  helperArgv: args => ['python3', 'spotlight-helper', ...args]
};
for (const name of ['leaveSettingsPanel', 'stopCurrencyProcess', 'resetView', 'updateCurrency', 'syncView', 'refreshPluginCommands',
    'rebuild', 'refreshSettings', 'refreshReminders', 'refreshToggleStates', 'resumeTour']) root[name] = noop;
const context = vm.createContext({root, Query: require('../lib/Query.js'), Currency: require('../lib/Currency.js'),
  WeatherIntent: require('../lib/WeatherIntent.js'), Web: require('../lib/Web.js'),
  Qt: {callLater: fn => fn()}, Util: {execArgv: argv => notifications.push(Array.from(argv))},
  tour: {started: false}, pointerGate: {reset: noop}, resultList: {positionViewAtBeginning: noop},
  aiPanel: {restoringScroll: false, restoreScroll(position) { this.restored = position; }},
  aiProcessComponent: {createObject(parent, properties) {
    return {...properties, running: false, write(value) { this.input = value; }, destroy: noop};
  }}
});
for (const name of ['currencyDebounce', 'suggestDebounce', 'fileDebounce', 'clipboardDebounce', 'tldrDebounce', 'typingGuard'])
  context[name] = {stop: noop, restart: noop};
for (const name of ['suggestProc', 'fileProc', 'clipboardProc', 'tldrProc']) context[name] = {running: false};
for (const name of ['open', 'close', 'stopQueryWork', 'stopAi', 'startAi', 'handleAiLine', 'notifyAiFinished',
    'failAi', 'helperReply', 'helperError', 'loadSettings']) {
  const match = source.match(new RegExp('^  function ' + name + '\\((.*?)\\) \\{\\n([\\s\\S]*?)^  \\}', 'm'));
  assert.ok(match, 'Missing QML lifecycle function ' + name);
  root[name] = vm.runInContext('(function(' + match[1] + ') {' + match[2] + '})', context);
}
const queryChanged = source.match(/^  onQueryChanged: \{\n([\s\S]*?)^  \}/m);
context.queryChanged = vm.runInContext('(function() {' + queryChanged[1] + '})', context);
context.input = {forceActiveFocus: noop};
Object.defineProperty(context.input, 'text', {
  get: () => root.query,
  set(value) { if (value !== root.query) { root.query = value; context.queryChanged(); } }
});
const event = (type, value, generation = root.aiGeneration) =>
  root.handleAiLine(JSON.stringify({ok: true, event: type, ...value}), generation);

context.input.text = 'ai: explain DNS resolution';
root.startAi();
const first = root.aiProcess, generation = root.aiGeneration;
assert.equal(first.input, 'explain DNS resolution');
root.close();
assert.equal(first.running, true, 'Hiding Spotlight must not stop its AI process');
event('progress', {text: 'Checking the lookup stages…'});
root.open('{}');
assert.equal(root.aiProcess, first, 'Reopening must reuse the running request');
assert.equal(root.aiGeneration, generation);
assert.equal(root.aiBusy, true);
assert.equal(root.aiActive, true);
assert.match(root.aiProgress, /lookup stages/);

context.input.text = 'terminal'; // Ordinary Spotlight searches can run alongside AI.
assert.equal(root.aiActive, false);
assert.equal(first.running, true, 'Typing another search must not cancel submitted AI work');
root.close();
event('result', {result: {text: 'DNS answer', commands: [], artifacts: []}});
assert.equal(root.aiResult.text, 'DNS answer');
assert.equal(root.aiBusy, false);
assert.equal(notifications.length, 1);
assert.equal(notifications[0][0], 'omarchy');
assert.ok(notifications[0].includes('Spotlight answer is ready'));
assert.deepEqual(notifications[0].slice(-6), ['--exec', 'omarchy-shell', 'shell', 'summon', root.pluginId, '{}']);
event('result', {result: {text: 'Duplicate answer'}});
assert.equal(notifications.length, 1, 'Only one completion toast per request');
root.open('{}');
assert.equal(context.input.text, 'ai: explain DNS resolution');
assert.equal(root.aiActive, true);
assert.equal(root.aiResult.text, 'DNS answer');
root.aiReadPosition = 137;
root.close(); root.open('{}');
assert.equal(context.aiPanel.restored, 137, 'Completed answers retain the reading position');

context.input.text = 'ai: make a checklist';
root.startAi();
event('result', {result: {text: 'Old request'}}, generation);
assert.equal(root.aiBusy, true, 'Old completions must not replace a newer request');
event('result', {result: {text: 'Visible answer'}});
assert.equal(notifications.length, 1, 'Reading the answer should not produce a toast');

context.input.text = 'ai: test a failed request';
root.startAi();
const failed = root.aiProcess;
root.close();
context.aiRun = failed;
const exited = source.match(/id: aiProcessComponent[\s\S]*?onExited: Qt\.callLater\(function\(\) \{([\s\S]*?)^      \}\)/m);
vm.runInContext('(function() {' + exited[1] + '})()', context);
assert.equal(root.aiBusy, false, 'A background process exit must leave the busy state');
assert.match(root.aiError, /stopped before/);
assert.equal(notifications.length, 2);
root.open('{}');
assert.match(root.aiError, /stopped before/);
root.startAi();
const cancelled = root.aiProcess, cancelledGeneration = root.aiGeneration;
root.stopAi();
assert.equal(cancelled.running, false, 'Explicit Cancel stops the request');
event('result', {result: {text: 'Cancelled response'}}, cancelledGeneration);
assert.equal(root.aiResult, null);
assert.equal(root.aiQuery, '');
assert.equal(notifications.length, 2);
console.log('AI requests survive hiding, reopening and other searches; completion, errors and cancellation are retained correctly');

root.settings.aiEnabled = true;
context.input.text = 'ai: background disable test';
root.startAi();
const disabledProcess = root.aiProcess, disabledGeneration = root.aiGeneration;
root.close();
root.loadSettings(JSON.stringify({ok: true, settings: {aiEnabled: false, aiProvider: 'codex'}}));
assert.equal(disabledProcess.running, false, 'Disabling AI cancels even while hidden');
assert.equal(root.aiBusy, false);
event('result', {result: {text: 'Disabled response'}}, disabledGeneration);
assert.equal(root.aiResult, null);
