# AETHER — 24/7 sovereign host (Cloudflare Containers + R2)

The AETHER plan's increment 3 (`docs/AETHER-BROADCAST-PLAN.md` §5.3): move the
generator into an always-on container so Brahma's radio streams 24/7, with R2 as
the durable, CDN-fronted segment store. This directory is the **complete deploy
unit** — code-ready. Actually pressing "go" is a small set of **human-gated
atoms** (below); everything buildable is built and verified.

## What runs

```
┌── Cloudflare Worker (worker.mjs) ─────────────────────────┐
│  /live/*  ── served from R2 (durable, edge-cached) ───────┼─▶ R2: aether-segments
│  else     ── proxied to the container ────────────────────┼─▶ ┌ Container ────────────┐
└───────────────────────────────────────────────────────────┘   │ entrypoint.sh:         │
                                                                  │  • broadcast.sh (gen) │
                                                                  │  • serve.js (:8080)    │
                                                                  │  • r2_sync.sh (opt)    │
                                                                  └───────────────────────┘
```

- **Container** (`Dockerfile`): ffmpeg + python3 + node, no SuperCollider — the
  broadcast's graceful fallback tiers keep the stream live, so the image is small
  and reliable. Runs the generator + the dependency-free `serve.js` (node
  builtins only; no `npm install`, no native builds).
- **Worker** (`worker.mjs`): serves durable segments from **R2** when present,
  else proxies to the live container. This is the "R2 for segments" read path;
  `tools/r2_sync.sh` is the write path (container → R2).

## Build (build context = the repository ROOT)

The Dockerfile COPYs repo-relative paths (`tools/`, `brahma/web/...`), so it must
build from the repo root:

```bash
docker build -f deploy/aether/Dockerfile -t aether-radio .
docker run -p 8080:8080 aether-radio        # → http://localhost:8080  (player + /live)
```

## Deploy — the human-gated atoms

These are the only irreducible steps (each is one action; nothing is parked):

1. **`L-MEDIA-ARK-HOST` — Workers Paid ($5/mo).** Cloudflare Containers require
   the Workers Paid plan. This is the standing spend lever in the registry; it is
   the one real cost gate for the whole 24/7 path.
2. **`wrangler login`** (once) — an interactive auth the organ can't do headless.
3. **Create the R2 bucket** (once): `wrangler r2 bucket create aether-segments`.
4. **Deploy**: from this directory, `wrangler deploy`.
5. **(Optional) R2 write path** — to make the stream durable/CDN-served, set the
   container secrets `R2_BUCKET`, `R2_ENDPOINT`, `AWS_ACCESS_KEY_ID`,
   `AWS_SECRET_ACCESS_KEY` (organ-owned credentials — provisioned via the
   credential organ / `wrangler secret`, **never** pasted in chat) and set
   `AETHER_R2=1`. Without them the container still serves `/live` locally.

> If your `wrangler` version builds the container image with *this directory* as
> the context (not the repo root), build + push the image yourself (the `docker
> build` above) to a registry and replace `image` in `wrangler.toml` with the
> pushed tag.

## Tuning (container env)

| Env | Default | Meaning |
|-----|---------|---------|
| `AETHER_SECONDS` | `12` | nominal seconds per rendered segment |
| `AETHER_LIST_SIZE` | `6` | rolling live-window length |
| `AETHER_SEED` | `1` | organism seed (a run's identity) |
| `AETHER_PERIOD` | `12` | segments per metabolic cycle |
| `AETHER_SOURCE` | — | a donor WAV to fold in (else self-generated) |
| `AETHER_R2` | `0` | `1` enables the R2 sync sidecar |

## Verified

- `serve.js` runs on node builtins and serves the player + `/live` (correct MIME,
  no-cache playlist, `video/mp2t` chunks, path-traversal blocked) — proven
  on-machine without Docker.
- `entrypoint.sh` / `r2_sync.sh` are `bash -n` clean; `worker.mjs` parses;
  `wrangler.toml` is valid TOML — all in `tools/smoke.sh`.
- The image build + `wrangler deploy` themselves run at deploy time (gated above).
