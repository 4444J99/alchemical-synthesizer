"use strict";
/**
 * ratelimit.js — token-bucket limiter for browser → engine control traffic.
 *
 * The browser is untrusted. A stuck Strudel pattern, a runaway loop or a hostile
 * page can emit events far faster than any musical use requires. This limiter
 * bounds that without disconnecting the client: excess frames are dropped and
 * reported, and the connection stays usable.
 */

/**
 * @param {object} opts
 * @param {number} [opts.ratePerSec] sustained refill rate
 * @param {number} [opts.burst]      bucket capacity
 * @param {() => number} [opts.now]  injectable clock (tests)
 */
function createTokenBucket({ ratePerSec = 200, burst = 400, now = () => Date.now() } = {}) {
  if (!(ratePerSec > 0)) throw new Error("ratePerSec must be > 0");
  if (!(burst > 0)) throw new Error("burst must be > 0");

  let tokens = burst;
  let last = now();

  /**
   * Take one or more tokens.
   * @returns {{ok: true} | {ok: false, retryAfterMs: number}}
   */
  function take(n = 1) {
    const t = now();
    const elapsedSec = Math.max(0, t - last) / 1000;
    last = t;
    tokens = Math.min(burst, tokens + elapsedSec * ratePerSec);
    if (tokens < n) {
      return { ok: false, retryAfterMs: Math.ceil(((n - tokens) / ratePerSec) * 1000) };
    }
    tokens -= n;
    return { ok: true };
  }

  function state() {
    return { tokens: Math.floor(tokens), burst, ratePerSec };
  }

  return { take, state };
}

module.exports = { createTokenBucket };
