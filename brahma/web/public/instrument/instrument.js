// ============================================================================
//  instrument.js — the browser body of Brahma's tracker/sampler instrument.
// ----------------------------------------------------------------------------
//  AETHER plan §5.4. The "mess around with it live" surface: a WebAudio step
//  sequencer driven by pattern.js (the node-tested brain) through an INJECTABLE
//  render adapter (the genesis's PHRASE_EVENT -> VOICE_RENDER_ADAPTER -> audio):
//    * WebAudioAdapter — synthesizes in the browser (always works, no device).
//    * OscAdapter      — drives the live SuperCollider rack over the Visual
//      Cortex WebSocket->OSC bridge (control only; capturing SC's audio back
//      needs a virtual audio device, which stays the one gated atom).
//  Plus a live analyser "orb" visual and the READABLE->CLUSTER->DISPERSAL arc
//  (the same metabolism the broadcast runs). Pure browser code — no build.
// ============================================================================
(function () {
  "use strict";
  if (typeof window === "undefined" || !window.Pattern) return; // node --check / no brain
  var P = window.Pattern;

  var $ = function (id) { return document.getElementById(id); };
  var scene = P.makeScene(16, P.TRACKS.length);
  // A little starter groove so the instrument sings on first play.
  P.setCell(scene, 3, 0, { note: 36, vel: 0.9 }); // ossuary (kick-ish)
  P.setCell(scene, 3, 8, { note: 36, vel: 0.9 });
  P.setCell(scene, 0, 4, { note: 60, vel: 0.7 });
  P.setCell(scene, 0, 12, { note: 60, vel: 0.7 });

  var state = { playing: false, step: 0, tempo: 120, phase: "manual", currentCmd: "", adapterName: "webaudio", cycle: 0 };

  // ---- audio graph (created lazily on first play; browsers gate autoplay) ----
  var ac = null, master = null, analyser = null, freqData = null, sampleRenderer = null, samples = null;
  function ensureAudio() {
    if (ac) return;
    var AC = window.AudioContext || window.webkitAudioContext;
    ac = new AC();
    analyser = ac.createAnalyser(); analyser.fftSize = 256;
    freqData = new Uint8Array(analyser.frequencyBinCount);
    master = window.SampleAudio.outputGraph(ac, analyser);
    sampleRenderer = new window.SampleAudio.Renderer(ac, master, window.BRAHMA_SAMPLE_LIMITS);
    analyser.connect(ac.destination);
  }

  // ---- render adapters ------------------------------------------------------
  // One renderer handles real sample slices and the existing synthetic voices.
  var WebAudioAdapter = {
    name: "WebAudio (local)",
    connected: function () { return true; },
    trigger: function (track, ev, when) {
      sampleRenderer.trigger(track, ev, when);
    },
  };
  // OSC adapter: send /brahma/instrument/note over the Cortex WebSocket bridge.
  var OscAdapter = {
    name: "OSC → SuperCollider", ws: null, ready: false,
    connect: function () {
      try {
        var proto = location.protocol === "https:" ? "wss" : "ws";
        this.ws = new WebSocket(proto + "://" + location.host);
        var self = this;
        this.ws.onopen = function () { self.ready = true; setOscStatus("OSC bridge: connected"); };
        this.ws.onclose = function () { self.ready = false; setOscStatus("OSC bridge: closed"); };
        this.ws.onerror = function () { self.ready = false; setOscStatus("OSC bridge: unavailable (run brahma/web server)"); };
      } catch (e) { setOscStatus("OSC bridge: unavailable"); }
    },
    connected: function () { return this.ready; },
    trigger: function (track, ev /*, when */) {
      if (ev.sampleId != null) throw new Error("Imported samples play in WebAudio (local). Select that engine to hear this pattern.");
      if (!this.ready) return;
      // Control message; the SC rack renders. Namespace is bridge-allowed (/brahma/).
      this.ws.send(JSON.stringify({
        address: "/brahma/instrument/note",
        args: [P.TRACKS[track], ev.note, Number(ev.gain.toFixed(3)), Number(ev.dur.toFixed(3))],
      }));
    },
  };
  function adapter() { return state.adapterName === "osc" ? OscAdapter : WebAudioAdapter; }
  function setOscStatus(s) { $("s-osc").textContent = s; }

  // ---- the scheduler (lookahead) --------------------------------------------
  var LOOKAHEAD = 0.1, TICK = 25;
  var nextStepTime = 0, timer = null;
  function stepDur() { return 60 / state.tempo / 4; } // 16th notes
  function scheduleStep(stepIndex, when) {
    var sd = stepDur();
    for (var t = 0; t < scene.tracks; t++) {
      var cell = scene.grid[t][stepIndex];
      if (!cell) continue;
      var rng = P.makeRng((stepIndex + 1) * (t + 1) * (state.cycle + 1));
      var events = P.expandCell(cell, sd, rng);
      for (var e = 0; e < events.length; e++) adapter().trigger(t, events[e], when);
    }
  }
  function scheduler() {
    while (nextStepTime < ac.currentTime + LOOKAHEAD) {
      try { scheduleStep(state.step, nextStepTime); }
      catch (e) { stop(); samples.report(e.message, true); return; }
      highlight(state.step);
      nextStepTime += stepDur();
      state.step = (state.step + 1) % scene.steps;
      if (state.step === 0) onLoop();
    }
  }
  function onLoop() {
    state.cycle++;
    if (state.phase === "auto") {
      var idx = state.cycle % P.PHASES.length;
      applyPhase(P.PHASES[idx], true);
    }
  }

  // ---- transport ------------------------------------------------------------
  function play() {
    if (state.adapterName === "osc" && scene.grid.some(function (row) { return row.some(function (c) { return c && c.sampleId; }); })) {
      samples.report("Imported samples play in WebAudio (local). Select that engine to hear this pattern.", true);
      return;
    }
    ensureAudio();
    if (ac.state === "suspended") ac.resume();
    if (state.adapterName === "osc" && !OscAdapter.ws) OscAdapter.connect();
    if (state.playing) return;
    state.playing = true; state.step = 0; nextStepTime = ac.currentTime + 0.05;
    $("play").setAttribute("aria-pressed", "true");
    timer = setInterval(scheduler, TICK);
  }
  function stop() {
    if (samples) samples.cancelNative();
    state.playing = false;
    if (timer) { clearInterval(timer); timer = null; }
    if (sampleRenderer) sampleRenderer.stopAll();
    $("play").setAttribute("aria-pressed", "false");
    clearHighlight();
  }

  // ---- the generative arc ---------------------------------------------------
  function applyPhase(phase, keepAuto) {
    scene = P.redistribute(scene, phase, (state.cycle + 1) * 7);
    state.phase = keepAuto ? "auto" : phase;
    renderGrid();
    var badge = $("s-phase");
    badge.textContent = phase.toUpperCase();
    badge.className = "badge phase-" + (P.PHASES.indexOf(phase) >= 0 ? phase : "readable");
    updateVersion();
  }

  // ---- DOM grid -------------------------------------------------------------
  function renderGrid() {
    var g = $("grid"); g.innerHTML = "";
    for (var t = 0; t < scene.tracks; t++) {
      var tr = document.createElement("tr");
      var name = document.createElement("td");
      name.className = "trk"; name.textContent = samples ? samples.trackLabel(t) : P.TRACKS[t]; tr.appendChild(name);
      for (var s = 0; s < scene.steps; s++) {
        var td = document.createElement("td");
        if (s % 4 === 0) td.className = "beat";
        var cell = scene.grid[t][s];
        if (cell) {
          td.classList.add("on"); td.textContent = cell.cmd || "•";
          if (cell.sampleId) { td.classList.add("sample"); td.textContent = (cell.slice + 1) + (cell.cmd || ""); td.title = "Chop " + (cell.slice + 1); }
        }
        (function (tt, ss, cellEl) {
          cellEl.addEventListener("click", function () { toggleCell(tt, ss); });
        })(t, s, td);
        tr.appendChild(td);
      }
      g.appendChild(tr);
    }
  }
  function toggleCell(t, s) {
    var cur = scene.grid[t][s];
    var baseNote = [48, 50, 55, 36, 67][t % 5];
    var amt = { RT: 4, ST: 4, OV: 1, HU: 0.3, DN: 0.5 }[state.currentCmd] || 0;
    var next = samples.cell(t, { note: baseNote, vel: 0.8, cmd: state.currentCmd, amt: amt });
    if (cur && cur.cmd === next.cmd && cur.sampleId === next.sampleId && cur.slice === next.slice) {
      P.setCell(scene, t, s, null); // click again with same cmd → clear
    } else {
      P.setCell(scene, t, s, next);
    }
    renderGrid(); updateVersion();
  }
  var playCells = [];
  function highlight(step) {
    clearHighlight();
    var rows = $("grid").rows;
    for (var r = 0; r < rows.length; r++) {
      var cell = rows[r].cells[step + 1]; // +1 for the track-name column
      if (cell) { cell.classList.add("playhead"); playCells.push(cell); }
    }
  }
  function clearHighlight() { playCells.forEach(function (c) { c.classList.remove("playhead"); }); playCells = []; }

  function updateVersion() { $("s-version").textContent = P.sceneVersion(scene); }

  // ---- the reactive orb (analyser-driven) -----------------------------------
  function drawOrb() {
    requestAnimationFrame(drawOrb);
    var c = $("orb"); if (!c) return;
    var ctx = c.getContext("2d");
    var w = c.width = c.clientWidth, h = c.height = c.clientHeight;
    ctx.clearRect(0, 0, w, h);
    var cx = w / 2, cy = h / 2;
    var level = 0;
    if (analyser) { analyser.getByteFrequencyData(freqData); }
    var bins = freqData ? freqData.length : 0;
    for (var i = 0; i < bins; i++) level += freqData[i];
    level = bins ? level / bins / 255 : 0;
    var rings = 5;
    for (var k = rings; k >= 1; k--) {
      var band = freqData ? freqData[Math.floor((k / rings) * (bins - 1))] / 255 : 0;
      var radius = 12 + k * 14 + band * 40 + level * 30;
      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      var hue = 210 + k * 20 + (state.phase === "dispersal" ? 120 : 0);
      ctx.strokeStyle = "hsla(" + hue + ",80%," + (55 + band * 30) + "%," + (0.15 + band * 0.5) + ")";
      ctx.lineWidth = 1.5 + band * 3;
      ctx.stroke();
    }
    ctx.fillStyle = "hsla(210,90%,70%," + (0.3 + level * 0.6) + ")";
    ctx.beginPath(); ctx.arc(cx, cy, 6 + level * 18, 0, Math.PI * 2); ctx.fill();
  }

  // ---- wiring ---------------------------------------------------------------
  $("play").addEventListener("click", play);
  $("stop").addEventListener("click", stop);
  $("tempo").addEventListener("input", function (e) { state.tempo = +e.target.value; $("tempoval").textContent = state.tempo; });
  $("cmd").addEventListener("change", function (e) { state.currentCmd = e.target.value; });
  $("adapter").addEventListener("change", function (e) {
    stop();
    state.adapterName = e.target.value;
    $("s-adapter").textContent = adapter().name;
    if (state.adapterName === "osc") { OscAdapter.connect(); } else { setOscStatus(""); }
  });
  $("phase").addEventListener("change", function (e) {
    var v = e.target.value;
    if (v === "manual") { state.phase = "manual"; $("s-phase").textContent = "manual"; $("s-phase").className = "badge phase-readable"; }
    else applyPhase(v);
  });
  $("clear").addEventListener("click", function () { scene = P.makeScene(scene.steps, scene.tracks); renderGrid(); updateVersion(); });

  function localEngine() {
    state.adapterName = "webaudio"; $("adapter").value = "webaudio";
    $("s-adapter").textContent = WebAudioAdapter.name; setOscStatus("");
  }
  samples = window.SampleControls.attach({
    renderer: function () { ensureAudio(); return sampleRenderer; },
    scene: function () { return scene; },
    transport: function () { return state; },
    stop: stop, local: localEngine,
    replaceScene: function (next) { scene = next; renderGrid(); updateVersion(); },
    restore: function (project) {
      scene = project.scene; state.tempo = project.tempo; state.phase = project.phase;
      state.cycle = project.cycle; state.step = 0;
      $("tempo").value = state.tempo; $("tempoval").textContent = state.tempo;
      $("phase").value = state.phase; $("s-phase").textContent = state.phase;
      $("s-phase").className = "badge phase-" + (P.PHASES.indexOf(state.phase) >= 0 ? state.phase : "readable");
      localEngine(); renderGrid(); updateVersion();
    },
  });

  renderGrid();
  updateVersion();
  $("s-adapter").textContent = WebAudioAdapter.name;
  drawOrb();
})();
