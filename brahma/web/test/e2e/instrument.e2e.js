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
    let crossings = 0, peak = 0, previous = 0;
    for (let i = Math.ceil(sr * 0.025); i < Math.floor(sr * 0.1); i++) {
      const sample = rendered.readInt16LE(44 + i * channels * 2);
      if (sample > 0 && previous <= 0) crossings++;
      peak = Math.max(peak, Math.abs(sample)); previous = sample;
    }
    assert.ok(peak > 500, "export must contain the uploaded sound");
    const hz = crossings / 0.075;
    assert.ok(hz > 420 && hz < 470, `expected the 440 Hz chop, got ${hz} Hz`);
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
});
