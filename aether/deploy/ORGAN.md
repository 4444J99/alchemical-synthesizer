# 📡 Aether — the broadcast product

**Kind:** product (a live deploy unit). **Lane:** `feat(aether):`.
Registered in [`../../ORGANS.md`](../../ORGANS.md). Deploy details in
[`README.md`](README.md); full plan in `../../docs/AETHER-BROADCAST-PLAN.md`.

Brahma's living 24/7 radio — a self-feeding organism:

```
capture ─▶ broadcast (generative HLS) ─▶ 24/7 host (CF Containers + R2)
        ─▶ RTMP reach (YouTube/Twitch) ─▶ Ouroboros (viewers feed it) ─▶ funnel
```

## What it owns

- **The deploy unit — this directory** (`deploy/aether/`): `worker.mjs`,
  `serve.js`, `Dockerfile`, `entrypoint.sh`, `wrangler.toml`, `rebroadcast.json`.
  The **complete, code-ready** unit; go-live is the gated `L-MEDIA-ARK-HOST`
  atom (Workers Paid $5/mo).
- **Operator tools** (in `tools/`):
  - **Container-coupled** (bundled/executed by the live image): `broadcast.sh`,
    `cellcycle.py`, `hls_append.py`, `r2_sync.sh`, `ingest_queue.py`.
  - **Host-side** (RTMP reach + lineage): `rebroadcast.sh`, `lineage.py`.
- **Reused Forge tools** (Aether → Forge, allowed): `broadcast.sh` calls
  `forge/tune.py` (submission capture) + `forge/bounce.sh` (SC-gated NRT tier), so
  the `Dockerfile` `COPY`s those two into `/app/forge/`. Both degrade gracefully
  if absent.

Makefile targets: `broadcast rebroadcast submit stations`.

## Boundary

- Aether **consumes** Brahma (streams `brahma/web`, broadcasts Brahma-rendered
  audio) and Forge output (`make submit` hands a finished track to the radio). It
  produces no tracks itself.
- **Build context = the repository ROOT.** `Dockerfile` COPYs repo-relative
  paths (`tools/…`, `brahma/web/…`), so the container reaches across the whole
  repo. This is why Aether cannot be lifted into a standalone `aether/` (or its
  own repo) without a coordinated rewire — the #33 "bounded module + gated
  extraction recipe" decision.

## Owned remaining work — GATED consolidation

Do **not** blind-move the container-coupled tools. Each move must land with a
matching edit to `Dockerfile` / `entrypoint.sh` / `serve.js` **and** be proven by
an actual container build+deploy — which is only reachable behind the paid
`L-MEDIA-ARK-HOST` lever. Until that lever is pulled:

1. The five container-coupled tools stay in `tools/` **by design** (not neglect).
2. When `L-MEDIA-ARK-HOST` is live, the extraction recipe is: move the five +
   the two host-side tools into `aether/`, repoint every `COPY tools/…` →
   `COPY aether/…`, and re-verify `docker build -f deploy/aether/Dockerfile .`
   serves `/live` + the player before deploy.

The host-side pair (`rebroadcast.sh`, `lineage.py`) may relocate independently
once Forge's decouple pattern (see `../../forge/ORGAN.md`) is in place, since they
carry no container coupling.
