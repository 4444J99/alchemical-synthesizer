"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const WebSocket = require("ws");
const { createAuth, isLoopbackAddress, parseCookies, safeEqual, randomToken, COOKIE } = require("../lib/auth");

// Set PORT=0 for ephemeral port before requiring server
process.env.PORT = "0";
process.env.HOST = "127.0.0.1";
process.env.BRAHMA_HUMAN_TOKEN = "test-human-token-1234567890123456";
process.env.BRAHMA_AGENT_TOKEN = "test-agent-token-1234567890123456";

const { server, wss, auth, sendPort, closeServer } = require("../server");

test.after(async () => {
  await new Promise((resolve) => closeServer(resolve));
});

test("lib/auth.js: randomToken generates 32-hex character string", () => {
  const t1 = randomToken();
  const t2 = randomToken();
  assert.strictEqual(typeof t1, "string");
  assert.strictEqual(t1.length, 32);
  assert.notStrictEqual(t1, t2);
  assert.match(t1, /^[0-9a-f]{32}$/);
});

test("lib/auth.js: safeEqual compares constant-time buffers", () => {
  assert.strictEqual(safeEqual("token-123", "token-123"), true);
  assert.strictEqual(safeEqual("token-123", "token-124"), false);
  assert.strictEqual(safeEqual("token-123", "token-1234"), false);
  assert.strictEqual(safeEqual("", ""), true);
});

test("lib/auth.js: isLoopbackAddress correctly classifies IP addresses", () => {
  assert.strictEqual(isLoopbackAddress("127.0.0.1"), true);
  assert.strictEqual(isLoopbackAddress("::1"), true);
  assert.strictEqual(isLoopbackAddress("::ffff:127.0.0.1"), true);
  assert.strictEqual(isLoopbackAddress("192.168.1.1"), false);
  assert.strictEqual(isLoopbackAddress("10.0.0.1"), false);
  assert.strictEqual(isLoopbackAddress(null), false);
  assert.strictEqual(isLoopbackAddress(undefined), false);
});

test("lib/auth.js: parseCookies extracts cookie attributes", () => {
  const parsed = parseCookies("brahma_human=val123; user_session=abc; note=hello%20world");
  assert.strictEqual(parsed.brahma_human, "val123");
  assert.strictEqual(parsed.user_session, "abc");
  assert.strictEqual(parsed.note, "hello world");
  assert.deepStrictEqual(parseCookies(null), {});
  assert.deepStrictEqual(parseCookies(""), {});
});

test("lib/auth.js: createAuth resolves human vs agent roles and prevents cross-spoofing", () => {
  const testAuth = createAuth({
    getPort: () => 3000,
    humanToken: "human-secret-1234567890123456",
    agentToken: "agent-secret-1234567890123456"
  });

  // Non-loopback requests always denied
  const extReq = { socket: { remoteAddress: "192.168.1.100" }, headers: { cookie: `brahma_human=${testAuth.humanToken}` } };
  assert.strictEqual(testAuth.roleOf(extReq), null);

  // Loopback with human cookie
  const humanReq = { socket: { remoteAddress: "127.0.0.1" }, headers: { cookie: `brahma_human=${testAuth.humanToken}` } };
  assert.strictEqual(testAuth.roleOf(humanReq), "human");

  // Loopback with agent Bearer token
  const agentReq = { socket: { remoteAddress: "127.0.0.1" }, headers: { authorization: `Bearer ${testAuth.agentToken}` } };
  assert.strictEqual(testAuth.roleOf(agentReq), "agent");

  // Cross-role spoofing: agent token in human cookie -> denied
  const spoofCookie = { socket: { remoteAddress: "127.0.0.1" }, headers: { cookie: `brahma_human=${testAuth.agentToken}` } };
  assert.strictEqual(testAuth.roleOf(spoofCookie), null);

  // Cross-role spoofing: human token in agent authorization -> denied
  const spoofBearer = { socket: { remoteAddress: "127.0.0.1" }, headers: { authorization: `Bearer ${testAuth.humanToken}` } };
  assert.strictEqual(testAuth.roleOf(spoofBearer), null);

  // Token exchange function
  assert.strictEqual(testAuth.exchangeHuman(testAuth.humanToken), true);
  assert.strictEqual(testAuth.exchangeHuman(testAuth.agentToken), false);
  assert.strictEqual(testAuth.exchangeHuman("bogus"), false);

  // Cookie header structure
  const header = testAuth.cookieHeader();
  assert.ok(header.includes(`brahma_human=${testAuth.humanToken}`));
  assert.ok(header.includes("HttpOnly"));
  assert.ok(header.includes("SameSite=Strict"));
  assert.ok(header.includes("Path=/"));
});

