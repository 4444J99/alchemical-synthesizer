const osc = require("osc");
const WebSocket = require("ws"); // ws ^8.21.3 (Dependabot update #1632814654, CI green)
const express = require("express");
const path = require("path");
const { createAuth, safeEqual } = require("./lib/auth");
const sandbox = require("./lib/sandbox");
const runtimes = require("./lib/runtimes");
const { createDirtBridge } = require("./lib/dirt");
const { createTokenBucket } = require("./lib/ratelimit");
const { createLiveSessions, createSession, oscArgs } = require("./lib/session");
const { createAgentLayer } = require("./lib/agent");

const HOST = process.env.HOST || "127.0.0.1";
const HTTP_PORT = process.env.PORT !== undefined ? Number(process.env.PORT) : 3000;
const OSC_UDP_PORT = Number(process.env.BRAHMA_OSC_LISTEN_PORT || 57122); // Listening for SC
const OSC_SEND_PORT = Number(process.env.BRAHMA_OSC_SEND_PORT || 57120); // Sending to SC
const DIRT_PORT = Number(process.env.BRAHMA_DIRT_PORT || process.env.DIRT_PORT) || 57130;

// Namespace whitelist: all OSC address prefixes allowed from browser → SC.
// /dirt/ is deliberately absent: Dirt traffic arrives on the UDP bridge (57130),
// which owns its translation and auto-release. A browser writing raw /dirt/play
// would bypass both.
const ALLOWED_NAMESPACES = [
    "/golem/", "/brahma/", "/chronos/", "/daemon/",
    "/moirai/", "/genesis/", "/arbor/", "/serpens/",
    "/scriptorium/", "/ableton/"
];

// Module registry cache (populated from SC broadcasts)
const moduleCache = {};
const paramCache = {};

// 1. HTTP Server & Middleware
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));
app.use("/golem", express.static(path.join(__dirname, "public", "golem")));
app.use("/cortex", express.static(path.join(__dirname, "public", "cortex")));

// Shared live-pattern registry. One gateway, one engine, one state.
const liveSessions = createLiveSessions();

let server;
const auth = createAuth({
    getPort: () => (server && server.address() ? server.address().port : HTTP_PORT),
    humanToken: process.env.BRAHMA_HUMAN_TOKEN,
    agentToken: process.env.BRAHMA_AGENT_TOKEN
});

// AETHER live broadcast: tools/broadcast.sh writes a rolling HLS stream +
// telemetry.json into out/live (gitignored). Serve it at /live so the theatron
// player (/aether) can attach. A live playlist/telemetry must NOT be cached, or
// a player never sees new segments; .ts chunks are immutable and cacheable.
const LIVE_DIR = process.env.BRAHMA_LIVE_DIR || path.join(__dirname, "..", "..", "out", "live");
app.use("/live", express.static(LIVE_DIR, {
    setHeaders: (res, filePath) => {
        if (filePath.endsWith(".m3u8") || filePath.endsWith(".json")) {
            res.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
        } else if (filePath.endsWith(".ts")) {
            res.setHeader("Content-Type", "video/mp2t");
        }
    },
}));

// REST API: module registry
app.get("/api/modules", (req, res) => {
    res.json(Object.values(moduleCache));
});

app.get("/api/modules/:name/params", (req, res) => {
    const params = paramCache[req.params.name] || [];
    res.json(params);
});

// REST API: Auth exchange (Human token -> HttpOnly cookie)
app.post("/api/auth/exchange", (req, res) => {
    if (!auth.isLoopback(req) || !auth.originOk(req)) {
        return res.status(403).json({ ok: false, error: "forbidden", message: "Loopback and trusted Origin required" });
    }
    const { token } = req.body || {};
    if (!auth.exchangeHuman(token)) {
        return res.status(401).json({ ok: false, error: "invalid_token", message: "Invalid or missing human token" });
    }
    res.setHeader("Set-Cookie", auth.cookieHeader());
    return res.json({ ok: true, role: "human" });
});

// REST API: Auth status
app.get("/api/auth/status", (req, res) => {
    const role = auth.roleOf(req);
    return res.json({ ok: true, role, authenticated: role !== null });
});

// Sandbox state & startup self-test
let sandboxStatus = {
    ok: false,
    backend: sandbox.backend(),
    checks: {},
    reason: "uninitialized",
    checkedAt: null
};

