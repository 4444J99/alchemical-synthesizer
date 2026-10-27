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
