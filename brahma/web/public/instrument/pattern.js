// ============================================================================
//  pattern.js — the pure logic of Brahma's tracker/sampler instrument.
// ----------------------------------------------------------------------------
//  AETHER plan §4 (the sampler instrument E3) + §5.4. "Tracker-brained,
//  Ableton-bodied": this module is the *brain* — backend-agnostic pattern +
//  per-cell command language + the owner's generative arc READABLE -> CLUSTER ->
//  DISPERSAL — with NO audio or DOM. instrument.js (browser) drives it through
//  an injectable render adapter (WebAudio or OSC->SuperCollider). Keeping the
//  logic here, pure and dependency-free, means it has a real self-test predicate
//  that runs in node (unlike WebAudio, which can't run headless).
//
//  Loads as a browser global (window.Pattern) AND as a node module (require),
//  so smoke can run `node pattern.js --self-test`.
// ============================================================================
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.Pattern = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  // The generative arc — same phases as the METABOLISM organism (tools/cellcycle.py).
  var PHASES = ["readable", "cluster", "dispersal"];

  // The five sampler creatures = the tracks (intake organs).
  var TRACKS = ["mnemosyne", "protean-hound", "chrysalid-siren", "ossuary-monk", "janiform-child"];

  // Per-cell command language (AETHER plan §4): where playback becomes
  // compositional infrastructure. Each expands a base step into sub-events.
  var COMMANDS = {
    "":   { name: "play",     desc: "one hit" },
    RT:   { name: "ratchet",  desc: "N evenly-spaced retriggers" },
    ST:   { name: "stutter",  desc: "a decaying roll" },
    OV:   { name: "overlap",  desc: "legato — sustain past the step" },
    HU:   { name: "humanize", desc: "jitter timing + velocity" },
    DN:   { name: "density",  desc: "probabilistic gate" },
  };

  // ---- deterministic PRNG (matches cellcycle.py's LCG, for reproducibility) --
  function lcg(seed) { return (seed * 1103515245 + 12345) & 0x7fffffff; }
  function makeRng(seed) {
    var s = (seed | 0) & 0x7fffffff || 1;
    return function () { s = lcg(s); return s / 0x7fffffff; };
  }

  // ---- scene model ----------------------------------------------------------
  // A scene is a mutable grid; a scene_version is an immutable snapshot id.
  function makeScene(steps, tracks) {
    steps = steps || 16;
    tracks = tracks || TRACKS.length;
    var grid = [];
    for (var t = 0; t < tracks; t++) {
      var row = [];
      for (var s = 0; s < steps; s++) row.push(null); // null = empty cell
      grid.push(row);
    }
    return { steps: steps, tracks: tracks, grid: grid, tempo: 120, phase: "readable" };
  }

  // A cell: { note, vel, cmd, amt }. Helper to set one.
  function setCell(scene, track, step, cell) {
    if (track < 0 || track >= scene.tracks || step < 0 || step >= scene.steps) return scene;
    scene.grid[track][step] = cell ? { note: cell.note != null ? cell.note : 60,
      vel: cell.vel != null ? cell.vel : 0.8, cmd: cell.cmd || "", amt: cell.amt != null ? cell.amt : 0 } : null;
    if (cell && cell.sampleId != null) {
      scene.grid[track][step].sampleId = cell.sampleId;
      scene.grid[track][step].slice = cell.slice != null ? cell.slice : 0;
    }
    return scene;
  }

  function activeCount(scene) {
    var n = 0;
    for (var t = 0; t < scene.tracks; t++) for (var s = 0; s < scene.steps; s++) if (scene.grid[t][s]) n++;
    return n;
  }

  // ---- FNV-1a hash → the immutable scene_version id -------------------------
  function sceneVersion(scene) {
    // Canonical string of the musically-meaningful state (not tempo/phase UI).
    var canon = JSON.stringify(scene.grid);
    var h = 0x811c9dc5;
    for (var i = 0; i < canon.length; i++) {
      h ^= canon.charCodeAt(i);
      h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
    }
    return "sv_" + ("0000000" + h.toString(16)).slice(-8);
  }

  // ---- per-cell command expansion ------------------------------------------
  // Expand a cell into timed sub-events within its step slot [0, stepDur).
  // Returns [] or [{ t, note, gain, dur }] (t is an offset in seconds).
  function expandTiming(cell, stepDur, rng) {
    if (!cell || cell.note == null) return [];
    rng = rng || makeRng(1);
    var note = cell.note, vel = cell.vel != null ? cell.vel : 0.8;
    var amt = cell.amt || 0;
    switch (cell.cmd) {
      case "RT": {
        var n = Math.max(2, Math.min(16, amt || 4));
        var out = [];
        for (var i = 0; i < n; i++) out.push({ t: (i / n) * stepDur, note: note, gain: vel, dur: stepDur / n });
        return out;
      }
      case "ST": {
        var m = Math.max(2, Math.min(16, amt || 4));
        var o = [];
        for (var j = 0; j < m; j++) o.push({ t: (j / m) * stepDur, note: note, gain: vel * Math.pow(0.7, j), dur: stepDur / m });
        return o;
      }
      case "OV": {
        var factor = 1 + (amt || 1);
        return [{ t: 0, note: note, gain: vel, dur: stepDur * factor }];
      }
      case "HU": {
        var jitter = (amt || 0.2);
        var dt = (rng() - 0.5) * 2 * jitter * stepDur;
        var dv = 1 + (rng() - 0.5) * jitter;
        return [{ t: Math.max(0, dt), note: note, gain: Math.max(0.05, Math.min(1, vel * dv)), dur: stepDur }];
      }
      case "DN": {
        var prob = amt != null && amt > 0 ? amt : 0.5;
        return rng() < prob ? [{ t: 0, note: note, gain: vel, dur: stepDur }] : [];
      }
      default:
        return [{ t: 0, note: note, gain: vel, dur: stepDur }];
    }
  }

  function expandCell(cell, stepDur, rng) {
    var events = expandTiming(cell, stepDur, rng);
    if (cell && cell.sampleId != null) events.forEach(function (ev) {
      ev.sampleId = cell.sampleId; ev.slice = cell.slice;
    });
    return events;
  }

  function inheritSample(source, changes) {
    if (source.sampleId != null) { changes.sampleId = source.sampleId; changes.slice = source.slice; }
    return changes;
  }

  // ---- the generative arc: redistribute a scene for a phase ------------------
  // READABLE  → sparse, linear (downbeats only) — legible.
  // CLUSTER   → dense, repeating clusters — bulked up.
  // DISPERSAL → atomized fragments scattered + stuttered — shedding structure.
  // Deterministic given `seed`. Returns a NEW scene (does not mutate input).
  function redistribute(scene, phase, seed) {
    var rng = makeRng(seed || 1);
    var out = makeScene(scene.steps, scene.tracks);
    out.tempo = scene.tempo; out.phase = phase;

    // Seed hits: the active cells of the input become the source material.
    var sources = [];
    for (var t = 0; t < scene.tracks; t++)
      for (var s = 0; s < scene.steps; s++)
        if (scene.grid[t][s]) sources.push({ t: t, s: s, cell: scene.grid[t][s] });
    // If the input is empty, seed one hit per track so the arc has material.
    if (!sources.length)
      for (var tt = 0; tt < scene.tracks; tt++) sources.push({ t: tt, s: 0, cell: { note: 48 + tt * 3, vel: 0.8, cmd: "", amt: 0 } });

    if (phase === "readable") {
      // Keep structural downbeats only: every 4th step, no ornament commands.
      sources.forEach(function (h) {
        if (h.s % 4 === 0) setCell(out, h.t, h.s, inheritSample(h.cell, { note: h.cell.note, vel: h.cell.vel, cmd: "", amt: 0 }));
      });
      // Guarantee at least a pulse on track 0.
      if (activeCount(out) === 0) setCell(out, sources[0].t, 0, inheritSample(sources[0].cell, { note: sources[0].cell.note, vel: 0.8, cmd: "", amt: 0 }));
    } else if (phase === "cluster") {
      // Redistribute each source into a short repeating cluster around it.
      sources.forEach(function (h) {
        var len = 2 + Math.floor(rng() * 3); // 2..4 wide
        for (var k = 0; k < len; k++) {
          var s = (h.s + k) % out.steps;
          setCell(out, h.t, s, inheritSample(h.cell, { note: h.cell.note, vel: 0.6 + rng() * 0.3, cmd: rng() < 0.3 ? "RT" : "", amt: 2 + Math.floor(rng() * 3) }));
        }
      });
    } else { // dispersal
      // Atomize: scatter fragments to random positions, favor stutters, thin out.
      sources.forEach(function (h) {
        var frags = 1 + Math.floor(rng() * 3);
        for (var f = 0; f < frags; f++) {
          var s2 = Math.floor(rng() * out.steps);
          setCell(out, h.t, s2, inheritSample(h.cell, { note: Math.max(0, Math.min(127, h.cell.note + Math.floor((rng() - 0.5) * 12))), vel: 0.4 + rng() * 0.4, cmd: rng() < 0.6 ? "ST" : "HU", amt: rng() < 0.6 ? 3 + Math.floor(rng() * 4) : 0.3 }));
        }
      });
    }
    return out;
  }

  return {
    PHASES: PHASES, TRACKS: TRACKS, COMMANDS: COMMANDS,
    makeRng: makeRng, makeScene: makeScene, setCell: setCell, activeCount: activeCount,
    sceneVersion: sceneVersion, expandCell: expandCell, redistribute: redistribute,
  };
});

