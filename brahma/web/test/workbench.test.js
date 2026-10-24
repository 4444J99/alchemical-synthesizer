"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

// Distinct ports from auth.test.js so the two files can run concurrently.
process.env.PORT = "0";
process.env.HOST = "127.0.0.1";
process.env.BRAHMA_OSC_LISTEN_PORT = "0";
process.env.BRAHMA_OSC_SEND_PORT = "57999";
process.env.BRAHMA_DIRT_PORT = "57131";

const ROOT = path.resolve(__dirname, "../../..");
const WB = path.resolve(__dirname, "../public/workbench");

const { server, closeServer } = require("../server");

test.after(async () => {
  await new Promise((resolve) => closeServer(resolve));
});

// ------------------------------------------------------------- licence boundary

test("workbench licence: full AGPL text ships", () => {
  const licence = fs.readFileSync(path.join(ROOT, "LICENSES/AGPL-3.0-or-later.txt"), "utf8");
  assert.ok(licence.includes("GNU AFFERO GENERAL PUBLIC LICENSE"), "licence text must be the AGPL");
  assert.ok(licence.includes("Version 3, 19 November 2007"), "must be version 3");
});

test("workbench licence: NOTICE lists the bundled dependencies", () => {
  const notice = fs.readFileSync(path.join(ROOT, "NOTICE"), "utf8");
  for (const pkg of ["@strudel/core", "@strudel/mini", "@strudel/transpiler", "codemirror"]) {
    assert.ok(notice.includes(pkg), `NOTICE must name ${pkg}`);
  }
  assert.ok(notice.includes("AGPL-3.0-or-later"), "NOTICE must state the workbench licence");
  assert.ok(notice.includes("MIT"), "NOTICE must state the MIT dependencies");
});

test("workbench licence: every shipped source carries an AGPL SPDX header", () => {
  const files = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === "vendor") continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/\.(js|mjs|html|css)$/.test(entry.name)) files.push(full);
    }
  };
  walk(WB);

  assert.ok(files.length >= 7, `expected the workbench subtree to have sources, found ${files.length}`);
  for (const file of files) {
    const head = fs.readFileSync(file, "utf8").split("\n").slice(0, 3).join("\n");
    assert.ok(
      head.includes("SPDX-License-Identifier: AGPL-3.0-or-later"),
      `${path.relative(ROOT, file)} must carry the AGPL SPDX header`
    );
  }
});

test("workbench licence: the page offers its source and imports only its own bundle", () => {
  const html = fs.readFileSync(path.join(WB, "index.html"), "utf8");
  assert.ok(html.includes("/workbench/source.json"), "page must link the source offer");
  assert.ok(html.includes('src="/workbench/vendor/workbench.js"'), "page must load the built bundle");

  // The MIT/LGPL Cortex page and the commercial product tree must not appear in the
  // page graph: they would mix licence obligations into an AGPL document.
  for (const banned of ["p5.min.js", "/cortex/", "/product/"]) {
    assert.ok(!html.includes(banned), `workbench page must not reference ${banned}`);
  }
});

// -------------------------------------------------------- source disclosure API