async function initSandbox() {
    try {
        const res = await sandbox.selfTest({ udpPort: OSC_SEND_PORT });
        sandboxStatus = {
            ...res,
            checkedAt: new Date().toISOString()
        };
        if (res.ok) {
            console.log(`[sandbox] Seatbelt isolation verified (backend: ${res.backend}, checks: 7/7 passed)`);
        } else {
            console.warn(`[sandbox] WARNING: Sandbox self-test failed (${res.reason}). Server-side runtimes DISABLED (fail-closed).`);
            if (process.env.BRAHMA_STRICT_SANDBOX === "1") {
                console.error(`[sandbox] FATAL: BRAHMA_STRICT_SANDBOX=1 specified. Aborting server startup.`);
                process.exit(1);
            }
        }
    } catch (err) {
        sandboxStatus = {
            ok: false,
            backend: sandbox.backend(),
            checks: {},
            reason: "exception:" + err.message,
            checkedAt: new Date().toISOString()
        };
        console.error(`[sandbox] Exception during sandbox self-test:`, err);
        if (process.env.BRAHMA_STRICT_SANDBOX === "1") {
            process.exit(1);
        }
    }
}

// AGPL source-disclosure surface. The workbench page is AGPL-3.0-or-later, and
// publishing it over HTTP requires offering its source. This endpoint names the exact
// running commit and every bundled dependency, with version, licence and upstream.
const pkg = require("./package.json");

const WORKBENCH_DEPENDENCIES = [
    { name: "@strudel/core", license: "AGPL-3.0-or-later", source: "https://codeberg.org/uzu/strudel" },
    { name: "@strudel/mini", license: "AGPL-3.0-or-later", source: "https://codeberg.org/uzu/strudel" },
    { name: "@strudel/transpiler", license: "AGPL-3.0-or-later", source: "https://codeberg.org/uzu/strudel" },
    { name: "codemirror", license: "MIT", source: "https://codemirror.net" },
    { name: "@codemirror/state", license: "MIT", source: "https://codemirror.net" },
    { name: "@codemirror/lang-javascript", license: "MIT", source: "https://codemirror.net" }
];

app.get("/workbench/source.json", (req, res) => {
    res.json({
        workbenchLicense: "AGPL-3.0-or-later",
        licenseFile: "/LICENSES/AGPL-3.0-or-later.txt",
        repository: "https://github.com/4444J99/alchemical-synthesizer",
        commit: process.env.BRAHMA_COMMIT_SHA || null,
        commitNote: "set BRAHMA_COMMIT_SHA at launch to pin the exact deployed revision",
        bundle: "/workbench/vendor/workbench.js",
        dependencies: WORKBENCH_DEPENDENCIES.map((d) => ({
            ...d,
            version: (pkg.dependencies && pkg.dependencies[d.name]) || "unlisted"
        }))
    });
});

// REST API: Agent composition loop (propose → accept → run).
//
// Three separate acts, three separate endpoints, and only a human may perform the
// last two. Accepting a proposal does not execute it; running does.
const agent = createAgentLayer({
    repoRoot: path.resolve(__dirname, "../.."),
    engineHealth: () => liveSessions.engineHealth()
});

function agentGuard(req, res, { requireHuman = false } = {}) {
    if (!auth.originOk(req)) {
        res.status(403).json({ ok: false, code: "forbidden_origin", message: "Untrusted Origin" });
        return null;
    }
    const role = auth.roleOf(req);
    if (requireHuman && role !== "human") {
        res.status(403).json({ ok: false, code: "human_role_required", message: "Human role required" });
        return null;
    }
    if (!requireHuman && role !== "human" && role !== "agent") {
        res.status(401).json({ ok: false, code: "auth_required", message: "Human or agent role required" });
        return null;
    }
    return role;
}

function agentReply(res, result, okStatus = 200) {
    if (result && result.ok === false) {
        const status = result.code === "forbidden" ? 403
            : result.code === "unknown_approval" ? 404
            : result.code === "invalid_transition" || result.code === "not_accepted" ? 409
            : 400;
        return res.status(status).json(result);
    }
    return res.status(okStatus).json(result);
}

app.get("/api/agent/providers", (req, res) => {
    if (!agentGuard(req, res)) return;
    return res.json({ providers: agent.available(), tools: agent.toolset() });
});

app.post("/api/agent/propose", async (req, res) => {
    const role = agentGuard(req, res);
    if (!role) return;

    const { provider, prompt, duration } = req.body || {};
    const result = await agent.propose({
        provider: provider || "mock",
        prompt: prompt || "",
        duration,
        proposedBy: role
    });
    return agentReply(res, result);
});

app.get("/api/agent/approvals", (req, res) => {
    if (!agentGuard(req, res)) return;
    return res.json({ approvals: agent.approvals.list() });
});

app.post("/api/agent/approvals/:id/accept", (req, res) => {
    if (!agentGuard(req, res, { requireHuman: true })) return;
    return agentReply(res, agent.accept(req.params.id, { actor: "human" }));
});

app.post("/api/agent/approvals/:id/reject", (req, res) => {
    if (!agentGuard(req, res, { requireHuman: true })) return;
    return agentReply(res, agent.reject(req.params.id, { actor: "human", reason: (req.body || {}).reason }));
});

