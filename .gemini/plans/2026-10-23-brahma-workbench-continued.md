# Plan — Brahma live-coding workbench: continuation, M1.5 → M5, and after

Date: 2026-10-23 · Repo: `~/Workspace/library/shelves/organvm-ii-poiesis/alchemical-synthesizer`
Branch: `feat/brahma-live-workbench` @ `c6691cf` · Supersedes the stage table in
`.gemini/plans/2026-10-22-brahma-live-coding-workbench.md` (S0–S4) for execution shape only.
The architecture in that document stands. This file corrects the *facts* and re-cuts the *stages*.

**Homing note:** this draft lives in the OpenCode plan root because the planning session
cannot write to the repo. The implementing agent commits it into the repo as
`.gemini/plans/2026-10-23-brahma-workbench-continued.md` (new file, never overwrite the 10-22 plan)
before making any code change, and pushes it on the same branch.

---

## 1. Verified state (checked live, this session)

| Claim from the session transcript | Live check | Verdict |
|---|---|---|
| M1 landed as `c6691cf` | `git log` — 12 files, +1891/−18 | true |
| 52 tests pass | `npm --prefix brahma/web test` → `tests 52 / pass 52 / fail 0` | true |
| Branch pushed | `origin/feat/brahma-live-workbench == c6691cf`; working tree clean | true |
| M2 "actively executing" | `brahma/web/public/workbench/` **does not exist** | false — nothing on disk |
| Plan committed | `.gemini/plans/2026-10-22-brahma-live-coding-workbench.md` @ `89e0d1d` | true |
| PR opened | `gh pr list` → #47, #52, #53, #54 only. **No PR for this branch** | false — not opened |

Also confirmed: writer lease free (`host-work-admission.py status` → `allowed: true, lease: null`);
`forge/bounce.sh`, `forge/analyze_audio.py`, `forge/validate_audio.py` exist;
`brahma/sc/13_nrt_renderer.scd` exists; SuperCollider 3.14.1 present; Node 26.12.1 locally
(CI pins Node 20); `esbuild` absent; `@strudel/web@1.3.0` and `codemirror@6.0.2` are current.

## 2. What M1 actually delivered — and what it did not

Delivered, verified by reading the code:

- `brahma/web/lib/auth.js` — 128-bit tokens, `timingSafeEqual`, loopback gate, Origin allowlist,
  human cookie + agent bearer. Sound.
- `brahma/web/lib/sandbox.js` — Seatbelt profile builder, scratch, ulimit, process-group teardown,
  7-check self-test. Sound.
- `brahma/web/lib/runtimes.js` — availability gating for strudel/tidal/sonicpi/sclang, fail-closed.
- `brahma/web/lib/dirt.js` — `/dirt/play` → `/brahma/live/play` translation, auto-release, panic map.
- `brahma/sc/31_live_gateway.scd` — `play`/`set`/`panic`/`ping`, typed `/brahma/live/error`,
  panic preserves `\immune_governor` (frees instances, never `s.freeAll`). Correct.
- `brahma/web/server.js` — loopback HTTP bind, WS `verifyClient` Origin check, human-only gate
  on the OSC forward path.

Six gaps. Each one is a real defect or a missing piece the S1 gate claimed was done:

