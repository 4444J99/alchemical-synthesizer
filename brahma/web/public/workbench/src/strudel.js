// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 4444J99
/**
 * strudel.js — Brahma output driver for Strudel's scheduler.
 *
 * Strudel's own WebAudio output is deliberately not used. `repl({ defaultOutput })`
 * hands this module every scheduled hap, and it routes each one to the gateway as a
 * Brahma `event` frame. Strudel supplies the pattern language and the clock; Brahma
 * supplies the sound.
 */

import { evalScope, repl } from "@strudel/core";
import { transpiler } from "@strudel/transpiler";
import { miniAllStrings } from "@strudel/mini";
import { DEFAULT_ENGINE, toEvent } from "./event-map.mjs";

const MAX_PENDING = 512;

// Strudel evaluates user code against a global scope. The host has to populate it,
// otherwise `note(...)` is undefined at evaluation time. `repl.evaluate` injects only
// its own helpers (all/each/hush/setCps), so the pattern language is added here.
const scopeReady = evalScope(evalScope, import("@strudel/core"), import("@strudel/mini"));

/**
 * @param {object} opts
 * @param {(frame: object) => void} opts.send        gateway frame sink
 * @param {(err: Error) => void} [opts.onError]      evaluation and scheduler errors
 * @param {(state: object) => void} [opts.onState]   started/cps changes
 * @param {() => number} [opts.now]                  seconds clock (tests)
 * @param {(fn: Function, ms: number) => any} [opts.schedule] timer (tests)
 */
export function createStrudel({ send, onError, onState, now, schedule } = {}) {
  const clock = now || (() => performance.now() / 1000);
  const setTimer = schedule || ((fn, ms) => setTimeout(fn, ms));

  const pending = new Set();
  const knownEngines = new Set();

  let currentEngine = DEFAULT_ENGINE;
  let patternId = "pattern";

  function clearPending() {
    for (const t of pending) clearTimeout(t);
    pending.clear();
  }

  /**
   * Sends at the scheduler's deadline. Strudel's `deadline` is already a relative
   * offset in seconds and `duration` is already in seconds — passing them through
   * unchanged is the whole timing contract.
   */
  function defaultOutput(hap, deadline, duration) {
    try {
      const frame = toEvent(hap.value, {
        duration,
        id: patternId,
        engine: currentEngine,
        knownEngines
      });
      if (!frame) return;

      if (pending.size >= MAX_PENDING) return; // a stuck pattern cannot grow unbounded

      const delaySecs = typeof deadline === "number" && Number.isFinite(deadline) ? deadline : 0;
      const delayMs = Math.max(0, Math.round(delaySecs * 1000));
      const timer = setTimer(() => {
        pending.delete(timer);
        send(frame);
      }, delayMs);
      pending.add(timer);
    } catch (err) {
      onError?.(err);
    }
  }

  miniAllStrings();

  const instance = repl({
    defaultOutput,
    getTime: clock,
    transpiler,
    onEvalError: (err) => onError?.(err),
    onToggle: (started) => {
      if (!started) clearPending();
      onState?.({ started });
    }
  });

  return {
    /** Evaluate Strudel source and start it. Resolves to the pattern, or undefined on error. */
    async evaluate(code, { id = "pattern", engine = DEFAULT_ENGINE } = {}) {
      await scopeReady;
      patternId = id;
      currentEngine = engine;
      return instance.evaluate(code, true);
    },
    stop() {
      clearPending();
      try { instance.stop(); } catch (_) { /* already stopped */ }
    },
    setKnownEngines(names) {
      knownEngines.clear();
      for (const n of names || []) knownEngines.add(String(n));
    },
    setCps(cps) {
      try { instance.setCps(cps); } catch (_) { /* invalid cps is ignored */ }
    },
    get cps() {
      return instance.scheduler.cps;
    },
    _pending: pending
  };
}
