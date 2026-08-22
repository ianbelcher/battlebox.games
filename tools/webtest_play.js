// Loads the exported browser build in a REAL browser and reports what
// happened: whether the page is cross-origin isolated (no isolation, no
// threads, no game), whether the wasm booted, and whether it reached the
// world server over wss.
//
// A run that merely fails to crash proves nothing, so this fails loudly
// unless it sees the game actually connect.
const puppeteer = require('puppeteer-core');

const URL = process.argv[2] || 'https://localhost:8443/';
const SECONDS = parseInt(process.argv[3] || '90', 10);

(async () => {
  // CHROME_PATH so this can run somewhere other than one machine — a
  // Linux box, CI, the live site — without editing the file. The macOS
  // path stays the default because that is where it is usually run by hand.
  const browser = await puppeteer.launch({
    executablePath: process.env.CHROME_PATH
      || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: 'new',
    args: [
      // For the LOCAL harness, whose certificate is self-signed on
      // purpose. Pointed at battlebox.games this is never exercised —
      // that certificate is a real one.
      '--ignore-certificate-errors',
      '--enable-unsafe-swiftshader',           // WebGL2 without a real GPU
      '--use-gl=angle', '--use-angle=swiftshader',
      '--no-sandbox', '--window-size=1280,800',
    ],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });

  const log = [];
  const errors = [];
  page.on('console', m => log.push(`${m.type()}: ${m.text()}`));
  page.on('pageerror', e => errors.push(`pageerror: ${e.message}`));
  page.on('requestfailed', r =>
    errors.push(`requestfailed: ${r.url().split('/').pop()} ${r.failure()?.errorText}`));

  const started = Date.now();
  await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 120000 });

  // THE REAL PATH A PLAYER TAKES, in order. It is three presses, not one,
  // and skipping any of them tests nothing:
  //
  //   1. a press takes the loading video down (boot.js swallows this one)
  //   2. Play — focused, so Enter hits it — joins the always-on game
  //   3. a press claims a seat in it
  //
  // This used to be "wait for the client to auto-connect, then click".
  // The client does not auto-connect any more; it opens a lobby and waits
  // to be told which game.
  // The ENTER gate first, BY SELECTOR. A click at a fixed coordinate is
  // not the same thing: boot.js only starts watching for the skip press
  // once that button has been clicked, so missing it leaves the video up
  // forever and looks exactly like the bug this check exists to find.
  //
  // A browser hands out pointer lock and audio only after a real user
  // gesture. Synthetic CDP input counts as one, so this is a genuine test
  // of that path rather than a bypass of it.
  await page.waitForSelector('#bb-enter', { timeout: 60000 });
  await page.click('#bb-enter');
  await new Promise(r => setTimeout(r, 2000));

  let dismissed = false;
  for (let i = 0; i < 40; i++) {
    await page.keyboard.press('Space');
    await new Promise(r => setTimeout(r, 1000));
    dismissed = await page.evaluate(() =>
      !document.body.classList.contains('bb-booting'));
    if (dismissed) { break; }
  }
  // Let the fade finish before anything is aimed at the game behind it.
  await new Promise(r => setTimeout(r, 2000));

  // Play has focus on the lobby screen, so Enter is the whole of what a
  // child has to do.
  await page.keyboard.press('Enter');

  let connected = false;
  for (let i = 0; i < SECONDS; i++) {
    await new Promise(r => setTimeout(r, 1000));
    if (log.some(l => /Connected to world server/i.test(l))) { connected = true; break; }
  }

  await page.mouse.click(640, 400);
  await new Promise(r => setTimeout(r, 1000));
  await page.keyboard.press('Space');
  await new Promise(r => setTimeout(r, 8000));
  await page.screenshot({ path: (process.argv[4] || 'shot.png').replace('.png', '-joined.png') });

  // Open the world menu with ` (NOT Escape — a browser keeps Escape for
  // releasing the mouse). This shot is also how the bundled symbol fonts
  // get checked: with no fonts, every icon in here draws as an empty box
  // with its code point in it.
  await page.keyboard.press('Backquote');
  await new Promise(r => setTimeout(r, 3000));
  await page.screenshot({ path: (process.argv[4] || 'shot.png').replace('.png', '-menu.png') });
  const joined = await page.evaluate(() => ({
    pointerLocked: document.pointerLockElement !== null,
  }));

  const state = await page.evaluate(() => ({
    isolated: window.crossOriginIsolated === true,
    hasSAB: typeof SharedArrayBuffer !== 'undefined',
    canvas: (() => {
      const c = document.querySelector('canvas');
      return c ? `${c.width}x${c.height}` : 'no canvas';
    })(),
    // DID THE LOADING SCREEN GET TOLD THE GAME IS UP?
    //
    // web/boot.js holds its video over everything until GDScript calls
    // window.bbLoadingDone(), and only then does a press take it down. If
    // nothing calls it the player sits on a frozen last frame, clicking,
    // until a 90-second failsafe lets them out — and NOTHING else in this
    // file notices: the canvas is there, the socket is open, the console
    // is clean. That is exactly how it shipped once.
    bootOverlayUp: window.bbBootUp === true,
    stillBooting: document.body.classList.contains('bb-booting'),
  }));

  await page.screenshot({ path: process.argv[4] || 'shot.png' });

  // A GDScript file that failed to compile is fatal and completely silent
  // from out here: Godot logs it, packs the broken script, boots anyway,
  // opens its websocket and draws a canvas. Every other check in this file
  // passed while game.gd had a parse error in it and the game did nothing.
  // So the console is evidence, not decoration — read it.
  const scriptErrors = log.filter(l =>
    /SCRIPT ERROR|Parse Error|Compile Error|Failed to load script/i.test(l));

  console.log('--- browser run ---');
  console.log('url            :', URL);
  console.log('crossOriginIso :', state.isolated);
  console.log('SharedArrayBuf :', state.hasSAB);
  console.log('canvas         :', state.canvas);
  console.log('loading screen :', state.stillBooting ? 'STILL UP (never told)' : 'lifted');
  console.log('lobby dismissed:', dismissed);
  console.log('pointerLocked  :', joined.pointerLocked);
  console.log('connected      :', connected, `(after ${Math.round((Date.now()-started)/1000)}s)`);
  // Chunks are meshed on worker threads. A handful of stalls under a
  // software rasterizer is normal; a stall for every chunk means the
  // threads are not running at all and everything is limping along on
  // the synchronous fallback.
  console.log('mesh stalls    :', log.filter(l => /Mesh worker stalled/.test(l)).length);
  console.log('script errors  :', scriptErrors.length);
  if (scriptErrors.length) {
    console.log('--- scripts that did not compile ---');
    console.log([...new Set(scriptErrors)].slice(0, 15).join('\n'));
  }
  console.log('--- console (last 40) ---');
  console.log(log.slice(-40).join('\n') || '(nothing)');
  if (errors.length) {
    console.log('--- errors ---');
    console.log([...new Set(errors)].slice(0, 25).join('\n'));
  }
  await browser.close();

  const ok = state.isolated && state.hasSAB && connected
    && !state.stillBooting && scriptErrors.length === 0;
  console.log(ok ? '\nWEB PLAY: PASS' : '\nWEB PLAY: FAIL');
  process.exit(ok ? 0 : 1);
})();
