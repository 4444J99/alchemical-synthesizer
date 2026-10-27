"use strict";
/**
 * marketplace.js — Specimen marketplace.
 *
 * Specimens (rendered audio artifacts, the NRT output of the engine) can be
 * listed for sale by creators on paid plans. Buyers purchase via the billing
 * layer; creators receive an 85% payout (tracked, paid out by the billing
 * provider in production).
 */

const { collection, logEvent } = require("../core/store");
const { getPlan } = require("../auth/plans");

const specimens = () => collection("specimens");
const PAYOUT_RATE = 0.85;

function listForSale(filter = {}) {
  let out = specimens().filter((s) => s.forSale && !s.simulated && s.audioUrl && s.ownerEmail);
  if (filter.creator) out = out.filter((s) => s.creator === filter.creator);
  if (filter.module) out = out.filter((s) => s.sourceModule === filter.module);
  return out.sort((a, b) => (b.createdAt > a.createdAt ? 1 : -1)).map(publicSpecimen);
}

function publicSpecimen(specimen) {
  const { ownerEmail, ...publicFields } = specimen;
  return publicFields;
}

function getSpecimen(id) {
  return specimens().find((s) => s.id === id) || null;
}

function ownedSpecimen(id, ownerEmail) {
  const specimen = getSpecimen(id);
  if (!specimen) throw new Error("specimen not found");
  if (typeof ownerEmail !== "string" || typeof specimen.ownerEmail !== "string" ||
      !specimen.ownerEmail || specimen.ownerEmail.toLowerCase() !== ownerEmail.toLowerCase()) {
    throw Object.assign(new Error("specimen is not owned by this account"), { code: "not_owned" });
  }
  return specimen;
}

/** List a specimen for sale — requires a plan that `canSell`. */
function listSpecimen({ specimenId, ownerEmail, ownerPlan, priceCents }) {
  const spc = ownedSpecimen(specimenId, ownerEmail);
  const plan = getPlan(ownerPlan);
  if (!plan.canSell) {
    const err = new Error("your plan cannot sell specimens — upgrade to Alchemist");
    err.code = "plan_forbidden";
    throw err;
  }
  if (spc.simulated || !spc.audioUrl) throw new Error("specimen has no completed audio artifact");
  if (!Number.isSafeInteger(priceCents) || priceCents <= 0) throw new Error("priceCents must be a positive integer");
  specimens().update((s) => s.id === specimenId, {
    forSale: true, priceCents, listedAt: new Date().toISOString()
  });
  logEvent("specimen.listed", `${specimenId}:${priceCents}`);
  return getSpecimen(specimenId);
}

function unlist(specimenId, ownerEmail) {
  ownedSpecimen(specimenId, ownerEmail);
  specimens().update((s) => s.id === specimenId, { forSale: false });
  return getSpecimen(specimenId);
}

/** Compute a payout split for a sale. */
function payoutSplit(priceCents) {
  const creator = Math.round(priceCents * PAYOUT_RATE);
  return { creatorCents: creator, platformCents: priceCents - creator, rate: PAYOUT_RATE };
}

module.exports = { listForSale, getSpecimen, publicSpecimen, listSpecimen, unlist, payoutSplit, PAYOUT_RATE };
