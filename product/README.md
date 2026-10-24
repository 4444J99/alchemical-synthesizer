# Brahma Foundry — Productization Layer

> *No more complete products locked in dusty drawers.* The Foundry is the
> commercial surface of the Alchemical Synthesizer: one Node service that turns
> the Brahma engine into a product you can run, sell, and let agents drive.

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
npm install
npm run seed     # optional: demo users, specimens, marketplace listings
npm start        # → http://localhost:4000/pricing
```

Then open the **dashboard** at `http://localhost:4000/dashboard`, sign up
(Account tab) to mint an API key, and render a specimen.

Verify everything end-to-end:

```bash
npm run smoke    # boots on an ephemeral port, exercises REST/MCP/ACP/metering/billing
```

## Runs anywhere (with or without SuperCollider)

The Foundry binds the same OSC topology as `brahma/web` (recv `57122`, send
`57120`). When a live SuperCollider engine is present, organism telemetry flows
in and `render_specimen` dispatches a real NRT command. When it is **not**
present (e.g. cloud deploy), renders are recorded and flagged
`simulated: true` — every surface stays functional. This is the honest seam: the
audio engine is local to performers; the product/control-plane is cloud-native.

## Monetization (built in logical order)

1. **Acquisition** — `/pricing` + waitlist + free `Initiate` plan.
2. **Metering + licensing** — every API/MCP/ACP call resolves an API key and
   charges the plan's monthly quota (`src/auth/metering.js`); 402/429 on
   exhaustion. License keys for self-host via `licensing.issueLicense()`.
3. **Marketplace** — render → list specimens for sale; creators keep 85%
   (`src/marketplace/`).
4. **Accounts / SaaS** — signup/login (scrypt-hashed), per-account keys, plan
   upgrades via checkout.

### Billing

Checkout works **today** via a deterministic stub. Set `STRIPE_SECRET_KEY`
(and `npm i stripe`) to switch to real Stripe Checkout — no code change. Point
Stripe webhooks at `/api/v1/billing/webhook/stripe`.

## Configuration

| Env | Default | Meaning |
| :--- | :--- | :--- |
| `PORT` | `4000` | HTTP port |
| `OSC_RECV_PORT` / `OSC_SEND_PORT` | `57122` / `57120` | SC bridge |
| `SC_HOST` | `127.0.0.1` | SuperCollider host |
| `FOUNDRY_DATA_DIR` | `./data` | JSON store location |
| `STRIPE_SECRET_KEY` | — | Enables real Stripe checkout |
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
- Stream real WAV audio from the SC NRT renderer at `/api/v1/specimens/:id/audio`.
- Replace the simulated trait map with live AE-stage spectral extraction
  (see the engine's `/docs/logos/praxis.md` Vector 1).
- Add refresh-token sessions + rotating signing secret for the dashboard.

## Docker

```bash
docker build -t brahma-foundry product/
docker run -p 4000:4000 -e PORT=4000 brahma-foundry
```

### API-key transport

Send API keys in the `Authorization: Bearer <key>` or `x-api-key` header. URL query parameters do not authenticate requests. This applies to REST, MCP, and ACP HTTP endpoints; the ACP stdio adapter retains its environment-to-header transport.
