"use strict";

/**
 * workbench.e2e.js — four tiers, one real browser, one real gateway.
 *
 *   Tier 1  UI        the workbench page serves and claims the human role from #t=
 *   Tier 2  protocol  server → browser frames are typed JSON, and run is acknowledged
 *   Tier 3  engine    a scheduled Strudel hap becomes an OSC /brahma/live/play packet
 *   Tier 4  panic     panic reaches /brahma/live/panic, not a generic freeAll
 *
 * Nothing in the chain is stubbed except SuperCollider itself: a UDP socket stands
 * where scsynth would listen, and every layer in between is the shipping code.
 *
 * Skips (with a stated reason) when no Chrome/Chromium is present, which is the case
 * on a bare CI runner. A skip is not a pass, and the reason says so.
 */

const { describe, it, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const dgram = require("node:dgram");
const fs = require("node:fs");
const path = require("node:path");
const osc = require("osc");

const CHROME_CANDIDATES = [
  process.env.BRAHMA_CHROME_PATH,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser"
].filter(Boolean);

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

describe("workbench E2E", () => {
  const ctx = { skipReason: null };

  before(async () => {
    const chrome = findChrome();
    if (!chrome) {
      if (process.env.BRAHMA_REQUIRE_BROWSER === "1") throw new Error("Chrome is required; set BRAHMA_CHROME_PATH to an installed test browser");
      ctx.skipReason = "no Chrome/Chromium binary on this host — browser E2E not run (this is a skip, not a pass)";
      return;
    }

    const puppeteer = require("puppeteer-core");
    const webDir = path.resolve(__dirname, "..", "..");

    // A UDP socket where SuperCollider would be. It stays bound; the gateway is told
    // to send here, so every packet goes to a real listener.
    const sink = dgram.createSocket("udp4");
    await new Promise((resolve) => sink.bind(0, "127.0.0.1", resolve));

    const env = {
      ...process.env,
      PORT: "0",
      HOST: "127.0.0.1",
      BRAHMA_OSC_LISTEN_PORT: "0",
      BRAHMA_OSC_SEND_PORT: String(sink.address().port),
      BRAHMA_DIRT_PORT: "57132",
      BRAHMA_COMMIT_SHA: "e2e-test-commit"
    };

    let output = "";
    const child = spawn(process.execPath, ["server.js"], { cwd: webDir, env });
    child.stdout.on("data", (d) => { output += d.toString(); });
    child.stderr.on("data", (d) => { output += d.toString(); });

    Object.assign(ctx, { chrome, puppeteer, sink, child, env, output: () => output, webDir });

    try {
      const portMatch = await waitForMatch(() => output, /VISUAL CORTEX ONLINE: http:\/\/127\.0\.0\.1:(\d+)/, 20000, "server boot");
      ctx.port = Number(portMatch[1]);

      const tokenMatch = await waitForMatch(() => output, /#t=([0-9a-f]{32})/, 10000, "human token handoff");
      ctx.token = tokenMatch[1]; // allow-secret

      ctx.browser = await puppeteer.launch({
        executablePath: chrome,
        headless: true,
        args: ["--no-first-run", "--no-default-browser-check", "--disable-dev-shm-usage",
          ...(process.env.BRAHMA_BROWSER_NO_SANDBOX === "1" ? ["--no-sandbox"] : [])]
      });

      ctx.page = await ctx.browser.newPage();
      ctx.pageErrors = [];
      ctx.consoleAll = [];

      // Capture the actual frames the server sends, from inside the page, so the
      // assertion is about the wire and not about a driver's event surface.
      await ctx.page.evaluateOnNewDocument(() => {
        window.__brahmaFrames = [];
        const Native = window.WebSocket;
        function Wrapped(...args) {
          const ws = new Native(...args);
          ws.addEventListener("message", (event) => {
            window.__brahmaFrames.push(typeof event.data === "string" ? event.data : "[binary]");
          });
          return ws;
        }
        Wrapped.prototype = Native.prototype;
        Object.setPrototypeOf(Wrapped, Native);
        window.WebSocket = Wrapped;
      });

      ctx.frames = async () => ctx.page.evaluate(() => window.__brahmaFrames || []);

      ctx.page.on("pageerror", (err) => ctx.pageErrors.push(err.message));
      ctx.page.on("console", (msg) => {
        const url = msg.location()?.url || "";
        ctx.consoleAll.push(`${msg.type()}: ${msg.text()} ${url}`);
        if (msg.type() === "error") ctx.pageErrors.push(`${msg.text()} ${url}`);
      });

      // The launch URL is exactly what the gateway printed: the token lives in the
      // fragment, which the page exchanges once for an HttpOnly cookie.
      await ctx.page.goto(`http://127.0.0.1:${ctx.port}/workbench/#t=${ctx.token}`, { waitUntil: "load" });
      await ctx.page.waitForFunction(
        () => /role: human/.test(document.querySelector("#status")?.textContent || ""),
        { timeout: 20000 }
      );
    } catch (err) {
      // Never leave a browser or server behind when setup fails.
      if (ctx.browser) await ctx.browser.close().catch(() => {});
      child.kill("SIGKILL");
      sink.close();
      throw err;
    }
  });

  after(async () => {
    if (ctx.browser) await ctx.browser.close().catch(() => {});
    if (ctx.child) ctx.child.kill("SIGKILL");
    if (ctx.sink) ctx.sink.close();
  });

  function skipIfNoChrome(t) {
    if (ctx.skipReason) {
      t.skip(ctx.skipReason);
      return true;
    }
    return false;
  }

  it("Tier 1 — UI: the page serves, claims the human role, and strips the token from the URL", async (t) => {
    if (skipIfNoChrome(t)) return;

    const title = await ctx.page.title();
    assert.ok(title.length > 0, "the page must have a title");

    const status = await ctx.page.evaluate(() => document.querySelector("#status")?.textContent || "");
    assert.match(status, /role: human/, "the launch token must have been exchanged for the human role");

    const url = ctx.page.url();
    assert.ok(!url.includes(ctx.token), "the launch token must be stripped from the URL after exchange");

    // The editor is the product: it must be present and populated.
    const editorText = await ctx.page.evaluate(() => document.querySelector(".cm-content")?.textContent || "");
    assert.ok(editorText.length > 0, "the editor must load with starter content");
  });

  it("Tier 2 — protocol: server frames are typed JSON and `run` is acknowledged", async (t) => {
    if (skipIfNoChrome(t)) return;

    const jsonFrames = async () => (await ctx.frames())
      .map((raw) => { try { return JSON.parse(raw); } catch (_) { return null; } })
      .filter(Boolean);

    // The status frame proves the socket carried a typed frame, not raw OSC.
    const started = Date.now();
    let status = null;
    while (!status && Date.now() - started < 10000) {
      status = (await jsonFrames()).find((f) => f.type === "status");
      if (!status) await new Promise((r) => setTimeout(r, 100));
    }
    assert.ok(status, `no typed status frame arrived; frames: ${(await ctx.frames()).slice(0, 5).join(" | ")}`);
    assert.equal(status.role, "human");

    // Attach the engine listener before the click: browser → WS → UDP is faster than
    // the CDP click round trip, so a listener attached after it can miss the first event.
    ctx.playPromise = waitForOsc(ctx.sink, (f) => f.address === "/brahma/live/play", 20000, "/brahma/live/play");
    ctx.playPromise.catch(() => {});

    await ctx.page.click("#run");

    const ackStarted = Date.now();
    let ack = null;
    while (!ack && Date.now() - ackStarted < 10000) {
      ack = (await jsonFrames()).find((f) => f.type === "ack");
      if (!ack) await new Promise((r) => setTimeout(r, 100));
    }
    assert.ok(ack, "running a pattern must be acknowledged by the gateway");

    // Every frame the server sends must be JSON with a type — no bare strings.
    for (const frame of await jsonFrames()) {
      assert.equal(typeof frame.type, "string", `untyped server frame: ${JSON.stringify(frame).slice(0, 120)}`);
    }
  });

  it("Tier 3 — engine: a scheduled hap reaches the engine socket as a typed play packet", async (t) => {
    if (skipIfNoChrome(t)) return;

    let play;
    try {
      play = await ctx.playPromise;
    } catch (err) {
      const log = await ctx.page.evaluate(() => document.querySelector("#log")?.textContent || "");
      err.message += `\n--- page log ---\n${log}\n--- console ---\n${ctx.consoleAll.slice(-30).join("\n")}`;
      throw err;
    }

    assert.equal(play.args[0].value, "prima_materia", "an unknown sound name falls back to the default engine");
    assert.match(play.args[1].value, /^pattern\.[a-f0-9]+\.\d+$/, "each run has its own stoppable instance");
    assert.equal(typeof play.args[2].value, "number", "note is numeric");
    assert.ok(play.args[2].value >= 0 && play.args[2].value <= 127, "note is a MIDI number");
    assert.ok(play.args[3].value > 0 && play.args[3].value <= 1, "velocity is normalised");
    assert.ok(play.args[4].value > 0, "duration is positive");

    // A page that only works because of console errors is not working.
    const fatal = ctx.pageErrors.filter((e) => !/favicon/i.test(e));
    assert.deepEqual(fatal, [], `page reported errors: ${fatal.join(" | ")}`);
  });

  it("Tier 4 — panic: the panic control reaches the panic address", async (t) => {
    if (skipIfNoChrome(t)) return;

    const panicPromise = waitForOsc(ctx.sink, (f) => f.address === "/brahma/live/panic", 10000, "/brahma/live/panic");
    await ctx.page.click("#panic");
    const panic = await panicPromise;

    assert.equal(panic.address, "/brahma/live/panic");
    assert.deepEqual(panic.args, [], "panic carries no payload");

    const log = await ctx.page.evaluate(() => document.querySelector("#log")?.textContent || "");
    assert.match(log, /panic/, "the UI must report the panic, not fail silently");
  });

  async function replaceActiveText(text) {
    await ctx.page.focus('.cm-content');
    const modifier = process.platform === 'darwin' ? 'Meta' : 'Control';
    await ctx.page.keyboard.down(modifier);
    await ctx.page.keyboard.press('KeyA');
    await ctx.page.keyboard.up(modifier);
    await ctx.page.keyboard.sendCharacter(text);
  }

  it('edited active buffer is the source that actually plays', async (t) => {
    if (skipIfNoChrome(t)) return;
    await replaceActiveText('note("a4").gain(0.1)');
    const played = waitForOsc(ctx.sink, (f) => f.address === '/brahma/live/play', 3000, 'edited note');
    await ctx.page.click('#run');
    try {
      const packet = await played;
      assert.equal(packet.args[2].value, 69, 'Run must use the current visible document');
    } finally { await ctx.page.click('#panic'); }
  });

  it('Stop releases the same instance as the scheduled events', async (t) => {
    if (skipIfNoChrome(t)) return;
    const played = waitForOsc(ctx.sink, (f) => f.address === '/brahma/live/play', 3000, 'started note');
    await ctx.page.click('#run');
    const packet = await played;
    const stopped = waitForOsc(ctx.sink, (f) => f.address === '/brahma/engine/freeAll', 1500, 'instance stop');
    await ctx.page.click('#stop');
    try { assert.equal((await stopped).args[0].value, packet.args[1].value); }
    finally { await ctx.page.click('#panic'); }
  });

  it('editing a playing buffer preserves Stop authority', async (t) => {
    if (skipIfNoChrome(t)) return;
    const played = waitForOsc(ctx.sink, (f) => f.address === '/brahma/live/play', 3000, 'started note');
    await ctx.page.click('#run');
    const packet = await played;
    await replaceActiveText('note("b4").gain(0.1)');
    const stopped = waitForOsc(ctx.sink, (f) => f.address === '/brahma/engine/freeAll', 1500, 'stop after edit');
    await ctx.page.click('#stop');
    try { assert.equal((await stopped).args[0].value, packet.args[1].value); }
    finally { await ctx.page.click('#panic'); }
  });

  it('Run applies an edited draft and leaves one registered performance', async (t) => {
    if (skipIfNoChrome(t)) return;
    await replaceActiveText('note("c4").gain(0.1)');
    let played = waitForOsc(ctx.sink, (f) => f.address === '/brahma/live/play', 3000, 'first draft');
    await ctx.page.click('#run');
    const first = await played;
    assert.equal(first.args[2].value, 60);
    await replaceActiveText('note("d4").gain(0.1)');
    const stopped = waitForOsc(ctx.sink, (f) => f.address === '/brahma/engine/freeAll', 1500, 'replaced performance');
    played = waitForOsc(ctx.sink, (f) => f.address === '/brahma/live/play' && f.args[2].value === 62, 3000, 'replacement draft');
    await ctx.page.click('#run');
    try {
      assert.equal((await stopped).args[0].value, first.args[1].value);
      const replacement = await played;
      await ctx.page.evaluate(() => { window.__brahmaFrames = []; });
      await ctx.page.click('#status-btn');
      await ctx.page.waitForFunction(() => window.__brahmaFrames.some((raw) => JSON.parse(raw).type === 'status'));
      const status = (await ctx.frames()).map(JSON.parse).find((f) => f.type === 'status');
      assert.equal(status.live.count, 1);
      assert.equal(status.live.patterns[0].instance, replacement.args[1].value);
      assert.notEqual(replacement.args[1].value, first.args[1].value);
      assert.equal((await ctx.frames()).map(JSON.parse).some((f) => f.code === 'duplicate_id'), false);
    } finally { await ctx.page.click('#panic'); }
  });

  async function liveStatus() {
    await ctx.page.evaluate(() => { window.__brahmaFrames = []; });
    await ctx.page.click('#status-btn');
    await ctx.page.waitForFunction(() => window.__brahmaFrames.some((raw) => JSON.parse(raw).type === 'status'));
    return (await ctx.frames()).map(JSON.parse).find((f) => f.type === 'status').live;
  }

  it('rapid Run–Stop–Run retains authority over the newest performance', async (t) => {
    if (skipIfNoChrome(t)) return;
    await replaceActiveText('note("e4").gain(0.1)');
    const played = waitForOsc(ctx.sink, (f) => f.address === '/brahma/live/play', 3000, 'rapid replacement');
    await ctx.page.evaluate(() => {
      document.querySelector('#run').click();
      document.querySelector('#stop').click();
      document.querySelector('#run').click();
    });
    try {
      await played;
      assert.match(await ctx.page.$eval('#running', (e) => e.textContent), /running:/);
      assert.equal((await liveStatus()).count, 1);
      await ctx.page.click('#stop');
      assert.equal((await liveStatus()).count, 0, 'Stop must remove the replacement registration');
    } finally { await ctx.page.click('#panic'); }
  });

  it('Stop abandons a pending evaluation and late completion cannot replace or stop its successor', async (t) => {
    if (skipIfNoChrome(t)) return;
    await replaceActiveText('await new Promise((resolve) => { globalThis.__releaseOldPattern = resolve; }); setcps(10); note("c4").gain(0.1)');
    await ctx.page.click('#run');
    await ctx.page.waitForFunction(() => typeof globalThis.__releaseOldPattern === 'function');
    await ctx.page.click('#stop');
    await replaceActiveText('note("d4").gain(0.1)');
    let played = waitForOsc(ctx.sink, (f) => f.address === '/brahma/live/play' && f.args[2].value === 62, 3000, 'new run after pending evaluation');
    played.catch(() => {});
    await ctx.page.click('#run');
    try {
      const current = await played;
      const firstAt = Date.now();
      await ctx.page.evaluate(() => globalThis.__releaseOldPattern());
      played = waitForOsc(ctx.sink, (f) => f.address === '/brahma/live/play', 3000, 'successor after old completion');
      const next = await played;
      assert.ok(Date.now() - firstAt > 1000, 'stale setcps must not change the replacement tempo');
      assert.equal(next.args[2].value, 62, 'stale source must not become the current scheduler pattern');
      assert.equal(next.args[1].value, current.args[1].value);
      assert.match(await ctx.page.$eval('#running', (e) => e.textContent), /running:/);
      await ctx.page.click('#stop');
      assert.equal((await liveStatus()).count, 0);
    } finally {
      await ctx.page.evaluate(() => globalThis.__releaseOldPattern?.());
      await ctx.page.click('#panic');
    }
  });
});
