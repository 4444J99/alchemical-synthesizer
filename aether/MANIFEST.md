# AETHER module manifest

The AETHER source boundary is the consolidated `aether/` prefix. Keep this map
current when adding files or changing the optional Brahma integration.

## AETHER-owned source

| Paths, relative to repository root | Responsibility |
|---|---|
| `aether/deploy/{serve.js,worker.mjs,Dockerfile,entrypoint.sh,wrangler.toml}` | Local/container/edge hosting |
| `aether/deploy/{serve.test.js,integration.test.js,worker.test.js}` | Host, source-layout, intake and edge predicates |
| `aether/deploy/rebroadcast.json` | RTMP configuration |
| `aether/tools/{broadcast.sh,cellcycle.py,hls_append.py}` | Generator and HLS transport |
| `aether/tools/{ingest_queue.py,lineage.py,tune.py}` | Operator intake, source capture and provenance |
| `aether/tools/{rebroadcast.sh,r2_sync.sh}` | Optional external delivery |
| `aether/web/listener/` | Listener and its browser-logic test |
| `aether/stations.json` | Source registry |
| `aether/docs/BROADCAST-PLAN.md` | Design history |

The current Dockerfile builds from repository root and copies only AETHER files.
Its SC-less fallback does not bundle Forge or Brahma. Local `broadcast.sh` may
call sibling `forge/bounce.sh` when SC and a donor are available; a standalone
build must explicitly choose whether to supply that optional dependency.

## Shared integration points

- Root `Makefile` and `tools/smoke.sh`: repository-wide entrypoints and checks.
- `brahma/web/server.js`: mounts `/aether/` from `aether/web/listener/` and consumes
  shared `out/live`; this is a host integration, not AETHER engine ownership.
- `product/server.js`, `product/public/home/`, and `product/bin/smoke.js`: Foundry
  surfaces the radio and reads the shared stream location.
- `tools/build_release.sh`: includes AETHER in the whole-repository source package.
- `forge/bounce.sh` and `brahma/sc/13_nrt_renderer.scd`: optional local NRT tier.

Foundry billing/accounts, Brahma DSP/Pd/Ableton, and Forge production tools remain
outside the AETHER source boundary. The complete repository's tests are not all
part of a standalone AETHER export.
