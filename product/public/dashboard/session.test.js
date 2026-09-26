"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const source = fs.readFileSync(require.resolve("./session.js"), "utf8");
function page(storage) {
  const context = vm.createContext({ localStorage: storage });
  vm.runInContext(source + "\nglobalThis.result = session;", context);
  return context.result;
}
test("credentials are memory-only, old storage is removed and reload signs out", () => {
  const stored = new Map([["foundry_key", "old-key"], ["foundry_email", "old-email"], ["unrelated", "keep"]]);
  const storage = { removeItem: (key) => stored.delete(key), setItem: () => assert.fail("persistent write") };
  const session = page(storage);
  assert.equal(stored.size, 1);
  assert.equal(stored.get("unrelated"), "keep");
  assert.equal(session.key, "");
  assert.equal(session.generation, 0);
  session.set("test-key", "person@example.test");
  assert.equal(session.key, "test-key");
  assert.equal(session.email, "person@example.test");
  assert.equal(session.generation, 1);
  assert.equal(page(storage).key, "");
  session.clear();
  assert.equal(session.key, "");
  assert.equal(session.email, "");
  assert.equal(session.generation, 2);
});
test("session generations invalidate pending same-account responses", () => {
  const session = page({ removeItem() {} });
  session.set("old-key", "person@example.test");
  const pendingGeneration = session.generation;
  session.clear();
  session.set("new-key", "person@example.test");
  assert.equal(session.email, "person@example.test");
  assert.notEqual(session.generation, pendingGeneration);
});
test("disabled browser storage does not prevent an in-memory session", () => {
  const session = page({ removeItem() { throw new Error("storage denied"); } });
  session.set("test-key", "person@example.test");
  assert.equal(session.key, "test-key");
});