| # | Gap | Evidence | Consequence |
|---|---|---|---|
| G1 | **No typed WS protocol.** Still raw OSC passthrough. No `run`/`stop`/`stop_all`/`status`/`error` envelope, no session manager. | `server.js:224–275` — `JSON.parse` → allowlist → `sendPort.send` | M2 has no protocol to code against; errors cannot reach the UI as structured messages |
| G2 | **Human token is generated but never displayed.** | `auth.js:40` generates; `server.js` never prints or opens it | A browser **cannot authenticate** unless `BRAHMA_HUMAN_TOKEN` is exported. M2 is hard-blocked on this |
| G3 | **OSC sockets bind `0.0.0.0`** | `server.js:187,194` `localAddress: "0.0.0.0"` | Violates R4 loopback requirement; the "hardened gateway" still receives from the network |
| G4 | **`/dirt/` is in the browser allowlist** | `server.js:20` `ALLOWED_NAMESPACES` includes `/dirt/` | Browser can bypass the Dirt bridge's translation and auto-release, writing raw `/dirt/play` to SC |
| G5 | **No rate limit on live control** | no limiter anywhere in `server.js` | Plan §5 promised per-session rate limiting. A stuck Strudel pattern can flood UDP |
| G6 | **No approval state machine** | no `accept`/`run`/hash code exists | R3's central safety boundary is unimplemented |

## 3. Two substrate mismatches that change M3

These are the most important findings, because the acceptance criteria as written cannot pass.

**M3-a. `forge/bounce.sh` cannot render a pattern.** Its contract is
`bounce.sh <input.wav> <output.wav> [duration]` — it normalises an existing audio file to stereo
44.1k and re-expresses it through `13_nrt_renderer.scd`'s `renderSpecimen(inputPath, outputPath, dur)`.
There is no code path from *pattern events* to a WAV. R3's loop
"pattern proposal → `forge/bounce.sh` → `analyze_audio.py`" is therefore unsatisfiable as stated.

**M3-b. `forge/analyze_audio.py` emits a visual envelope, not metrics.** It writes
`{version, fps, sr, frames, duration, bands, env:[{rms,bands[],flat,onset}]}` — normalised,
frame-indexed, tuned for `tree/video.js`. It has no summary output. `validate_audio.py` *does*
compute the right pass/fail facts (RMS silence threshold, peak clipping, DC offset, spectral
diversity) but only prints `CHECK ...` lines and exits 0/1.

Resolution (additive, reuses the existing math — no rewrite):

- **M3 adds `renderPattern`** to `13_nrt_renderer.scd`: build a `Score` from a timestamped event
  list (`engine, instance, note, vel, dur, params`) and `recordNRT` it with no audio device. Same
  `d_recv` bundle strategy as `renderSpecimen`. `forge/render_pattern.sh` wraps it so the gateway
  never embeds sclang.
- **M3 adds `--summary-json`** to `forge/analyze_audio.py` (mean/max RMS, peak, per-band means,
  onset count, flatness mean) and `--json` to `forge/validate_audio.py`. Both additive flags;
  default behaviour unchanged so AETHER and `tree/video.js` keep working.
- **R3's acceptance criterion is restated** as: *pattern → `render_pattern.sh` → WAV →
  `analyze_audio.py --summary-json` + `validate_audio.py --json` → measurable metrics returned to
  the agent*. `bounce.sh` stays the audio-re-expression path it already is.

## 4. Execution shape — why this is not a 16-agent team

The previous run spent roughly an hour of a multi-agent quota on **one** milestone: ~16 agent
conversations (coordinator, orchestrator, 6 survey explorers, 1 worker, 2 reviewers, 2 challengers,
1 auditor, 2 cron monitors), and the monitors kept firing every 8–10 minutes *after* the 429 for
~90 minutes, because each progress report is a model call and nothing halted the loop.

For M1.5–M5 the shape is:

- **One implementer, sequentially, one milestone at a time.** No orchestrator, no explorers.
  Reconnaissance for this plan is already done and is written down in §1–§3.
- **At most one reviewer per milestone, at the end, batched.** One adversarial pass over the whole
  milestone diff, not five agents over one commit.
- **No cron monitoring.** Status is read from `git log` and the test command when needed.
- **No fanout.** The work is four files at a time, not a fleet.
- Each milestone is one attempt ≤30 min including ≤10 min verification, then stop and report.

## 5. Milestones

### M1.5 — Close the M1 debts (small, unblocks everything)

