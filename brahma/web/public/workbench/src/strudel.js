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
import { parse } from "acorn";
import escodegen from "escodegen";
import { walk } from "estree-walker";
import { DEFAULT_ENGINE, toEvent } from "./event-map.mjs";

const MAX_PENDING = 512;
// Strudel installs these helpers globally for each repl. Capture their current
// closures before user code can await, so a cancelled continuation retains its
// own scheduler/transform state. Explicit globalThis mutations are not isolated.
const REPL_HELPERS = "all,each,hush,cpm,setCps,setcps,setCpm,setcpm,compileKabel";

function scopedTranspiler(code, options) {
  const compiled = transpiler(code, options);
  const methods = ["p", "cpm"];
  const ast = parse(compiled.output, { ecmaVersion: 2022, allowAwaitOutsideFunction: true, allowReturnOutsideFunction: true });
  walk(ast, { leave(node) {
    const member = node.type === "CallExpression" && node.callee;
    if (!member || node.optional || member.type !== "MemberExpression" || member.optional || member.object.type === "Super") return;
    const name = member.computed ? member.property.value : member.property.name;
    if (!methods.includes(name)) return;
    // Strudel turns labels into pattern.p(label), and replaces that prototype
    // method for every repl. Bind the callee to this evaluation before any await.
    node.callee = { type: "CallExpression", optional: false,
      callee: { type: "Identifier", name: "__brahmaPatternMethod" },
      arguments: [member.object, { type: "Literal", value: name }] };
  } });
  const output = escodegen.generate(ast);
  return { ...compiled, output: `return (({${REPL_HELPERS}}, Pattern) => {
    const ownedMethods = { p: Pattern.prototype.p, cpm: Pattern.prototype.cpm };
    const __brahmaPatternMethod = (target, name) => {
      const method = target instanceof Pattern ? ownedMethods[name] : target[name];
      return typeof method === "function" ? method.bind(target) : method;
    };
    return (async () => {${output}})();
  })(globalThis, globalThis.Pattern);` };
}

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

  let active = null;
  let savedCps = 0.5;
  let generation = 0;

  function clearPending() {
    for (const t of pending) clearTimeout(t);
    pending.clear();
  }

  /**
   * Sends at the scheduler's deadline. Strudel's `deadline` is already a relative
   * offset in seconds and `duration` is already in seconds — passing them through
   * unchanged is the whole timing contract.
   */
  function defaultOutput(owner, hap, deadline, duration) {
    if (owner.generation !== generation) return;
    try {
      const frame = toEvent(hap.value, {
        duration,
        id: owner.id,
        engine: owner.engine,
        knownEngines
      });
      if (!frame) return;

      if (pending.size >= MAX_PENDING) return; // a stuck pattern cannot grow unbounded

      const delaySecs = typeof deadline === "number" && Number.isFinite(deadline) ? deadline : 0;
      const delayMs = Math.max(0, Math.round(delaySecs * 1000));
      const scheduledGeneration = generation;
      const timer = setTimer(() => {
        pending.delete(timer);
        if (scheduledGeneration === generation) send(frame);
      }, delayMs);
      pending.add(timer);
    } catch (err) {
      onError?.(err);
    }
  }

  miniAllStrings();

  return {
    /** Evaluate Strudel source and start it. Resolves to the pattern, or undefined on error. */
    async evaluate(code, { id = "pattern", engine = DEFAULT_ENGINE } = {}) {
      const requestedGeneration = ++generation;
      clearPending();
      const previous = active;
      active = null;
      try { previous?.instance.stop(); } catch (_) { /* already stopped */ }
      await scopeReady;
      if (requestedGeneration !== generation) return;
      // An abandoned top-level await cannot be forcibly cancelled in this
      // context. Give each evaluation its own scheduler and only start it once
      // evaluation completes while it still owns the current generation.
      const owner = { generation: requestedGeneration, id, engine, instance: null };
      const instance = repl({
        defaultOutput: (hap, deadline, duration) => defaultOutput(owner, hap, deadline, duration),
        getTime: clock,
        transpiler: scopedTranspiler,
        onEvalError: (err) => { if (owner.generation === generation) onError?.(err); },
        onToggle: (started) => {
          if (owner.generation !== generation) return;
          if (!started) clearPending();
          onState?.({ started });
        }
      });
      owner.instance = instance;
      active = owner;
      instance.setCps(savedCps);
      const result = await instance.evaluate(code, false);
      if (requestedGeneration === generation && result) await instance.start();
      if (requestedGeneration !== generation) instance.stop();
      return result;
    },
    stop() {
      generation += 1;
      clearPending();
      const previous = active;
      active = null;
      try { previous?.instance.stop(); } catch (_) { /* already stopped */ }
    },
    setKnownEngines(names) {
      knownEngines.clear();
      for (const n of names || []) knownEngines.add(String(n));
    },
    setCps(cps) {
      if (!Number.isFinite(cps) || cps <= 0) return;
      savedCps = cps;
      try { active?.instance.setCps(cps); } catch (_) { /* invalid cps is ignored */ }
    },
    get cps() {
      return active?.instance.scheduler.cps ?? savedCps;
    },
    _pending: pending
  };
}
