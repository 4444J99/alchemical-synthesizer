# Repository verification, critique and hardening — 2026-10-24–26

## Outcome

This pass repairs reproduced runtime, native-audio, browser, artifact, payment,
ownership and integration failures. It replaces several success-shaped placeholders
with explicit unavailable/simulated states and adds acceptance predicates that
exercise the advertised behavior. It preserves the Brahma / Forge / AETHER source
boundaries and the human approval gate.

The repository is materially more verifiable. It is still a synthesis/research
system with an incomplete measured absorption workflow and a commerce scaffold.
Focused local tests do not establish full-rack hardware operation, perceptual
fidelity, production billing or an operational cloud radio.

Work is prepared on `fix/verified-hardening-2026-10-24` for a draft review PR.
No merge, deployment, release publication, paid provider call, account purchase,
repository split, visibility change, or destructive cleanup was performed.
Publication and hosted-check status belong to the final PR/handoff record; they
must not be inferred from this report's local test results.

## Scope and provenance

The initial revision was `bf6c8257ac976efaf526ae1b612bb7371f96f64a`, with 104 reachable
commits. The history review covered that commit inventory, all 74 then-existing PRs,
their available review endpoints, and six issues. It then incorporated the five
concurrent main-line commits through `24651b0693808bd91836ab2013ad1f5f357a1d41`:
109 reachable commits and 75 PRs (62 merged, 13 closed unmerged, zero open at the
2026-10-25 02:46:55 UTC snapshot).

This is a complete history/PR inventory with targeted source review and executable
acceptance, not a claim that every line or hardware combination was exhaustively
proved. Historical open review threads were used as leads, not counted as distinct
current vulnerabilities. The original 74-PR inventory had 114 threads, 105 unresolved;
thread resolution metadata alone does not say whether a later patch fixed a concern.