test("lib/auth.js: originOk permits localhost/127.0.0.1/[::1] and blocks foreign origins", () => {
  const testAuth = createAuth({ getPort: () => 3000 });

  assert.strictEqual(testAuth.originOk({ headers: { origin: "http://127.0.0.1:3000" }, socket: { remoteAddress: "127.0.0.1" } }), true);
  assert.strictEqual(testAuth.originOk({ headers: { origin: "http://localhost:3000" }, socket: { remoteAddress: "127.0.0.1" } }), true);
  assert.strictEqual(testAuth.originOk({ headers: { origin: "http://[::1]:3000" }, socket: { remoteAddress: "::1" } }), true);

  assert.strictEqual(testAuth.originOk({ headers: { origin: "http://evil.com" }, socket: { remoteAddress: "127.0.0.1" } }), false);
  assert.strictEqual(testAuth.originOk({ headers: { origin: "https://attacker.org:3000" }, socket: { remoteAddress: "127.0.0.1" } }), false);
  assert.strictEqual(testAuth.originOk({ headers: { origin: "http://192.168.1.1:3000" }, socket: { remoteAddress: "127.0.0.1" } }), false);

  // Missing origin permitted on loopback only
  assert.strictEqual(testAuth.originOk({ headers: {}, socket: { remoteAddress: "127.0.0.1" } }), true);
  assert.strictEqual(testAuth.originOk({ headers: {}, socket: { remoteAddress: "::1" } }), true);
  assert.strictEqual(testAuth.originOk({ headers: {}, socket: { remoteAddress: "192.168.1.1" } }), false);
});

// --- Gateway Server Integration Tests ---

test("Gateway Integration: binds to loopback and respects HOST env var", () => {
  const addr = server.address();
  assert.strictEqual(addr.address, "127.0.0.1");
  assert.ok(addr.port > 0);
});

test("Gateway Integration: /api/auth/exchange sets HttpOnly cookie", async () => {
  const port = server.address().port;

  // 1. Successful exchange with human token
  const res = await fetch(`http://127.0.0.1:${port}/api/auth/exchange`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Origin": `http://127.0.0.1:${port}`
    },
    body: JSON.stringify({ token: auth.humanToken }) // allow-secret
  });
  assert.strictEqual(res.status, 200);
  const data = await res.json();
  assert.strictEqual(data.ok, true);
  assert.strictEqual(data.role, "human");
  const cookie = res.headers.get("set-cookie");
  assert.ok(cookie.includes("brahma_human="));
  assert.ok(cookie.includes("HttpOnly"));
  assert.ok(cookie.includes("SameSite=Strict"));

  // 2. Rejected exchange with invalid token
  const badRes = await fetch(`http://127.0.0.1:${port}/api/auth/exchange`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Origin": `http://127.0.0.1:${port}`
    },
    body: JSON.stringify({ token: "invalid-token" }) // allow-secret
  });
  assert.strictEqual(badRes.status, 401);

  // 3. Rejected exchange with foreign Origin
  const evilRes = await fetch(`http://127.0.0.1:${port}/api/auth/exchange`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Origin": "http://evil.com"
    },
    body: JSON.stringify({ token: auth.humanToken }) // allow-secret
  });
  assert.strictEqual(evilRes.status, 403);
});

test("Gateway Integration: /api/auth/status reflects session role", async () => {
  const port = server.address().port;

  // 1. Unauthenticated request
  const resAnon = await fetch(`http://127.0.0.1:${port}/api/auth/status`);
  assert.strictEqual(resAnon.status, 200);
  const dataAnon = await resAnon.json();
  assert.strictEqual(dataAnon.ok, true);
  assert.strictEqual(dataAnon.role, null);
  assert.strictEqual(dataAnon.authenticated, false);

  // 2. Human cookie request
  const resHuman = await fetch(`http://127.0.0.1:${port}/api/auth/status`, {
    headers: {
      "Cookie": `brahma_human=${auth.humanToken}`
    }
  });
  assert.strictEqual(resHuman.status, 200);
  const dataHuman = await resHuman.json();
  assert.strictEqual(dataHuman.ok, true);
  assert.strictEqual(dataHuman.role, "human");
  assert.strictEqual(dataHuman.authenticated, true);

  // 3. Agent Bearer token request
  const resAgent = await fetch(`http://127.0.0.1:${port}/api/auth/status`, {
    headers: {
      "Authorization": `Bearer ${auth.agentToken}`
    }
  });
  assert.strictEqual(resAgent.status, 200);
  const dataAgent = await resAgent.json();
  assert.strictEqual(dataAgent.ok, true);
  assert.strictEqual(dataAgent.role, "agent");
  assert.strictEqual(dataAgent.authenticated, true);
});

