"use strict";
const { describe, it, before, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");
const crypto = require("node:crypto");

// Each quarter-second has a different pitch, making wrong chop offsets or an
// oscillator fallback audible and measurable without a physical audio device.
function donorWav() {
  const rate = 8000, frames = 16000, b = Buffer.alloc(44 + frames * 2);
  b.write("RIFF"); b.writeUInt32LE(b.length - 8, 4); b.write("WAVEfmt ", 8);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(rate, 24); b.writeUInt32LE(rate * 2, 28);
  b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write("data", 36);
  b.writeUInt32LE(frames * 2, 40);
  for (let i = 0; i < frames; i++) {
    const t = i / rate, hz = 220 + 110 * Math.floor(t / 0.25);
    b.writeInt16LE(Math.round(0.4 * 32767 * Math.sin(2 * Math.PI * hz * t)), 44 + i * 2);
  }
  return b;
}
async function until(fn, ms = 10000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const result = await fn(); if (result) return result;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error("Timed out waiting for instrument operation");
}

describe("local sample instrument", () => {
  const ctx = {};
  before(async () => {
    const chrome = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium", "/usr/bin/google-chrome", "/usr/bin/chromium"].find(fs.existsSync);
    if (!chrome) { ctx.skip = "Chrome unavailable; sample browser acceptance unmeasured"; return; }
    ctx.dir = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-sample-e2e-"));
    ctx.donor = path.join(ctx.dir, 'donor "one".wav'); fs.writeFileSync(ctx.donor, donorWav());
    const webDir = path.resolve(__dirname, "../..");
    let output = "";
    ctx.server = spawn(process.execPath, ["server.js"], { cwd: webDir,
      env: { ...process.env, PORT: "0", HOST: "127.0.0.1", BRAHMA_OSC_LISTEN_PORT: "0",
        BRAHMA_OSC_SEND_PORT: "59998", BRAHMA_DIRT_PORT: "0", BRAHMA_HUMAN_TOKEN: "sample-browser-fixture-token" } });
    ctx.server.stdout.on("data", d => { output = (output + d).slice(-16000); });
    ctx.server.stderr.on("data", d => { output = (output + d).slice(-16000); });
    const match = await until(() => /VISUAL CORTEX ONLINE: http:\/\/127\.0\.0\.1:(\d+)/.exec(output));
    ctx.url = `http://127.0.0.1:${match[1]}/instrument/`;
    ctx.browser = await require("puppeteer-core").launch({ executablePath: chrome, headless: true,
      args: ["--no-first-run", "--no-default-browser-check", "--autoplay-policy=no-user-gesture-required"] });
    ctx.page = await ctx.browser.newPage();
    ctx.errors = []; ctx.page.on("pageerror", e => ctx.errors.push(e.message));
    const cdp = await ctx.page.createCDPSession();
    await cdp.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: ctx.dir });
    await ctx.page.goto(ctx.url);
  });
  after(async () => {
    if (ctx.browser) await ctx.browser.close();
    if (ctx.server) ctx.server.kill("SIGTERM");
    if (ctx.dir) fs.rmSync(ctx.dir, { recursive: true, force: true });
  });
  const skip = t => { if (ctx.skip) { t.skip(ctx.skip); return true; } return false; };
  async function upload(selector, filename) {
    const input = await ctx.page.$(selector);
    assert.ok(input, `the instrument needs ${selector}`);
    await input.uploadFile(filename);
  }
  async function status(pattern) {
    await ctx.page.waitForFunction(source => new RegExp(source).test(document.querySelector("#sample-status").textContent),
      { timeout: 10000 }, pattern);
  }
  async function setInput(selector, value) {
    await ctx.page.$eval(selector, (el, v) => { el.value = v; el.dispatchEvent(new Event("input", { bubbles: true })); }, value);
  }

  it("imports real audio, edits chops, saves bytes, reopens and exports the chosen sample", async t => {
    if (skip(t)) return;
    await upload("#audio-file", ctx.donor); await status("Loaded");
    assert.equal(await ctx.page.$$eval("#chops button", buttons => buttons.length), 8);
    await ctx.page.click('#chops button[data-slice="2"]');
    await setInput("#slice-start", "0.5"); await setInput("#slice-end", "0.7");
    await ctx.page.click("#apply-slice");
    await ctx.page.click("#clear");
    await ctx.page.click("#grid tr:nth-child(1) td:nth-child(2)");
    await setInput("#tempo", "104");
    await setInput("#project-name", "Chopped session");
    await ctx.page.click("#freeze");
    const saved = await until(() => fs.readdirSync(ctx.dir).find(f => f.endsWith(".brahma.json")));
    ctx.saved = path.join(ctx.dir, saved);
    const project = JSON.parse(fs.readFileSync(ctx.saved, "utf8"));
    assert.equal(project.tempo, 104); assert.equal(project.sources.length, 1);
    assert.deepEqual(project.sources[0].slices[2], { start: 0.5, end: 0.7 });
    assert.deepEqual(Buffer.from(project.sources[0].data, "base64"), donorWav());
    assert.equal(project.sources[0].sha256, crypto.createHash("sha256").update(donorWav()).digest("hex"));
    assert.equal(project.scene.grid[0][0].sampleId, project.sources[0].id);
    assert.equal(project.scene.grid[0][0].slice, 2);
    await ctx.page.reload();
    await upload("#open-project", ctx.saved); await status("Opened");
    assert.equal(await ctx.page.$eval("#tempo", el => el.value), "104");
    assert.equal(await ctx.page.$eval("#project-name", el => el.value), "Chopped session");
    assert.equal(await ctx.page.$$eval("#grid td.on", cells => cells.length), 1);
    await ctx.page.click("#export-loop");
    const wav = await until(() => fs.readdirSync(ctx.dir).find(f => f.endsWith(".wav") && !f.startsWith("donor")));
    const rendered = fs.readFileSync(path.join(ctx.dir, wav));
    assert.equal(rendered.toString("ascii", 0, 4), "RIFF");
    assert.equal(rendered.readUInt16LE(22), 2);
    const sr = rendered.readUInt32LE(24), channels = rendered.readUInt16LE(22);
    assert.equal(rendered.readUInt32LE(40) / (channels * 2), Math.round(16 * 60 / 104 / 4 * sr),
      "loop WAV must have exactly one musical cycle, without trailing padding");
    let crossings = 0, peak = 0, previous = 0;
    for (let i = Math.ceil(sr * 0.025); i < Math.floor(sr * 0.1); i++) {
      const sample = rendered.readInt16LE(44 + i * channels * 2);
      if (sample > 0 && previous <= 0) crossings++;
      peak = Math.max(peak, Math.abs(sample)); previous = sample;
    }
    assert.ok(peak > 500, "export must contain the uploaded sound");
    const hz = crossings / 0.075;
    assert.ok(hz > 420 && hz < 470, `expected the 440 Hz chop, got ${hz} Hz`);
    if (process.env.BRAHMA_INSTRUMENT_SCREENSHOT) await ctx.page.screenshot({
      path: process.env.BRAHMA_INSTRUMENT_SCREENSHOT, fullPage: true });
    assert.deepEqual(ctx.errors, []);
  });

  it("failed project restore preserves the currently playable source and pattern", async t => {
    if (skip(t)) return;
    assert.ok(ctx.saved, "round-trip acceptance must create a portable project");
    const broken = JSON.parse(fs.readFileSync(ctx.saved));
    broken.sources[0].data = Buffer.from("not the source").toString("base64");
    const filename = path.join(ctx.dir, "corrupt.json"); fs.writeFileSync(filename, JSON.stringify(broken));
    await upload("#open-project", filename); await status("integrity");
    assert.equal(await ctx.page.$$eval("#grid td.on", cells => cells.length), 1);
    assert.match(await ctx.page.$eval("#sample-source", el => el.selectedOptions[0].textContent), /donor/);
    await ctx.page.click('#chops button[data-slice="2"]');
    await ctx.page.click("#stop");
    assert.deepEqual(ctx.errors, []);
  });

  it("real renderer cancels scheduled sample voices and refuses missing samples", async t => {
    if (skip(t)) return;
    const project = JSON.parse(fs.readFileSync(ctx.saved));
    const measured = await ctx.page.evaluate(async project => {
      const audio = new OfflineAudioContext(2, 48000, 48000);
      const renderer = new SampleAudio.Renderer(audio, audio.destination);
      await renderer.loadSources(project.sources);
      renderer.trigger(0, { sampleId: project.sources[0].id, slice: 2, note: 60, gain: 0.8, dur: 0.2, t: 0 }, 0.5);
      renderer.stopAll();
      let missing = "";
      try { renderer.trigger(0, { sampleId: "missing", slice: 0, note: 60, gain: 1, dur: 0.1, t: 0 }, 0); }
      catch (e) { missing = e.message; }
      const result = await audio.startRendering();
      let peak = 0; for (const v of result.getChannelData(0)) peak = Math.max(peak, Math.abs(v));
      return { peak, missing };
    }, project);
    assert.equal(measured.peak, 0, "stop must cancel future as well as current voices");
    assert.match(measured.missing, /missing|unavailable/i);
  });

  it("duplicate imports reuse the decoded buffer and preserve edited chops", async t => {
    if (skip(t)) return;
    await ctx.page.evaluate(() => {
      window.decodeCount = 0;
      window.originalDecode = AudioContext.prototype.decodeAudioData;
      AudioContext.prototype.decodeAudioData = function (...args) {
        window.decodeCount++; return window.originalDecode.apply(this, args);
      };
    });
    try {
      await upload("#audio-file", ctx.donor); await status("Loaded existing source");
      assert.equal(await ctx.page.evaluate(() => window.decodeCount), 0);
      assert.equal(await ctx.page.$$eval("#sample-source option", opts => opts.length), 2);
      await ctx.page.click('#chops button[data-slice="2"]');
      assert.equal(await ctx.page.$eval("#slice-end", el => el.value), "0.700");
    } finally {
      await ctx.page.evaluate(() => { AudioContext.prototype.decodeAudioData = window.originalDecode; });
    }
  });

  it("Stop cancels an audition waiting for the audio context to resume", async t => {
    if (skip(t)) return;
    const triggers = await ctx.page.evaluate(async () => {
      const originalResume = AudioContext.prototype.resume, originalTrigger = SampleAudio.Renderer.prototype.trigger;
      let resolveResume, count = 0;
      AudioContext.prototype.resume = () => new Promise(resolve => { resolveResume = resolve; });
      SampleAudio.Renderer.prototype.trigger = function (...args) { count++; return originalTrigger.apply(this, args); };
      try {
        document.querySelector('#chops button[data-slice="2"]').click();
        document.querySelector("#stop").click();
        resolveResume(); await Promise.resolve(); await Promise.resolve();
        return count;
      } finally {
        document.querySelector("#stop").click();
        AudioContext.prototype.resume = originalResume; SampleAudio.Renderer.prototype.trigger = originalTrigger;
      }
    });
    assert.equal(triggers, 0, "Stop must invalidate pending auditions as well as existing voices");
  });

  it("changing engines stops playback and cannot send sample notes over OSC", async t => {
    if (skip(t)) return;
    await ctx.page.click("#play");
    assert.equal(await ctx.page.$eval("#play", el => el.getAttribute("aria-pressed")), "true");
    await ctx.page.select("#adapter", "osc");
    assert.equal(await ctx.page.$eval("#play", el => el.getAttribute("aria-pressed")), "false");
    await ctx.page.click("#play"); await status("Imported samples play in WebAudio");
    assert.equal(await ctx.page.$eval("#play", el => el.getAttribute("aria-pressed")), "false");
    await ctx.page.select("#adapter", "webaudio");
  });

  async function nativeFixture() {
    const bytes = donorWav();
    for (let i = 44; i < bytes.length; i += 2) bytes.writeInt16LE(-bytes.readInt16LE(i), i);
    const hash = crypto.createHash("sha256").update(bytes).digest("hex");
    ctx.nativeReady = true; ctx.nativeInputHash = null;
    await ctx.page.setRequestInterception(true);
    const handler = request => {
      const suffix = new URL(request.url()).pathname.replace("/api/instrument/native", "");
      if (!new URL(request.url()).pathname.startsWith("/api/instrument/native/jobs")) return request.continue();
      if (suffix.endsWith("/audio")) return request.respond({ status: 200, contentType: "audio/wav", body: bytes });
      if (request.method() === "POST") { ctx.nativeRequest = JSON.parse(request.postData()); ctx.nativeInputHash = ctx.nativeRequest.audio.sha256; }
      const resolved = ctx.nativeRequest && ctx.nativeRequest.material ? require("../../public/instrument/material-model").resolve(
        ctx.nativeRequest.module, ctx.nativeRequest.params, ctx.nativeRequest.material) : null;
      const job = { id: "native_browser_fixture", module: "solve_pitch_shift", params: { semitones: 7, mix: 1 },
        state: request.method() === "DELETE" ? "cancelled" : request.method() === "POST" || !ctx.nativeReady ? "running" : "completed",
        sourceSha256: ctx.nativeInputHash, result: { sha256: hash, duration: 2,
          definitionSha256: "a".repeat(64), rackSha256: "b".repeat(64) } };
      if (resolved) {
        job.params = resolved.params; job.material = resolved.material; job.baseParams = ctx.nativeRequest.params;
        job.result.modelSha256 = resolved.modelSha256;
      }
      return request.respond({ status: request.method() === "POST" ? 202 : 200,
        contentType: "application/json", body: JSON.stringify(job) });
    };
    ctx.page.on("request", handler);
    return async () => { ctx.page.off("request", handler); await ctx.page.setRequestInterception(false); };
  }
  async function connectNative() {
    await ctx.page.evaluate(async () => {
      const response = await fetch("/api/auth/exchange", { method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ token: "sample-browser-fixture-token" }) }); // allow-secret: synthetic test session only
      if (!response.ok) throw new Error("fixture session exchange failed");
    });
    assert.ok(await ctx.page.$("#native-connect"), "the instrument needs native transformation controls");
    await ctx.page.click("#native-connect");
    await ctx.page.waitForFunction(() => document.querySelector("#native-module").options.length > 200);
    assert.match(await ctx.page.$eval("#module-count", el => el.textContent), /245 native definitions.*26 material mappings.*21/);
    assert.equal(await ctx.page.$$eval("#module-ledger tr", rows => rows.length), 245);
    await ctx.page.select("#native-module", "solve_pitch_shift");
    await setInput('#native-params input[data-param="semitones"]', "7");
  }
  it("applies native audio while playing and saves its exact recipe and retained original", async t => {
    if (skip(t)) return;
    await upload("#open-project", ctx.saved); await status("Opened");
    const cleanup = await nativeFixture();
    try {
      await connectNative();
      await setInput("#project-name", "Native acceptance");
      await ctx.page.click("#play");
      await ctx.page.click("#native-render");
      await ctx.page.waitForFunction(() => /Applied/.test(document.querySelector("#native-status").textContent));
      assert.equal(await ctx.page.$eval("#play", el => el.getAttribute("aria-pressed")), "true");
      await ctx.page.click("#stop"); await ctx.page.click("#freeze"); await status("Saved");
      const filename = path.join(ctx.dir, "Native-acceptance.brahma.json");
      await until(() => fs.existsSync(filename));
      const project = JSON.parse(fs.readFileSync(filename));
      assert.equal(project.sources.length, 2);
      const output = project.sources.find(source => source.recipe);
      assert.equal(output.recipe.module, "solve_pitch_shift");
      assert.equal(output.recipe.params.semitones, 7);
      assert.equal(output.recipe.parentId, project.sources[0].id);
      assert.equal(project.scene.grid[0][0].sampleId, output.id);
      assert.deepEqual(output.slices[2], { start: .5, end: .7 });
      await upload("#open-project", filename); await status("Opened");
      assert.equal(await ctx.page.$eval('#native-params input[data-param="semitones"]', el => el.value), "7");
      await ctx.page.click("#native-original");
      assert.match(await ctx.page.$eval("#sample-source", el => el.selectedOptions[0].textContent), /donor/);
    } finally { await cleanup(); }
  });
  it("Stop invalidates a pending native result without replacing the current source", async t => {
    if (skip(t)) return;
    await upload("#open-project", ctx.saved); await status("Opened");
    const cleanup = await nativeFixture();
    try {
      await connectNative(); ctx.nativeReady = false;
      await ctx.page.click("#native-render");
      await ctx.page.waitForFunction(() => /Rendering/.test(document.querySelector("#native-status").textContent));
      await ctx.page.click("#stop"); ctx.nativeReady = true;
      await ctx.page.waitForFunction(() => /Cancelled/.test(document.querySelector("#native-status").textContent));
      assert.equal(await ctx.page.$$eval("#sample-source option", opts => opts.length), 2);
      assert.equal(await ctx.page.$eval("#play", el => el.getAttribute("aria-pressed")), "false");
    } finally { await cleanup(); }
  });

  it("vessel meters follow actual per-track audio and clear immediately on Stop", async t => {
    if (skip(t)) return;
    const project = JSON.parse(fs.readFileSync(ctx.saved));
    const measured = await ctx.page.evaluate(async project => {
      const context = new AudioContext(); await context.resume();
      const renderer = new SampleAudio.Renderer(context, context.destination);
      if (typeof renderer.level !== "function") { await context.close(); return { available: false }; }
      await renderer.loadSources(project.sources);
      renderer.trigger(0, { sampleId: project.sources[0].id, slice: 2, note: 60, gain: .8, dur: .2, t: 0 }, context.currentTime);
      await new Promise(resolve => setTimeout(resolve, 80));
      const playing = renderer.level(0).rms, unrelated = renderer.level(1).rms;
      renderer.stopAll(); const stopped = renderer.level(0).rms;
      await context.close(); return { available: true, playing, unrelated, stopped };
    }, project);
    assert.equal(measured.available, true, "renderer must expose real audio activity");
    assert.ok(measured.playing > .01); assert.equal(measured.unrelated, 0); assert.equal(measured.stopped, 0);
  });
  it("material vessels preview distinct controls, save per track and fence edits made during a render", async t => {
    if (skip(t)) return;
    await upload("#open-project", ctx.saved); await status("Opened");
    await connectNative();
    assert.ok(await ctx.page.$("#material-enable"), "material controls must be present in the instrument");
    await ctx.page.click("#material-enable");
    await ctx.page.select("#material-phase", "gas");
    const gas = await ctx.page.$eval("#material-effective", el => el.textContent);
    await ctx.page.select("#material-phase", "solid");
    const solid = await ctx.page.$eval("#material-effective", el => el.textContent);
    assert.notEqual(gas, solid);
    await setInput("#project-name", "Vessel persistence");
    await ctx.page.click("#freeze"); await status("Saved");
    const filename = path.join(ctx.dir, "Vessel-persistence.brahma.json");
    const project = await until(() => {
      try { return JSON.parse(fs.readFileSync(filename)); } catch (_) { return null; }
    });
    assert.equal(project.phase, "manual");
    assert.equal(project.vessels[0].material.phase, "solid");
    await ctx.page.reload(); await upload("#open-project", filename); await status("Opened");
    await connectNative();
    assert.equal(await ctx.page.$eval("#material-phase", el => el.value), "solid");
    await ctx.page.select("#sample-track", "1");
    assert.equal(await ctx.page.$eval("#material-enable", el => el.checked), false);
    await ctx.page.select("#sample-track", "0");
    assert.equal(await ctx.page.$eval("#material-phase", el => el.value), "solid");
    const cleanup = await nativeFixture();
    try {
      ctx.nativeReady = false; await ctx.page.click("#native-render");
      await ctx.page.waitForFunction(() => /Rendering/.test(document.querySelector("#native-status").textContent));
      await ctx.page.select("#material-phase", "gas"); ctx.nativeReady = true;
      await ctx.page.waitForFunction(() => /Cancelled/.test(document.querySelector("#native-status").textContent));
      assert.equal(await ctx.page.$$eval("#sample-source option", opts => opts.length), 2);
      assert.deepEqual(ctx.errors, []);
    } finally { await cleanup(); }
  });

  it("applied material controls and retained original survive a complete browser save/reopen", async t => {
    if (skip(t)) return;
    await upload("#open-project", ctx.saved); await status("Opened"); await connectNative();
    const cleanup = await nativeFixture();
    try {
      await ctx.page.click("#material-enable"); await ctx.page.select("#material-phase", "gas");
      await ctx.page.click("#play"); await ctx.page.click("#native-render");
      await ctx.page.waitForFunction(() => /Applied|receipt mismatch/.test(document.querySelector("#native-status").textContent));
      assert.match(await ctx.page.$eval("#native-status", el => el.textContent), /^Applied/);
      assert.equal(await ctx.page.$eval("#play", el => el.getAttribute("aria-pressed")), "true");
      assert.equal(ctx.nativeRequest.material.phase, "gas");
      await ctx.page.click("#stop"); await setInput("#project-name", "Applied matter");
      await ctx.page.click("#freeze"); await status("Saved");
      const filename = path.join(ctx.dir, "Applied-matter.brahma.json");
      const saved = await until(() => { try { return JSON.parse(fs.readFileSync(filename)); } catch (_) { return null; } });
      const output = saved.sources.find(source => source.recipe);
      assert.equal(output.recipe.material.phase, "gas"); assert.equal(output.recipe.baseParams.semitones, 7);
      assert.equal(output.recipe.params.semitones, 3); assert.equal(output.recipe.params.mix, .82);
      assert.ok(saved.sources.some(source => source.id === output.recipe.parentId));
      await ctx.page.reload(); await upload("#open-project", filename); await status("Opened");
      await ctx.page.waitForFunction(() => document.querySelector("#native-module").options.length > 200);
      assert.equal(await ctx.page.$eval("#material-phase", el => el.value), "gas");
      assert.equal(await ctx.page.$eval('.vessel-card[data-track="0"]', el => el.dataset.phase), "gas");
      assert.equal(await ctx.page.$eval('#native-params input[data-param="semitones"]', el => el.value), "7");
      if (process.env.BRAHMA_MATERIAL_SCREENSHOT) await ctx.page.screenshot({ path: process.env.BRAHMA_MATERIAL_SCREENSHOT, fullPage: true });
      assert.deepEqual(ctx.errors, []);
    } finally { await cleanup(); }
  });
});
