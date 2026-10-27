"use strict";
/**
 * seed.js — Populate the store with demo data so the dashboard and marketplace
 * are alive on first boot. Idempotent-ish: safe to run repeatedly.
 *
 *   node bin/seed.js
 */

const licensing = require("../src/auth/licensing");
const engine = require("../src/core/engine");
const marketplace = require("../src/marketplace/marketplace");
const { collection, flushSync } = require("../src/core/store");

function ensureUser(email, password, plan) {
  try {
    const r = licensing.createUser({ email, password, plan });
    if (plan && plan !== "free") licensing.setPlan(email, plan);
    console.log(`  user ${email} (${plan})  apiKey=${r.apiKey}`);
    return r;
  } catch (e) {
    console.log(`  user ${email} exists — skipping`);
    return null;
  }
}

function main() {
  if (process.env.NODE_ENV === "production") throw new Error("Demo accounts must not be seeded in production");
  console.log("Seeding Brahma Foundry…");

  ensureUser("demo@brahma.studio", "transmute-me", "creator");
  ensureUser("pro@brahma.studio", "transmute-me", "pro");

  // Render a handful of specimens and list some for sale.
  const modules = ["Azoth", "Nebula", "Relinquished", "Buchlaeus", "Quintessence"];
  let i = 0;
  for (const m of modules) {
    const spc = engine.renderSpecimen({ module: m, title: `${m} — demo specimen`, creator: "demo@brahma.studio" }, { ownerEmail: "demo@brahma.studio" });
    if (!spc.simulated && i++ % 2 === 0) {
      marketplace.listSpecimen({ specimenId: spc.id, ownerEmail: "demo@brahma.studio", ownerPlan: "creator", priceCents: 300 + i * 100 });
    }
  }
  console.log("  Simulated specimens remain unlisted until real audio artifacts exist.");

  // A couple of waitlist entries.
  const wl = collection("waitlist");
  for (const e of ["early@adopter.io", "curious@modular.fm"]) {
    if (!wl.find((w) => w.email === e)) wl.insert({ email: e, interest: "demo", createdAt: new Date().toISOString() });
  }

  flushSync();
  console.log("Seed complete.");
  process.exit(0);
}

main();
