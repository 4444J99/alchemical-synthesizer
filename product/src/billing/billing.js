"use strict";
/**
 * billing.js — Checkout & orders. Stripe-optional.
 *
 * Real checkout requires the Stripe SDK, API key and webhook signing secret.
 * Local demonstration checkout is a separate, explicit opt-in and is disabled
 * in production. A verified paid session must match its persisted order.
 */

const crypto = require("crypto");
const { collection, logEvent } = require("../core/store");
const { getPlan, PLANS } = require("../auth/plans");
const { setPlan } = require("../auth/licensing");
const { payoutSplit, getSpecimen } = require("../marketplace/marketplace");

const orders = () => collection("orders");

let stripe = null;
let stripeReady = false;
const apiKey = String(process.env.STRIPE_SECRET_KEY || "").trim();
const webhookSecret = String(process.env.STRIPE_WEBHOOK_SECRET || "").trim();
const stubEnabled = !apiKey && process.env.FOUNDRY_ALLOW_STUB_BILLING === "1" && process.env.NODE_ENV !== "production";
(function initStripe() {
  if (!apiKey) return;
  try {
    stripe = require("stripe")(apiKey);
    stripeReady = Boolean(webhookSecret);
    console.log(stripeReady ? "[billing] Stripe configured" : "[billing] Checkout disabled: webhook secret missing");
  } catch (e) {
    console.warn("[billing] Checkout disabled: Stripe SDK unavailable");
  }
})();

function billingError(message, status = 400) {
  return Object.assign(new Error(message), { status });
}

function requireCheckout() {
  if (!stripeReady && !stubEnabled) throw billingError("billing_unavailable", 503);
}

function baseUrl(req) {
  if (process.env.PUBLIC_URL) return process.env.PUBLIC_URL.replace(/\/$/, "");
  const proto = req.headers["x-forwarded-proto"] || req.protocol || "http";
  return `${proto}://${req.headers.host}`;
}

/** Create a checkout for a plan upgrade. */
async function checkoutPlan({ email, plan, req }) {
  const target = getPlan(plan);
  if (!target || target.id === "free") throw new Error("choose a paid plan");
  if (target.contactSales) return { contactSales: true, plan: target.id };
  requireCheckout();

  const order = baseOrder({ email, kind: "plan", amountCents: target.priceCents, meta: { plan: target.id } });

  if (stripeReady) {
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer_email: email,
      line_items: [{ price_data: {
        currency: "usd",
        recurring: { interval: "month" },
        product_data: { name: `Brahma — ${target.name}` },
        unit_amount: target.priceCents
      }, quantity: 1 }],
      success_url: `${baseUrl(req)}/dashboard?checkout=success&order=${order.id}`,
      cancel_url: `${baseUrl(req)}/pricing?checkout=cancel`,
      metadata: { orderId: order.id, plan: target.id, email }
    });
    orders().update((o) => o.id === order.id, { provider: "stripe", sessionId: session.id });
    return { checkoutUrl: session.url, orderId: order.id, provider: "stripe" };
  }

  // Stub: a local confirm URL that simulates a completed payment.
  const confirmUrl = `${baseUrl(req)}/api/v1/billing/confirm?order=${order.id}&token=${order.confirmToken}`;
  return { checkoutUrl: confirmUrl, orderId: order.id, provider: "stub", stub: true };
}

/** Create a checkout to buy a marketplace specimen. */
async function checkoutSpecimen({ email, specimenId, req }) {
  const spc = getSpecimen(specimenId);
  if (!spc || !spc.forSale || spc.simulated || !spc.audioUrl || !spc.ownerEmail) throw new Error("specimen not for sale");
  requireCheckout();
  const split = payoutSplit(spc.priceCents);
  const order = baseOrder({
    email, kind: "specimen", amountCents: spc.priceCents,
    meta: { specimenId, creator: spc.creator, ownerEmail: spc.ownerEmail, ...split }
  });

  if (stripeReady) {
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      customer_email: email,
      line_items: [{ price_data: {
        currency: "usd",
        product_data: { name: spc.title },
        unit_amount: spc.priceCents
      }, quantity: 1 }],
      success_url: `${baseUrl(req)}/dashboard?checkout=success&order=${order.id}`,
      cancel_url: `${baseUrl(req)}/marketplace?checkout=cancel`,
      metadata: { orderId: order.id, specimenId, email }
    });
    orders().update((o) => o.id === order.id, { provider: "stripe", sessionId: session.id });
    return { checkoutUrl: session.url, orderId: order.id, provider: "stripe" };
  }

  const confirmUrl = `${baseUrl(req)}/api/v1/billing/confirm?order=${order.id}&token=${order.confirmToken}`;
  return { checkoutUrl: confirmUrl, orderId: order.id, provider: "stub", stub: true };
}

