// THE LOADING SCREEN: the video, full screen, and nothing else on top of
// it. It plays once, holds on its last frame, and stays there until the
// player presses something — at which point it fades and the game is
// behind it, fully loaded.
//
// That last part is the whole design. The game used to come up BEHIND the
// loading screen while it was still building itself, so you watched a
// half-drawn world through a title card and a progress bar. Holding the
// screen until a deliberate press gives the world all the time it needs
// and hands over on a moment the player chose.
//
// THE VIDEO IS OPTIONAL. Drop a `demo.mp4` next to this file and it is the
// loading screen; leave it out and there is no overlay at all and you get
// Godot's own. Every failure path — missing file, codec the browser will
// not take, autoplay refused — ends with the overlay removed rather than a
// black rectangle over the game, because this is the one page every single
// player sees.
//
// IT PLAYS WITH SOUND, and the game is silenced while it does — two
// soundtracks at once is nobody's idea of an opening.
//
// GETTING THE SOUND TAKES A GESTURE, AND MIGHT NOT NEED ONE TWICE.
//
// No browser will play audio until the visitor has interacted with the
// page. That is why there is a title screen with a button on it: pressing
// it IS the interaction, so the video can be heard.
//
// It does not stay that way forever. Chrome keeps a per-site Media
// Engagement score, and once a visitor has watched enough audible video
// on an origin it starts allowing unmuted autoplay outright. Firefox and
// Safari have their own, stricter versions of the same idea. So on a
// return visit the gate is often unnecessary — and the honest way to find
// out is to TRY: play() rejects immediately when autoplay is refused.
//
// So a visit that got sound remembers it (BEEN_HEARD), and the next visit
// starts the video straight away. If the browser says no, the promise
// rejects within a frame or two, the flag is dropped and the title screen
// appears exactly as it would have. The stored bit is a guess about what
// the browser will allow; play() is the answer. Never treat the bit as
// the answer — Safari in particular will refuse long after Chrome stops.
//
// `playsinline` is for iOS, which otherwise takes it full-screen.
(function () {
  'use strict';

  var DEMO = 'demo.mp4';

  // Set only after sound has actually been HEARD for a few seconds, which
  // is roughly what a browser is scoring too. Sound that was allowed for
  // half a second and then stopped is not evidence of anything.
  var BEEN_HEARD = 'bb.heard';
  var HEARD_AFTER_SECONDS = 4;

  var boot = null;
  var video = null;
  var gone = false;
  var gameReady = false;
  var pressed = false;
  var statusLine = null;

  // Read by GDScript (Game._process) to keep the game silent while this is
  // up. A flag rather than a call, because JavaScript cannot reach into
  // Godot — it has to be Godot that asks.
  window.bbBootUp = true;

  // Storage is not always there to be written to: private windows, blocked
  // cookies, embedded webviews. None of that should cost anybody the
  // loading screen, so every access is wrapped and a failure just means
  // the gate is shown, which is the behaviour we started with.
  function remembered(key) {
    try { return window.localStorage.getItem(key) === '1'; } catch (e) { return false; }
  }
  function remember(key, on) {
    try {
      if (on) { window.localStorage.setItem(key, '1'); }
      else { window.localStorage.removeItem(key); }
    } catch (e) { /* nothing to do, and nothing worth breaking over */ }
  }

  // --- taking the screen down -------------------------------------------

  function teardown() {
    if (gone) { return; }
    gone = true;
    document.body.classList.remove('bb-booting');
    // The gate is a SEPARATE element in front of everything, so anything
    // that tears the screen down has to take it too. Without this, a
    // video that failed before anybody pressed ENTER left the button
    // sitting over a game nobody could reach.
    var gate = document.getElementById('bb-gate');
    if (gate && gate.parentNode) { gate.parentNode.removeChild(gate); }
    if (!boot) {
      window.bbBootUp = false;
      return;
    }
    boot.classList.add('bb-gone');
    window.setTimeout(function () {
      if (boot && boot.parentNode) { boot.parentNode.removeChild(boot); }
      boot = null;
      // AFTER the fade, not at the start of it. This flag releases two
      // things on the Godot side — the game's own audio, and the
      // microphone — and both of them stepping in while the video is
      // still audible and still fading is exactly the mess this is
      // supposed to avoid.
      window.bbBootUp = false;
      // The canvas has to get the keyboard back or the game is deaf: the
      // press that dismissed this went to the window, not to Godot.
      var canvas = document.getElementById('canvas');
      if (canvas && canvas.focus) { canvas.focus(); }
    }, 800);
  }

  // A press only counts once the game is actually ready. Pressing early is
  // remembered rather than ignored, so an impatient player does not have
  // to press twice — but it never uncovers a world that is still building
  // itself, which is the thing this screen exists to prevent.
  function requestDismiss() {
    pressed = true;
    if (gameReady) { teardown(); }
  }

  // Called from GDScript (Game.web_loading_done) once the world is on
  // screen, and on a failed connect, where the game's own screen has
  // something to say and must not be sat behind a video.
  window.bbLoadingDone = function () {
    gameReady = true;
    setStatus('ready');
    if (pressed) { teardown(); }
  };

  // If the game never says anything, let the player out anyway. A loading
  // screen with no way past it is worse than one that lifts early.
  window.setTimeout(function () {
    gameReady = true;
    setStatus('ready');
    if (pressed) { teardown(); }
  }, 90000);

  // --- the press --------------------------------------------------------

  function listen() {
    // Capture phase: the canvas may be focused by now and would otherwise
    // swallow these before they reach the window.
    ['keydown', 'mousedown', 'touchstart', 'pointerdown'].forEach(function (ev) {
      window.addEventListener(ev, requestDismiss, true);
    });
    // Gamepads raise no events — the API is poll-only — so a pad press has
    // to be looked for. Cheap enough at 10 Hz, and it stops the moment the
    // screen is down.
    var poll = window.setInterval(function () {
      if (gone) { window.clearInterval(poll); return; }
      if (!navigator.getGamepads) { return; }
      var pads = navigator.getGamepads();
      for (var i = 0; i < pads.length; i++) {
        var pad = pads[i];
        if (!pad || !pad.buttons) { continue; }
        for (var b = 0; b < pad.buttons.length; b++) {
          var button = pad.buttons[b];
          if (button && (button.pressed || button.value > 0.5)) {
            requestDismiss();
            return;
          }
        }
      }
    }, 100);
  }

  // --- the title screen -------------------------------------------------

  function setStatus(state) {
    if (!statusLine) { return; }
    statusLine.textContent = state === 'ready'
      ? 'Ready when you are' : 'Building the world…';
    statusLine.className = state === 'ready' ? 'bb-status bb-ready' : 'bb-status';
  }

  // The gate: the game's name, a turning block, and one button.
  //
  // It is here because a browser will not play sound until somebody has
  // interacted with the page, and a silent intro is not much of an intro.
  // The press that gets past it IS that interaction.
  //
  // Since it has to exist, it may as well be the title screen: this is the
  // first thing every player sees, and it used to be an unlabelled cube
  // over a button, which said nothing about what they had opened.
  //
  // Nothing waits on it. The video preloads and Godot downloads the game
  // from the instant the page appears, so by the time anybody has pressed
  // the button both are well under way — press it and skip straight
  // through and the world is already there.
  function buildGate() {
    var gate = document.createElement('div');
    gate.id = 'bb-gate';

    var stage = document.createElement('div');
    stage.className = 'bb-stage';
    // Three blocks, not one: two small ones drifting behind the main one
    // so the screen reads as a world made of blocks rather than as a lone
    // shape somebody could not find a logo for.
    ['bb-cube bb-far-a', 'bb-cube bb-far-b', 'bb-cube bb-main'].forEach(function (cls) {
      var cube = document.createElement('div');
      cube.className = cls;
      ['t', 'b', 'n', 's', 'e', 'w'].forEach(function (face) {
        var side = document.createElement('div');
        side.className = face;
        cube.appendChild(side);
      });
      stage.appendChild(cube);
    });
    gate.appendChild(stage);

    var title = document.createElement('div');
    title.className = 'bb-title';
    title.textContent = 'BattleBox';
    gate.appendChild(title);

    var tagline = document.createElement('div');
    tagline.className = 'bb-tagline';
    tagline.textContent = 'Build. Battle. Be the last one standing.';
    gate.appendChild(tagline);

    var enter = document.createElement('button');
    enter.id = 'bb-enter';
    enter.type = 'button';
    enter.innerHTML = '<span class="bb-tri"></span>Play';
    gate.appendChild(enter);

    // Says what is going on behind this screen. Pressing early is already
    // remembered, so this is not an instruction — it is the difference
    // between "this page is broken" and "this page is working".
    statusLine = document.createElement('div');
    gate.appendChild(statusLine);
    setStatus(gameReady ? 'ready' : 'loading');

    var hint = document.createElement('div');
    hint.className = 'bb-hint';
    hint.textContent = 'Turn your sound up';
    gate.appendChild(hint);

    document.body.appendChild(gate);

    var opened = false;
    var open = function () {
      if (opened) { return; }
      opened = true;
      gate.classList.add('bb-gone');
      window.setTimeout(function () {
        if (gate.parentNode) { gate.parentNode.removeChild(gate); }
      }, 500);
      playVideo();
      // Only NOW start watching for the press that skips the video —
      // otherwise this very click would count as one and the intro would
      // be gone in the same instant it started.
      window.setTimeout(listen, 120);
    };
    enter.addEventListener('click', open);

    // ANYWHERE on the screen, and any key.
    //
    // Only the button used to work, which meant Space and Enter did
    // nothing at all on the one screen every player has to get past —
    // on a game that is otherwise played entirely from a controller or
    // the space bar. A four-year-old clicks the middle of the screen.
    gate.addEventListener('pointerdown', open);
    window.addEventListener('keydown', function (e) {
      // Not modifier chords: those are the browser's, not ours.
      if (e.metaKey || e.ctrlKey || e.altKey) { return; }
      open();
    });
    // Focused so the button is visibly the thing that is about to happen,
    // and so a screen reader lands on it.
    if (enter.focus) { enter.focus(); }

    // A pad has no button to click, so any pad press opens it too.
    var padPoll = window.setInterval(function () {
      if (opened) { window.clearInterval(padPoll); return; }
      if (!navigator.getGamepads) { return; }
      var pads = navigator.getGamepads();
      for (var i = 0; i < pads.length; i++) {
        var pad = pads[i];
        if (!pad || !pad.buttons) { continue; }
        for (var b = 0; b < pad.buttons.length; b++) {
          if (pad.buttons[b] && pad.buttons[b].pressed) { open(); return; }
        }
      }
    }, 100);
  }

  // --- the video --------------------------------------------------------

  // Try it with sound. Returns a promise that resolves if the browser
  // allowed audible playback and rejects if it refused — which is the
  // signal the whole gate-skipping decision rests on, so it is NOT
  // swallowed here. Muted is the fallback, and only once we have been
  // told no.
  function playUnmuted() {
    video.muted = false;
    video.removeAttribute('muted');
    var started = video.play();
    // Older browsers return undefined rather than a promise. Treat that
    // as "no idea", which means: show the gate, same as a refusal.
    if (!started || typeof started.then !== 'function') {
      return Promise.reject(new Error('no promise from play()'));
    }
    return started;
  }

  function playMuted() {
    video.muted = true;
    video.setAttribute('muted', '');
    var retry = video.play();
    if (retry && typeof retry.catch === 'function') { retry.catch(abandonAll); }
  }

  // With a real user gesture behind it this is allowed to have sound.
  function playVideo() {
    if (!video) { return; }
    playUnmuted().catch(playMuted);
  }

  // Evidence, not optimism: the flag goes on only once the video has been
  // AUDIBLE and PLAYING for several seconds, which is roughly what a
  // browser scores too. A play() that was allowed and then immediately
  // paused or muted proves nothing about the next visit.
  function watchForRealAudio() {
    var check = function () {
      if (video.muted || video.volume === 0 || video.paused) { return; }
      if (video.currentTime >= HEARD_AFTER_SECONDS) {
        remember(BEEN_HEARD, true);
        video.removeEventListener('timeupdate', check);
      }
    };
    video.addEventListener('timeupdate', check);
  }

  var abandonAll = function () {
    gameReady = true;
    pressed = true;
    teardown();
  };

  function start() {
    video = document.createElement('video');
    video.src = DEMO;
    // NOT autoplay: whether it plays by itself is decided below, and the
    // attribute would take that decision away and start it muted.
    video.autoplay = false;
    // NOT looped: it plays once and holds on its last frame, which is
    // where it waits for the player.
    video.loop = false;
    video.playsInline = true;
    video.preload = 'auto';
    video.setAttribute('playsinline', '');
    video.setAttribute('aria-hidden', 'true');

    // No video, no overlay. Anything wrong with it and the screen simply
    // is not there — Godot's own loading shows through, which is worse
    // looking and infinitely better than a black screen over the game.
    video.addEventListener('error', abandonAll);

    boot = document.createElement('div');
    boot.id = 'bb-boot';
    boot.appendChild(video);
    document.body.classList.add('bb-booting');
    document.body.appendChild(boot);

    watchForRealAudio();

    if (!remembered(BEEN_HEARD)) {
      buildGate();
      return;
    }
    // Been here, heard it play. Ask for the intro outright — and put the
    // title screen up after all if the browser turns out to disagree.
    playUnmuted().then(function () {
      // A moment before arming the skip, so a pointer event still in
      // flight from the click that opened the tab cannot dismiss the
      // intro before a single frame of it has been seen.
      window.setTimeout(listen, 600);
    }).catch(function () {
      remember(BEEN_HEARD, false);
      video.pause();
      try { video.currentTime = 0; } catch (e) { /* not seekable yet */ }
      buildGate();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
