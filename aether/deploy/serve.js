#!/usr/bin/env node
// ============================================================================
//  serve.js — dependency-free static + live-HLS server for the AETHER container.
// ----------------------------------------------------------------------------
//  The 24/7 sovereign host (AETHER plan §5.3) runs the generator (broadcast.sh)
//  alongside this server. It is deliberately built on node BUILTINS ONLY — no
//  express, no `osc` (and thus no native `serialport` build) — so the container
//  image needs no `npm install`, stays tiny, and can't fail on a native build.
//
//  It serves two things:
//    /live/*   the rolling HLS stream written by broadcast.sh (LIVE_DIR):
//              .m3u8/.json no-cache, .ts as video/mp2t.
//    /*        a static surface (STATIC_DIR) — the theatron player, so the
//              container is a self-contained "watch it live" host. index.html
//              at the directory root.
//    /healthz  liveness for the container platform.
//
//  Env: PORT (default 8080), AETHER_LIVE_DIR (default workspace out/live),
//       AETHER_STATIC_DIR (default the bundled player), AETHER_SUBMIT_TOKEN
//       (operator-only intake; disabled when unset). The container sets /live.
// ============================================================================
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");
const { timingSafeEqual } = require("crypto");

const PORT = Number(process.env.PORT || 8080);
const AETHER_ROOT = path.resolve(__dirname, "..");
const WORKSPACE = fs.existsSync(path.join(AETHER_ROOT, "..", "brahma")) ? path.dirname(AETHER_ROOT) : AETHER_ROOT;
const LIVE_DIR = process.env.AETHER_LIVE_DIR || path.join(WORKSPACE, "out", "live");
const STATIC_DIR = process.env.AETHER_STATIC_DIR ||
  (fs.existsSync(path.join(__dirname, "player")) ? path.join(__dirname, "player") : path.join(__dirname, "..", "web", "listener"));
// Ω submission intake: POST /submit enqueues a trusted operator's stream URL through the
// single queue authority (tools/ingest_queue.py), which tools/broadcast.sh pops
// so a creature eats it live. Tools dir defaults to the container layout (/app),
// overridable for local dev.
const QUEUE_DIR = path.join(LIVE_DIR, "queue");
const TOOLS_DIR = process.env.AETHER_TOOLS_DIR ||
  (fs.existsSync(path.join(__dirname, "tools", "ingest_queue.py")) ? path.join(__dirname, "tools") : path.join(__dirname, "..", "tools"));
const SUBMIT_TOKEN = String(process.env.AETHER_SUBMIT_TOKEN || "").trim();
let submitBusy = false;

function json(res, code, value) {
  if (!res.destroyed && !res.writableEnded) res.writeHead(code, { "Content-Type": "application/json" }).end(JSON.stringify(value));
}

function authorized(req) {
  const expected = Buffer.from(`Bearer ${SUBMIT_TOKEN}`);
  const provided = Buffer.from(req.headers.authorization || "");
  return provided.length === expected.length && timingSafeEqual(provided, expected);
}

// Publish only transport artifacts. Queue records and private generator state
// share the live directory but are never part of the listener surface.
function publicLiveKey(urlPath) {
  try {
    const key = decodeURIComponent(urlPath.slice("/live/".length));
    return /^(?:stream\.m3u8|seg_\d+\.ts|telemetry\.json|lineage\.json)$/.test(key) ? key : null;
  } catch { return null; }
}

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8",
  ".m3u8": "application/vnd.apple.mpegurl", ".ts": "video/mp2t",
  ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml",
  ".wav": "audio/wav", ".mp3": "audio/mpeg", ".mp4": "video/mp4", ".ico": "image/x-icon",
};

/** Resolve a URL path to a file under `root`, safe against traversal. Returns
 *  the absolute path or null if it escapes root / does not exist. */
function safeResolve(root, urlPath) {
  try {
    const rel = decodeURIComponent(urlPath.split("?")[0]).replace(/^\/+/, "");
    const base = fs.realpathSync(root);
    const inside = (file) => {
      const relative = path.relative(base, file);
      return relative !== ".." && !relative.startsWith(".." + path.sep) && !path.isAbsolute(relative);
    };
    let abs = path.resolve(base, rel);
    if (!inside(abs)) return null;
    abs = fs.realpathSync(abs);
    if (!inside(abs)) return null;
    if (fs.statSync(abs).isDirectory()) abs = path.join(abs, "index.html");
    abs = fs.realpathSync(abs);
    return inside(abs) && fs.statSync(abs).isFile() ? abs : null;
  } catch { return null; }
}