app.post("/api/agent/approvals/:id/run", (req, res) => {
    if (!agentGuard(req, res, { requireHuman: true })) return;
    return agentReply(res, agent.run(req.params.id, { actor: "human" }), 202);
});

app.get("/api/agent/jobs/:id", (req, res) => {
    if (!agentGuard(req, res)) return;
    const job = agent.runner.get(req.params.id);
    if (!job) return res.status(404).json({ ok: false, code: "unknown_job", message: `No job ${req.params.id}` });
    return res.json({ job });
});

// REST API: Runtime status discovery
app.get("/api/runtimes", (req, res) => {    const role = auth.roleOf(req);
    const runtimesList = runtimes.getRuntimeStatus({ role, sandboxStatus });
    return res.json({
        sandbox: {
            ok: sandboxStatus.ok,
            backend: sandboxStatus.backend,
            checks: sandboxStatus.checks,
            reason: sandboxStatus.reason
        },
        runtimes: runtimesList
    });
});

// REST API: Sandboxed SuperCollider sclang evaluation (opt-in behind BRAHMA_ALLOW_SCLANG=1 and human role)
app.post("/api/runtimes/sclang/eval", async (req, res) => {
    if (!auth.originOk(req)) {
        return res.status(403).json({ ok: false, error: "forbidden_origin", message: "Untrusted Origin" });
    }
    if (auth.roleOf(req) !== "human") {
        return res.status(403).json({ ok: false, error: "human_role_required", message: "Human role required for sclang execution" });
    }
    if (process.env.BRAHMA_ALLOW_SCLANG !== "1") {
        return res.status(403).json({ ok: false, error: "sclang_disabled_by_env", message: "sclang execution disabled: BRAHMA_ALLOW_SCLANG != 1" });
    }
    if (!sandboxStatus.ok) {
        return res.status(503).json({ ok: false, error: "sandbox_unavailable", message: "Sandbox self-test failed or unavailable" });
    }
    const { code, timeoutMs } = req.body || {};
    if (typeof code !== "string" || !code.trim()) {
        return res.status(400).json({ ok: false, error: "bad_request", message: "Missing code in request body" });
    }
    try {
        const result = await runtimes.executeSclang({ code, timeoutMs });
        return res.json(result);
    } catch (err) {
        return res.status(500).json({ ok: false, error: err.code || "exec_error", message: err.message });
    }
});

// Bind HTTP server to loopback by default
server = app.listen(HTTP_PORT, HOST, () => {
    const port = server.address() ? server.address().port : HTTP_PORT;
    console.log(`--- VISUAL CORTEX ONLINE: http://${HOST}:${port} ---`);
    console.log(`--- GOLEM UI: http://${HOST}:${port}/golem ---`);
    console.log(`--- CORTEX UI: http://${HOST}:${port}/cortex ---`);
    // Human token handoff. Without this, no browser can obtain the human role and
    // the workbench is unusable: the token is per-launch and random.
    if (process.env.BRAHMA_HUMAN_TOKEN) {
        console.log(`--- HUMAN ROLE: supplied by environment, not printed ---`);
    } else {
        console.log(`--- WORKBENCH (human): http://${HOST}:${port}/workbench/#t=${auth.humanToken} ---`); // allow-secret
        console.log(`--- Open that URL on this machine to claim the human role. ---`);
    }
});

// 2. WebSocket Server (for Browser & Workbench) with Origin Verification
const wss = new WebSocket.Server({
    server,
    verifyClient: (info, cb) => {
        if (!auth.originOk(info.req)) {
            // Reject untrusted Origin headers with HTTP 403 Forbidden
            return cb(false, 403, "Forbidden");
        }
        return cb(true);
    }
});

// 3. OSC UDP Port (From SuperCollider). Loopback only: the engine runs on this host.
const udpPort = new osc.UDPPort({
    localAddress: HOST,
    localPort: OSC_UDP_PORT,
    metadata: true
});

// 4. OSC Send Port (To SuperCollider)
const sendPort = new osc.UDPPort({
    localAddress: HOST,
    localPort: 0, // ephemeral
    remoteAddress: "127.0.0.1",
    remotePort: OSC_SEND_PORT,
    metadata: true
});

// 5. Dirt Protocol Bridge (UDP 127.0.0.1:57130 -> SC 57120)
const dirtBridge = createDirtBridge({
    port: DIRT_PORT,
    scPort: OSC_SEND_PORT,
    scHost: "127.0.0.1",
    bindAddress: "127.0.0.1",
    metadata: true
});

dirtBridge.on("ready", ({ port, scPort }) => {
    console.log(`--- DIRT BRIDGE ONLINE: UDP ${port} -> SC ${scPort} ---`);
});