Concurrent PRs [78](https://github.com/4444J99/alchemical-synthesizer/pull/78),
[79](https://github.com/4444J99/alchemical-synthesizer/pull/79),
[80](https://github.com/4444J99/alchemical-synthesizer/pull/80), and
[81](https://github.com/4444J99/alchemical-synthesizer/pull/81) were reconciled before
final verification. A retained checkpoint and SHA-256 comparison preserved all
36 already-modified files while advancing the base. No unique prior work was dropped.

A second upstream reconciliation incorporated **28 more commits across 48 files**
through `e27f020306273c697a6c7909ca1c7c4e3ea5e9c2`. The October 26 snapshot has
137 commits reachable from main and 93 PRs: 72 merged, 15 closed unmerged, and six
open. The complete prior 100-path hardening tree was checkpointed before this
integration; overlapping changes were resolved deliberately and the combined
functional gates were rerun. The original evidence receipt is retained as a
historical snapshot, not presented as verification of the later source.

The six open PRs (#97–#102) form a sampling/native-transformation/UI stack. They
were inventoried and reviewed separately; four concrete current-head findings
remain open, including two reproduced callback failures in PR102. Their code is
not part of this main-based hardening branch. See the
[open-stack review](2026-10-26-open-stack-review.md) and
[history inventory](2026-10-26-history-evidence.json).

The working environment was Linux, Node 24.22.1, Python 3.12, SuperCollider 3.13,
ffmpeg, a named dummy-JACK backend, and Chrome for Testing 156.0.8078.47. Browser
and native checks use generated fixtures. Docker and the `organvm` command were
unavailable. Native physical-device and cloud acceptance were not replaced by mocks
and then reported as real operation.

## Principal findings and repairs

### 1. Human cancellation did not reliably stop the work

The previous stop path lost authenticated actor information in adapters, did not
retain usable process ownership, could leave descendants alive, and could allow
queued work to begin or late completion to overwrite cancellation.

The runner now owns terminal cancellation, abort signals and queue removal.
The executor owns a bounded process group and terminates descendants on abort,
timeout, overflow and wrapper exit. HTTP and MCP preserve the human actor; agents
remain unable to accept/run/stop work through human-only tools. The supervised Forge
path keeps its children in that group. Malformed cookies and malformed event shapes
fail without crashing or falling through to paid composition.

Evidence: `brahma/web/test/agent-stop.test.js`, `agent-admission.test.js`,
`auth-malformed-ws.test.js`, HTTP/MCP/auth regressions, and the full web suite.

### 2. Provider availability overstated capability and blocked startup

Optional runtime probing was synchronous on a request/startup path. Some adapters
reported availability or produced fixture-shaped results without a working bridge.
Key-only model configuration could select an unsuitable implicit model.

Registry construction/listing is now cheap; explicit probes are asynchronous,
bounded and deduplicated per registry, and shutdown cancels pending probes and
their descendants. Tidal/Sonic Pi installation is discovery
metadata and their unimplemented adapters remain unavailable. Claude/Gemini need
an explicit nonblank model as well as a key. Gemini is exposed consistently through
MCP. Mock output remains clearly deterministic. No paid provider was contacted.

Evidence: `providers-hardening.test.js`, agent/provider, conformance and sandbox
regressions. The original web suite had three availability failures; the revised
full suite passes under the actual installed/absent runtime mix.

### 3. The workbench could play a different draft or lose Stop authority

The editor returned stale text. Editing a running tab discarded its playback identity.
Registration and event instance IDs disagreed. Rapid Run–Stop–Run reused an ID, so a
late acknowledgement could clear the replacement. An unresolved top-level await
retained the admission lock; later completion and globally injected tempo helpers
could interfere with a newer pattern.

Run now reads the visible CodeMirror document and waits for registration acceptance.
Every run has a distinct registration/instance ID, while the tab keeps a useful
human label. Editing marks a draft without surrendering Stop authority. Each
evaluation owns its scheduler, admission state and lexical Strudel helper bindings.
Stop clears that ownership immediately; stale completion cannot replace, stop or
change the tempo of its successor. Connection loss stops local scheduling and queues
registration cleanup. Explicit global JavaScript mutations remain outside this
playback isolation; this is not a sandbox for untrusted code.

Ten real-browser cases exercise UI, role exchange, typed protocol, real UDP delivery,
panic, edits, replacement, rapid transport and delayed evaluation including stale
`setcps`. A UDP fixture establishes transport; it does not prove audible engine output.

### 4. IMMUNE added its output to the dangerous signal

The protection SynthDef used additive `Out` on a bus that already carried its input.
A native fixture with amplitude 5 produced a peak of approximately **5.899702** despite
a requested 0.9 limit, with 38,735 samples above 0.90001.

The governor now uses `ReplaceOut` for its protected bus. Native NRT verification
bounds both channels to **0.90001**, quarantines the runaway channel after settling,
and verifies the safe channel is not doubled. This is evidence for that governor;
full-rack routing and node-order acceptance still need a successful full-loader test.

Mechanism references: [SC Out](https://doc.sccode.org/Classes/Out.html) and
[SC ReplaceOut](https://doc.sccode.org/Classes/ReplaceOut.html).

### 5. Measurement and contract code needed executable semantics

The original metrics file did not parse under the installed SC runtime, and the
visual pipeline could emit plausible random values without captured audio. The
concurrently merged contract implementation also failed class compilation and used
incompatible JSON/range assumptions.

The class API and phase-11 collector now share one `BrahmaMetrics` implementation
that analyzes real samples with explicit definitions: Hann-windowed
spectral-centroid stability, Shannon spectral-power entropy, and absolute zero-lag
Pearson correlation for aligned input/output. It is bounded to 64 complete 1024-sample
windows by default, selects a channel explicitly, and returns unavailable for
missing, nonfinite, silent or insufficient data. Stress is available only for a
running server. Live capture remains unwired and normal telemetry says so; synthetic
telemetry is opt-in and labelled.

Independent native review reproduced corruption when two stock SC Buffer reads
shared a buffer number. The adapter now coalesces per-buffer requests, tracks each
chunk offset/count once and cleans up responders/routines on completion or timeout.
Both simultaneous measurements preserve all 16 active windows in the regression.

AdamKadmon delegates schema work to `BrahmaContracts`, using the stock decoder,
validated numeric contract data, required shapes, optional/dotted range types,
and deep-copy normalization. Unknown contracts are rejected. A final validity check prevents contradictory parent/child ranges from
returning an invalid normalized result. Schema `strictness` is metadata; `provenance_min_confidence` controls the separately
validated measurement threshold. Selected thresholds are applied consistently
through provenance and FSAP admission. Changed traits cannot retain donor evidence. A compatible target that explicitly
permits proxies now accepts a real transform (centroid 0.2→0.36) with unknown
confidence instead of a fabricated score; measured targets still reject it until
remeasurement. All four shipped substrate contracts currently require measurements,
and the non-audio schemas use scalar axes, so this does not claim a completed
nested-to-scalar cross-substrate pipeline.
`attachMeasurements` structurally validates caller-supplied numbers; it does not
authenticate their capture. Optional FluCoMa uses an explicit separate method and
is unverified without that plugin. Capability signing reports unavailable; the old permission stub
is not promoted into a security boundary.

The trait overlay follows the currently selected organism, handles empty/expired
selection, fits narrow viewports, and labels proxy/incomplete values explicitly.

### 6. Forge could report an old or corrupt file as a successful render

Both wrappers discarded renderer failure and accepted any nonempty destination.
The native NRT callback also printed completion and exited zero after a failing
server. Paths and duration were interpolated into generated SC code.

Each wrapper now renders in private staging on the destination filesystem and
publishes with an atomic rename only after success and verification of the complete
stereo 44.1 kHz PCM16 WAV payload and expected duration. Old output survives failure.
Inputs and finite durations are validated, fractional durations work, paths travel as
data, and native/timeout exit status propagates. Fixed internal filenames avoid stock
SC shell/path quoting hazards. The supervised-process behavior is retained.

Native tests cover both actual renderers, unusual literal paths and a failing
`scsynth` returning 19. Offline fixtures reject absent, stale, corrupt, truncated,
wrong-rate, mono and wrong-duration candidates. Direct calls to the SC renderer do
not acquire the wrappers' staging guarantees. Actual macOS execution remains untested.

### 7. Payment authority and existing-order compatibility were incomplete

The former unsigned webhook/confirmation paths could mark orders paid without a
verified provider event. Configuration also silently fell back to demo billing.

Stripe now requires SDK, API key and endpoint secret, verifies the raw request body,
and matches provider, session ID, paid status, amount, currency and order state.
The legacy unsigned endpoint returns 410. Stub billing is an explicit nonproduction
opt-in and can confirm only its own stub orders. Repeated valid callbacks fulfil once.
Legacy Stripe orders with an absent currency field retain their previous USD contract
and gain explicit currency only after a verified matching event.

The tests use the official SDK's local signature generator and synthetic stores;
there was no checkout or live payment. Subscription renewal, cancellation, refunds,
disputes, payouts and transactional persistence remain blockers for commercial use.
Reference: [Stripe webhook signature verification](https://docs.stripe.com/webhooks/signature).

### 8. Specimen identity, engine observation and audio serving were misleading

Binding UDP previously implied an online engine; a simulated record could claim an
audio URL; creator-supplied data could affect sale authority; file streaming did not
adequately handle escaping symlinks, ranges and read failures.

Engine status now requires fresh valid observed telemetry and expires after two
seconds. Rendering remains explicitly simulated with no audio URL until a completion
and artifact-ingestion contract exists. Authenticated ownership is carried through
REST, MCP, HTTP ACP and native ACP stdio as trusted context. Display names do not
confer or transfer ownership. Only the owner can list/unlist a verified real specimen;
legacy unowned and simulated records cannot become listings.

Audio serving checks canonical containment and regular files, opens a descriptor
before headers, handles supported single ranges and suffix ranges, and controls
read failures. The directory hierarchy is assumed to be managed by trusted local
processes; this is not a defense against a hostile local process replacing ancestors
concurrently. Observed UDP telemetry is not authenticated engine identity.

### 9. AETHER relocation was incomplete at active consumers

CI referenced a removed security-test path; Docker copied missing/partial sources;
the listener referenced an undefined stream base; host and broadcaster defaults
disagreed; nested submission values or NUL could terminate the host. Submitted
lineage also reached an HTML construction path.

The consolidated paths now align across host, listener, broadcaster, CI and Docker
inputs. The standalone host and generator share workspace `out/live`; the container
explicitly chooses `/live`. Field validation and controlled process launch preserve
liveness. Lineage uses DOM text. Intake is disabled unless configured with a trusted
operator token, and public submission UI is withheld pending isolated fetching.
Only known playlist/segment/telemetry/lineage files are published through local and
edge reads; queue/generator records are excluded from new R2 syncs.

No Docker engine was available. The current image also lacks the optional AWS CLI
needed for R2 writes, and platform credential injection is not established here.
Previously uploaded objects were not deleted; an existing deployment needs its own
bucket audit. Source export/consolidation is not independent operational acceptance.

### 10. Packaging, dependency resolution and CI needed stronger evidence

Release copying previously swept working-directory state and could omit the built
workbench. The build now uses tracked source paths with explicit sensitive/runtime
exclusions, rebuilds the browser asset, labels dirty source, and rejects invalid
version labels (including overlong labels) before changing output. A preflight
rejects tracked symlinks, linked ancestors and nonregular sources, preventing ZIP
dereferencing from importing outside files. Both package locks now actually resolve OSC's
nested WebSocket dependency to the patched version; declaring an override alone had
left the vulnerable nested copy installed.

CI selects Node 24, quotes recursive test globs, restores AETHER security coverage,
runs complete Foundry/web suites, installs the Chrome revision declared by locked
Puppeteer and requires browser execution. Its installer uses the necessary root
privilege for Debian browser dependencies. A separate job installs native SC/JACK
and executes DSP plus real Forge NRT predicates. Release version input travels as
environment data rather than interpolated shell code. Hosted execution remains an
observed external gate, not something the local checks can certify in advance.
PR workflows now cover all base branches, addressing the missing Actions checks
on the open feature stack. Build provenance is unsigned checksum-bound metadata;
the SPDX inventory identifies the AGPL workbench boundary and makes no combined
license or complete dependency-inventory claim.

### 11. New launch/install entry points needed ownership and acceptance

The newly merged installer used unsupported `sclang -e`, exited before doing its
work when stock sclang rejected that option, and installed only six of the now
nine classes. The launcher accepted an unrelated HTTP 200 while its own child
failed, did not build the workbench, and left descendants running after termination.

Installation now exposes the recursive class directory, migrates only owned old
symlinks, refuses foreign duplicate classes (including behind directory links),
and verifies a real bounded file driver. The native runner uses supported `-l`
configuration, standard binary discovery, private language ports, and bounded
output/process cleanup.

The existing shell launcher delegates to a Python supervisor. It builds the
workbench, watches its own child's fresh startup banner and HTTP assets, and owns
each tier's process group through startup failure, unexpected exit and shutdown.
The human launch capability is forwarded to the local terminal and redacted from
persisted logs; environment-supplied tokens remain unprinted. Real web-only launch
served the workbench, bundle, module registry, substrate schema and AETHER listener,
then stopped successfully. Physical-device and full-loader behavior remains separate.

## Fresh local verification

The exact commands and source fingerprints are recorded in
[current integration evidence](2026-10-26-integration-evidence.json). The
[earlier receipt](2026-10-24-verification-evidence.json) records the preceding tree.

| Gate | Result | What it establishes |
|---|---:|---|
| Workbench unit/integration | 177 passed; 2 platform skips | Auth, protocol, lifecycle, providers, editor mapping, overlay and related server contracts |
| Foundry regression | 57 passed | Accounts, adapters, ownership, billing, telemetry and audio streaming |
| Required real-browser E2E | 10 passed | Page → gateway → UDP and playback ownership |
| AETHER plus engine-path regression | 10 passed | Nine AETHER predicates plus example engine path integrity |
| Native DSP | 8 passed | Nine classes/72 scripts; governor, metrics, telemetry, contracts, provenance/transformations and dummy-server lifecycle |
| Forge, native enabled | 11 passed | Real WAVs and render/publication failure handling |
| Release fixtures | 2 passed | Private-state exclusion, rebuilt asset and invalid-version behavior |
| Launch/install/runner/archive tools | 19 passed | Real process lifecycle, collision safety, bounded native runner, archive integrity and symlink exclusion |
| Strict repository smoke | 75 passed | Repository integration and bounded media paths |
| Foundry smoke | 21 passed | Local surface integration and actual fixture audio serving |
| Full npm audits, both packages | 0 findings | Advisory inventory at the time of the check |

The Linux web run explicitly skipped two macOS/Seatbelt-only assertions. All
other listed final runs completed without skips; the required real browser and
both native opt-ins ran. No macOS sandbox acceptance is inferred from Linux. Counts describe
different levels of grouping and overlap, so they should not be added into a claim
of independent coverage. A packaged archive launch/checksum check is recorded in the
handoff after building the committed source.

Independent review found and then reverified the AETHER, workflow, browser, legacy
payment, concurrent-buffer and normalization fixes. The root independently inspected
Forge and executed its complete suite. No critical/important finding remains open in
those reviewed changed slices. The separate open-stack findings remain listed in
the stack review; this does not certify the untouched system globally.

## Critique of the development process

The principal problem was the distance between an appealing capability description
and the acceptance test beneath it. A bound socket became an engine; an old output
became a new render; a fixture became an adapter; a structural CI check became an
operational claim. The project benefits more from honest state and completion
contracts than from another layer of interfaces.

The review sequence also allowed findings to arrive after integration. PRs 71, 74,
75 and 76 merged within seconds; PR81 merged before its later review findings.
Main had no enforced protection in the observed repository state. The original
[full CI run](https://github.com/4444J99/alchemical-synthesizer/actions/runs/40127111860)
failed on the moved AETHER test path. Removing that invocation in PR80 reduced
coverage rather than preserving the relocated predicate. This branch restores it.

The current upstream baseline improved: [full CI on e27f020](https://github.com/4444J99/alchemical-synthesizer/actions/runs/40208921091)
succeeded on October 25, including a real unpacked-release launch. That is distinct
from the earlier failed baseline and from the combined branch being verified here.
The supplementary inventory nevertheless found failing full Smoke checks on nine
of the ten newly merged PR heads, seven merges within 3–46 seconds, and no recorded
`APPROVED` review among those ten. PR94's successful check and merge share a one-second
timestamp, so their order cannot be established from that precision.

Direct writes also briefly replaced the server with literal `PLACEHOLDER`
([88ab801](https://github.com/4444J99/alchemical-synthesizer/commit/88ab801721a02de930d4935a00938c1a128c3b9b))
and the smoke script with literal shell-substitution text
([deecbc2](https://github.com/4444J99/alchemical-synthesizer/commit/deecbc22a3b60814b475d34344c0604a6cf347a9)).
Later commits repaired them. Minimal-CI/status receipts were insufficient to catch
these functional regressions. Read back every written file, inspect the diff, and
execute the real path before treating a write or green receipt as completion.

Recommended integration policy: wait for the required substantive gates and review
against the exact head revision. Treat a resolved thread, closed issue or merged PR
as history, not as a substitute for a reproduced result. Do not silently skip a
required runtime. Keep the current two-item implementation limit. Repository rules
and required-check configuration were not changed by this pass.

## Next milestones

1. **Acceptance baseline and launchable distribution.** Observe hosted checks,
   independently run the actual archive/container, make optional MIDI initialization
   nonfatal, verify full-loader routing/shutdown/re-entry, and then publish release
   assets with checksums. Keep physical MIDI/Pd/Ableton and listening decisions explicit.
2. **One measured donor-to-artifact workflow.** Capture input/output with provenance,
   derive the defined metrics, validate a trait contract, perform one transformation,
   record render completion/ownership and play the verified WAV. Reconcile the existing
   PR97–102 sampling stack onto this foundation and repair its transport handoff,
   donor-pause, A/B-range and renderer-meter findings. Execute successful transformations
   as well as rejection paths, then connect Foundry after completion/artifact ingestion
   exists. Retain explicit capture trust and a human before/after listening decision.
3. **Independently operable AETHER.** Specify donor/tone versus optional NRT dependencies,
   verify a standalone checkout and actual image, isolate public URL fetching, establish
   R2/credential injection, and rehearse sustained streaming plus restart/rollback.

Real alternative-language adapters and production commerce follow those foundations.
The current artistic direction—contact, transformation, lineage and re-expression—
remains intact; the next milestone should make one instance of it observable end to end.
