# Verification and hardening design — 2026-10-24

## Intent and authority

The current request is to review existing work, verify it, harden it, critique it,
and advance the repository. This pass repairs demonstrable failures in existing
contracts. It does not create a new product architecture or authorize a merge,
release, deployment, paid provider call, repository split, or visibility change.

Starting revision: `bf6c8257ac976efaf526ae1b612bb7371f96f64a` in
`4444J99/alchemical-synthesizer`. Work occurs on an isolated `fix/` branch.

## Approach

A path-only CI repair would leave runtime, audio, and distribution defects.
Adding new engines or interfaces would expand unverified behavior. The selected
engineering approach is to repair the existing boundaries with executable
evidence and preserve the current Brahma / Forge / AETHER ownership layout.
This is an implementation judgment under the current hardening request, not a
claim that the user approved a new creative direction.

## Required behavior

- Human stop requests reach the renderer, terminate its process group, make
  cancellation terminal, and prevent queued work from starting. Agents retain
  the propose-only boundary. Malformed authentication data cannot crash a server.
- Optional provider discovery never blocks gateway startup. Unconfigured models,
  absent runtimes, and demonstration fixtures cannot claim working composition.
- AETHER's consolidated source paths work for CI, Docker inputs, local intake,
  listener routes, and the shared live-output location.
- Release packages include executable workbench assets and only intended source
  files; runtime tokens, environment files, caches, output media, and local stores
  stay outside the archive. Invalid version labels fail before changing output.
- The output governor overwrites its protected bus. Metrics execute against
  actual sample data, report unavailable input honestly, and name what they
  measure. Native checks distinguish compilation, NRT rendering, and live/audio
  acceptance.
- Verification records identify exact revisions, command outcomes, and remaining
  limits. Green minimal CI or an old merged PR is not full acceptance.

## Constraints and acceptance

Keep existing public APIs compatible where practical; use small additions where
needed to express cancellation and measurement state. Keep at most two active
implementation items. Prove important bugs with failing tests, then rerun the
affected tests and integrated checks. Do not weaken security gates. Preserve
history and all unique work. No bulk cleanup or unrelated restructuring.

Final acceptance for this pass is reviewed changes, locally reproduced checks,
a concrete evolution plan, and a reviewable branch/PR when publication is
available. Hosted CI, physical-device performance, paid APIs, and artistic
listening acceptance remain separate predicates.

## Evidence-driven scope update

Upstream advanced during review to `24651b0`, including a new contract/trait-overlay
feature. It was reconciled into this branch before further verification. Reproduced
failures expanded this pass to browser transport/evaluation ownership, Foundry
payment and specimen authority, and Forge publication integrity. These remain
repairs to existing advertised behavior. The native metric review also required
coalesced, offset-tracked Buffer reads and a final normalization-validity check.
AETHER public URL intake is closed pending isolated fetching; trusted-operator
intake remains available behind explicit configuration and authentication.

The next feature milestone is a measured donor-to-artifact workflow. Its capture,
completion and listening acceptance are not claimed by this hardening pass.
