---
date: 2026-10-25
slug: verify-and-repair-release-artifact
status: EXECUTED
closure: PR #92 → ab8b569 (merged, squash)
---

# Plan — Verify and repair the release artifact (2026-10-25)

## Context

This plan is **retroactive**. The work was performed under `/verify` without a pre-authored plan; this file records what was done so the lane's plan discipline is not violated by omission. Per the plan-discipline rule ("Plans are artifacts — after writing a plan, commit and push it") and the closeout ritual, a session that produced a merged PR must leave a plan record.

No pre-existing plan authored this session → named here as a gap, now closed by this file.

## Objective

Verify the alchemical-synthesizer honestly from live evidence (`/verify`, run twice) and repair only what verification proves broken. Constraints: $0 additional API spend, no direct push to `main`, status words evidence-bound, fix bases not gates.

## What was verified (first pass, at `b028fcf` == `origin/main`, clean)

- `tools/smoke.sh`: 74 passed / 0 failed / 0 skipped
- web tests (`brahma/web`, `node --test test/`): 147 / 147
- `product/bin/smoke.js`: 21 passed / 0 failed
- native SC `phase_a` / `class_runtime` / `flucoma_buffer`: all `BRAHMA_TEST_PASS`
- CI security regression tests: 12 / 12
- `tools/build_release.sh`: builds `v1.0.0-115-gb028fcf`

## Defect proven (not inferred)

`tools/build_release.sh` copied the working tree with `--exclude='*/vendor'`. The only `vendor/` directory in the repository is the built workbench bundle (`brahma/web/public/workbench/vendor/workbench.js`, 955 KB, gitignored), and `brahma/web/public/workbench/index.html:49` loads it as the page's entry module. Every release artifact shipped a workbench page whose own script 404s. `make dist` never built the bundle either.

Evidence: `tar -tzf dist/*.tar.gz | grep 'workbench/vendor'` → no output, while `ls -l …/workbench.js` → 955078 bytes.

## Repair

Branch `fix/release-artifact-workbench-bundle` → PR #92 → merged `--squash --match-head-commit b99fd38…` → `ab8b569` on `origin/main`.

`tools/build_release.sh`:
- drop `*/vendor` from the tar exclude list (the bundle is a runtime asset, not a vendored binary; nothing else was protected by it)
- refuse to pack when the bundle is absent, naming the exact build command
- assert the bundle survived staging, so a future exclude pattern cannot silently strip it again
- `shellcheck` clean, `bash -n` clean

## Verification of the repair (second pass, at `ab8b569`, clean)

- smoke re-run: 74 passed / 0 failed / 0 skipped
- artifacts rebuilt: `v1.0.0-116-gab8b569.tar.gz` + `.zip`, both contain `brahma/web/public/workbench/vendor/workbench.js` (955078 bytes)
- end-to-end from a clean unpack: `npm ci` (116 pkgs) → boot `server.js` → `GET /` 200, `/workbench/` 200, `/workbench/source.json` 200, `/workbench/vendor/workbench.js` 200 / 955078 bytes
- guard test: bundle moved aside → `build_release.sh` exits 1 with the remediation message; bundle restored
- CI at `ab8b569`: `CI Minimal` success, `pages-build-deployment` success, `CI` failure (pre-existing runner-level stall, signature unchanged: `server: alive (Sl), listening=0`, 64/7/1)

## Closure marks

- EXECUTED: PR #92 (merged `ab8b569`), verified end-to-end at runtime
- No atoms touched this session (atom registry untouched)
- No IRF entries created (lane convention tracks closeout via plan files)

## Out of scope (named, not swept)

- CI `Smoke test (shipped-test)` runner-level non-bind — needs console access (BLOCKED)
- `axis_labels` has zero consumers in `brahma/substrate/*.json` — schema divergence, not a break
- Host-global `~/.config/git/attributes:132` `tests export-ignore` — chezmoi source
- `aether/deploy/Dockerfile:32` stale `COPY deploy/aether/…` — owner AETHER extraction lane; no docker on host to verify
- Another session pushes directly to `main` (`1b3d1e2`, `def46fd`, `2298e05`, `f671572`) — operator action
- Release publication (tag push) — human gate; artifacts local and gitignored
EOF
echo written