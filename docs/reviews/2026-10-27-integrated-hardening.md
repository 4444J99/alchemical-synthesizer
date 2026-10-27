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

The initial inspected archive was built from clean source commit
`2409fde5e5cefb34ef605f49378dc0d89953c9e3`; the later browser-discovery fix changes
the test harness only at that checkpoint. The retained tar and ZIP contain 470 source files and the same
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
full integration observations. The labelled-Strudel cancellation finding has its
separate browser/protocol evidence below.

## Independent review: cancelled labelled evaluations

The reviewer reproduced a cancelled pending source containing `$: note("c4")`
registering C4 into a newer pending source that requested D4. Upstream Strudel
rewrites labels into `pattern.p(label)` and replaces that prototype method for
each repl. The adapter now captures the evaluation's `p` and `cpm` methods and
rewrites their call sites using the already-installed parser/code generator.
Their exact existing versions are direct locked dependencies; upstream source
is unchanged. Labelled patterns remain supported, with responsive Stop and Run.

The actual browser/gateway regression failed before the repair (60 instead of
62). It now passes with plain and labelled successors, plus an ordinary JavaScript
`p` getter/method retaining its receiver. All 11 workbench browser checks and 54
affected workbench/protocol checks passed. An initial post-edit run still used the
old generated bundle and failed; that attempt is retained as
`strudel-label-review-stale-bundle.txt`. Explicit rebuilding preceded the passing
runs. Two ephemeral human launch capabilities were redacted from the web log.

The earlier release archives and full-suite results remain historical: they
precede both independent-review repairs. The updated bundle's hash/size and
source identities are in `strudel-label-review-receipt.json`. Refreshed archive
acceptance follows below. Pattern code remains trusted JavaScript, with the
side-effect and sandbox limitations documented in the workbench README.

## Refreshed release after accepted review fixes

After the parent independently accepted both repairs, the release builder ran
from clean source commit `1d9fa17576c9b6e24a308ebd7219569f592a742c`. The tar and
ZIP each contain 515 files, including the same 957695-byte corrected workbench
bundle. The actual tar passed safe extraction, locked dependency installation,
all seven HTTP checks, bundle identity and source-revision checks. The ZIP passed
structure inspection. The provenance records `source_state: clean`.

| Archive | SHA-256 |
| --- | --- |
| `dist/alchemical-synthesizer-integration-20261027-1d9fa17-reviewed.tar.gz` | `5caa6f7a67730cfb165850af23d33aee773f4ea45c6a8917c42736aad0cd0e07` |
| `dist/alchemical-synthesizer-integration-20261027-1d9fa17-reviewed.zip` | `441841a2073825b1cadc25d34282a9dd3ed372031dce274e64e9d3e6e64a5d84` |

The previous five artifact files were moved unchanged into a unique directory
under the configured custody staging root before rebuilding. Every retained file
matched its pre-move hash, and both earlier archives still match the original
release receipt. `reviewed-release-artifacts.json` records their retained paths,
the new archive sizes/hashes and bundle identity. `reviewed-release-gate-receipt.json`
records the original bounded commands and results; logs retain all three passes.
No implementation file changed during this refresh. Its later evidence commit
contains report/receipt additions only. No public release or deployment occurred,
and no unrelated full suite was repeated.