function baseOrder({ email, kind, amountCents, meta }) {
  const order = {
    id: "ord_" + crypto.randomBytes(8).toString("hex"),
    email: String(email || "").toLowerCase(),
    kind, amountCents, currency: "usd", meta,
    status: "pending",
    provider: stripeReady ? "stripe" : "stub",
    confirmToken: stripeReady ? null : crypto.randomBytes(16).toString("hex"),
    createdAt: new Date().toISOString()
  };
  orders().insert(order);
  return order;
}

/** Private transition: callers must establish the matching payment authority. */
function fulfil(orderId) {
  const order = orders().find((o) => o.id === orderId);
  if (!order) return { ok: false, error: "order_not_found" };
  if (order.status === "paid") return { ok: true, order, already: true };

  orders().update((o) => o.id === orderId, { status: "paid", paidAt: new Date().toISOString() });
  if (order.kind === "plan" && order.meta && order.meta.plan) {
    setPlan(order.email, order.meta.plan);
  }
  logEvent("order.fulfilled", `${orderId}:${order.kind}`);
  return { ok: true, order: orders().find((o) => o.id === orderId) };
}

function confirmStub(orderId, token) {
  const order = getOrder(orderId);
  if (!stubEnabled || !order || order.provider !== "stub") throw billingError("stub_confirmation_unavailable", 403);
  if (typeof token !== "string" || token !== order.confirmToken) throw billingError("bad_token", 403);
  return fulfil(order.id);
}

function handleStripeWebhook(rawBody, signature) {
  if (!stripeReady) throw billingError("stripe_webhook_unavailable", 503);
  let event;
  try {
    event = stripe.webhooks.constructEvent(rawBody, signature, webhookSecret);
  } catch (_) {
    throw billingError("invalid_webhook_signature");
  }
  if (event.type !== "checkout.session.completed" && event.type !== "checkout.session.async_payment_succeeded") {
    return { received: true, ignored: true };
  }
  const session = event.data?.object;
  const order = getOrder(session?.metadata?.orderId);
  // Before this field existed every checkout was hardcoded to USD. Infer only
  // an absent field on those persisted orders; an explicit different or invalid
  // currency still fails. Migration occurs only after the paid event matches.
  const expectedCurrency = order && Object.hasOwn(order, "currency") ? order.currency : "usd";
  if (!order || order.provider !== "stripe" || !order.sessionId || session.id !== order.sessionId ||
      session.payment_status !== "paid" || !Number.isSafeInteger(session.amount_total) ||
      session.amount_total !== order.amountCents || session.currency !== expectedCurrency ||
      !["pending", "paid"].includes(order.status)) {
    throw billingError("payment_does_not_match_order");
  }
  if (!Object.hasOwn(order, "currency")) orders().update((o) => o.id === order.id, { currency: expectedCurrency });
  fulfil(order.id);
  return { received: true };
}

function getOrder(id) { return orders().find((o) => o.id === id) || null; }
function listOrders(email) { return orders().filter((o) => o.email === String(email).toLowerCase()); }
function status() { return { stripe: stripeReady, mode: stripeReady ? "stripe" : stubEnabled ? "stub" : "disabled", plans: Object.keys(PLANS) }; }

module.exports = { checkoutPlan, checkoutSpecimen, confirmStub, handleStripeWebhook, getOrder, listOrders, status, stripeReady: () => stripeReady };
