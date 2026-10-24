"use strict";
/**
 * metering.js — Usage metering + quota enforcement.
 *
 * Every metered request resolves an API key, rolls its monthly counter, and
 * rejects with 402/429 when the plan quota is exhausted. This is the mechanism
 * that turns the agent-facing surfaces (API/MCP/ACP) into a billable product.
 */

const { collection } = require("../core/store");
const { resolveApiKey, monthKey } = require("./licensing");
const { getPlan } = require("./plans");

const keys = () => collection("apiKeys");

function extractKey(req) {
  const auth = req.headers["authorization"] || "";
  if (auth.startsWith("Bearer ")) return auth.slice(7).trim();
  if (req.headers["x-api-key"]) return String(req.headers["x-api-key"]).trim();
  // URLs may enter logs, browser history and referrers. Accept credentials
  // only in headers; query parameters never authenticate a request.
  return null;
}

/** Roll the usage period if the month changed; returns the live row. */
function rollPeriod(row) {
  const now = monthKey();
  if (!row.usage || row.usage.periodStart !== now) {
    keys().update((k) => k.key === row.key, { usage: { count: 0, periodStart: now } });
    row.usage = { count: 0, periodStart: now };
  }
  return row;
}

function quotaFor(row) {
  return getPlan(row.plan).monthlyQuota;
}

/**
 * Express middleware factory.
 * @param {object} opts  { cost: number, require: boolean }
 *   cost     — how many units this endpoint consumes (default 1)
 *   require  — if true, reject anonymous requests (default true)
 */
function meter(opts = {}) {
  const cost = opts.cost == null ? 1 : opts.cost;
  const required = opts.require !== false;

  return (req, res, next) => {
    const key = extractKey(req);
    if (!key) {
      if (!required) { req.auth = { anonymous: true, plan: "free" }; return next(); }
      return res.status(401).json({ error: "missing_api_key", hint: "Send 'Authorization: Bearer <key>' — create one at /dashboard" });
    }
    const row = resolveApiKey(key);
    if (!row) return res.status(401).json({ error: "invalid_api_key" });

    rollPeriod(row);
    const quota = quotaFor(row);
    if (quota !== Infinity && row.usage.count + cost > quota) {
      return res.status(429).json({
        error: "quota_exceeded",
        plan: row.plan,
        used: row.usage.count,
        quota,
        hint: "Upgrade your plan at /pricing"
      });
    }

    // Charge the request.
    if (cost > 0) {
      const next_count = row.usage.count + cost;
      keys().update((k) => k.key === row.key, { usage: { count: next_count, periodStart: row.usage.periodStart } });
      row.usage.count = next_count;
    }

    req.auth = {
      key: row.key,
      ownerEmail: row.ownerEmail,
      plan: row.plan,
      usage: row.usage,
      quota: quota === Infinity ? "unlimited" : quota
    };
    res.setHeader("X-Foundry-Quota", String(quota === Infinity ? "unlimited" : quota));
    res.setHeader("X-Foundry-Usage", String(row.usage.count));
    next();
  };
}

/** Non-middleware variant for MCP/ACP handlers that authenticate manually. */
function chargeKey(key, cost = 1) {
  const row = resolveApiKey(key);
  if (!row) return { ok: false, error: "invalid_api_key", status: 401 };
  rollPeriod(row);
  const quota = quotaFor(row);
  if (quota !== Infinity && row.usage.count + cost > quota) {
    return { ok: false, error: "quota_exceeded", status: 429, plan: row.plan, used: row.usage.count, quota };
  }
  const next_count = row.usage.count + cost;
  keys().update((k) => k.key === row.key, { usage: { count: next_count, periodStart: row.usage.periodStart } });
  row.usage.count = next_count;
  return { ok: true, auth: { key: row.key, ownerEmail: row.ownerEmail, plan: row.plan, usage: row.usage, quota } };
}

module.exports = { meter, chargeKey, extractKey };
