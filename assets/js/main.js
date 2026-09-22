// Copy buttons on code blocks.
document.querySelectorAll('.copy').forEach((btn) => {
  btn.addEventListener('click', async () => {
    const code = btn.parentElement.querySelector('code');
    if (!code) return;
    try {
      await navigator.clipboard.writeText(code.innerText.trimEnd());
      btn.classList.add('done');
      setTimeout(() => btn.classList.remove('done'), 1400);
    } catch {
      btn.textContent = 'Select and copy';
    }
  });
});

const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

// Scroll reveal: blocks below the fold rise in once they enter the viewport.
if (!reduced) {
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
  }, { rootMargin: '0px 0px -12%' });
  document.querySelectorAll('[data-reveal]').forEach((el) => {
    if (el.getBoundingClientRect().top > innerHeight) { el.classList.add('reveal'); io.observe(el); }
  });
}

// Animated palettes. A demo waits until it is on screen, types a query, crossfades the results in,
// flips the switch if the selected row has one, clears the query and moves on to the next scene.
// The hero returns to its empty-query view between scenes; the smaller demos hold the last result.
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const onScreen = new Set();
const watch = new IntersectionObserver((entries) => {
  for (const e of entries) e.isIntersecting ? onScreen.add(e.target) : onScreen.delete(e.target);
}, { threshold: 0.4 });

const run = async (demo) => {
  const query = demo.querySelector('[data-query]');
  const all = [...demo.querySelectorAll('[data-scene]')];
  const idle = all.find((s) => !s.dataset.scene);
  const scenes = all.filter((s) => s.dataset.scene);
  if (scenes.length < 2) return;
  const pills = [...demo.querySelectorAll('.pill')].map((p) => [p, p.classList.contains('on')]);
  let current = all[0];

  const swap = async (next) => {
    current.classList.add('is-out');
    await wait(200);
    next.hidden = false;
    current.hidden = true;
    current.classList.remove('is-out');
    current = next;
    pills.forEach(([p, on]) => { if (!next.contains(p)) p.classList.toggle('on', on); });
  };
  const type = async (text) => {
    for (const ch of text) { query.textContent += ch; await wait(35 + Math.random() * 55); }
  };
  const clear = async () => {
    while (query.textContent) { query.textContent = query.textContent.slice(0, -1); await wait(14); }
  };
  const hold = async (scene) => {
    const pill = scene.querySelector('.is-selected .pill');
    if (!pill) return wait(3000);
    await wait(1400);
    scene.classList.add('is-pressed');
    await wait(170);
    pill.classList.toggle('on');
    scene.classList.remove('is-pressed');
    await wait(2000);
  };

  watch.observe(demo);
  let i = idle ? -1 : 0;
  for (;;) {
    while (document.hidden || !onScreen.has(demo)) await wait(300);
    if (i < 0) {
      await wait(1600);
    } else {
      await hold(scenes[i]);
      await clear();
      if (idle) { await swap(idle); await wait(900); } else { await wait(300); }
    }
    i = (i + 1) % scenes.length;
    await type(scenes[i].dataset.scene);
    await wait(220);
    await swap(scenes[i]);
  }
};
if (!reduced) document.querySelectorAll('[data-demo]').forEach(run);

// Switch board: while on screen, one row is pressed and its switch flips every few seconds.
const flip = async (board) => {
  const rows = [...board.children].filter((r) => r.querySelector('.pill'));
  if (rows.length < 2) return;
  watch.observe(board);
  let last;
  for (;;) {
    await wait(3200);
    while (document.hidden || !onScreen.has(board)) await wait(300);
    let row;
    do row = rows[Math.floor(Math.random() * rows.length)]; while (row === last);
    last = row;
    row.classList.add('is-pressed');
    await wait(170);
    row.querySelector('.pill').classList.toggle('on');
    await wait(500);
    row.classList.remove('is-pressed');
  }
};
if (!reduced) document.querySelectorAll('.board').forEach(flip);
