"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { once } = require("node:events");
const { setTimeout: delay } = require("node:timers/promises");
const Stripe = require("stripe");
const signingSecret = "whsec_" + "local_fixture_only";
const product = path.resolve(__dirname, "../..");

async function fixture(t, env = {}, { legacyOrder = false } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "foundry-billing-"));
  const order = { id: "ord_fixture", email: "buyer@example.test", kind: "plan", amountCents: 900,
    currency: "usd", meta: { plan: "creator" }, provider: "stripe", sessionId: "cs_fixture",
    confirmToken: "local-confirm-fixture", status: "pending" };
  if (legacyOrder) delete order.currency;
  fs.writeFileSync(path.join(dir, "store.json"), JSON.stringify({ orders: [order],
    users: [{ email: order.email, plan: "free" }], events: [] }));
  const child = spawn(process.execPath, ["-e", "const {server}=require('./server');server.once('listening',()=>console.log('TEST_PORT='+server.address().port));"], {
    cwd: product,
    env: { ...process.env, PORT: "0", OSC_RECV_PORT: "0", FOUNDRY_DATA_DIR: dir,
      STRIPE_SECRET_KEY: "", STRIPE_WEBHOOK_SECRET: "", FOUNDRY_ALLOW_STUB_BILLING: "", ...env },
    stdio: ["ignore", "pipe", "pipe"]
  });
  let output = "";
  child.stdout.on("data", (d) => { output += d; });
  child.stderr.on("data", (d) => { output += d; });
  t.after(async () => {
    if (child.exitCode === null) { const ended = once(child, "exit"); child.kill("SIGTERM"); await ended; }
    fs.rmSync(dir, { recursive: true, force: true });
  });
  for (let i = 0; i < 100 && !/TEST_PORT=(\d+)/.test(output); i++) {
    if (child.exitCode !== null) throw new Error("billing fixture failed to start: " + output);
    await delay(25);
  }
  const match = output.match(/TEST_PORT=(\d+)/);
  assert.ok(match, "billing fixture did not start");
  const base = `http://127.0.0.1:${match[1]}/api/v1`;
  const post = (route, body, headers = {}) => fetch(base + route, {
    method: "POST", headers: { "content-type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body)
  });
  const stored = async () => { await delay(80); return JSON.parse(fs.readFileSync(path.join(dir, "store.json"), "utf8")); };
  return { base, post, stored, order, child };
}

function event(patch = {}) {
  return { id: "evt_fixture", type: "checkout.session.completed", data: { object: {
    id: "cs_fixture", metadata: { orderId: "ord_fixture" }, payment_status: "paid", amount_total: 900,
    currency: "usd", ...patch
  } } };
}
function signed(body, timestamp) {
  return { "stripe-signature": Stripe.webhooks.generateTestHeaderString({ payload: body, secret: signingSecret, timestamp }) }; // allow-secret: synthetic test signature
}

test("billing: raw Stripe events require valid signatures and matching paid order data", { timeout: 15000 }, async (t) => {
  const f = await fixture(t, { STRIPE_SECRET_KEY: "sk_test_" + "local_fixture_only", STRIPE_WEBHOOK_SECRET: signingSecret,
    FOUNDRY_ALLOW_STUB_BILLING: "1" });
  let res = await f.post("/billing/webhook/stripe", event());
  assert.equal(res.status, 400); await res.text();
  const raw = JSON.stringify(event());
  res = await f.post("/billing/webhook/stripe", raw, { "stripe-signature": "invalid" });
  assert.equal(res.status, 400); await res.text();
  res = await f.post("/billing/webhook/stripe", raw + " ", signed(raw));
  assert.equal(res.status, 400, "signature covers the untouched raw bytes"); await res.text();
  res = await f.post("/billing/webhook/stripe", raw, signed(raw, 1));
  assert.equal(res.status, 400, "old signatures cannot be replayed outside tolerance"); await res.text();
  for (const patch of [{ id: "cs_other" }, { payment_status: "unpaid" }, { amount_total: 1 }, { currency: "eur" }]) {
    const body = JSON.stringify(event(patch));
    res = await f.post("/billing/webhook/stripe", body, signed(body));
    assert.equal(res.status, 400); await res.text();
    assert.equal((await f.stored()).orders[0].status, "pending");
  }
  res = await f.post("/billing/webhook", event());
  assert.equal(res.status, 410); await res.text();
  res = await fetch(f.base + "/billing/confirm?order=ord_fixture&token=local-confirm-fixture"); // allow-secret: synthetic local fixture
  assert.equal(res.status, 403); await res.text();
  for (let replay = 0; replay < 2; replay++) {
    res = await f.post("/billing/webhook/stripe", raw, signed(raw));
    assert.equal(res.status, 200); await res.text();
  }
  const db = await f.stored();
  assert.equal(db.orders[0].status, "paid");
  assert.equal(db.users[0].plan, "creator");
  assert.equal(db.events.filter((e) => e.type === "order.fulfilled").length, 1);
  assert.equal(f.child.exitCode, null);
});

test("billing: unconfigured billing does not create orders or accept callbacks", async (t) => {
  const f = await fixture(t);
  let res = await f.post("/billing/webhook/stripe", event());
  assert.equal(res.status, 503); await res.text();
  res = await f.post("/billing/checkout/plan", { email: "buyer@example.test", plan: "creator" });
  assert.equal(res.status, 503); await res.text();
  assert.equal((await f.stored()).orders.length, 1);
});

test("billing: pre-upgrade USD orders require the same verified payment and gain explicit currency", async (t) => {
  const f = await fixture(t, { STRIPE_SECRET_KEY: "sk_test_" + "local_fixture_only", STRIPE_WEBHOOK_SECRET: signingSecret }, { legacyOrder: true });
  const wrong = JSON.stringify(event({ currency: "eur" }));
  assert.equal((await f.post("/billing/webhook/stripe", wrong, signed(wrong))).status, 400);
  assert.equal((await f.stored()).orders[0].status, "pending");
  const valid = JSON.stringify(event());
  assert.equal((await f.post("/billing/webhook/stripe", valid, signed(valid))).status, 200);
  const stored = await f.stored();
  assert.equal(stored.orders[0].currency, "usd");
  assert.equal(stored.orders[0].status, "paid");
  assert.equal(stored.users[0].plan, "creator");
});

test("billing: explicit local stub mode confirms only its own stub orders", async (t) => {
  const f = await fixture(t, { FOUNDRY_ALLOW_STUB_BILLING: "1" });
  let res = await fetch(f.base + "/billing/confirm?order=ord_fixture&token=local-confirm-fixture"); // allow-secret: synthetic local fixture
  assert.equal(res.status, 403); await res.text();
  res = await f.post("/billing/checkout/plan", { email: "buyer@example.test", plan: "creator" });
  assert.equal(res.status, 200);
  const checkout = (await res.json()).data;
  assert.equal(checkout.provider, "stub");
  const confirmed = await fetch(checkout.checkoutUrl);
  assert.equal(confirmed.status, 200); await confirmed.text();
  const db = await f.stored();
  assert.equal(db.orders.find((o) => o.id === checkout.orderId).status, "paid");
  assert.equal(db.orders[0].status, "pending");
});