test("GET /workbench/source.json names the licence, repository and dependencies", async () => {
  const port = server.address().port;
  const res = await fetch(`http://127.0.0.1:${port}/workbench/source.json`);
  assert.equal(res.status, 200);

  const body = await res.json();
  assert.equal(body.workbenchLicense, "AGPL-3.0-or-later");
  assert.equal(body.licenseFile, "/LICENSES/AGPL-3.0-or-later.txt");
  assert.match(body.repository, /alchemical-synthesizer$/);
  assert.ok("commit" in body, "the served revision must be reported (null when unpinned)");

  const names = body.dependencies.map((d) => d.name);
  for (const required of ["@strudel/core", "@strudel/mini", "@strudel/transpiler", "codemirror"]) {
    assert.ok(names.includes(required), `source.json must list ${required}`);
  }
  for (const dep of body.dependencies) {
    assert.ok(dep.version && dep.version !== "unlisted", `${dep.name} must report a pinned version`);
    assert.ok(dep.license, `${dep.name} must report a licence`);
    assert.ok(/^https:\/\//.test(dep.source), `${dep.name} must report an upstream source`);
  }

  const strudel = body.dependencies.find((d) => d.name === "@strudel/core");
  assert.equal(strudel.version, "1.2.6");
  assert.equal(strudel.license, "AGPL-3.0-or-later");
});

test("GET /workbench/ serves the page", async () => {
  const port = server.address().port;
  const res = await fetch(`http://127.0.0.1:${port}/workbench/`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-type") || "", /text\/html/);
  const html = await res.text();
  assert.ok(html.includes("live workbench"));
});

// ------------------------------------------------------------- hap → event map

test("event-map: note control becomes a Brahma event", async () => {
  const { toEvent } = await import(
    pathToFileURL(path.join(WB, "src/event-map.mjs")).href
  );

  const ev = toEvent({ note: 60, s: "sawtooth" }, {
    duration: 0.25,
    id: "pattern",
    engine: "prima_materia",
    knownEngines: new Set()
  });

  assert.equal(ev.type, "event");
  assert.equal(ev.note, 60);
  assert.equal(ev.id, "pattern");
  assert.equal(ev.instance, "pattern");
  assert.equal(ev.engine, "prima_materia", "an unknown sound name falls back to the default engine");
  assert.equal(ev.vel, 0.8, "no gain control means the documented default");
  assert.equal(ev.dur, 0.25, "the scheduler's duration is already in seconds and passes through");
});

test("event-map: a sound matching a real module selects that engine", async () => {
  const { toEvent } = await import(
    pathToFileURL(path.join(WB, "src/event-map.mjs")).href
  );

  const ev = toEvent({ note: 48, s: "chimera" }, {
    duration: 0.5,
    id: "bass",
    knownEngines: new Set(["chimera"])
  });

  assert.equal(ev.engine, "chimera");
  assert.equal(ev.dur, 0.5);
});

test("event-map: note names become MIDI, since Strudel passes strings", async () => {
  const { noteOf, midiFromName } = await import(
    pathToFileURL(path.join(WB, "src/event-map.mjs")).href
  );

  // This is what the browser E2E caught: hap.value.note is "e3", not 52.
  assert.equal(noteOf({ note: "e3" }), 52);
  assert.equal(noteOf({ note: "c3" }), 48, "C4 = 60, so c3 is 48");
  assert.equal(noteOf({ note: "c#4" }), 61);
  assert.equal(noteOf({ note: "eb2" }), 39);
  assert.equal(noteOf({ note: "bb3" }), 58);
  assert.equal(noteOf({ note: "a4" }), 69);
  assert.equal(midiFromName("not-a-note"), null);
  assert.equal(noteOf({ note: "not-a-note" }), null);
  assert.equal(noteOf({ note: "60" }), 60, "a numeric string still reads as MIDI");
});

test("event-map: pitch comes from note, freq, or nothing", async () => {
  const { noteOf } = await import(
    pathToFileURL(path.join(WB, "src/event-map.mjs")).href
  );

  assert.equal(noteOf({ note: 69 }), 69);
  assert.equal(noteOf({ note: 60.4 }), 60, "note rounds");
  assert.equal(noteOf({ note: 300 }), 127, "note clamps to the MIDI range");
  assert.equal(noteOf({ freq: 440 }), 69, "440 Hz is A4");
  assert.equal(noteOf({ freq: 220 }), 57, "220 Hz is A3");
  assert.equal(noteOf({}), null, "a hap without pitch yields no event");
  assert.equal(noteOf({ s: "bd" }), null);
});

test("event-map: velocity, duration and params are clamped and filtered", async () => {
  const { toEvent, MAX_DUR_SECS } = await import(
    pathToFileURL(path.join(WB, "src/event-map.mjs")).href
  );

  const ev = toEvent(
    { note: 60, velocity: 2, cutoff: 800, resonance: 0.4, label: "not numeric" },
    { duration: 999, id: "pattern" }
  );

  assert.equal(ev.vel, 1, "velocity clamps to 1");
  assert.equal(ev.dur, MAX_DUR_SECS, "duration clamps to the engine cap");
  assert.deepEqual(ev.params, ["cutoff", 800, "resonance", 0.4], "only numeric extras pass through");

  const silent = toEvent({ s: "bd" }, { duration: 1 });
  assert.equal(silent, null, "a hap with no pitch produces no event");
});
