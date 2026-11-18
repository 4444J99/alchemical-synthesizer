"use strict";
/**
 * store.js — Minimal file-backed persistence.
 *
 * Deliberately dependency-free: the Foundry must run on a bare Node install
 * with no external database. Collections are plain arrays/objects persisted to
 * a single JSON file, written atomically. For real scale this is swapped for a
 * proper DB behind the same interface — see product/README.md (praxis).
 */

const fs = require("fs");
const path = require("path");

const DATA_DIR = process.env.FOUNDRY_DATA_DIR || path.join(__dirname, "..", "..", "data");
const DB_PATH = path.join(DATA_DIR, "store.json");

const EMPTY = {
  users: [],        // { id, email, passwordHash, salt, plan, createdAt }
  apiKeys: [],      // { key, ownerEmail, plan, label, status, createdAt, usage:{count, periodStart} }
  specimens: [],    // { id, title, creator, priceCents, sourceModule, traitMap, audioUrl, forSale, simulated, renderState, renderId, createdAt }
                    // renderState: unavailable | pending | failed | complete (issue #96); audioUrl is set only on complete
  orders: [],       // { id, email, items, amountCents, status, provider, sessionId, createdAt }
  waitlist: [],     // { email, interest, createdAt }
  events: []        // { ts, type, ref } — lightweight audit trail
};

let cache = null;
let writeTimer = null;

function ensureDir() {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
}

function load() {
  if (cache) return cache;
  ensureDir();
  try {
    if (fs.existsSync(DB_PATH)) {
      cache = Object.assign({}, EMPTY, JSON.parse(fs.readFileSync(DB_PATH, "utf8")));
    } else {
      cache = JSON.parse(JSON.stringify(EMPTY));
    }
  } catch (e) {
    console.error("[store] corrupt store, starting fresh:", e.message);
    cache = JSON.parse(JSON.stringify(EMPTY));
  }
  // Guarantee every collection exists even if the file predates a new one.
  for (const k of Object.keys(EMPTY)) if (!cache[k]) cache[k] = JSON.parse(JSON.stringify(EMPTY[k]));
  return cache;
}

/** Atomic, debounced flush to disk. */
function persist() {
  if (writeTimer) return;
  writeTimer = setTimeout(() => {
    writeTimer = null;
    try {
      ensureDir();
      const tmp = DB_PATH + ".tmp";
      fs.writeFileSync(tmp, JSON.stringify(cache, null, 2));
      fs.renameSync(tmp, DB_PATH);
    } catch (e) {
      console.error("[store] write failed:", e.message);
    }
  }, 50);
}

function flushSync() {
  if (writeTimer) { clearTimeout(writeTimer); writeTimer = null; }
  try {
    ensureDir();
    fs.writeFileSync(DB_PATH, JSON.stringify(load(), null, 2));
  } catch (e) { /* best effort */ }
}

/** A thin collection accessor. */
function collection(name) {
  const db = load();
  if (!db[name]) db[name] = [];
  return {
    all: () => db[name],
    find: (pred) => db[name].find(pred),
    filter: (pred) => db[name].filter(pred),
    insert: (row) => { db[name].push(row); persist(); return row; },
    update: (pred, patch) => {
      const row = db[name].find(pred);
      if (row) { Object.assign(row, patch); persist(); }
      return row;
    },
    remove: (pred) => {
      const i = db[name].findIndex(pred);
      if (i >= 0) { const [r] = db[name].splice(i, 1); persist(); return r; }
      return null;
    }
  };
}

function logEvent(type, ref) {
  const db = load();
  db.events.push({ ts: new Date().toISOString(), type, ref });
  if (db.events.length > 5000) db.events.splice(0, db.events.length - 5000);
  persist();
}

// Persist on exit so nothing is lost.
process.on("SIGINT", () => { flushSync(); process.exit(0); });
process.on("SIGTERM", () => { flushSync(); process.exit(0); });

module.exports = { collection, logEvent, flushSync, DB_PATH, DATA_DIR };
