"use strict";
/**
 * rest.js — REST API (/api/v1).
 *
 * The HTTP face of the capability core plus account, billing, marketplace and
 * waitlist endpoints. Metered endpoints require an API key (Bearer/x-api-key).
 */

const express = require("express");
const { rateLimit } = require("../auth/rate-limit");
const fs = require("fs");
const path = require("path");
const actions = require("../core/actions");
const licensing = require("../auth/licensing");
const { meter } = require("../auth/metering");
const { getPlan, listPlans } = require("../auth/plans");
const billing = require("../billing/billing");
const marketplace = require("../marketplace/marketplace");
const { collection } = require("../core/store");

// Where real (non-simulated) specimen audio lives on disk. A specimen's
// audioUrl is either an absolute http(s) URL (a CDN/R2 object — we redirect) or
// a filename resolved under this dir (we stream it, path-traversal-safe).
const SPECIMENS_DIR = process.env.BRAHMA_SPECIMENS_DIR || path.join(__dirname, "..", "..", "data", "specimens");
const AUDIO_TYPES = {
  ".wav": "audio/wav", ".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".aac": "audio/aac",
  ".ogg": "audio/ogg", ".flac": "audio/flac", ".opus": "audio/opus", ".mp4": "video/mp4"
};

const router = express.Router();
// Share signup/login admission before JSON parsing or password hashing.
const accountLimit = rateLimit({ limit: 10 });
router.use(["/account/signup", "/account/login"], accountLimit);
const audioLimit = rateLimit({ limit: 120 });
router.use(express.json({ limit: "256kb" }));

const ok = (res, data) => res.json({ ok: true, data });
const fail = (res, code, msg, extra = {}) => res.status(code).json({ ok: false, error: msg, ...extra });

// ---- meta ----
router.get("/", (req, res) => ok(res, {
  service: "brahma-foundry", version: "0.1.0",
  surfaces: { rest: "/api/v1", mcp: "/mcp", acp_comm: "/acp", acp_client: "/acp/jsonrpc" },
  capabilities: actions.listActions().map((a) => a.name),
  docs: "/api/v1/openapi.json"
}));

router.get("/openapi.json", (req, res) => res.json(buildOpenApi()));

// ---- catalog (free, unmetered reads but allow anonymous) ----
router.get("/modules", meter({ cost: 0, require: false }), (req, res) =>
  ok(res, actions.invoke("list_modules", { category: req.query.category, q: req.query.q })));

router.get("/modules/:name", meter({ cost: 0, require: false }), (req, res) => {
  try { ok(res, actions.invoke("get_module", { name: req.params.name })); }
  catch (e) { fail(res, 404, e.message); }
});

router.get("/organism/state", meter({ cost: 0, require: false }), (req, res) =>
  ok(res, actions.invoke("get_organism_state")));

// ---- render (metered, billable) ----
router.post("/render", meter({ cost: 1 }), (req, res) => {
  try {
    const spc = actions.invoke("render_specimen", {
      module: req.body.module, title: req.body.title,
      creator: req.body.creator || req.auth.ownerEmail, durationSec: req.body.durationSec
    }, req.auth);
    ok(res, { specimen: spc, usage: req.auth.usage, quota: req.auth.quota });
  } catch (e) { fail(res, 400, e.message); }
});

// ---- specimens / marketplace ----
router.get("/specimens", (req, res) => ok(res, marketplace.listForSale({ module: req.query.module, creator: req.query.creator })));

router.get("/specimens/:id", (req, res) => {
  const s = marketplace.getSpecimen(req.params.id);
  return s ? ok(res, marketplace.publicSpecimen(s)) : fail(res, 404, "specimen_not_found");
});

router.get("/specimens/:id/audio", audioLimit, (req, res) => {
  const s = marketplace.getSpecimen(req.params.id);
  if (!s) return fail(res, 404, "specimen_not_found");
  if (s.simulated || !s.audioUrl) {
    return fail(res, 409, "specimen_simulated", { hint: "This specimen has no verified audio artifact. Specimen creation currently produces simulated records." });
  }
  // Existing artifacts can be registered separately as a local file or CDN URL.
  // Redirect absolute URLs; stream local files with single-range support.
  const resolved = resolveSpecimenAudio(s.audioUrl);
  if (!resolved) return fail(res, 404, "audio_file_missing", { note: "audioUrl does not resolve to a stored specimen file." });
  if (resolved.url) return res.redirect(302, resolved.url);
  return streamFile(req, res, resolved.file);
});

router.post("/specimens/:id/list", meter({ cost: 0 }), (req, res) => {
  try {
    const s = marketplace.listSpecimen({
      specimenId: req.params.id, ownerEmail: req.auth.ownerEmail,
      ownerPlan: req.auth.plan, priceCents: req.body.priceCents
    });
    ok(res, s);
  } catch (e) { fail(res, ["plan_forbidden", "not_owned"].includes(e.code) ? 403 : 400, e.message); }
});

