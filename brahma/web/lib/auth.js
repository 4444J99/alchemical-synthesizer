"use strict";
/**
 * auth.js — loopback trust, Origin checking, and the two roles.
 *
 *   human  per-launch random token, exchanged once for an HttpOnly SameSite=Strict
 *          cookie. May edit, accept, run, stop-all and change settings.
 *   agent  a separate token (Authorization: Bearer). May read, propose and run
 *          offline render/analyze. It can never obtain the human role.
 *
 * Tokens are 128-bit random, compared in constant time, and never logged.
 */

const crypto = require("crypto");

const COOKIE = "brahma_human";

function randomToken() { return crypto.randomBytes(16).toString("hex"); }

function safeEqual(a, b) {
  const x = Buffer.from(String(a)), y = Buffer.from(String(b));
  if (x.length !== y.length) return false;
  return crypto.timingSafeEqual(x, y);
}

function isLoopbackAddress(addr) {
  if (!addr) return false;
  return addr === "127.0.0.1" || addr === "::1" || addr === "::ffff:127.0.0.1";
}

function parseCookies(header) {
  const out = {};
  for (const part of String(header || "").split(";")) {
    const i = part.indexOf("=");
    if (i <= 0) continue;
    try {
      out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
    } catch (_) {
      // Cookies are untrusted, including on WebSocket upgrades. An invalid
      // encoding contributes no credential and must not escape the handler.
    }
  }
  return out;
}

function createAuth({ getPort, humanToken, agentToken } = {}) {
  const human = humanToken || randomToken();
  const agent = agentToken || randomToken();

  /** Origins that count as "this gateway, in a browser on this machine". */
  function allowedOrigins() {
    const p = getPort();
    return new Set([`http://127.0.0.1:${p}`, `http://localhost:${p}`, `http://[::1]:${p}`]);
  }

  /**
   * Browser requests carry an Origin; it must be this gateway. A request with no
   * Origin is a non-browser local client — acceptable only on loopback, and it
   * still needs a token for any privileged action.
   */
  function originOk(req) {
    const origin = req.headers.origin;
    if (origin === undefined) return isLoopbackAddress(req.socket && req.socket.remoteAddress);
    return allowedOrigins().has(origin);
  }

  function isLoopback(req) { return isLoopbackAddress(req.socket && req.socket.remoteAddress); }

  /** Resolve the role of a request, or null. Loopback is required for both roles. */
  function roleOf(req) {
    if (!isLoopback(req)) return null;
    const cookies = parseCookies(req.headers.cookie);
    if (cookies[COOKIE] && safeEqual(cookies[COOKIE], human)) return "human";
    const auth = req.headers.authorization || "";
    if (auth.startsWith("Bearer ") && safeEqual(auth.slice(7).trim(), agent)) return "agent";
    return null;
  }

  function exchangeHuman(token) { return typeof token === "string" && safeEqual(token, human); } // allow-secret

  function cookieHeader() {
    return `${COOKIE}=${human}; HttpOnly; SameSite=Strict; Path=/; Max-Age=86400`;
  }

  return { roleOf, originOk, isLoopback, exchangeHuman, cookieHeader, humanToken: human, agentToken: agent, COOKIE };
}

module.exports = { createAuth, isLoopbackAddress, parseCookies, safeEqual, randomToken, COOKIE };
