"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function renderer() {
  const calls = [];
  let translation = [0, 0];
  const stack = [];
  const node = { key: "seat", name: "Seat", hebrew: "", color: [10, 20, 30], x: 0.5 };
  const ctx = {
    Math, width: 320, height: 480, TWO_PI: Math.PI * 2, HALF_PI: Math.PI / 2,
    CENTER: "center", CLOSE: "close", cos: Math.cos, sin: Math.sin,
    millis: () => 0, noise: () => 0.5,
    constrain: (v, lo, hi) => Math.max(lo, Math.min(hi, v)),
    lerp: (a, b, t) => a + (b - a) * t,
    map: (v, a, b, c, d) => c + (v - a) / (b - a) * (d - c),
    dist: (a, b, c, d) => Math.hypot(a - c, b - d),
    COSMOS: { SEPHIROT: [node], PATHS: [], LIGHTNING: ["seat"], nodePos: () => ({ x: 160, y: 160 }) },
    Substrates: { seatFor: () => "seat", colorFor: () => [10, 20, 30] },
    drawingContext: { save() {}, restore() {}, setLineDash() {} },
    push: () => stack.push([...translation]), pop: () => { translation = stack.pop(); },
    translate: (x, y) => { translation = [translation[0] + x, translation[1] + y]; },
    rect: (x, y, w, h) => calls.push({ kind: "rect", x: x + translation[0], y: y + translation[1], w, h }),
    text: (value) => calls.push({ kind: "text", value: String(value) })
  };
  for (const key of ["stroke", "strokeWeight", "line", "noStroke", "fill", "circle", "textAlign", "textSize", "noFill", "beginShape", "vertex", "endShape"]) ctx[key] = () => {};
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(__dirname, "../public/tree/tree-renderer.js"), "utf8") + "\nthis.tree = Tree;", ctx);
  const box = { cx: 160, top: 20, treeW: 300, treeH: 400 };
  const settings = { maxDepth: 0, recursionBudget: 0 };
  return { tree: ctx.tree, calls, draw: () => ctx.tree.render(box, 0, 255, settings), update: (rows) => ctx.tree.update(rows, 0.016, settings) };
}

test("tree: selecting an empty vessel does not crash the next draw", () => {
  const r = renderer(); r.update({}); r.draw();
  assert.ok(r.tree.pick(160, 160), "empty vessels remain pickable for the inspector");
  assert.doesNotThrow(r.draw);
});

test("tree: selected traits follow current organism state and disappear when it expires", () => {
  const r = renderer();
  r.update({ one: { type: "Before", coherence: 0.5, entropy: 2 } }); r.draw(); r.tree.pick(160, 160);
  r.update({ one: { type: "After", coherence: 0.7, entropy: 1 } });
  r.calls.length = 0; r.draw();
  assert.ok(r.calls.some((c) => c.kind === "text" && /TRAIT.*After/i.test(c.value)));
  r.update({}); r.calls.length = 0; r.draw();
  assert.equal(r.calls.some((c) => c.kind === "rect"), false);
});

test("tree: trait panel fits a narrow viewport and identifies derived proxies", () => {
  const r = renderer();
  r.update({ one: { type: "Test", coherence: 0.7, entropy: 1 } }); r.draw(); r.tree.pick(160, 160);
  r.calls.length = 0; r.draw();
  const panel = r.calls.find((c) => c.kind === "rect");
  assert.ok(panel && panel.x >= 0 && panel.x + panel.w <= 320 && panel.y >= 0 && panel.y + panel.h <= 480);
  assert.ok(r.calls.some((c) => c.kind === "text" && /proxy/i.test(c.value)));
});

test("tree: incomplete captured trait maps are not filled with invented midpoint values", () => {
  const r = renderer();
  r.update({ one: { type: "Test", coherence: 0.7, entropy: 1, traitMap: { spectral_profile: 0.3 } } });
  r.draw(); r.tree.pick(160, 160); r.calls.length = 0; r.draw();
  assert.ok(r.calls.some((c) => c.kind === "text" && /incomplete/i.test(c.value)));
});