router.post("/specimens/:id/unlist", meter({ cost: 0 }), (req, res) => {
  try { ok(res, marketplace.unlist(req.params.id, req.auth.ownerEmail)); }
  catch (e) { fail(res, e.code === "not_owned" ? 403 : 400, e.message); }
});

// ---- accounts ----
router.post("/account/signup", (req, res) => {
  try { ok(res, licensing.createUser({ email: req.body.email, password: req.body.password })); }
  catch (e) { fail(res, 400, e.message); }
});

router.post("/account/login", (req, res) => {
  const user = licensing.authenticate(req.body.email, req.body.password);
  if (!user) return fail(res, 401, "invalid_credentials");
  ok(res, { user, keys: licensing.listKeysFor(user.email) });
});

router.get("/account/keys", meter({ cost: 0 }), (req, res) =>
  ok(res, licensing.listKeysFor(req.auth.ownerEmail)));

router.post("/account/keys", meter({ cost: 0 }), (req, res) =>
  ok(res, { ...licensing.issueApiKey(req.auth.ownerEmail, req.auth.plan, req.body.label || "key") }));

router.post("/account/keys/revoke", meter({ cost: 0 }), (req, res) => {
  const target = licensing.resolveApiKey(req.body.key);
  if (!target || target.ownerEmail !== req.auth.ownerEmail) return fail(res, 403, "key_not_owned");
  licensing.revokeApiKey(req.body.key);
  ok(res, { revoked: true });
});

router.get("/account/usage", meter({ cost: 0 }), (req, res) =>
  ok(res, { ownerEmail: req.auth.ownerEmail, plan: req.auth.plan, usage: req.auth.usage, quota: req.auth.quota }));

// ---- plans & billing ----
router.get("/plans", (req, res) => ok(res, listPlans()));
router.get("/billing/status", (req, res) => ok(res, billing.status()));

router.post("/billing/checkout/plan", async (req, res) => {
  try { ok(res, await billing.checkoutPlan({ email: req.body.email, plan: req.body.plan, req })); }
  catch (e) { fail(res, e.status || 400, e.message); }
});

router.post("/billing/checkout/specimen", async (req, res) => {
  try { ok(res, await billing.checkoutSpecimen({ email: req.body.email, specimenId: req.body.specimenId, req })); }
  catch (e) { fail(res, e.status || 400, e.message); }
});

// Stub confirm (used when Stripe is not configured) — simulates a paid webhook.
router.get("/billing/confirm", (req, res) => {
  let order;
  try { order = billing.confirmStub(req.query.order, req.query.token).order; }
  catch (e) { return fail(res, e.status || 400, e.message); }
  res.send(`<!doctype html><meta charset=utf8><title>Order confirmed</title>
    <body style="font-family:system-ui;background:#120a1e;color:#d4d4d8;text-align:center;padding:4rem">
    <h1 style="color:#e94560">Payment confirmed (stub)</h1>
    <p>Order <code>${order.id}</code> — ${order.kind} — fulfilled.</p>
    <p><a style="color:#d4a853" href="/dashboard">Return to dashboard →</a></p>
    <p style="opacity:.5;font-size:.8rem">Local demonstration only. No payment was processed.</p></body>`);
});

// The former unsigned fallback is retired. Only the raw signed route is valid.
router.post("/billing/webhook", (req, res) => {
  fail(res, 410, "use_signed_stripe_webhook");
});

// ---- waitlist (top-of-funnel) ----
router.post("/waitlist", (req, res) => {
  const email = String(req.body.email || "").trim().toLowerCase();
  if (!email.includes("@")) return fail(res, 400, "valid email required");
  const wl = collection("waitlist");
  if (!wl.find((w) => w.email === email)) {
    wl.insert({ email, interest: req.body.interest || "", createdAt: new Date().toISOString() });
  }
  ok(res, { joined: true });
});

// ---- specimen audio resolution + streaming ----

/**
 * Resolve a specimen's audioUrl to something servable.
 *   { url }  — an absolute http(s) URL (CDN/R2): the caller redirects.
 *   { file } — an on-disk file under SPECIMENS_DIR (path-traversal-safe).
 *   null     — unresolvable / escapes the specimens dir / missing.
 */
