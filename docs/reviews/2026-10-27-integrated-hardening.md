# Sampling and hardening integration evidence

Observed on macOS, 2026-10-27. The integration branch starts from main
`d67514b7c48fb1fdac49915c72629c305f263374` and merges PR #103 source
`e341f3be9dcb356dbfa169c18455a2676aea974d` with its ancestry intact. The peer
branch was not changed. Existing sampling, native, provider, release and smoke
checks remain present; CI also retains the additional hardening gates.

## Reconciliation

- Resolved the CI conflict by keeping both sets of tests, including Foundry smoke.
- Verified automatic merges retain native-sample routing and shutdown, early web
  dependency installation, and one temporary npm diagnostic log per invocation.
- Corrected macOS test fixtures: use Meta+A in Chrome, compare resolved installer
  paths, and configure the offscreen Qt plugin only on Linux.
- Wait for complete downloaded project JSON before checking its exact recipe.
- Require sample browser acceptance to honor the configured Chrome path and
  required-browser flag; support the existing disposable-CI sandbox opt-in.
- Annotated four confirmed secret-scan false positives: an environment lookup and
  synthetic local payment fixtures. No actual credential was added.

## Current local results

| Gate | Observed result | Evidence file in 2026-10-27-integration-logs/ |
| --- | --- | --- |
| Web unit/integration | 204 pass; 1 opt-in native skip | web-tests.txt |
| Installed native sample admission | 8 pass, including skipped case above | native-sample-admission.txt |
| Foundry regression | 57 pass | foundry-tests.txt |
| AETHER and engine paths | 10 pass | aether-tests.txt |
| Required configured-browser acceptance | 26 pass; 0 skip | browser-tests-configured.txt |
| Python tools and installed donor checks | 48 pass | python-tests-fixed.txt |
| Native DSP/contracts/compilation | 7 pass; 1 Linux dummy-JACK skip | native-dsp.txt |
| Forge wrappers and actual NRT renders | 11 pass | native-forge-fixed.txt |
| Release isolation | 2 pass | release-isolation.txt |
| Strict smoke | 107 pass; 0 skip | strict-smoke.txt |
| Foundry smoke | 21 pass | foundry-smoke.txt |
| Both complete npm dependency audits | 0 findings | web-audit.txt; foundry-audit.txt |
| Actual release tar | Safe extraction, locked install, 7 HTTP checks, exact bundle and source revision | release-tar-runtime.txt |
| Actual release ZIP | Structure valid | release-zip-structure.txt |

The initial browser, installer and Forge failures are retained in the original
logs. The first browser rerun also exposed the incomplete-download race; its
failure is retained in browser-tests-fixed.txt. Subsequent logs identify each
correction. Counts overlap; they are not additive test coverage.

Every test command ran with a hard wall deadline and low process priority. JSON
receipts record commands, relevant opt-ins, deadlines, elapsed time and exit codes.
Two ephemeral human launch capabilities were redacted from web-tests.txt. The
receipts do not include environment secrets. Log hashes are in evidence-sha256.json.
Port 3939 was free before and after the tests; unrelated existing listeners and
installed runtime configuration were not changed.

## Acceptance boundaries

The inspected archive was built from clean source commit
`2409fde5e5cefb34ef605f49378dc0d89953c9e3`; the later browser-discovery fix changes
the test harness only. The tar and ZIP contain 470 source files and the same
956838-byte workbench bundle. Archive hashes and sizes are recorded in
release-artifacts.json. The test artifacts remain in the retained checkout's
ignored dist directory; no public release or deployment was performed.

Linux dummy-JACK acceptance remains configured in CI and was not run on this
macOS host. Hosted CI, independent review, PR creation and repository merge belong
to the parent task. Full-rack device audio/MIDI/Pd/Ableton, artistic acceptance,
actual radio hosting and production billing/storage remain separate acceptance.

## Independent review: required trait structure

The final review reproduced a regression in the canonical native trait validator:
empty required objects, and nonfinite/nonnumeric leaves outside a declared range,
were accepted. Required dimensions now receive recursive structural validation
before range checks. Numeric metadata such as `sources: 24` remains unbounded
when its contract has no range; categorical `type` metadata is preserved.

The native regression checks every canonical dimension for an empty object,
positive/negative infinity, NaN and a nonnumeric leaf, both during validation and
normalization. It failed before the repair. The scoped native contract test and
all repository SC source compilation passed after the repair (2 tests). Logs are
`contracts-review-red.txt` and `contracts-review-green.txt` in the existing log
directory. These scoped results supplement, rather than replace, the earlier
full integration observations. A separate labelled-Strudel cancellation finding
remains under repair and is not covered by the native contract checks.