// ---- self-test (node: `node pattern.js --self-test`) ------------------------
if (typeof require !== "undefined" && require.main === module) {
  var P = module.exports;
  var fails = [];

  // 1. scene_version: stable, and changes when the grid changes.
  var sc = P.makeScene(16, 5);
  var v0 = P.sceneVersion(sc);
  if (P.sceneVersion(sc) !== v0) fails.push("sceneVersion not stable");
  P.setCell(sc, 0, 0, { note: 60, vel: 0.9 });
  if (P.sceneVersion(sc) === v0) fails.push("sceneVersion did not change after edit");

  // 2. per-cell commands expand correctly.
  var rt = P.expandCell({ note: 60, vel: 0.8, cmd: "RT", amt: 4 }, 0.5, P.makeRng(1));
  if (rt.length !== 4) fails.push("RT ratchet should yield 4 events, got " + rt.length);
  var st = P.expandCell({ note: 60, vel: 0.8, cmd: "ST", amt: 4 }, 0.5, P.makeRng(1));
  if (!(st.length === 4 && st[3].gain < st[0].gain)) fails.push("ST stutter should decay in gain");
  var ov = P.expandCell({ note: 60, vel: 0.8, cmd: "OV", amt: 1 }, 0.5, P.makeRng(1));
  if (!(ov.length === 1 && ov[0].dur > 0.5)) fails.push("OV overlap should sustain past the step");
  var plain = P.expandCell({ note: 60, vel: 0.8, cmd: "" }, 0.5);
  if (plain.length !== 1) fails.push("plain cell should yield 1 event");
  if (P.expandCell(null, 0.5).length !== 0) fails.push("empty cell should yield 0 events");

  // 3. HU humanize is deterministic given a seed.
  var h1 = P.expandCell({ note: 60, vel: 0.8, cmd: "HU", amt: 0.3 }, 0.5, P.makeRng(7));
  var h2 = P.expandCell({ note: 60, vel: 0.8, cmd: "HU", amt: 0.3 }, 0.5, P.makeRng(7));
  if (JSON.stringify(h1) !== JSON.stringify(h2)) fails.push("HU not deterministic for a fixed seed");

  // 4. the arc: density readable < cluster, dispersal scatters/atomizes.
  var base = P.makeScene(16, 5);
  P.setCell(base, 0, 0, { note: 48 }); P.setCell(base, 1, 4, { note: 50 }); P.setCell(base, 2, 8, { note: 52 });
  var rd = P.redistribute(base, "readable", 3);
  var cl = P.redistribute(base, "cluster", 3);
  var di = P.redistribute(base, "dispersal", 3);
  if (!(P.activeCount(rd) <= P.activeCount(cl))) fails.push("readable density should be <= cluster (" + P.activeCount(rd) + " vs " + P.activeCount(cl) + ")");
  if (P.activeCount(cl) < 3) fails.push("cluster should bulk up density");
  // dispersal should introduce ornament commands (ST/HU).
  var hasOrnament = di.grid.some(function (row) { return row.some(function (c) { return c && (c.cmd === "ST" || c.cmd === "HU"); }); });
  if (!hasOrnament) fails.push("dispersal should atomize with ST/HU commands");

  // 5. redistribute is deterministic + does not mutate the input.
  var beforeVer = P.sceneVersion(base);
  var a = P.redistribute(base, "cluster", 9), b = P.redistribute(base, "cluster", 9);
  if (P.sceneVersion(a) !== P.sceneVersion(b)) fails.push("redistribute not deterministic for a fixed seed");
  if (P.sceneVersion(base) !== beforeVer) fails.push("redistribute mutated its input scene");

  if (fails.length) { console.log("pattern self-test: FAIL"); fails.forEach(function (f) { console.log("  - " + f); }); process.exit(1); }
  console.log("pattern self-test: PASS (scene_version, per-cell commands, generative arc, determinism)");
}
