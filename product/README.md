# Brahma Foundry — Productization Layer

> *No more complete products locked in dusty drawers.* The Foundry is the
> product surface of the Alchemical Synthesizer: one Node service for accounts,
> metering, specimen records, and agent adapters. Real rendering and production
> payment lifecycle integration remain unfinished.

It exposes **every** surface the build called for, over a single capability
core (`src/core/actions.js`) — the protocol is a skin, the capability is the
body:

| Surface | Route | Purpose |
| :--- | :--- | :--- |
| **Dashboard UI** | `/dashboard` | Telemetry, render, catalog, marketplace, keys, usage |
| **Pricing / landing** | `/pricing` | Plans, Stripe(-stub) checkout, waitlist |
| **REST API** | `/api/v1` | Metered, key-gated, OpenAPI at `/api/v1/openapi.json` |
| **MCP server** | `/mcp` | JSON-RPC 2.0 tools for any MCP agent |
| **ACP — Communication** | `/acp/runs` | BeeAI-style agent-to-agent interop |
| **ACP — Client** | `/acp/jsonrpc` + `bin/acp-stdio.js` | Zed-style editor/agent clients |
| **Live telemetry** | `ws://…/ws` | Organism state at 5 Hz |

## Quick start

```bash
cd product
npm ci          # Node 24+
npm run seed     # optional local demo users and simulated, unlisted specimens
npm start        # → http://localhost:4000/pricing
```

Then open the **dashboard** at `http://localhost:4000/dashboard`, sign up
(Account tab) to mint an API key, and create a simulated specimen record.

Verify the local HTTP/MCP/ACP and audio-serving contracts:

```bash
npm run smoke    # boots on an ephemeral port, exercises REST/MCP/ACP/metering/billing
```

## Runs anywhere (with or without SuperCollider)

The Foundry uses recv `57122` and send `57120` by default. Configure a different
receive port if the Visual Cortex is already using `57122`. A listener binding
does not mean the engine is online: valid observed organism telemetry is required
and expires after two seconds. This is observation, not authenticated engine identity.

`render_specimen` always creates `simulated: true` with `audioUrl: null`. No NRT
completion or artifact-ingestion contract exists in this bridge. Existing real
artifacts may be registered separately and served through the audio endpoint;
simulated records return `409` there and cannot be listed for sale.

## Monetization (built in logical order)

1. **Acquisition** — `/pricing` + waitlist + free `Initiate` plan.
2. **Metering + licensing** — every API/MCP/ACP call resolves an API key and
   charges the plan's monthly quota (`src/auth/metering.js`); 402/429 on
   exhaustion. License keys for self-host via `licensing.issueLicense()`.
3. **Marketplace** — only an authenticated owner may list or unlist a real
   specimen. Creator display names do not confer ownership. The 85% creator
   split is a calculation and order record; automated payouts are not implemented.
4. **Accounts / SaaS** — signup/login (scrypt-hashed), per-account keys, plan
   upgrades via checkout.

### Billing

Checkout is disabled until configured. Real Stripe Checkout requires the optional
Stripe SDK, `STRIPE_SECRET_KEY`, and `STRIPE_WEBHOOK_SECRET`. Send signed events
to `/api/v1/billing/webhook/stripe`; the endpoint verifies the untouched raw body
and matches the paid session, order, amount, and currency before fulfilment.
The unsigned legacy webhook returns `410`, and Stripe orders cannot use local
confirmation tokens. Pre-upgrade orders that lack currency retain the original
USD contract and gain explicit currency only after a matching verified payment.

For an isolated local demonstration, set `FOUNDRY_ALLOW_STUB_BILLING=1` with no
Stripe API key and `NODE_ENV` other than `production`. Only orders created in that
mode can use stub confirmation. `npm run smoke` selects this mode explicitly and
does not contact Stripe. Renewal, cancellation, refunds, disputes, payout delivery,
and transactional persistence remain production blockers.

## Configuration

| Env | Default | Meaning |
| :--- | :--- | :--- |
| `PORT` | `4000` | HTTP port |
| `OSC_RECV_PORT` / `OSC_SEND_PORT` | `57122` / `57120` | SC bridge |
| `SC_HOST` | `127.0.0.1` | SuperCollider host |
| `FOUNDRY_DATA_DIR` | `./data` | JSON store location |
| `STRIPE_SECRET_KEY` | — | Stripe API credential; requires SDK and webhook secret |
| `STRIPE_WEBHOOK_SECRET` | — | Required signature verification secret for the Stripe endpoint |
| `FOUNDRY_ALLOW_STUB_BILLING` | `0` | Explicit nonproduction demo billing with no Stripe key |
| `PUBLIC_URL` | — | Canonical base URL for checkout redirects |
| `CORS_ORIGIN` | `*` | Restrict browser origins |

## Architecture

```
product/
  server.js                 HTTP + WS + surface mounting
  src/
    core/
      actions.js            ← the single capability registry (all surfaces wrap this)
      engine.js             OSC bridge to SuperCollider (+ simulation fallback)
      catalog.js            module catalog (seed + live registry merge)
      store.js              dependency-free JSON persistence
    auth/   plans · licensing (scrypt, keys) · metering (quota)
    billing/ billing.js     Stripe-optional checkout + orders + fulfilment
    marketplace/            specimen listing + payout split
    api/    rest.js · mcp.js · acp.js
  public/   pricing/ · dashboard/
  bin/      seed.js · smoke.js · acp-stdio.js
```

## Praxis (what to harden next)

- Swap the JSON store for Postgres behind the same `store.collection()` interface.
- Connect an acknowledged renderer and validated artifact ingestion to specimen creation;
  the existing audio endpoint already streams registered real files with range support.
- Replace the simulated trait map with live AE-stage spectral extraction
  (see the engine's `/docs/logos/praxis.md` Vector 1).
- Complete subscription/refund/payout lifecycle before selling subscriptions or specimens.
- Add refresh-token sessions + rotating signing secret for the dashboard.

## Docker

```bash
docker build -t brahma-foundry product/
docker run -p 4000:4000 -e PORT=4000 brahma-foundry
```

### API-key transport

Send API keys in the `Authorization: Bearer <key>` or `x-api-key` header. URL query parameters do not authenticate requests. This applies to REST, MCP, and ACP HTTP endpoints; the ACP stdio adapter retains its environment-to-header transport.
