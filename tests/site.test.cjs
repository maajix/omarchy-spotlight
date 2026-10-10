// Run with node tests/site.test.cjs. Uses only Node's standard library.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const home = read('static/index.html'), docs = read('static/docs/index.html');

for (const html of [home, docs]) {
  for (const [, attrs, script] of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)) {
    if (!attrs.includes('application/ld+json')) new vm.Script(script);
  }
}
const articles = new Map([...docs.matchAll(/<article[^>]*data-slug="([^"]+)"[^>]*>([\s\S]*?)<\/article>/g)].map(([, slug, body]) => [slug, body]));
for (const [slug, body] of articles) {
  const ids = [...body.matchAll(/\bid="([^"]+)"/g)].map(([, id]) => id);
  assert.equal(ids.length, new Set(ids).size, `Duplicate heading ID in ${slug}`);
  for (const [, target, anchor] of body.matchAll(/href="\?p=([^"#]+)(?:#([^" ]+))?"/g)) {
    assert(articles.has(target), `${slug} links to missing page ${target}`);
    if (anchor) assert(articles.get(target).includes(`id="${anchor}"`), `${slug} links to missing heading ${target}#${anchor}`);
  }
}
const data = JSON.parse(home.match(/<script type="application\/ld\+json">(.*?)<\/script>/s)[1]);
assert.equal(data['@graph'][0].softwareVersion, '1.7.2');
assert(docs.includes('id="1-7-2"') && read('static/llms.txt').includes('1.7.2'));
const context = { HERO: [], svg: () => '<svg></svg>', esc: String };
const examples = home.slice(home.indexOf('const AI = ['), home.indexOf('const rowsHTML ='));
vm.runInNewContext(examples + '; this.examples = AI;', context);
assert.equal(context.examples.length, 13);
assert.equal(home.match(/data-count="12">12<\/b><span>(.*?)<\/span>/)[1], 'AI artifact types');
const palette = context.examples.find((card) => card.name === 'Palettes').card;
for (const hex of ['#0B1426', '#17334A', '#327A91', '#72E0CF']) assert(palette.includes(`--swatch:${hex}`));
for (const type of ['map','weather','palette','chart','comparison','timeline','dashboard','places','diff','checklist','diagram','gallery']) assert(articles.get('ai-artifacts').includes(`id="${type}"`));
assert.equal([...docs.matchAll(/data-since="1\.7"/g)].length, 2);
assert(!home.includes('.views:hover .tab.on::after'));
console.log(`PASS: JavaScript syntax, ${articles.size} docs pages and links, release metadata, all artifact examples and palette values.`);