| Task | File | Gate |
|---|---|---|
| Print the human token at launch as `http://127.0.0.1:PORT/#t=<token>` and on stdout; keep env override | `server.js` | boot log shows the URL; `/api/auth/exchange` then `/api/auth/status` → `role: human` |
| Bind OSC listener and sender to `127.0.0.1` | `server.js:187,194` | `lsof -nP -iUDP:57122` shows `127.0.0.1`, not `*` |
| Remove `/dirt/` from the browser allowlist; Dirt inbound stays bridge-only | `server.js:17–21` | new test: `/dirt/play` from a human WS client → `forbidden_address` |
| Token-bucket rate limit on live control (default 200 msg/s, burst 400) | `server.js`, `lib/ratelimit.js` | test: burst 1000 → excess dropped with a typed error, process stays up |
| Typed WS envelope: `{type:"run"\|"stop"\|"stop_all"\|"status"\|"error", ...}`; OSC passthrough retained for legacy clients | `server.js`, `lib/session.js` | `live_bridge.test.js` extended: run/status/error round-trip; legacy raw OSC still works |

Commit: `fix(live): close gateway debts — token handoff, loopback OSC, dirt allowlist, rate limit, typed protocol`

### M2 — Browser workbench + Strudel (AGPL subtree)

Nothing exists yet. This is the biggest single milestone.

| Task | Path |
|---|---|
| Build decision: add `esbuild` as a **devDependency**, `npm run build:workbench` → `public/workbench/vendor/`, gitignore the output, and have `tools/smoke.sh` invoke the build | `brahma/web/package.json` |
| Pin exact `@strudel/web@1.3.0` and `codemirror@6.0.2` (+ `@codemirror/lang-javascript`) | `package.json`, `package-lock.json` |
| Workbench page and editor: multi-tab, syntax highlighting, error gutter, transport, panic button | `public/workbench/index.html`, `app.js`, `editor.js` |
| Strudel adapter: evaluate mini-notation in-page, emit `/brahma/live/play` events over WS with tempo-accurate timing (look-ahead scheduler, not `setInterval`) | `public/workbench/strudel-adapter.js` |
| Error panel wired to the typed `error` envelope, plus client-side Strudel parse errors | `public/workbench/panel.js` |
| AGPL artefacts: SPDX header in every file under `public/workbench/`, `LICENSES/AGPL-3.0-or-later.txt`, `NOTICE`, `CHANGELOG` stub, footer Source link | repo root + subtree |
| `GET /workbench/source.json` → repo URL, running commit SHA, Strudel package + version + Codeberg URL, licence list | `server.js` |
| Licence checker script: SPDX headers present, no disallowed dependency reachable from the workbench page, `product/` not in the page graph | `tools/check-workbench-licence.sh` |
| Keep `public/index.html` (p5 Cortex) untouched — the workbench is a separate route, so the p5/LGPL page and the AGPL page never share a document | — |

Gate: licence checker passes; headless-Chrome E2E types a Strudel pattern, clicks run, and events
arrive at a **stub OSC sink** with correct timing; then the same against the real engine with
`/brahma/live/pong` returning a module count > 0. A render shows measurable non-silence.

Commit: `feat(workbench): AGPL-isolated Strudel live-coding workbench`

### M3 — AI tools, approval loop, offline audition

