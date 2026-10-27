# AETHER — the broadcast product

**Lane:** `feat(aether):`. Source home: `aether/`. Registered in
[ORGANS.md](../../ORGANS.md); source map in [MANIFEST.md](../MANIFEST.md).

The product captures sources, advances an organism, publishes rolling HLS and
records public lineage. Deployment, RTMP rebroadcast and R2 durability are optional
operational surfaces with separate acceptance requirements.

## Ownership

- `aether/deploy/`: host, container, Worker, platform configuration and host tests.
- `aether/tools/`: broadcast, tuning, HLS, operator intake, lineage and delivery.
- `aether/web/listener/`: public player; no operator credentials.
- `aether/stations.json` and `aether/docs/`: source registry and design history.

## Dependency contract

The current container copies only AETHER files and uses donor/tone rendering.
Local broadcast may call sibling `forge/bounce.sh` for the SC-gated NRT tier.
Foundry and the Visual Cortex expose optional radio links/mounts; their code and
billing do not become part of AETHER.

Consolidation is complete. Remaining work is actual container and standalone
acceptance, followed by a configured deployment and rollback rehearsal. See
[README.md](README.md) and [EXTRACTION.md](../EXTRACTION.md).
