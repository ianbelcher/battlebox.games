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

  // Poll until the game says it connected, or we run out of patience.
  let connected = false;
  for (let i = 0; i < SECONDS; i++) {
    await new Promise(r => setTimeout(r, 1000));
    if (log.some(l => /Connected to world server/i.test(l))) { connected = true; break; }
  }

  // Actually join. A browser hands out pointer lock and audio only after
  // a real user gesture, so this clicks the canvas first — exactly what a
  // player does. Synthetic CDP input counts as a gesture, so this is a
  // genuine test of that path, not a bypass of it.
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

  const ok = state.isolated && state.hasSAB && connected && scriptErrors.length === 0;
  console.log(ok ? '\nWEB PLAY: PASS' : '\nWEB PLAY: FAIL');
  process.exit(ok ? 0 : 1);
})();
