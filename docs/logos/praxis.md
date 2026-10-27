# Praxis — The Next Acceptance Milestones

The current [Pragma](pragma.md) establishes sample-derived measurements and more
substantive regression gates. The next advance is to connect those building blocks
into one trustworthy musical workflow. Expanding the module catalog first would
increase the surface that remains unverified.

## 1. Establish the release baseline

- Land the reviewed hardening branch only after hosted gates are observed passing.
- Require full web/Foundry regressions, real-browser acceptance, native DSP and
  render-wrapper checks, and release isolation.
- Build and launch the actual distribution in a clean environment; publish archives
  and matching checksums only after that test.
- Make optional MIDI initialization nonfatal and verify the full loader's routing,
  responder installation, governor ordering, shutdown and re-entry.
- Finish AETHER's real container build and bounded restart/shutdown checks.

Acceptance: an identified revision, reproducible commands, downloadable artifacts,
and an honest list of platform prerequisites. A minimal green check is insufficient.

## 2. Complete one measured audio-to-artifact workflow

Use a documented donor recording and one transformation path:

1. Capture input and output with channel, rate, time window and alignment recorded.
2. Compute the documented metrics and validate the appropriate trait contract.
3. Feed measured values and their provenance to the trait view; preserve unavailable
   state if any capture or analysis step fails.
4. Render a validated WAV, record completion and ownership, and make it playable.
5. Listen to the donor/output pair and record a human acceptance decision separately
   from numerical validity.

Connect Foundry's render action only after completion and artifact ingestion exist.
Repair FSAP donor handling and the A/B benchmark as part of this vertical workflow.
FluidBuf can expand analysis later; it is not a prerequisite for the implemented
core FFT/correlation measurements. `strictness` is contract metadata, not a measured
quality threshold.

Acceptance: a real donor → transformation → measured result → playable artifact,
with failure, timeout, cancellation and stale-result paths demonstrated.

## 3. Make AETHER independently operable

- Specify the donor/tone baseline and optional Brahma/Forge NRT dependency.
- Validate a standalone checkout, Docker context, listener and bounded broadcast.
- Add an isolated fetch service before reopening public network submissions.
- Establish the R2 write toolchain, credential injection, deployment and rollback.
- Run a sustained stream trial with restart, segment continuity and provenance checks.

Acceptance: an independently runnable distribution with observed operational
behavior. Source export alone does not satisfy it.

## Subsequent capability work

Real Tidal/Sonic Pi adapters need a documented bridge and round-trip acceptance.
Commerce needs transactional storage, subscription/refund/dispute reconciliation
and payout delivery before production use. Broader trait dimensions, distributed
OSC, VCV integration and new visual substrates should follow measured workflow
and listening evidence.

Keep no more than two implementation items active. For each milestone, define the
failure examples and acceptance artifact before marking a roadmap item complete.