test("Gateway Integration: WebSocket verifyClient enforces 403 on untrusted Origin", async () => {
  const port = server.address().port;

  // Untrusted Origin rejected with 403
  let caughtErr = null;
  try {
    await new Promise((resolve, reject) => {
      const ws = new WebSocket(`ws://127.0.0.1:${port}`, {
        headers: { Origin: "http://attacker.com" }
      });
      ws.on("open", () => { ws.close(); resolve(); });
      ws.on("unexpected-response", (req, res) => reject(new Error(`unexpected-response:${res.statusCode}`)));
      ws.on("error", reject);
    });
  } catch (e) {
    caughtErr = e;
  }
  assert.ok(caughtErr);
  assert.match(caughtErr.message, /unexpected-response:403/);

  // Trusted Origin succeeds
  const wsOk = new WebSocket(`ws://127.0.0.1:${port}`, {
    headers: { Origin: `http://localhost:${port}` }
  });
  await new Promise((resolve, reject) => {
    wsOk.on("open", resolve);
    wsOk.on("error", reject);
  });
  wsOk.close();
});

test("Gateway Integration: WebSocket forwards messages for human and rejects agent/unauthenticated", async () => {
  const port = server.address().port;

  let oscSent = [];
  const originalSend = sendPort.send.bind(sendPort);
  sendPort.send = (msg) => {
    oscSent.push(msg);
  };

  try {
    // 1. Unauthenticated client attempting live command
    const wsAnon = new WebSocket(`ws://127.0.0.1:${port}`, {
      headers: { Origin: `http://127.0.0.1:${port}` }
    });
    await new Promise(r => wsAnon.on("open", r));
    const anonReply = await new Promise(resolve => {
      wsAnon.on("message", d => resolve(JSON.parse(d)));
      wsAnon.send(JSON.stringify({ address: "/dirt/play", args: ["bd", 60] }));
    });
    assert.strictEqual(anonReply.error, "forbidden");
    assert.strictEqual(oscSent.length, 0);
    wsAnon.close();

    // 2. Agent token client attempting live command
    const wsAgent = new WebSocket(`ws://127.0.0.1:${port}`, {
      headers: {
        Origin: `http://127.0.0.1:${port}`,
        Authorization: `Bearer ${auth.agentToken}`
      }
    });
    await new Promise(r => wsAgent.on("open", r));
    const agentReply = await new Promise(resolve => {
      wsAgent.on("message", d => resolve(JSON.parse(d)));
      wsAgent.send(JSON.stringify({ address: "/brahma/live/play", args: ["synth", 1, 60, 0.8, 1.0] }));
    });
    assert.strictEqual(agentReply.error, "forbidden");
    assert.strictEqual(oscSent.length, 0);
    wsAgent.close();

    // 3. In-band auth on unauthenticated client upgrading to human
    const wsInBand = new WebSocket(`ws://127.0.0.1:${port}`, {
      headers: { Origin: `http://127.0.0.1:${port}` }
    });
    await new Promise(r => wsInBand.on("open", r));
    const ackReply = await new Promise(resolve => {
      wsInBand.on("message", d => resolve(JSON.parse(d)));
      wsInBand.send(JSON.stringify({ type: "auth", token: auth.humanToken })); // allow-secret
    });
    assert.strictEqual(ackReply.address, "/brahma/auth/ack");
    assert.strictEqual(ackReply.role, "human");

    // Now send live command from newly authenticated socket
    wsInBand.send(JSON.stringify({ address: "/brahma/live/play", args: ["synth", 1, 60, 0.8, 1.0] }));
    await new Promise(r => setTimeout(r, 50));
    assert.strictEqual(oscSent.length, 1);
    assert.strictEqual(oscSent[0].address, "/brahma/live/play");
    wsInBand.close();

    // 4. Human authenticated client sending /dirt/play
    const wsHuman = new WebSocket(`ws://127.0.0.1:${port}`, {
      headers: {
        Origin: `http://127.0.0.1:${port}`,
        Cookie: `brahma_human=${auth.humanToken}`
      }
    });
    await new Promise(r => wsHuman.on("open", r));
    wsHuman.send(JSON.stringify({ address: "/dirt/play", args: ["cp", 64] }));

    await new Promise(r => setTimeout(r, 50));
    assert.strictEqual(oscSent.length, 2);
    assert.strictEqual(oscSent[1].address, "/dirt/play");
    assert.strictEqual(oscSent[1].args[0].value, "cp");
    wsHuman.close();
  } finally {
    sendPort.send = originalSend;
  }
});