| Task | Path |
|---|---|
| Shared async tool lib: `list_modules`, `get_params`, `get_engine_health`, `propose_edit`, `render_offline`, `analyze_audio`, `save_song`, optional live `trigger`/`set_param`. Each has `name, schema, scope, cost:0, role, async handler(ctx,args)` | `brahma/web/lib/tools/` |
| Approval state machine: `proposed --accept(H)--> accepted --run(H)--> executed`, stale-hash reject | `brahma/web/lib/approval.js` |
| Provider interface + Gemini adapter; Claude adapter against a mock transport (no key on this machine) | `brahma/web/lib/agent/providers/` |
| Agent loop in the gateway (propose → render → analyze → iterate), streamed to the workbench panel | `brahma/web/lib/agent/loop.js` |
| `renderPattern` + `forge/render_pattern.sh` (see §3) | `brahma/sc/13_nrt_renderer.scd`, `forge/` |
| `--summary-json` / `--json` modes (see §3) | `forge/analyze_audio.py`, `forge/validate_audio.py` |
| Make `mcp.js` `await` handlers (backward compatible); register local tools only under `BRAHMA_LOCAL_TOOLS=1` + loopback + agent token | `product/src/api/mcp.js`, `product/src/core/local-tools.js` |

Gate: registry enumeration proves the `agent` role has **no** accept/run/eval tool; a stale-hash
`run` is rejected; Gemini loop completes propose → render → metrics on this machine; mock-provider
+ key-redaction tests pass; MCP async test passes; `tools/smoke.sh` still green.

Commit: `feat(agent): async tools, approval state machine, offline audition loop`

### M4 — Conformance, runtime adapters, E2E tiers

| Task | Gate |
|---|---|
| Dirt protocol conformance test (handshake + `/dirt/play` + panic, wire-format level) | passes against a captured-packet fixture |
| Tidal / Sonic Pi adapters must report `unavailable: not_installed` — never a fake green | status endpoint test |
| sclang opt-in test: env gate, human role, sandbox self-test, eval-denied-by-default | unit + E2E |
| Headless-Chrome E2E suite (Tier 1: UI, Tier 2: WS protocol, Tier 3: engine, Tier 4: panic) | committed, runnable via `npm run test:e2e` |

Commit: `test(live): conformance, runtime availability, four-tier E2E`

### M5 — Integration and PR

- Full `tools/smoke.sh --strict` + `npm test` + E2E; fix regressions only.
- Rebase onto current `main`; resolve `brahma/web/package.json` / lockfile conflicts with
  dependabot #52/#54 by taking the newer dependency versions.
- Open a **draft** PR against `main` with the implemented/tested/observed table. Do **not** merge.
- Report the three states separately, with commands and outputs.

## 6. Decisions I am making (not asking)

These follow from the plan's own §0 decisions and the code:

1. **`/dirt/` leaves the browser allowlist.** The bridge exists precisely to own that translation.
2. **Bundling with `esbuild` as a devDependency**, output gitignored, rebuilt by smoke. Vendoring a
   committed bundle would hide licence and version drift from the licence checker.
3. **Workbench is a separate HTML document from `public/index.html`.** Cleanest AGPL/LGPL boundary;
   it also keeps the p5 Cortex page out of the AGPL combined work.
4. **`bounce.sh` is not repurposed.** `renderPattern` is added beside `renderSpecimen`.
5. **No auto-run, no setting that enables it**, per §0.
6. **Reviewer budget is one pass per milestone.** The previous run's five-agent review of one
   milestone was thorough and unaffordable; M1's tests already pass and its code was read.

## 7. Genuine human gates (the only ones)

| Gate | Why it is human |
|---|---|
| Audible confirmation | I can measure non-silence; only you can confirm it sounds right |
| Strudel licence position if this ever ships as a hosted commercial service | legal, not engineering |
| `ANTHROPIC_API_KEY` | credential action; Claude adapter stays mock-tested until you provide one |

## 8. Verification matrix (how results get reported)

Every row reports **Implemented** (code on branch) / **Tested** (command + result) / **Observed**
(seen at runtime). Never collapse them.

