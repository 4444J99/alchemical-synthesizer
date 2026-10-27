#!/usr/bin/env node
"use strict";
// Real local browser + HTTP + native DSP acceptance for a private song project.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const assert = require("node:assert/strict"), { spawn } = require("node:child_process");
const ROOT = path.resolve(__dirname, ".."), WEB = path.join(ROOT, "brahma/web");
const M = require(path.join(WEB, "public/instrument/sample-project.js"));
const puppeteer = require(path.join(WEB, "node_modules/puppeteer-core"));
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
async function until(fn, timeout = 30000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { const result = await fn(); if (result) return result; await new Promise(resolve => setTimeout(resolve, 50)); }
  throw new Error("Timed out waiting for sketch acceptance");
}
function measure(filename, seconds) {
  const bytes = fs.readFileSync(filename), rate = bytes.readUInt32LE(24), frames = bytes.readUInt32LE(40) / 4;
  assert.equal(bytes.toString("ascii", 0, 4), "RIFF"); assert.equal(bytes.readUInt16LE(22), 2);
  assert.equal(rate, 44100); assert.equal(frames, Math.round(seconds * rate));
  let peak = 0, squares = 0;
  for (let offset = 44; offset < bytes.length; offset += 2) { const value = bytes.readInt16LE(offset); peak = Math.max(peak, Math.abs(value)); squares += value * value; }
  assert.ok(peak > 32, "the exported sketch must contain audio");
  return { sha256: sha(bytes), frames, duration: frames / rate, peakDbfs: 20 * Math.log10(peak / 32768),
    rmsDbfs: 20 * Math.log10(Math.sqrt(squares / ((bytes.length - 44) / 2)) / 32768) };
}
async function main() {
  if (!process.argv[2]) throw new Error("Usage: node tools/verify-song-sketch.cjs PRIVATE_PROJECT.brahma.json");
  const filename = path.resolve(process.argv[2]), originalBytes = fs.readFileSync(filename);
  const original = await M.deserialize(originalBytes.toString());
  const destination = fs.mkdtempSync(path.join(path.dirname(filename), "verification-"));
  const humanToken = crypto.randomBytes(16).toString("hex"); // allow-secret: ephemeral test launch identity, never persisted
  const child = spawn(process.execPath, ["server.js"], { cwd: WEB,
    env: { ...process.env, PORT: "0", HOST: "127.0.0.1", BRAHMA_OSC_LISTEN_PORT: "0", BRAHMA_OSC_SEND_PORT: "59998",
      BRAHMA_DIRT_PORT: "57138", BRAHMA_HUMAN_TOKEN: humanToken } });
  let logs = "", browser;
  child.stdout.on("data", data => { logs = (logs + data).slice(-16000); });
  child.stderr.on("data", data => { logs = (logs + data).slice(-16000); });
  try {
    const match = await until(() => /VISUAL CORTEX ONLINE: http:\/\/127\.0\.0\.1:(\d+)/.exec(logs));
    const base = "http://127.0.0.1:" + match[1];
    const chrome = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/usr/bin/google-chrome", "/usr/bin/chromium"].find(fs.existsSync);
    assert.ok(chrome, "installed Chrome is required for musical sketch acceptance");
    browser = await puppeteer.launch({ executablePath: chrome, headless: true,
      args: ["--no-first-run", "--no-default-browser-check", "--autoplay-policy=no-user-gesture-required"] });
    const page = await browser.newPage(), errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.setViewport({ width: 1500, height: 1100 });
    const cdp = await page.createCDPSession();
    await cdp.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: destination });
    await page.evaluateOnNewDocument(() => {
      const create = AudioContext.prototype.createAnalyser;
      AudioContext.prototype.createAnalyser = function (...args) { const analyser = create.apply(this, args); window.acceptanceAnalyser = analyser; return analyser; };
    });
    await page.goto(base + "/instrument/#t=" + humanToken);
    await page.waitForFunction(() => document.querySelector("#native-module").options.length > 200);
    assert.equal(await page.evaluate(() => location.hash), "", "launch credentials must be removed from the address");
    async function open(project) {
      await (await page.$("#open-project")).uploadFile(project);
      await page.waitForFunction(() => /^Opened/.test(document.querySelector("#sample-status").textContent));
    }
    async function name(value) { await page.$eval("#project-name", (el, value) => { el.value = value; }, value); }
    async function save(value) {
      await name(value); await page.click("#freeze");
      const file = path.join(destination, value + ".brahma.json"); await until(() => fs.existsSync(file));
      return { file, project: await M.deserialize(fs.readFileSync(file, "utf8")) };
    }
    async function exportLoop(value) {
      await name(value); await page.click("#export-loop");
      const file = path.join(destination, value + "-loop.wav"); await until(() => fs.existsSync(file)); return file;
    }
    await open(filename);
    assert.equal(await page.$$eval("#grid tr", rows => rows.length), 5);
    assert.equal(await page.$$eval("#grid tr:first-child td", cells => cells.length), 33);
    assert.equal(await page.$$eval("#chops button", pads => pads.length), 8);
    const baseline = await save("Son-of-a-Preacher-Man-sketch");
    assert.deepEqual(baseline.project.sources, original.sources);
    assert.deepEqual(baseline.project.scene, original.scene);
    await page.click("#play");
    await until(async () => page.evaluate(() => {
      if (!window.acceptanceAnalyser) return false;
      const data = new Float32Array(window.acceptanceAnalyser.fftSize); window.acceptanceAnalyser.getFloatTimeDomainData(data);
      return data.some(value => Math.abs(value) > .001);
    }));
    await page.click("#stop");
    const seconds = original.scene.steps * 60 / original.tempo / 4;
    const loop = await exportLoop("Son-of-a-Preacher-Man-sketch"), baselineMeasure = measure(loop, seconds);
    await open(baseline.file);
    const reopenedLoop = await exportLoop("Son-of-a-Preacher-Man-reopened");
    const firstPcm = fs.readFileSync(loop), secondPcm = fs.readFileSync(reopenedLoop);
    assert.equal(firstPcm.length, secondPcm.length);
    let maxPcmDelta = 0, changedSamples = 0;
    for (let at = 44; at < firstPcm.length; at += 2) {
      const delta = Math.abs(firstPcm.readInt16LE(at) - secondPcm.readInt16LE(at));
      maxPcmDelta = Math.max(maxPcmDelta, delta); if (delta) changedSamples++;
    }
    assert.ok(maxPcmDelta <= 1, "reopened audio must agree within one PCM quantization step");
    await page.select("#native-module", "solve_pitch_shift");
    await page.$eval('#native-params input[data-param="semitones"]', el => { el.value = 5; });
    await page.$eval('#native-params input[data-param="mix"]', el => { el.value = .75; });
    await page.click("#play"); const started = Date.now(); await page.click("#native-render");
    await page.waitForFunction(() => {
      const status = document.querySelector("#native-status");
      return /^Applied/.test(status.textContent) || status.classList.contains("error");
    }, { timeout: 150000 });
    const nativeStatus = await page.$eval("#native-status", el => el.textContent);
    assert.match(nativeStatus, /^Applied/, nativeStatus);
    assert.equal(await page.$eval("#play", el => el.getAttribute("aria-pressed")), "true");
    const nativeMilliseconds = Date.now() - started;
    await page.click("#stop");
    const variation = await save("Son-of-a-Preacher-Man-native-variation");
    const active = variation.project.sources.find(source => source.id === variation.project.trackSources[0]);
    assert.equal(active.recipe.module, "solve_pitch_shift");
    assert.deepEqual(active.recipe.params, { semitones: 5, mix: .75 });
    assert.ok(variation.project.sources.some(source => source.id === original.sources[0].id));
    const variationLoop = await exportLoop("Son-of-a-Preacher-Man-native-variation"), variationMeasure = measure(variationLoop, seconds);
    assert.notEqual(variationMeasure.sha256, baselineMeasure.sha256);
    await open(variation.file);
    assert.equal(await page.$eval('#native-params input[data-param="semitones"]', el => el.value), "5");
    await page.screenshot({ path: path.join(destination, "instrument.png"), fullPage: true });
    await page.click("#native-original");
    await page.waitForFunction(() => /^Original restored/.test(document.querySelector("#native-status").textContent));
    assert.equal(sha(fs.readFileSync(filename)), sha(originalBytes), "starter project must remain unchanged");
    assert.deepEqual(errors, []);
    const result = { checks: { originalProjectPreserved: true, playbackMeasured: true, saveReopenExact: true,
      reopenedWavWithinOnePcmStep: true, nativeHttpDspRender: true, nativeAppliedWhilePlaying: true,
      nativeRecipeReopened: true, restoreOriginal: true }, nativeMilliseconds,
      reopenDifference: { maxPcmDelta, changedSamples }, sources: original.sources.length, variationSources: variation.project.sources.length,
      tempo: original.tempo, steps: original.scene.steps, baseline: baselineMeasure, variation: variationMeasure };
    fs.writeFileSync(path.join(destination, "verification.json"), JSON.stringify(result, null, 2) + "\n");
    const html = '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Son of a Preacher Man - Brahma sketch</title><style>body{background:#080b15;color:#e5e8f3;font:17px system-ui;max-width:950px;margin:3rem auto;padding:1rem}a,h1{color:#98b5ff}article{border:1px solid #303650;border-radius:12px;padding:1.5rem;margin:1rem 0}audio{width:100%}img{width:100%}</style><h1>Son of a Preacher Man / Brahma sketch</h1><p>Eight chops, a native palette, Golem drums. 32 steps at 92 BPM. The source recordings and earlier takes remain preserved.</p><article><h2>Starter sketch</h2><audio controls src="Son-of-a-Preacher-Man-sketch-loop.wav"></audio><p><a href="Son-of-a-Preacher-Man-sketch.brahma.json" download>Download editable project</a></p></article><article><h2>Native pitch variation</h2><audio controls src="Son-of-a-Preacher-Man-native-variation-loop.wav"></audio><p>+5 semitones, 75% wet; rendered through the actual native module while the sequence kept playing.</p><p><a href="Son-of-a-Preacher-Man-native-variation.brahma.json" download>Download editable variation</a></p></article><p>Open either project in Brahma /instrument/. Native controls use the local server launch link. These are editable sketches for listening and development.</p><img src="instrument.png" alt="Verified Brahma project with native controls and drum tracks"><script>document.addEventListener("play",e=>{if(e.target.tagName==="AUDIO")document.querySelectorAll("audio").forEach(a=>{if(a!==e.target)a.pause()})},true)</script>';
    fs.writeFileSync(path.join(destination, "index.html"), html);
    console.log(JSON.stringify({ directory: destination, ...result }));
  } catch (error) {
    fs.writeFileSync(path.join(destination, "failure.json"), JSON.stringify({ error: error.message }) + "\n");
    throw error;
  } finally {
    if (browser) await browser.close();
    child.kill("SIGTERM");
    const killer = setTimeout(() => child.kill("SIGKILL"), 5000);
    if (child.exitCode === null) await new Promise(resolve => child.once("close", resolve));
    clearTimeout(killer);
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
