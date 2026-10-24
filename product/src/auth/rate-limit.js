"use strict";

/** Process-local admission before expensive handlers. Peer addresses come from
 * the socket, never caller-controlled forwarding headers. A proxy therefore
 * shares a budget until its identity is explicitly configured at deployment. */
function rateLimit({ limit, windowMs = 60000, maxPeers = 10000, now = Date.now }) {
  if (![limit, windowMs, maxPeers].every((n) => Number.isSafeInteger(n) && n > 0)) {
    throw new TypeError("rate limits must be positive safe integers");
  }
  const peers = new Map();
  let nextSweep = 0;
  const sweep = (time) => {
    let soonestReset = time + windowMs;
    for (const [key, value] of peers) {
      if (value.reset <= time) peers.delete(key);
      else soonestReset = Math.min(soonestReset, value.reset);
    }
    nextSweep = soonestReset;
  };
  return (req, res, next) => {
    const time = now();
    if (time >= nextSweep) sweep(time);
    const peer = req.socket.remoteAddress || "unknown";
    let budget = peers.get(peer);
    if (budget && budget.reset <= time) { peers.delete(peer); budget = undefined; }
    const reject = (wait) => {
      res.setHeader("Retry-After", String(Math.max(1, Math.ceil(wait / 1000))));
      return res.status(429).json({ ok: false, error: "rate_limit_exceeded" });
    };
    if (!budget) {
      // Do not evict live budgets: rotating identities must not reset a limit.
      if (peers.size >= maxPeers) sweep(time);
      if (peers.size >= maxPeers) return reject(nextSweep - time);
      budget = { count: 0, reset: time + windowMs };
      peers.set(peer, budget);
    }
    if (budget.count >= limit) return reject(budget.reset - time);
    budget.count++;
    return next();
  };
}
module.exports = { rateLimit };