| Item | Test | Honest limit |
|---|---|---|
| Human token handoff | boot → exchange → status = human | observable |
| Loopback OSC bind | `lsof -nP -iUDP:57122` | observable |
| Dirt allowlist closed | WS send `/dirt/play` → typed reject | observable |
| Rate limit | burst 1000 → drops, no crash | observable |
| Typed protocol | run/status/error round-trip | observable |
| Strudel → engine | headless Chrome → stub sink, then live pong | observable |
| Measured output | `render_pattern.sh` → WAV → summary + validate JSON | **measured, not heard** |
| Error surfacing | bad expression, unknown engine, sandbox denial, crash | observable |
| Panic | voices = 0, no surviving process groups, silent capture | observable |
| Approval boundary | registry enumeration + stale hash | tested |
| Agent loop | Gemini live; Claude mock | Gemini only on this machine |
| Tidal / Sonic Pi | `unavailable: not_installed` | **not claimed as live** |

## 9. What follows M5

Ordered by dependency, each an independent landing.

**N1 — Land it.** Resolve dependabot conflicts, rebase, merge via the repo's policy, tag. Nothing
ships before this. The branch is currently invisible as a PR, which is the single largest
durability risk in the whole effort.

**N2 — PR #47 reconciliation.** `fix/security-findings-20260916` rewrites `acp.js`, `metering.js`,
`rest.js` and is `CONFLICTING`. It must land or be superseded before ACP work; the local-tools
reuse path deliberately avoided those files so this stays tractable.

**N3 — ACP as a real agent host.** Once #47 lands, replace the regex `interpret()` with a
tool-calling loop so external ACP clients (editors, other agents) drive Brahma without the
gateway's own loop. This was deferred with reasons in the 10-22 plan §7; it is the natural second
front-end.

**N4 — Real Tidal and Sonic Pi.** Install GHC/cabal and Sonic Pi, then turn the two
`not_installed` adapters into live paths: Dirt conformance against real Tidal, and decide whether
Sonic Pi attaches to the shared engine or runs its own scsynth and sends events only (the plan's
open question). Also: the Linux `bwrap` backend, currently unimplemented behind the same interface.

**N5 — Remote and multi-client.** WebRTC or HLS return audio so the workbench works off-machine;
session sharing so two people can jam. The AETHER HLS path (`tools/broadcast.sh`, `/live` static
mount) is already there and is the cheapest first step.

**N6 — Song state and lineage.** `save_song` currently writes a project file; make it a real
project format with lineage provenance, tied into the existing `forge/` pipeline
(`stemforge.py`, `package.sh`, `render_video.mjs`) so a session can end as a released artefact
rather than a buffer.

**N7 — The compositional layer.** This is the actual product intent behind "use agents and AI to
build songs": an agent that holds a song plan across many cycles (section map, motif development,
mix targets), auditions each candidate offline, scores it against measured targets, and keeps a
lineage of what it rejected and why. Everything needed for this exists after M3; N7 is the
orchestration on top.

**N8 — Cost and observability.** Provider token usage is logged per run per §7 of the 10-22 plan.
Turn that into a budget surface: per-session spend, a hard stop, and a visible meter in the
workbench. The previous session's quota burn is the argument for this being a feature, not a
footnote.

**N9 — Commercial boundary review.** If `product/` ever serves the workbench or the agent loop as a
paid product, the AGPL position needs your review before that ships. Recorded, not decided.

## 10. Risks

- **Code execution from a browser** remains the top risk. M1.5 tightens the three loose edges
  (token handoff, OSC bind, Dirt allowlist); M2 must not widen them by adding a new send path.
- **Licence boundary** is the second. The checker script is the enforcement, not the prose.
- **Merge conflicts** in `brahma/web/package.json` with #52/#54 are near-certain — the M2 build
  step edits that file. Rebase, don't pre-empt.
- **Quota** is the third. Hence §4: one implementer, batched review, no cron.
- **`analyze_audio.py` coupling** — `tree/video.js` consumes its envelope format. The `--summary-json`
  flag must be additive; do not restructure the existing output.

---

**First action on approval:** commit this file into the repo at
`.gemini/plans/2026-10-23-brahma-workbench-continued.md`, push, then start M1.5 (the token handoff
alone unblocks the browser).