function sendFile(res, file, extraHeaders) {
  const ext = path.extname(file).toLowerCase();
  const headers = Object.assign({ "Content-Type": MIME[ext] || "application/octet-stream" }, extraHeaders || {});
  let stat;
  try { stat = fs.statSync(file); } catch { res.writeHead(404).end("not found"); return; }
  headers["Content-Length"] = stat.size;
  res.writeHead(200, headers);
  const stream = fs.createReadStream(file);
  stream.on("error", () => res.destroy());
  stream.pipe(res);
}

const server = http.createServer((req, res) => {
  const urlPath = (req.url || "/").split("?")[0];

  if (urlPath === "/healthz") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ ok: true, uptime: process.uptime() }));
  }

  // Remote URLs are fetched by ffmpeg on the broadcaster's network. Until that
  // worker has isolated egress, admission is for trusted operators only.
  if (urlPath === "/submit" && req.method === "POST") {
    if (!SUBMIT_TOKEN) return json(res, 503, { ok: false, error: "operator intake is not configured" });
    if (!authorized(req)) return json(res, 401, { ok: false, error: "operator authorization required" });
    let body = "";
    let bytes = 0;
    req.on("data", (c) => {
      bytes += c.length;
      if (bytes > 4096) { json(res, 413, { ok: false, error: "submission too large" }); return; }
      body += c;
    });
    req.on("end", () => {
      if (bytes > 4096) return;
      let payload;
      try { payload = JSON.parse(body || "{}"); } catch { payload = {}; }
      if (!payload || typeof payload !== "object" || Array.isArray(payload)) payload = {};
      for (const key of ["url", "license", "attribution"]) {
        if ((payload[key] !== undefined && typeof payload[key] !== "string") ||
            (typeof payload[key] === "string" && /[\x00-\x1f\x7f]/.test(payload[key]))) {
          return json(res, 400, { ok: false, error: "submission fields must be strings without control characters" });
        }
      }
      let url;
      try {
        url = new URL((payload.url || "").trim());
        if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password) throw new Error("invalid URL");
      } catch { return json(res, 400, { ok: false, error: "an http(s) stream URL without credentials is required" }); }
      if (submitBusy) return json(res, 429, { ok: false, error: "queue busy; retry shortly" });
      const args = [path.join(TOOLS_DIR, "ingest_queue.py"), "add", "--url", url.href,
        "--license", payload.license || "unknown", "--dir", QUEUE_DIR];
      if (payload.attribution) args.push("--attribution", payload.attribution);
      submitBusy = true;
      try {
        execFile("python3", args, { timeout: 5000, maxBuffer: 64 * 1024 }, (err, stdout) => {
          submitBusy = false;
          if (err) return json(res, 503, { ok: false, error: "queue unavailable" });
          let rec;
          try { rec = JSON.parse(stdout); } catch { return json(res, 503, { ok: false, error: "invalid queue response" }); }
          if (!rec || typeof rec.id !== "string") return json(res, 503, { ok: false, error: "invalid queue response" });
          json(res, 200, { ok: true, id: rec.id, note: "queued for the next available segment" });
        });
      } catch {
        submitBusy = false;
        json(res, 503, { ok: false, error: "queue unavailable" });
      }
    });
    return;
  }

  // Live stream: served from LIVE_DIR. Playlists/telemetry must not be cached.
  if (urlPath.startsWith("/live/")) {
    const key = publicLiveKey(urlPath);
    const file = key && safeResolve(LIVE_DIR, key);
    if (!file) { res.writeHead(404).end("no stream yet"); return; }
    const noCache = file.endsWith(".m3u8") || file.endsWith(".json");
    return sendFile(res, file, noCache ? { "Cache-Control": "no-cache, no-store, must-revalidate" } : undefined);
  }

  // Static surface (the theatron player). Root -> index.html.
  const file = safeResolve(STATIC_DIR, urlPath === "/" ? "/index.html" : urlPath);
  if (!file) { res.writeHead(404).end("not found"); return; }
  return sendFile(res, file);
});

if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`[aether] serve.js on :${PORT}  live=${LIVE_DIR}  static=${STATIC_DIR}`);
  });

  // Graceful shutdown so the container platform can recycle us cleanly.
  for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => { server.close(() => process.exit(0)); });
}

module.exports = { server, safeResolve, publicLiveKey };
