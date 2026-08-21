// Voice chat for the browser build.
//
// This lives in JavaScript, beside Godot rather than inside it, for one
// reason: Godot's WebRTC binding only carries data channels, so it cannot
// be handed a microphone track. Out here we get getUserMedia, Opus, echo
// cancellation, noise suppression and a jitter buffer from the browser for
// nothing, and they are the parts that are miserable to write by hand.
//
// It is served from the same origin as the game ON PURPOSE. /play/ sends
// Cross-Origin-Embedder-Policy: require-corp so Godot's threads can have
// SharedArrayBuffer, and that blocks any script pulled off a CDN.
//
// ONE ENDPOINT PER MACHINE, not per player. A split-screen couch has one
// microphone, so per-seat voice was never real — see the note in voice.gd.
//
// Godot talks to this by evaluating calls on window.BBVoice, and reads
// anything coming back by polling drain()/status(). Polling rather than
// callbacks because a poll cannot arrive while the engine is mid-frame.
(function () {
  'use strict';

  // No TURN. A relay would have to run on the server and carry every
  // conversation; STUN covers the large majority of home networks and
  // this is a game for a few people at a time. If somebody's network
  // turns out to be hostile, that is when to add coturn.
  var ICE = { iceServers: [{ urls: ['stun:stun.l.google.com:19302',
                                    'stun:stun1.l.google.com:19302'] }] };

  var BBVoice = {
    state: 'off',        // off | asking | on | denied | unsupported
    selfId: 0,
    muted: false,
    volume: 1,
    mic: null,
    peers: {},           // remote peer id -> { pc, audio, stream }
    outbox: [],          // [{to, data}] waiting for Godot to send
    error: '',

    // --- lifecycle -------------------------------------------------
    async enable(selfId) {
      this.selfId = selfId | 0;
      if (this.state === 'on' || this.state === 'asking') return;
      if (!navigator.mediaDevices || !window.RTCPeerConnection) {
        this.state = 'unsupported';
        this.error = 'this browser has no microphone support';
        return;
      }
      this.state = 'asking';
      // The three constraints that make a shared room mic bearable — but
      // ASKED FOR, not demanded. Some devices (and Chrome's own synthetic
      // capture device) refuse the whole request when they cannot satisfy
      // a named constraint, and a browser that will not open the mic at
      // all is worse than one without echo cancellation.
      var nice = { echoCancellation: true, noiseSuppression: true,
                   autoGainControl: true };
      try {
        this.mic = await navigator.mediaDevices.getUserMedia({
          audio: nice, video: false });
      } catch (e) {
        this.error = String(e && e.name ? e.name : e);
        try {
          this.mic = await navigator.mediaDevices.getUserMedia({
            audio: true, video: false });
          this.error = '';
        } catch (e2) {
          this.state = 'denied';
          this.error = String(e2 && e2.name ? e2.name : e2);
          return;
        }
      }
      this.applyMute();
      this.state = 'on';
      // Any connection built BEFORE the microphone existed has no outgoing
      // track and never will — setPeers() sees it already there and leaves
      // it alone, so that pairing is silent one way forever. This is the
      // common case, not a corner: whoever turns voice on second gets an
      // offer while they still have no mic. Tearing them down and letting
      // the next poll rebuild them is cheaper than renegotiating, and it
      // cannot leave a half-built one behind.
      var ids = Object.keys(this.peers);
      for (var i = 0; i < ids.length; i++) this.dropPeer(ids[i], true);
    },

    disable() {
      for (var id in this.peers) this.dropPeer(id);
      if (this.mic) { this.mic.getTracks().forEach(function (t) { t.stop(); }); }
      this.mic = null;
      this.state = 'off';
    },

    setMuted(m) { this.muted = !!m; this.applyMute(); },

    // How loud everyone ELSE is, 0..100. Applied to each remote element
    // rather than to a gain node: the browser is already mixing these, and
    // one property per peer is the whole job.
    setVolume(pct) {
      this.volume = Math.max(0, Math.min(100, pct | 0)) / 100;
      for (var id in this.peers) {
        if (this.peers[id].audio) this.peers[id].audio.volume = this.volume;
      }
    },

    applyMute() {
      if (!this.mic) return;
      var live = !this.muted;
      this.mic.getAudioTracks().forEach(function (t) { t.enabled = live; });
    },

    // --- the mesh --------------------------------------------------
    // `ids` is a comma-separated list of every OTHER machine in the world.
    setPeers(ids) {
      if (this.state !== 'on') return;
      var want = {};
      String(ids || '').split(',').forEach(function (s) {
        var n = parseInt(s, 10);
        if (n) want[n] = true;
      });
      for (var have in this.peers) {
        if (!want[have]) this.dropPeer(have);
      }
      // A connection can finish its handshake and still never start ICE:
      // if candidates were in flight while the far side rebuilt, they went
      // to a peer connection that no longer exists, and neither end ever
      // sends more. It sits at signalingState 'stable' with
      // iceConnectionState 'new' forever, looking negotiated and carrying
      // nothing. Give it a few seconds, then throw it away and re-dial.
      var now = Date.now();
      for (var check in this.peers) {
        var pe = this.peers[check];
        if (!pe.born) pe.born = now;
        var stalled = pe.pc.signalingState === 'stable'
          && pe.pc.iceConnectionState === 'new'
          && now - pe.born > 8000;
        if (stalled) this.dropPeer(check, true);
      }
      for (var id in want) {
        if (!this.peers[id]) {
          // Only ONE side offers, or both do at once and the handshake
          // collides. Lower id calls; higher id waits to be called.
          this.makePeer(parseInt(id, 10), this.selfId < parseInt(id, 10));
        }
      }
    },

    makePeer(id, initiator) {
      var self = this;
      var pc = new RTCPeerConnection(ICE);
      var audio = new Audio();
      audio.autoplay = true;
      audio.volume = this.volume;
      // Candidates that turn up before setRemoteDescription() throw if you
      // hand them straight to the peer connection. Swallowing that
      // exception loses them, and losing an early candidate is exactly the
      // kind of failure that works on one network and not the next.
      var entry = { pc: pc, audio: audio, stream: null, pending: [],
                    remoteReady: false, born: Date.now() };
      this.peers[id] = entry;
      // Detached <audio> elements do not reliably play a MediaStream in
      // Chrome. It has to be in the document.
      audio.style.display = 'none';
      document.body.appendChild(audio);

      if (this.mic) {
        this.mic.getTracks().forEach(function (t) { pc.addTrack(t, self.mic); });
      }
      pc.ontrack = function (ev) {
        entry.stream = ev.streams[0];
        audio.srcObject = ev.streams[0];
        audio.play().catch(function () { /* resumed by the next click */ });
      };
      pc.onicecandidate = function (ev) {
        if (ev.candidate) {
          self.send(id, { t: 'ice', c: ev.candidate });
        }
      };
      pc.onconnectionstatechange = function () {
        // Dropping it is what REBUILDS it: the next setPeers() poll sees
        // the peer missing and starts again. Left in place, a failed
        // connection is silent for the rest of the session.
        if (pc.connectionState === 'failed'
            || pc.connectionState === 'closed') {
          self.dropPeer(id);
        }
      };
      if (initiator) {
        pc.createOffer().then(function (o) {
          return pc.setLocalDescription(o);
        }).then(function () {
          self.send(id, { t: 'offer', d: pc.localDescription });
        }).catch(function (e) { self.note(id, 'offer: ' + e); });
      }
      return entry;
    },

    // `notify` tells the far side to drop us too. Rebuilding one end of a
    // connection silently leaves the other holding a live object pointed
    // at a closed one: it never re-offers, because setPeers() can see the
    // peer is "already there". That is a permanently dead pairing, and it
    // is what turning voice on late used to cause on the OTHER machine.
    dropPeer(id, notify) {
      var e = this.peers[id];
      if (!e) return;
      if (notify) this.send(id, { t: 'bye' });
      try { e.pc.close(); } catch (x) {}
      if (e.audio) {
        e.audio.srcObject = null;
        if (e.audio.parentNode) e.audio.parentNode.removeChild(e.audio);
      }
      delete this.peers[id];
    },

    send(to, obj) { this.outbox.push({ to: to | 0, data: JSON.stringify(obj) }); },

    // Godot hands us whatever another machine sent.
    onSignal(from, json) {
      var self = this;
      from = from | 0;
      var msg;
      try { msg = JSON.parse(json); } catch (e) { return; }
      if (msg.t === 'bye') {
        // They are rebuilding. Let go, and the next poll re-dials.
        this.dropPeer(from, false);
        return;
      }
      var entry = this.peers[from];
      if (!entry) {
        if (msg.t !== 'offer') return;   // nothing to answer with yet
        entry = this.makePeer(from, false);
      }
      var pc = entry.pc;
      if (msg.t === 'offer') {
        // Both sides offering at once leaves the handshake wedged. Only
        // the lower id is supposed to offer, so an offer arriving at the
        // side that is already offering is a collision: the caller wins.
        if (pc.signalingState !== 'stable' && this.selfId < from) return;
        pc.setRemoteDescription(msg.d).then(function () {
          return pc.createAnswer();
        }).then(function (a) {
          return pc.setLocalDescription(a);
        }).then(function () {
          self.send(from, { t: 'answer', d: pc.localDescription });
          self.flushCandidates(from);
        }).catch(function (e) { self.note(from, 'answer: ' + e); });
      } else if (msg.t === 'answer') {
        pc.setRemoteDescription(msg.d).then(function () {
          self.flushCandidates(from);
        }).catch(function (e) { self.note(from, 'setRemote(answer): ' + e); });
      } else if (msg.t === 'ice') {
        if (entry.remoteReady) {
          pc.addIceCandidate(msg.c).catch(function () {});
        } else {
          entry.pending.push(msg.c);
        }
      }
    },

    // Hand over every candidate that was waiting for a remote description.
    // A failed handshake is invisible otherwise: the promise rejects, the
    // connection sits at 'new' forever and nothing anywhere says why.
    note(id, what) {
      var e = this.peers[id];
      if (e) e.lastError = String(what);
      this.error = String(what);
    },

    flushCandidates(id) {
      var e = this.peers[id];
      if (!e) return;
      e.remoteReady = true;
      var queued = e.pending;
      e.pending = [];
      for (var i = 0; i < queued.length; i++) {
        e.pc.addIceCandidate(queued[i]).catch(function () {});
      }
    },

    // --- what Godot polls ------------------------------------------
    drain() {
      var out = JSON.stringify(this.outbox);
      this.outbox = [];
      return out;
    },

    status() {
      var talking = [];
      for (var id in this.peers) {
        var e = this.peers[id];
        if (e.stream && e.pc.connectionState === 'connected') talking.push(id | 0);
      }
      return JSON.stringify({
        state: this.state, muted: this.muted,
        connected: talking, error: this.error,
      });
    },
  };

  window.BBVoice = BBVoice;
})();
