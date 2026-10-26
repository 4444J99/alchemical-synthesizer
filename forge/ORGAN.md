# ⚒ Forge — the production pipeline

**Kind:** tool (a repeatable pipeline). **Lane:** `feat(forge):`.
Registered in [`../ORGANS.md`](../ORGANS.md).

The pipeline for turning source audio into rendered audio, a matching visual and
an export package:

```
ingest ─▶ rip (stems) ─▶ forge (recombine) ─▶ render (NRT through Brahma) ─▶ visual ─▶ package
```

## What it owns

The pipeline tools and its runtime output both live here (`forge/stems/`,
`forge/recipes/` are gitignored output):

| Tool | Stage |
|------|-------|
| `forge/ingest.sh` | any song → scsynth-ready WAV (ffmpeg) |
| `forge/rip.py` | song → stems (demucs → ffmpeg fallback cascade) |
| `forge/forge.sh` · `forge/stemforge.py` | recombine stolen stems into a recipe + provenance |
| `forge/bounce.sh` · `forge/render-pattern.sh` | headless NRT audio and event rendering through Brahma |
| `forge/validate_audio.py` | audio validation |
| `forge/analyze_audio.py` · `forge/render_video.mjs` · `forge/videotrack.sh` | audio-reactive visual export (`brahma/web`) |
| `forge/package.sh` | social-ready bundle (video + cover) |
| `forge/setup-demucs.sh` · `forge/setup-video.sh` | one-time provisioning |

Makefile targets: `ingest rip forge render track stemtrack demucs videotrack
video package validate`. Station capture (`make tune`, `make stations`) belongs to
[`aether/tools/tune.py`](../aether/tools/tune.py).

## Boundary

- Forge **draws on Brahma** (renders through `brahma/sc/*`, visualizes
  `brahma/web`) and produces artifacts. It does not stream — handing a finished
  track to the radio is Aether's job (`make submit`).
- `tools/build_release.sh` is **not** Forge — it is repo-level release infra
  (CI-coupled). Leave it in `tools/`.
- AETHER can call Forge/Brahma NRT on a local host with SuperCollider. Its current
  [container](../aether/deploy/Dockerfile) copies only AETHER source and uses
  donor/tone rendering; it does not bundle Forge or SuperCollider.

## Consolidation and acceptance

Forge source consolidation is complete. The later AETHER move transferred
`tune.py` into `aether/tools/`; no repeat move is needed. New Forge features land
under `forge/` and shared acceptance harnesses remain in `tools/`.

On 2026-10-25, the wrapper/native suite passed **11/11** with
`BRAHMA_FORGE_NATIVE=1 python3 tools/test_forge.py`. It checks argument and path
handling, render failures/timeouts, and publication of the expected valid WAV.
These checks do not establish the entire ingest-to-video pipeline, listening
acceptance, or a deployed radio. See the current acceptance section in
[ROADMAP.md](../ROADMAP.md#current-acceptance--2026-10-25).
