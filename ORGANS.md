# Repository ownership map

The repository contains three creative/technical lanes and shared integration
infrastructure. This map describes current paths; it does not certify deployment.

| Lane | Home | Responsibility |
|---|---|---|
| Brahma | `brahma/` | Synthesis, trait contracts, live engine control, Pd/Ableton and browser interfaces |
| Forge | `forge/` | Ingest, stems, offline rendering, audio analysis, video and packaging |
| AETHER | `aether/` | Source capture, generative broadcast, HLS, radio listener and deployment candidate |
| Foundry | `product/` | Brahma accounts, metering, protocol adapters and specimen commerce scaffold |
| Shared | `tools/`, root `Makefile`, `.github/workflows/` | Cross-repository tests, build and release infrastructure |

Existing lane prefixes (`feat(brahma):`, `feat(forge):`, `feat(aether):`) remain
useful. Each feature has an owning lane; host integration points may refer to
another lane without taking ownership of it.

## Source and runtime dependencies

- Forge consumes Brahma's NRT renderer and visual assets.
- AETHER may consume Forge/Brahma NRT when installed locally. Its current
  container uses donor/tone rendering and copies only `aether/` source.
- `aether/tools/tune.py` belongs to AETHER. It is no longer `forge/tune.py`.
- Foundry and the Visual Cortex read repository `out/live`; the latter mounts
  `aether/web/listener/` at `/aether/`. AETHER's standalone host uses the same
  local default. `AETHER_LIVE_DIR` overrides it.
- Foundry's `render_specimen` is a simulated-record operation. A live engine
  observation does not supply render completion or a verified artifact.

## Tool map

| Files | Owner |
|---|---|
| `forge/{ingest.sh,rip.py,forge.sh,stemforge.py}` | Forge ingestion and recombination |
| `forge/{bounce.sh,render-pattern.sh,analyze_audio.py,validate_audio.py}` | Forge rendering and measurement |
| `forge/{render_video.mjs,videotrack.sh,package.sh,setup-demucs.sh,setup-video.sh}` | Forge visual/export tooling |
| `aether/tools/{broadcast.sh,cellcycle.py,hls_append.py}` | AETHER generator and transport |
| `aether/tools/{tune.py,ingest_queue.py,lineage.py}` | AETHER capture and provenance |
| `aether/tools/{r2_sync.sh,rebroadcast.sh}` | AETHER external delivery |
| `tools/{smoke.sh,gen_test_tone.py,build_release.sh,test_release.py,test_forge.py}` | Shared verification and distribution |
| `tools/dsp/` | Native Brahma acceptance harness |

## Consolidation status

Forge and AETHER source consolidation is complete. Current AETHER boundaries and
standalone acceptance are documented in [aether/MANIFEST.md](aether/MANIFEST.md)
and [aether/EXTRACTION.md](aether/EXTRACTION.md). Do not repeat obsolete move recipes.

The AETHER container still needs an actual build/run and platform verification.
Those are distinct from the completed file relocation, and local verification does
not require paid hosting. [The review](docs/reviews/2026-10-24-verification-hardening.md)
records what was exercised and what remains unverified.