function resolveSpecimenAudio(audioUrl) {
  if (typeof audioUrl !== "string" || !audioUrl) return null;
  if (/^https?:\/\//i.test(audioUrl)) return { url: audioUrl };
  try {
    const base = fs.realpathSync(SPECIMENS_DIR);
    const candidate = path.resolve(base, audioUrl.replace(/^\/+/, ""));
    const contained = (file) => {
      const relative = path.relative(base, file);
      return relative && relative !== ".." && !relative.startsWith(".." + path.sep) && !path.isAbsolute(relative);
    };
    if (!contained(candidate)) return null;
    const file = fs.realpathSync(candidate);
    if (!contained(file) || !fs.statSync(file).isFile()) return null;
    return { file };
  } catch { return null; }
}

/** Return one inclusive byte range, or null for an invalid/unsupported range. */
function parseAudioRange(header, size) {
  const match = typeof header === "string" && /^bytes=[ \t]*(\d*)-(\d*)$/i.exec(header.trim());
  if (!match || (!match[1] && !match[2]) || size === 0) return null;
  const length = BigInt(size);
  if (!match[1]) {
    const suffix = BigInt(match[2]);
    if (suffix === 0n) return null;
    return { start: suffix >= length ? 0 : Number(length - suffix), end: size - 1 };
  }
  const start = BigInt(match[1]);
  const end = match[2] ? BigInt(match[2]) : length - 1n;
  if (start >= length || end < start) return null;
  return { start: Number(start), end: end >= length ? size - 1 : Number(end) };
}

/** Stream one opened regular file, handling both range and read failures. */
function streamFile(req, res, file) {
  let fd;
  let stat;
  const unavailable = () => {
    for (const header of ["Content-Length", "Content-Range", "Content-Type", "Cache-Control"]) res.removeHeader(header);
    return fail(res, 404, "audio_file_missing");
  };
  try {
    // Pin the file descriptor before sending headers. Recheck the opened file
    // so a removed/replaced file or a special file cannot become a false 200.
    fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0) | (fs.constants.O_NONBLOCK || 0));
    stat = fs.fstatSync(fd);
    if (!stat.isFile() || !Number.isSafeInteger(stat.size)) {
      fs.closeSync(fd);
      return unavailable();
    }
  } catch {
    if (fd !== undefined) fs.closeSync(fd);
    return unavailable();
  }

  let range = req.headers.range;
  const unit = typeof range === "string" && /^([^=\s]+)=/.exec(range.trim());
  // Range applies to GET. Unknown units and unsupported multipart requests
  // fall back to the full representation, as do empty files. No strong artifact
  // validator is established here, so If-Range cannot authorize a partial body.
  if (req.method !== "GET" || stat.size === 0 || req.headers["if-range"] !== undefined ||
      (unit && unit[1].toLowerCase() !== "bytes") || (typeof range === "string" && range.includes(","))) {
    range = undefined;
  }
  const bytes = range === undefined ? null : parseAudioRange(range, stat.size);
  if (range !== undefined && !bytes) {
    fs.closeSync(fd);
    res.status(416).setHeader("Content-Range", `bytes */${stat.size}`);
    return res.end();
  }

  const type = AUDIO_TYPES[path.extname(file).toLowerCase()] || "application/octet-stream";
  res.setHeader("Accept-Ranges", "bytes");
  res.setHeader("Content-Type", type);
  res.setHeader("Cache-Control", "public, max-age=3600"); // a specimen file is immutable

  if (bytes) {
    res.status(206);
    res.setHeader("Content-Range", `bytes ${bytes.start}-${bytes.end}/${stat.size}`);
    res.setHeader("Content-Length", bytes.end - bytes.start + 1);
  } else {
    res.setHeader("Content-Length", stat.size);
  }
  if (req.method === "HEAD") {
    fs.closeSync(fd);
    return res.end();
  }

  let stream;
  try { stream = fs.createReadStream(file, { fd, autoClose: true, ...bytes }); }
  catch {
    fs.closeSync(fd);
    return unavailable();
  }
  stream.once("error", () => {
    if (res.headersSent) res.destroy();
    else unavailable();
  });
  res.once("close", () => stream.destroy());
  return stream.pipe(res);
}

// ---- minimal OpenAPI generator ----
function buildOpenApi() {
  return {
    openapi: "3.0.0",
    info: { title: "Brahma Foundry API", version: "0.1.0", description: "Productization API for the Alchemical Synthesizer." },
    servers: [{ url: "/api/v1" }],
    paths: {
      "/modules": { get: { summary: "List modules" } },
      "/modules/{name}": { get: { summary: "Get module" } },
      "/organism/state": { get: { summary: "Live organism telemetry" } },
      "/render": { post: { summary: "Render a specimen (metered)", security: [{ apiKey: [] }] } },
      "/specimens": { get: { summary: "List marketplace specimens" } },
      "/specimens/{id}/audio": { get: { summary: "Stream a specimen's audio (Range-enabled; 302 to CDN, 409 if simulated)" } },
      "/plans": { get: { summary: "List plans" } },
      "/billing/checkout/plan": { post: { summary: "Start a plan checkout" } },
      "/account/signup": { post: { summary: "Create an account" } },
      "/waitlist": { post: { summary: "Join the waitlist" } }
    },
    components: { securitySchemes: { apiKey: { type: "http", scheme: "bearer" } } }
  };
}

module.exports = router;
