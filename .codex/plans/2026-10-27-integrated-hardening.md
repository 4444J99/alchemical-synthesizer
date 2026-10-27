# Integrate reviewed hardening with the sampling instrument

Owner: Codex repository-reconciliation subtask. Branch:
`integrate/verified-hardening-20261027`, based on freshly fetched main
`d67514b7c48fb1fdac49915c72629c305f263374`.

1. Merge PR #103's source head `e341f3be9dcb356dbfa169c18455a2676aea974d`
   with ancestry and authorship intact, without changing its peer branch.
2. Reconcile CI by retaining both main's sampling/browser/release checks and
   PR #103's render/release/Foundry/native gates. Preserve the merged early
   dependency installation and unique npm diagnostic log in the smoke path.
3. Inspect automatic merges in the server, README and smoke script for semantic
   integration defects. Preserve all intended capabilities and evidence limits.
4. Run bounded implicated web, browser, Foundry, Python, native and smoke gates;
   retain failures and observations rather than weakening checks. Inspect running
   listeners before launching isolated test servers. Do not alter global settings.
5. Commit and push the integrated branch with its verification evidence. Parent
   performs independent review and owns PR creation and merge.

The existing isolated smoke checkout is clean and its earlier branch is remotely
preserved. No other worktree, private musical history, installed runtime or
deployment is part of this mutation scope.

## Execution checkpoint - 2026-10-27 15:10 UTC

The integration merge is committed as `b99a99c`; PR #103 remains untouched.
`eb837be` fixes macOS fixture assumptions (Select All modifier, canonical temporary
path and Linux-only Qt setup). `2409fde` waits for the native project download to
contain complete JSON. Original failures remain in the integration log directory.

The merged web, Foundry, AETHER, Python, native DSP/Forge and smoke gates have run.
The full browser suite passed 26 tests with zero skips after fixture correction.
A clean-source archive at `2409fde5e5cefb34ef605f49378dc0d89953c9e3` passed
safe extraction, locked install, seven live HTTP checks, bundle/source revision
matching, and ZIP structure checks. No archive was published as a release.

A final CI fixture correction makes instrument acceptance honor the configured
browser path and required-browser setting already used by the workbench suite.
The configured-browser rerun and installed native-sample admission test are in
progress under process deadlines. Remaining steps: record their results, scan and
commit evidence, push, and hand the exact head to the parent reviewer. There are
no active earlier runner processes. The retained `dist/` contains the inspected
archive; do not remove the checkout or installed dependencies as session cleanup.

## Final local verification

Configured Chrome acceptance passed all 26 tests; installed native sample admission
passed all 8 tests, including the initially skipped native pipeline test. No test
process remains running. The full evidence report is
`docs/reviews/2026-10-27-integrated-hardening.md`; original failures are retained.
The branch is ready for parent independent review after publication.

## Independent review follow-up

The parent assigned this checkout and branch to the independent reviewer as sole
writer for two accepted findings. Required native trait dimensions again reject
empty, nonfinite and nonnumeric structure while preserving finite metadata counts.
Actual native regressions failed before the fix; the scoped contract and source
compilation tests passed afterward. Keep this fix atomic. A second atomic change
will isolate labelled Strudel evaluation state during cancellation and replacement;
the parent will independently inspect both fixes before its exact-head PR.
