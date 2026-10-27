# AETHER — the living radio

AETHER is the broadcast product within this repository. Its source is consolidated
under `aether/`: it captures sources, advances a generative organism, and publishes
a rolling HLS stream. The local renderer can use the sibling Brahma/Forge NRT path;
the current container uses donor playback or a generated tone and includes no SC.

## Current boundary

| Component | Location | Role |
|---|---|---|
| Deploy unit | [deploy/](deploy/README.md) | Local host, container, Cloudflare Worker and R2 configuration |
| Broadcast tools | [tools/](tools/) | Broadcast, tuning, HLS, queue, lineage, rebroadcast and R2 sync |
| Listener | [web/listener/](web/listener/) | HLS player and public lineage |
| Stations | [stations.json](stations.json) | Source registry with recorded license tags |
| Design history | [docs/BROADCAST-PLAN.md](docs/BROADCAST-PLAN.md) | Original broadcast plan |
| Shared entrypoints | Root `Makefile` | `broadcast`, `rebroadcast`, `submit`, `tune`, `stations` |

[MANIFEST.md](MANIFEST.md) identifies integration points outside this prefix.
[EXTRACTION.md](EXTRACTION.md) records the remaining standalone acceptance work;
the completed directory move must not be repeated.

## Local operation

From the repository root, with Node 24+, Python 3.11+ and ffmpeg installed:

```bash
bash aether/tools/broadcast.sh --segments 3 --seconds 2 --no-nrt
node aether/deploy/serve.js
# Open http://localhost:8080/ and /live/stream.m3u8
```

Both commands use repository `out/live` by default. An independently extracted
AETHER tree uses its own `out/live`; a container explicitly sets
`AETHER_LIVE_DIR=/live`. `AETHER_LIVE_DIR` overrides both generator and host.

The gateway also mounts the listener at `/aether/`. Network intake at `POST /submit`
is **disabled by default**. It can be enabled for a trusted operator with
`AETHER_SUBMIT_TOKEN` and a matching Bearer header. The listener does not solicit
public submissions. URLs are fetched on the broadcaster's network, so this is an
operator trust boundary, not a safe public URL-fetching service. Public intake
needs isolated egress, redirect/DNS controls, admission limits, and moderation.
The local `make submit` queue path remains available to the operator.

The host and edge publish only `stream.m3u8`, `seg_*.ts`, `telemetry.json`, and
`lineage.json`. Pending/consumed queue records and generator state stay private.
License labels record provenance; they do not establish rights clearance.

## Evidence and remaining acceptance

The [verification review](../docs/reviews/2026-10-24-verification-hardening.md)
records host/listener/edge tests and a bounded ffmpeg broadcast using default
paths. The edge tests use an in-memory platform adapter. No actual container build,
Cloudflare deployment, R2 upload, or sustained public stream was performed in that
pass. AETHER's coherence/fidelity/entropy remain explicitly provisional indicators;
they are not the engine's new sample-derived measurements.
