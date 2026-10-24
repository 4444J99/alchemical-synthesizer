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
//  Env: PORT (default 8080), AETHER_LIVE_DIR (default /live),
//       AETHER_STATIC_DIR (default the bundled player).
// ============================================================================
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");

const PORT = Number(process.env.PORT || 8080);
const LIVE_DIR = process.env.AETHER_LIVE_DIR || "/live";
const STATIC_DIR = process.env.AETHER_STATIC_DIR || path.join(__dirname, "player");
// Ω submission intake: POST /submit enqueues a viewer's stream URL through the
// single queue authority (tools/ingest_queue.py), which tools/broadcast.sh pops
// so a creature eats it live. Tools dir defaults to the container layout (/app),
// overridable for local dev.
const QUEUE_DIR = path.join(LIVE_DIR, "queue");
const TOOLS_DIR = process.env.AETHER_TOOLS_DIR ||
  (fs.existsSync("/app/tools/ingest_queue.py") ? "/app/tools" : path.join(__dirname, "..", "..", "tools"));

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

  // Ω: a viewer feeds the organism. POST /submit { url, license?, attribution? }
  // -> enqueue via the single queue authority; broadcast.sh pops it, a creature
  // eats it live. Rights posture stays human-gated (license recorded, not cleared).
  if (urlPath === "/submit" && req.method === "POST") {
    let body = "";
    req.on("data", (c) => { body += c; if (body.length > 4096) req.destroy(); });
    req.on("end", () => {
      let payload;
      try { payload = JSON.parse(body || "{}"); } catch { payload = {}; }
      const url = String(payload.url || "").trim();
      if (!/^https?:\/\//i.test(url)) {
        res.writeHead(400, { "Content-Type": "application/json" });
        return res.end(JSON.stringify({ ok: false, error: "a http(s) stream URL is required" }));
      }
      const args = [path.join(TOOLS_DIR, "ingest_queue.py"), "add", "--url", url,
        "--license", String(payload.license || "unknown"), "--dir", QUEUE_DIR];
      if (payload.attribution) args.push("--attribution", String(payload.attribution));
      execFile("python3", args, { timeout: 5000 }, (err, stdout) => {
        if (err) {
          res.writeHead(503, { "Content-Type": "application/json" });
          return res.end(JSON.stringify({ ok: false, error: "queue unavailable" }));
        }
        let rec = {};
        try { rec = JSON.parse(stdout); } catch { /* ignore */ }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: true, id: rec.id || null, note: "queued — a creature will eat it live." }));
      });
    });
    return;
  }

  // Live stream: served from LIVE_DIR. Playlists/telemetry must not be cached.
  if (urlPath.startsWith("/live/")) {
    const file = safeResolve(LIVE_DIR, urlPath.slice("/live".length));
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

module.exports = { server, safeResolve };