dirtBridge.on("error", (err) => {
    console.warn(`Dirt bridge notice (${err.code || err.message}) — continuing server execution`);
});

dirtBridge.start();

wss.on("connection", (ws, req) => {
    // Role is held in a mutable cell so typed frames can upgrade the connection
    // (auth) without the protocol layer reaching into ws internals.
    const role = { current: auth.roleOf(req) };

    const limiter = createTokenBucket({
        ratePerSec: Number(process.env.BRAHMA_EVENT_RATE || 200),
        burst: Number(process.env.BRAHMA_EVENT_BURST || 400)
    });

    const session = createSession({
        getRole: () => role.current,
        setRole: (r) => { role.current = r; },
        exchangeHuman: (t) => auth.exchangeHuman(t),
        isAgentToken: (t) => safeEqual(t, auth.agentToken),
        sendOsc: (address, args) => sendPort.send({ address, args: oscArgs(args) }),
        allowedPrefixes: ALLOWED_NAMESPACES,
        limiter,
        sessions: liveSessions,
        send: (payload) => {
            if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(payload));
        }
    });

    ws.role = role.current;
    console.log(`Client Connected to Visual Cortex [role: ${ws.role || "unauthenticated"}]`);

    ws.on("message", (message) => {
        session.handle(message.toString());
        ws.role = role.current;
    });
});

// Broadcast incoming OSC to all WebSocket clients + cache registry data
udpPort.on("message", (oscMsg) => {
    // Engine health signal: /brahma/live/pong <module_count> <live_voice_count>
    if (oscMsg.address === "/brahma/live/pong") {
        liveSessions.recordPong(oscMsg.args[0]?.value, oscMsg.args[1]?.value);
    }

    // Cache registry module broadcasts
    if (oscMsg.address === "/brahma/registry/module") {
        const name = oscMsg.args[0]?.value;
        if (name) {
            moduleCache[name] = {
                name: name,
                category: oscMsg.args[1]?.value || "",
                synthDef: oscMsg.args[2]?.value || "",
                numParams: oscMsg.args[3]?.value || 0,
                numInstances: oscMsg.args[4]?.value || 0,
                description: oscMsg.args[5]?.value || ""
            };
        }
    }

    // Cache registry param broadcasts
    if (oscMsg.address === "/brahma/registry/param") {
        const moduleName = oscMsg.args[0]?.value;
        const paramName = oscMsg.args[1]?.value;
        if (moduleName && paramName) {
            if (!paramCache[moduleName]) paramCache[moduleName] = [];
            const existing = paramCache[moduleName].findIndex(p => p.name === paramName);
            const param = {
                name: paramName,
                default: oscMsg.args[2]?.value || 0,
                min: oscMsg.args[3]?.value || 0,
                max: oscMsg.args[4]?.value || 1,
                units: oscMsg.args[5]?.value || "",
                desc: oscMsg.args[6]?.value || ""
            };
            if (existing >= 0) {
                paramCache[moduleName][existing] = param;
            } else {
                paramCache[moduleName].push(param);
            }
        }
    }

    // Broadcast to all WebSocket clients
    const jsonMsg = JSON.stringify({
        address: oscMsg.address,
        args: oscMsg.args
    });

    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(jsonMsg);
        }
    });
});

udpPort.on("ready", () => {
    console.log(`OSC Listener Ready on port ${OSC_UDP_PORT}`);
});

sendPort.on("ready", () => {
    console.log(`OSC Sender Ready -> port ${OSC_SEND_PORT}`);
});

// Graceful UDP degradation: degrade, don't die
udpPort.on("error", (err) => {
    console.warn(`OSC listener unavailable on ${OSC_UDP_PORT} — serving HTTP without live SC telemetry (${err.code || err.message})`);
});
sendPort.on("error", (err) => {
    console.warn(`OSC sender unavailable — serving HTTP without SC control (${err.code || err.message})`);
});

udpPort.open();
sendPort.open();

// Fail-closed sandbox self-test on boot
initSandbox();

function closeServer(cb) {
    try { dirtBridge.close(); } catch (_) {}
    try { udpPort.close(); } catch (_) {}
    try { sendPort.close(); } catch (_) {}
    try { wss.close(); } catch (_) {}
    if (server) {
        server.close(cb);
    } else if (cb) {
        cb();
    }
}

process.on("SIGTERM", () => closeServer());
process.on("SIGINT", () => closeServer());

module.exports = {
    app,
    server,
    wss,
    auth,
    dirtBridge,
    sandboxStatus,
    initSandbox,
    closeServer,
    udpPort,
    sendPort,
    liveSessions,
    ALLOWED_NAMESPACES,
    HOST,
    HTTP_PORT
};
