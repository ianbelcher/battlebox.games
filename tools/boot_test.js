// THE LOADING SCREEN, IN A REAL BROWSER.
//
//     CHROME_PATH=/path/to/chrome node tools/boot_test.js
//
// Serves web/ on its own and drives three visits through Chrome, because
// the interesting behaviour of that screen is entirely about what a
// browser will and will not allow, and nothing else in this repository
// can see it:
//
//   1. A first-ever visitor gets the title screen, and pressing Play
//      starts the intro WITH SOUND.
//   2. A visitor who has already heard it gets no title screen at all —
//      the intro simply plays.
//   3. A visitor whose browser refuses anyway gets the title screen back,
//      from the start of the video, and the stored guess is dropped.
//
// The third case is the one worth having a test for. `bb.heard` is a
// GUESS about what the browser will permit next time; play() is the
// answer. If the fallback ever broke, a returning player would get a
// silent, half-started intro — or no intro and a dead screen — and every
// other check here would still pass.
//
// Chrome's real autoplay rule is a per-site engagement score that cannot
// be set from outside, so each visit is launched with an explicit
// --autoplay-policy standing in for "this browser trusts us" and "this
// browser does not". The profile is shared across the three so that
// localStorage carries between them, exactly as it would for a player.
//
// NOT IN CI: the build image has no browser in it, and putting one there
// would add hundreds of megabytes to every deploy. Run it by hand when
// touching web/boot.js or web/boot.css. tools/webtest_play.js has the
// same requirement for the same reason.
const puppeteer = require('puppeteer-core');
const http = require('http');
const fs = require('fs');
const path = require('path');

const WEB = path.join(__dirname, '..', 'web');
const PORT = 8799;
const PROFILE = fs.mkdtempSync(path.join(require('os').tmpdir(), 'bb-boot-'));
const CHROME = process.env.CHROME_PATH
  || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const MIME = {
  '.html': 'text/html', '.css': 'text/css',
  '.js': 'text/javascript', '.mp4': 'video/mp4',
};

// The page Godot generates, minus Godot: boot.css and boot.js are
// injected into the export's shell, so a harness page carrying the same
// two files is the same screen. This keeps the test from needing a full
// export — which takes minutes and would mean nobody ran it.
const HARNESS = `<!doctype html><html><head><meta charset="utf-8">
<title>BattleBox</title><link rel="stylesheet" href="boot.css"></head>
<body><canvas id="canvas"></canvas><div id="status"></div>
<script src="boot.js"></script></body></html>`;

const server = http.createServer((req, res) => {
  let name = req.url.split('?')[0];
  if (name === '/') {
    res.writeHead(200, {'Content-Type': 'text/html'});
    return res.end(HARNESS);
  }
  const file = path.join(WEB, name);
  if (!file.startsWith(WEB) || !fs.existsSync(file)) {
    res.writeHead(404);
    return res.end('not here');
  }
  res.writeHead(200, {'Content-Type': MIME[path.extname(file)] || 'application/octet-stream'});
  fs.createReadStream(file).pipe(res);
});

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

// What the screen looks like from the outside: is the title screen up,
// what has been remembered, and what is the video actually doing.
const look = (page) => page.evaluate(() => ({
  gate: !!document.getElementById('bb-gate'),
  heard: (() => {
    try { return localStorage.getItem('bb.heard'); } catch (e) { return 'UNREADABLE'; }
  })(),
  video: (() => {
    const v = document.querySelector('#bb-boot video');
    if (!v) { return null; }
    return {paused: v.paused, muted: v.muted, at: +v.currentTime.toFixed(1)};
  })(),
}));

async function visit(policy) {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    userDataDir: PROFILE,
    args: ['--no-sandbox', '--window-size=1280,800', `--autoplay-policy=${policy}`],
  });
  const page = await browser.newPage();
  await page.setViewport({width: 1280, height: 800});
  await page.goto(`http://127.0.0.1:${PORT}/`, {waitUntil: 'networkidle2'});
  return {browser, page};
}

(async () => {
  if (!fs.existsSync(path.join(WEB, 'demo.mp4'))) {
    console.error('web/demo.mp4 is missing — there is no loading screen to test.');
    process.exit(1);
  }
  let failures = 0;
  const check = (pass, what) => {
    console.log((pass ? '  ok  ' : ' FAIL ') + what);
    if (!pass) { failures++; }
  };

  server.listen(PORT);
  try {
    // --- a first-ever visitor ------------------------------------------
    let at = await visit('document-user-activation-required');
    let saw = await look(at.page);
    check(saw.gate, 'a first visit shows the title screen');
    check(saw.heard === null, `nothing is remembered yet (heard=${saw.heard})`);
    check(saw.video && saw.video.paused, 'the intro waits behind it');

    await at.page.click('#bb-enter');
    await wait(7000);
    saw = await look(at.page);
    check(!saw.gate, 'pressing Play takes the title screen away');
    check(saw.video && !saw.video.muted && !saw.video.paused,
      'and the intro plays WITH SOUND, which is the point of the screen');
    check(saw.video && saw.video.at >= 4,
      `it ran past 4s of audible video (at=${saw.video && saw.video.at})`);
    check(saw.heard === '1', `so the visit is remembered (heard=${saw.heard})`);
    await at.browser.close();

    // --- coming back, to a browser that now allows it -------------------
    at = await visit('no-user-gesture-required');
    await wait(1500);
    saw = await look(at.page);
    check(!saw.gate, 'a returning visitor gets NO title screen');
    check(saw.video && !saw.video.paused && !saw.video.muted,
      'the intro just plays, with sound, unprompted');
    await at.browser.close();

    // --- coming back, to a browser that refuses anyway ------------------
    at = await visit('document-user-activation-required');
    await wait(2000);
    saw = await look(at.page);
    check(saw.gate, 'a refused autoplay puts the title screen back');
    check(saw.heard === null, `and drops the guess (heard=${saw.heard})`);
    check(saw.video && saw.video.at < 1,
      `leaving the intro at its start, not part-played (at=${saw.video && saw.video.at})`);
    await at.browser.close();
  } finally {
    server.close();
    fs.rmSync(PROFILE, {recursive: true, force: true});
  }

  console.log(failures ? `\n${failures} checks FAILED` : '\nboot test: all checks passed');
  process.exit(failures ? 1 : 0);
})();
