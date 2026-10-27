# AETHER local host and deployment candidate

This directory contains a dependency-free Node host, a container recipe, and a
Cloudflare Worker/R2 adapter. Host-side tests are executable locally. An actual
image build, cloud deployment and sustained radio operation require their own
verification; source presence and configuration parsing do not establish them.

## What runs

The container starts `broadcast.sh` and `serve.js` together. It contains Node 24,
Python and ffmpeg, and uses donor playback or a genome-reactive tone. It does not
contain SuperCollider or a partial Forge installation.

The Worker serves allowed listener artifacts from R2 when present and proxies
other requests to the container. `r2_sync.sh` is the optional write path; it needs
an AWS CLI installation that the current base image does not provide. R2 is not
an accepted operational feature of this image yet.

## Local build

The build context is the monorepo root; COPY paths start with `aether/`:

```bash
docker build -f aether/deploy/Dockerfile -t aether-radio .
docker run --rm -p 8080:8080 aether-radio
```

The listener is at `http://localhost:8080/`. Docker was unavailable in the
2026-10-24 review environment, so the image itself was not built or run there.
The integration suite checks every COPY source and runs the host/broadcaster
outside Docker. A standalone export must adapt the context explicitly.

## Intake and public files

`POST /submit` accepts `{ "url": "https://...", "license": "...", "attribution": "..." }`
only when `AETHER_SUBMIT_TOKEN` is set and `Authorization: Bearer <operator token>`
matches. Provision a random token as an operator secret; never embed it in the
listener. Missing configuration returns `503`, unauthorized requests `401`, and
invalid fields `400`. Intake is serialized within one host process.

This route authorizes a trusted operator to request a fetch on the broadcaster's
network. It does not make arbitrary public URLs safe. Public intake remains closed
pending an isolated fetch service and admission controls. License/attribution
fields are provenance metadata rather than clearance decisions.

Only the playlist, segment files, telemetry and public lineage are exposed under
`/live`. Queue records, consumed submissions and generator state are excluded from
both host/edge reads and new R2 syncs. If an older deployment copied private records
to R2, audit existing objects and bucket visibility separately: this change does
not delete previously uploaded objects.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `8080` | Host port |
| `AETHER_LIVE_DIR` | Workspace `out/live`; container `/live` | Shared generator/host output |
| `AETHER_STATIC_DIR` | Bundled listener | Static player location |
| `AETHER_SUBMIT_TOKEN` | Unset | Trusted-operator intake; unset disables it |
| `AETHER_SECONDS` | `12` | Nominal seconds per segment |
| `AETHER_LIST_SIZE` | `6` | Rolling playlist window |
| `AETHER_SEED` / `AETHER_PERIOD` | `1` / `12` | Generator seed and metabolic cycle |
| `AETHER_SOURCE` | Unset | Optional donor WAV |
| `AETHER_R2` | `0` | Optional sync sidecar, after its CLI and credentials are provisioned |

## Deployment acceptance

Validate the Worker build against the installed Cloudflare tooling, actual Docker
image, configured account/bucket, container environment injection, restart and
rollback before deployment. Platform plans and credentials are deployment inputs;
a local image build does not require purchasing a platform plan.

The current pass exercised `serve.test.js`, `integration.test.js`, and
`worker.test.js` with temporary local fixtures, plus listener tests and the root
smoke harness. Worker tests substitute the platform adapter and do not contact
Cloudflare or R2. See the [review](../../docs/reviews/2026-10-24-verification-hardening.md)
for exact scope and remaining gates.
