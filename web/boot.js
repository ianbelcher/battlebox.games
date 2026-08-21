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
// Getting the sound took a gate. No browser will play audio until the
// visitor has interacted with the page, and asking politely does not
// help: the answer is no, every time, for anybody who has not been back
// to the site enough times to earn it. So there is one button in front of
// the video, and pressing it IS the interaction. Nothing waits on it —
// the video preloads and Godot downloads the game from the instant the
// page appears — so the gate costs the moment it takes to press and
// nothing else.
//
// `playsinline` is for iOS, which otherwise takes it full-screen.
(function () {
  'use strict';

  var DEMO = 'demo.mp4';

  var boot = null;
  var video = null;
  var gone = false;
  var gameReady = false;
  var pressed = false;

  // Read by GDScript (Game._process) to keep the game silent while this is
  // up. A flag rather than a call, because JavaScript cannot reach into
  // Godot — it has to be Godot that asks.
  window.bbBootUp = true;

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
    if (pressed) { teardown(); }
  };

  // If the game never says anything, let the player out anyway. A loading
  // screen with no way past it is worse than one that lifts early.
  window.setTimeout(function () {
    gameReady = true;
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

  // --- building it ------------------------------------------------------

  // The gate: a turning block and one button. It is here because a
  // browser will not play sound until somebody has interacted with the
  // page, and a silent intro is not much of an intro. The click that gets
  // past it IS that interaction, so the video can come up with its audio.
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
    var cube = document.createElement('div');
    cube.className = 'bb-cube';
    ['t', 'b', 'n', 's', 'e', 'w'].forEach(function (face) {
      var side = document.createElement('div');
      side.className = face;
      cube.appendChild(side);
    });
    stage.appendChild(cube);
    gate.appendChild(stage);

    var enter = document.createElement('button');
    enter.id = 'bb-enter';
    enter.type = 'button';
    enter.textContent = 'ENTER';
    gate.appendChild(enter);

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

  // With a real user gesture behind it this is allowed to have sound.
  // Muted is still the fallback rather than nothing at all.
  function playVideo() {
    if (!video) { return; }
    video.muted = false;
    var started = video.play();
    if (started && typeof started.catch === 'function') {
      started.catch(function () {
        video.muted = true;
        video.setAttribute('muted', '');
        var retry = video.play();
        if (retry && typeof retry.catch === 'function') { retry.catch(abandonAll); }
      });
    }
  }

  var abandonAll = function () {
    gameReady = true;
    pressed = true;
    teardown();
  };

  function start() {
    video = document.createElement('video');
    video.src = DEMO;
    // NOT autoplay: it waits behind the gate. `preload` is the important
    // half — the file starts coming down immediately, so pressing ENTER
    // plays rather than buffers.
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

    buildGate();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
