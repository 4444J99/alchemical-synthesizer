# PR / Issue Evolution Report — `alchemical-synthesizer`

**Date:** 2026-11-17  
**Stream:** B (PR / Issue Evolution) of the Autonomous Ecosystem Retirement & Enrichment plan  
**Method:** full remote inventory via `gh` (all states), heuristic supersession detection, local git/oss evidence. Machine-readable evidence: `.opencode/plans/stream-b/2026-11-17-pr-issue-data.json`  
**Staging run:** `09_Engineering/custody-staging/run-20261117-104235-session-retirement/`

> Supersession links below are **evidence-backed candidates**, not licensed merges. No remote PR was closed and no history was rewritten by this pass. Destructive actions are listed as ready-to-run commands for the owner or the orchestration stream.

## 1. Repository state

| Field | Value |
|---|---|
| Local path | `/Volumes/Archive4T/Projects/alchemical-synthesizer` |
| GitHub remote | `4444J99/alchemical-synthesizer` |
| Upstream archived | no |
| Default branch (remote) | main |
| Local branch | `main` |
| Dirty files | 0 |
| Linked worktrees | 1 (canonical checkout) |
| Last commit | 2026-10-25T11:51:26 — fix: unblock web startup and verify clean release artifacts (#94) |
| Plan surfaces | .codex/plans, .claude/plans |

## 2. PR inventory

| Metric | Count |
|---|---|
| PRs (all states) | 107 |
| Merged | 83 |
| Open | 0 |
| Closed unmerged | 24 |

Closed-unmerged classification:

| Class | Count |
|---|---|
| closed without successor | 16 |
| superseded (rewrite series) | 8 |

## 3. Evolution decisions (old → new)

| Old PR | Old title | Successor | Basis |
|---|---|---|---|
| #8 | chore(deps): bump the npm_and_yarn group across 1 directory with 2 updat | #51 | superseded (rewrite series) |
| #13 | chore(deps): bump the npm_and_yarn group across 1 directory with 3 updat | #51 | superseded (rewrite series) |
| #46 | chore(deps): bump qs from 6.15.2 to 6.16.0 in /product in the npm_and_ya | #53 | superseded (rewrite series) |
| #48 | chore(deps): bump ws from 8.21.3 to 8.22.0 in /brahma/web in the npm-dep | #116 | superseded (rewrite series) |
| #54 | chore(deps): bump the npm-deps group across 1 directory with 2 updates | #117 | superseded (rewrite series) |
| #72 | Merge PR #47: security hardening (resolved against main) | #73 | superseded (rewrite series) |
| #84 | Fix SuperCollider crash probes and validate native Brahma measurements | #86 | superseded (rewrite series) |
| #85 | Fix SuperCollider crash probes and validate native Brahma measurements | #86 | superseded (rewrite series) |

### Repo-level absorptions

| Archived source | Lives now at | Evidence |
|---|---|---|
| 4444J99/audio-synthesis-bridge (archived upstream) | this repo, `legacy/` | PR #112 `chore(legacy): import scrubbed snapshot` |
| 4444J99/universal-waveform-explorer | this repo, `legacy/` | PR #111 `chore(legacy): import scrubbed snapshot` |

## 4. Items marked archived

- **83 merged PRs** — resolved, no action; history is the archive.
- **8 closed-unmerged PRs with a traced successor** — archived as superseded; each row in §3 is a complete old → new mapping.
- **16 PRs closed without a traced successor** — archived as abandoned. Titles are retained in the evidence file in case a later re-cut needs the original scope.

## 5. Open PR triage

_No open PRs._
## 6. Issues

| Metric | Count |
|---|---|
| Issues (all states) | 10 |
| Open | 3 |
| Open and idle > 45 days | 0 |

Most common labels on open issues: `jules` (1).

## 7. Follow-up flags

- No open follow-ups: this repo is at lifecycle steady state.

## 8. Provenance and limits

- PR/issue inventory: `gh pr list`/`gh issue list --state all` for `4444J99/alchemical-synthesizer`, captured 2026-11-17.
- Supersession classes: explicit `supersedes #N` in title; dependency retry (same package + directory, newer bump merged); rewrite series (identical title stem, later PR merged); producer retirement (Limen/Jules branch, no successor); otherwise abandoned.
- Heuristic limit: a title-stem match can link two genuinely different changes. Treat §3 as a review queue, not as settled provenance.
- No remote mutation was performed: no PR closed, no issue closed, no branch deleted.
