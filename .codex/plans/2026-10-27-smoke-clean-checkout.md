# Clean-checkout smoke repair

Owner: Codex music-reconciliation subtask, isolated branch
`fix/smoke-clean-checkout-20261027`, based on `origin/main` at `8a850ced`.
Scope: `tools/smoke.sh` dependency ordering and invocation-owned npm diagnostics.

1. Reproduce native sample service failures without installed web dependencies.
2. Reuse PR #104 commit `9bd58bec73fba5e0ad107440a9c85477685f7194`
   with its original attribution; leave the peer branch unchanged.
3. Allocate one unique npm log for the invocation, share it between both install
   sites and boot diagnostics, then remove only that log after diagnostics finish.
4. Run `bash tools/smoke.sh --strict` from this clean checkout with a hard deadline,
   inspect existing listeners first, and retain actual pass/fail observations.
5. Publish the isolated branch for parent integration; do not create or merge a PR.

## Initial observations

- Native worktree creation cannot resolve this home-directory task as a Git repo;
  the manual worktree fallback created the isolated checkout from the fetched main.
- Repository worktrees and branches were inspected; Conductor reported no active
  sessions. The peer PR #104 branch is remote-only in this clone and was untouched.
- No TCP listener occupied the smoke port 3939 before verification.
- With no `brahma/web/node_modules`, `node --test
  brahma/web/test/native-samples.test.js` exited 1: seven failures reporting
  `MODULE_NOT_FOUND` for `express`, plus one separately opt-in native-render skip.
- Main installs dependencies in section 5, after section 3 already requires them.
  Both the proposed early install and existing late install use the shared fixed
  `/tmp/brahma_npm.log`, which can mix diagnostics across invocations.
