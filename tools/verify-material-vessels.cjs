#!/usr/bin/env node
"use strict";
// Actual browser -> authenticated HTTP -> native DSP -> saved project acceptance.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const assert = require("node:assert/strict"), { spawn } = require("node:child_process");
const ROOT = path.resolve(__dirname, ".."), WEB = path.join(ROOT, "brahma/web");
const Project = require(path.join(WEB, "public/instrument/sample-project"));
const Material = require(path.join(WEB, "public/instrument/material-model"));
const puppeteer = require(path.join(WEB, "node_modules/puppeteer-core"));
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
async function until(fn, ms = 30000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const value = await fn(); if (value) return value; await new Promise(resolve => setTimeout(resolve, 50)); }
  throw new Error("Material acceptance deadline reached");
}
async function completeJson(file) {
  return until(() => { try { return JSON.parse(fs.readFileSync(file)); } catch (_) { return false; } });
}
function measure(file) {
  const bytes = fs.readFileSync(file);
  assert.equal(bytes.toString("ascii", 0, 4), "RIFF");
  assert.equal(bytes.length, bytes.readUInt32LE(4) + 8);
  let peak = 0, sum = 0;
  for (let at = 44; at < bytes.length; at += 2) { const value = bytes.readInt16LE(at); peak = Math.max(peak, Math.abs(value)); sum += value * value; }
  assert.ok(peak > 32, "export must contain measured audio");
  return { sha256: sha(bytes), frames: bytes.readUInt32LE(40) / 4,
    peakDbfs: 20 * Math.log10(peak / 32768), rmsDbfs: 20 * Math.log10(Math.sqrt(sum / ((bytes.length - 44) / 2)) / 32768) };
}
async function main() {
  if (!process.argv[2]) throw new Error("Usage: node tools/verify-material-vessels.cjs PRIVATE_PROJECT.brahma.json");
  const input = path.resolve(process.argv[2]), originalBytes = fs.readFileSync(input);
  const original = await Project.deserialize(originalBytes.toString());
  assert.ok(original.trackSources[0], "the first track needs a retained sample");
  const directory = fs.mkdtempSync(path.join(path.dirname(input), "material-verification-")); fs.chmodSync(directory, 0o700);
  const token = crypto.randomBytes(16).toString("hex"); // allow-secret: transient synthetic test launch, never saved
  const server = spawn(process.execPath, ["server.js"], { cwd: WEB, env: { ...process.env,
    HOST: "127.0.0.1", PORT: "0", BRAHMA_OSC_LISTEN_PORT: "0", BRAHMA_OSC_SEND_PORT: "59998",
    BRAHMA_DIRT_PORT: "0", BRAHMA_HUMAN_TOKEN: token } });
  let logs = "", browser;
  const collect = data => { logs = (logs + data).slice(-16000); };
  server.stdout.on("data", collect); server.stderr.on("data", collect);
  const hardDeadline = setTimeout(() => { server.kill("SIGTERM"); if (browser) browser.close().catch(() => {}); }, 600000);
  try {
    const match = await until(() => /VISUAL CORTEX ONLINE: http:\/\/127\.0\.0\.1:(\d+)/.exec(logs));
    const chrome = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/usr/bin/google-chrome", "/usr/bin/chromium"].find(fs.existsSync);
    assert.ok(chrome, "installed Chrome is required");
    browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ["--no-first-run", "--no-default-browser-check", "--autoplay-policy=no-user-gesture-required"] });
    const page = await browser.newPage(), errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.setViewport({ width: 1440, height: 1100 });
    const cdp = await page.createCDPSession();
    await cdp.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: directory });
    await page.goto("http://127.0.0.1:" + match[1] + "/instrument/#t=" + token);
    await page.waitForFunction(() => document.querySelector("#native-module").options.length > 200);
    const open = async file => {
      await (await page.$("#open-project")).uploadFile(file);
      await page.waitForFunction(() => /^Opened/.test(document.querySelector("#sample-status").textContent));
    };
    await open(input);
    await page.select("#native-module", "ditto_morphic_core");
    await page.click("#material-enable");
    const setInput = async (selector, value) => page.$eval(selector, (input, value) => {
      input.value = value; input.dispatchEvent(new Event("input", { bubbles: true }));
    }, value);
    await setInput('[data-material="water"]', 50); await setInput('[data-material="silica"]', 50);
    const phases = [];
    for (const phase of ["solid", "liquid", "gas"]) {
      await page.select("#material-phase", phase);
      await page.click("#play"); const started = Date.now(); await page.click("#native-render");
      await page.waitForFunction(() => /^Applied/.test(document.querySelector("#native-status").textContent) ||
        document.querySelector("#native-status").classList.contains("error"), { timeout: 155000 });
      const status = await page.$eval("#native-status", el => el.textContent);
      assert.match(status, /^Applied/);
      assert.equal(await page.$eval("#play", el => el.getAttribute("aria-pressed")), "true");
      await page.click("#stop");
      const name = "Material-" + phase;
      await setInput("#project-name", name); await page.click("#freeze");
      const projectFile = path.join(directory, name + ".brahma.json"), project = await completeJson(projectFile);
      const clean = await Project.deserialize(JSON.stringify(project));
      const output = clean.sources.find(source => source.id === clean.trackSources[0]);
      assert.equal(output.recipe.material.phase, phase);
      assert.deepEqual(output.recipe.material.composition, [{ id: "silica", fraction: .5 }, { id: "water", fraction: .5 }]);
      const resolved = Material.resolve("ditto_morphic_core", output.recipe.baseParams, output.recipe.material);
      assert.deepEqual(output.recipe.params, resolved.params);
      assert.equal(output.recipe.modelSha256, resolved.modelSha256);
      assert.ok(clean.sources.some(source => source.id === output.recipe.parentId));
      await page.click("#export-loop");
      const wav = path.join(directory, name + "-loop.wav");
      await until(() => { try { const b = fs.readFileSync(wav); return b.length > 44 && b.length === b.readUInt32LE(4) + 8; } catch (_) { return false; } });
      const measured = measure(wav);
      await page.reload(); await open(projectFile);
      await page.waitForFunction(() => document.querySelector("#native-module").options.length > 200);
      assert.equal(await page.$eval("#material-phase", el => el.value), phase);
      assert.equal(await page.$eval('.vessel-card[data-track="0"]', el => el.dataset.phase), phase);
      await page.screenshot({ path: path.join(directory, phase + ".png"), fullPage: true });
      phases.push({ phase, milliseconds: Date.now() - started, outputSha256: output.sha256, effectiveParams: output.recipe.params,
        baseParams: output.recipe.baseParams, modelSha256: output.recipe.modelSha256, exported: measured });
    }
    assert.equal(new Set(phases.map(item => item.outputSha256)).size, 3, "phase-specific native outputs must differ");
    await page.setViewport({ width: 390, height: 844 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, "mobile page must not overflow horizontally");
    await page.screenshot({ path: path.join(directory, "mobile.png"), fullPage: true });
    await page.click("#native-original");
    assert.match(await page.$eval("#native-status", el => el.textContent), /^Original restored/);
    assert.equal(sha(fs.readFileSync(input)), sha(originalBytes)); assert.deepEqual(errors, []);
    const receipt = { schema: "brahma.material-browser-acceptance.v1", inputProjectSha256: sha(originalBytes),
      checks: { originalPreserved: true, nativePhaseOutputsDiffer: true, appliedWhilePlaying: true,
        saveReopenMaterialExact: true, exportedAudioMeasured: true, restoreOriginal: true, mobileOverflowAbsent: true }, phases };
    fs.writeFileSync(path.join(directory, "verification.json"), JSON.stringify(receipt, null, 2) + "\n");
    console.log(JSON.stringify({ directory, ...receipt }));
  } catch (error) {
    fs.writeFileSync(path.join(directory, "failure.json"), JSON.stringify({ error: error.message }) + "\n"); throw error;
  } finally {
    clearTimeout(hardDeadline); if (browser) await browser.close(); server.kill("SIGTERM");
    const killer = setTimeout(() => server.kill("SIGKILL"), 5000);
    if (server.exitCode === null) await new Promise(resolve => server.once("close", resolve)); clearTimeout(killer);
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
