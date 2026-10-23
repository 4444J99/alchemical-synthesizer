"use strict";

/**
 * workbench.e2e.js — real browser → real gateway → real UDP.
 *
 * This is the only test that exercises the whole sound path: Chrome runs the
 * workbench, the workbench schedules a Strudel pattern, the gateway forwards typed
 * events over OSC, and a UDP socket where SuperCollider would normally listen
 * receives them. Nothing in the chain is stubbed except the engine itself.
 *
 * Skips (with a stated reason) when no Chrome/Chromium binary is present, which is
 * the case on a bare CI runner. A skip is not a pass: the printed reason says so.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const dgram = require("node:dgram");
const fs = require("node:fs");
const path = require("node:path");
const osc = require("osc");

const CHROME_CANDIDATES = [
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser"
];

const TEST_TIMEOUT_MS = 60000;

function findChrome() {
  return CHROME_CANDIDATES.find((p) => {
    try {
      return fs.existsSync(p);
    } catch (_) {
      return false;
    }
  });
}

function waitForMatch(read, re, timeoutMs, label) {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const tick = setInterval(() => {
      const text = read();
      const m = text.match(re);
      if (m) {
        clearInterval(tick);
        resolve(m);
      } else if (Date.now() - started > timeoutMs) {
        clearInterval(tick);
        reject(new Error(`timed out waiting for ${label}\n--- output ---\n${text.slice(-2000)}`));
      }
    }, 50);
  });
}

function waitForOsc(sink, predicate, timeoutMs, label) {
  const seen = [];
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      sink.off("message", onMessage);
      reject(new Error(`timed out waiting for OSC ${label}; saw: ${seen.join(", ") || "nothing"}`));
    }, timeoutMs);

    function onMessage(packet) {
      let frame;
      try {
        frame = osc.readPacket(packet, { metadata: true });
      } catch (err) {
        seen.push(`undecodable(${err.message})`);
        return;
      }
      seen.push(frame.address);
      if (predicate(frame)) {
        clearTimeout(timer);
        sink.off("message", onMessage);
        resolve(frame);
      }
    }

    sink.on("message", onMessage);
  });
}

test("E2E: browser runs a pattern and panics through the gateway", { timeout: TEST_TIMEOUT_MS + 15000 }, async (t) => {
  const chrome = findChrome();
  if (!chrome) {
    t.skip("no Chrome/Chromium binary on this host — browser E2E not run (this is a skip, not a pass)");
    return;
  }

  const puppeteer = require("puppeteer-core");
  const webDir = path.resolve(__dirname, "..", "..");

  // A UDP socket where SuperCollider would be. We keep it bound and hand its port to
  // the gateway, so the gateway sends to a real listener.
  const sink = dgram.createSocket("udp4");
  await new Promise((resolve) => sink.bind(0, "127.0.0.1", resolve));
  const sinkPort = sink.address().port;

  const env = {
    ...process.env,
    PORT: "0",                       // ephemeral; the real port is parsed from stdout
    HOST: "127.0.0.1",
    BRAHMA_OSC_LISTEN_PORT: "0",
    BRAHMA_OSC_SEND_PORT: String(sinkPort),
    BRAHMA_DIRT_PORT: "57132",       // distinct from the unit tests
    BRAHMA_COMMIT_SHA: "e2e-test-commit"
  };

  let output = "";
  const child = spawn(process.execPath, ["server.js"], { cwd: webDir, env });
  child.stdout.on("data", (d) => { output += d.toString(); });
  child.stderr.on("data", (d) => { output += d.toString(); });

  let browser;
  try {
    const portMatch = await waitForMatch(() => output, /VISUAL CORTEX ONLINE: http:\/\/127\.0\.0\.1:(\d+)/, 20000, "server boot");
    const port = Number(portMatch[1]);

    const tokenMatch = await waitForMatch(() => output, /#t=([0-9a-f]{32})/, 10000, "human token handoff");
    const token = tokenMatch[1]; // allow-secret

    browser = await puppeteer.launch({
      executablePath: chrome,
      headless: true,
      args: ["--no-first-run", "--no-default-browser-check", "--disable-dev-shm-usage"]
    });

    const page = await browser.newPage();
    const pageErrors = [];
    const consoleAll = [];
    page.on("pageerror", (err) => pageErrors.push(err.message));
    page.on("console", (msg) => {
      const url = msg.location()?.url || "";
      consoleAll.push(`${msg.type()}: ${msg.text()} ${url}`);
      if (msg.type() === "error") pageErrors.push(`${msg.text()} ${url}`);
    });

    // The launch URL is exactly what the gateway printed: the token lives in the
    // fragment, which the page exchanges once for an HttpOnly cookie.
    await page.goto(`http://127.0.0.1:${port}/workbench/#t=${token}`, { waitUntil: "load" });

    await page.waitForFunction(
      () => /role: human/.test(document.querySelector("#status")?.textContent || ""),
      { timeout: 15000 }
    );

    // The fragment must be gone from the URL once claimed, so it cannot leak in a copy.
    const url = page.url();
    assert.ok(!url.includes(token), "the launch token must be stripped from the URL after exchange");

    // The control path requires no ordinary audio gesture: Strudel is not producing
    // WebAudio, so clicking run is the whole interaction.
    await page.click("#run");

    let play;
    try {
      play = await waitForOsc(
        sink,
        (f) => f.address === "/brahma/live/play",
        20000,
        "/brahma/live/play (pattern event reached the engine socket)"
      );
    } catch (err) {
      const logText = await page.evaluate(() => document.querySelector("#log")?.textContent || "");
      err.message += `\n--- page log ---\n${logText}\n--- page errors ---\n${pageErrors.join(" | ")}`;
      err.message += `\n--- console ---\n${consoleAll.slice(-40).join("\n")}`;
      err.message += `\n--- server output ---\n${output.slice(-2000)}`;
      throw err;
    }

    assert.equal(play.args[0].value, "prima_materia", "default engine is used for a non-module sound name");
    assert.equal(play.args[1].value, "pattern", "the active tab id becomes the instance");
    assert.equal(typeof play.args[2].value, "number", "note is numeric");
    assert.ok(play.args[2].value >= 0 && play.args[2].value <= 127, "note is a MIDI number");
    assert.ok(play.args[4].value > 0, "duration is positive");

    // Panic must reach the engine and must be the real panic address, not freeAll.
    // The listener is attached *before* the click: the round trip through
    // browser → WS → UDP is faster than the CDP click response.
    const panicPromise = waitForOsc(sink, (f) => f.address === "/brahma/live/panic", 10000, "/brahma/live/panic");
    await page.click("#panic");
    const panic = await panicPromise;
    assert.ok(panic, "panic reached the engine socket");

    await page.screenshot({ path: "/tmp/brahma_workbench_e2e.png", fullPage: true });

    // A page that only works because of console errors is not working.
    const fatal = pageErrors.filter((e) => !/favicon/i.test(e));
    assert.deepEqual(fatal, [], `page reported errors: ${fatal.join(" | ")}`);
  } finally {
    if (browser) await browser.close().catch(() => {});
    child.kill("SIGKILL");
    sink.close();
  }
});
