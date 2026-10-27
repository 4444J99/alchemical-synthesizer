# Verification and Hardening Implementation Plan

> **For agentic workers:** Apply systematic debugging and test-driven development;
> root coordinates independent tasks and reviews the complete change.

**Goal:** Repair failed runtime, distribution, and DSP contracts with reproducible evidence.

**Architecture:** Preserve existing organ boundaries and APIs. Put lifecycle state
in its owning runner, keep provider discovery asynchronous, use the consolidated
AETHER paths, and add native DSP predicates alongside the existing web checks.

**Tech Stack:** Node.js, SuperCollider, Python, Bash, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-24-verification-hardening-design.md`

## Global constraints

- Baseline is `bf6c8257ac976efaf526ae1b612bb7371f96f64a`.
- Preserve human acceptance/run control, organ ownership, and original history.
- No paid calls, deployed changes, merges, or repository restructuring.
- At most two active implementation items; other workers perform read-only review.
- Do not treat technical checks as auditory/artistic acceptance.

## Review focus

1. Cancellation before launch, during work, after completion, and with queued work.
2. Absent or slow optional runtimes and configured keys without a model.
3. A release built after real local usage, with private runtime files present.
4. AETHER entry points from the repository and staged container layout.
5. Silence, invalid samples, repeated notes, and above-threshold native audio.

## Task 1 — Runtime control and authentication

Files: `brahma/web/lib/agent/{jobs,tools,index}.js`, MCP adapters, `server.js`,
`lib/auth.js`, and focused `brahma/web/test/` regressions.

- [x] Reproduce stop-role, process-handle, snapshot-state, and malformed-auth failures.
- [x] Implement runner-owned terminal cancellation and actual process-group termination.
- [x] Preserve agent restrictions and pass the authenticated human actor in adapters.
- [x] Run focused HTTP/MCP/lifecycle regressions and existing workbench tests.

## Task 2 — Distribution and AETHER integration

Files: `tools/build_release.sh`, `tools/smoke.sh`, `.github/workflows/`,
`aether/deploy/`, `aether/tools/`, listener mount, and release/integration tests.

- [x] Reproduce missing Docker/CI sources, listener/intake/default-output failures,
      and ignored runtime-file inclusion in a temporary release fixture.
- [x] Fix active path consumers, preserve AETHER security coverage, and use a
      source allowlist plus explicitly rebuilt workbench assets in packages.
- [x] Run security tests, strict smoke, distribution checks and container-source
      validation; run Docker only if an actual engine is available.

## Task 3 — Truthful, responsive providers

Files: `brahma/web/lib/agent/providers.js`, provider tests, provider MCP schema.

- [x] Prove construction stays responsive with a slow optional executable.
- [x] Make probes asynchronous/bounded and state local to each registry.
- [x] Require explicit model configuration and reject malformed event submissions
      without falling through to a paid provider.
- [x] Label unimplemented adapters unavailable instead of returning fixed fixtures.
- [x] Verify configured Gemini is discoverable over MCP without a live paid call.

## Task 4 — Native DSP safety and measurement

Files: safety governor, metrics collector, native tests, and directly affected SC
loading/call sites. Scope follows native reproduction, not speculative rewriting.

- [x] Install/use headless SuperCollider and capture baseline compilation failures.
- [x] Prove governor clipping/quarantine behavior with an NRT waveform fixture.
- [x] Repair unsafe bus output and invalid/asynchronous sample measurement code.
- [x] Test silence, invalid input, stationary tone, changing tone, and noise;
      expose missing measurement as unavailable.
- [x] Record full-loader/live hardware limits separately from focused predicates.

## Task 5 — Independent review and closeout

- [x] Review full history and unresolved threads; classify current versus repaired findings.
- [x] Verify the complete change independently; fix concrete important findings.
- [x] Run integrated checks and bind their results to the final revision.
- [x] Write the review/evolution report with exact links and residual acceptance work.
- [x] Publish the prepared branch/PR and observe hosted checks; final handoff records
      publication separately from integration. No merge or deployment is authorized.

## Progress and rulings

- Baseline: full hosted CI fails on the old AETHER test path. Correct-path local
  security regressions pass 14/14. Foundry smoke passes 21/21.
- Baseline web suite fails three availability assertions on an absent GHCi host;
  initial default-sandbox socket failures were environment restrictions and were
  rerun with authorized loopback access.
- This pass uses the current hardening request as authority for reversible fixes;
  historical closeout approvals do not authorize integration.

## Scope added from reproduced evidence

- [x] Reconcile concurrent upstream work through `24651b0` without losing the original
  changes; all 36 pre-reconciliation file hashes were preserved.
- [x] Repair workbench active-document, registration identity, cancellation, and
  stale asynchronous helper ownership; verify ten real-browser cases.
- [x] Repair the concurrently merged JSON contracts and trait overlay; test empty
  selection, current data, viewport bounds and explicit proxy values.
- [x] Verify and harden Foundry payment authority, legacy USD compatibility,
  authenticated ownership, observed engine state, and audio containment/ranges.
- [x] Repair Forge stale-output acceptance, native exit handling, paths, durations,
  format/payload verification and atomic publication; run eleven native/fixture groups.
- [x] Resolve independent-review findings for concurrent Buffer reads, inconsistent
  normalization, AETHER malformed fields/default paths, and CI runtime/installer contracts.
- [x] Refresh nested WebSocket overrides and verify both complete dependency audits
  report zero known findings after clean locked installs.
- [x] Correct active documentation while preserving generated sections and the
  historical roadmap. Record production and hardware limits in the review.

Initial pre-e27f020 local functional verification: web 171, Foundry 57, browser 10, AETHER plus
engine-path 10, native DSP 6, Forge 11, release fixtures 2, strict smoke 74,
Foundry smoke 21; every listed run passed with no skips. Packaged-build and hosted
publication evidence are recorded in the final handoff, not inferred from these counts.


## October 26 upstream reconciliation

- [x] Preserve the complete 100-path checkpoint and reconcile 28 upstream commits
  through `e27f020`; inventory 137 main commits and 93 PRs at the recorded snapshot.
- [x] Integrate shared class/collector metrics, schema/provenance contracts and
  native transformation APIs; execute phase/class assertions under SC 3.13.
- [x] Repair fabricated proxy confidence; verify a successful compatible proxy
  transformation while rejecting stale evidence for measured targets.
- [x] Repair recursive class installation, portable native runner and supervised
  launch ownership; preserve human capability handoff without persisted tokens.
- [x] Preserve both archive checkers and reject symlinked sources/ancestors and
  overlong labels before touching existing output; correct unsigned metadata scope.
- [x] Restore gateway role/pong behavior and integrate probe cancellation.
- [x] Enable PR CI for stacked base branches and document four current-head
  findings in the separate unmerged sampling/UI stack.

Current combined checks: web 177 passed / 2 macOS-only skips, Foundry 57, Chrome 10,
AETHER + engine-path 10, native 8, Forge 11, tool regressions 19, release fixtures 2,
strict smoke 75, Foundry smoke 21. Both full npm audits report zero findings.

Publication: draft PR103 is open. Initial remote head 2eb21e1 has full CI running
and CI Minimal successful; final public-head results belong to the final handoff.
The actual committed-source archive passed checksums, clean install and seven HTTP
checks. Main remains e27f020 and has not been merged by this pass.
