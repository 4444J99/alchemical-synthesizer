"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

test("listener initializes, polls lineage, and renders submitted text without HTML", async () => {
  const elements = new Map();
  const htmlWrites = [];
  const fetches = [];
  function element() {
    return {
      textContent: "", style: {}, children: [], className: "", classList: { toggle() {} },
      get childElementCount() { return this.children.length; },
      set innerHTML(text) { htmlWrites.push(text); this.children = []; },
      appendChild(node) { this.children.push(node); },
      append(...nodes) { this.children.push(...nodes); },
      replaceChildren(...nodes) { this.children = nodes; },
      addEventListener() {}, canPlayType() { return "probably"; }
    };
  }
  const source = "https://x/<svg onload=alert(1)>";
  const creature = "<img src=x onerror=alert(1)>";
  const context = {
    document: {
      getElementById(id) { if (!elements.has(id)) elements.set(id, element()); return elements.get(id); },
      createElement: element, createTextNode(text) { return { textContent: text }; }
    },
    window: {}, setInterval() {}, setTimeout() {},
    fetch: async (url) => {
      fetches.push(url);
      return { ok: true, json: async () => url.endsWith("lineage.json")
        ? { entries: [{ source, creature }] }
        : { now: { phase: "readable", creature, epoch: 0, segment: 0 }, recent: [{ creature, phase: "readable" }] } };
    }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "aether.js"), "utf8"), context);
  await new Promise(setImmediate);
  assert.ok(fetches.includes("/live/lineage.json"));
  assert.equal(elements.get("audio").src, "/live/stream.m3u8");
  assert.ok(!htmlWrites.some((html) => /<svg|<img/.test(html)), "untrusted lineage reached innerHTML");
  const text = (node) => (node.textContent || "") + (node.children || []).map(text).join("");
  assert.match(text(elements.get("chain")), /<img/);
});
