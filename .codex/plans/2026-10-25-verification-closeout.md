# Verification repair implementation plan

**Goal:** Repair reproducible defects from verification, prove the shipped behavior,
and land the owned changes through an exact-head PR. Owner: issue #93.

**Architecture:** Capability discovery runs asynchronously without delaying HTTP.
Release packaging selects tracked source plus the explicitly built workbench asset,
independent of host export-ignore attributes. Artifact verification exercises the
unpacked release and refuses missing assets or private runtime state.

**Tech stack:** Node.js, Bash, Python standard library, GitHub Actions.
**Spec:** https://github.com/4444J99/alchemical-synthesizer/issues/93

## Constraints and admission

- User authorized host-pressure override on 2026-10-25, one writer, serial checks,
  no overall time limit. Individual subprocesses remain bounded.
- No paid APIs, Docker startup, direct trunk push, relaxed measurement gates,
  provider removal, synchronous CI waiting, or changes to other sessions' worktrees.
- Base: ab8b569a7548f17b1e8d671ae4244856e2ef7d63.
- Owned checkout: Workspace/.worktrees/alchemical-verify-repair-20261025;
  branch fix/verification-closeout-20261025. Retain it at closeout unless retirement
  is separately proven safe. Native worktree creation could not resolve the home
  directory as a repository; explicit Git worktree fallback succeeded.

## Review focus

- Slow or missing ghci must not delay HTTP or make Tidal falsely available.
- Failed/repeated probes must not share stale availability across registries.
- Ignored local state and symlinks must not enter release archives.
- Native tests and the built workbench must survive packaging even with global
  tests export-ignore attributes.
- Artifact checks must fail on HTTP/asset errors and release their own processes.

## Tasks

1. Provider startup (`brahma/web/lib/agent/providers.js`, new provider probe tests).
   Add slow executable and registry-isolation regressions; observe baseline failure.
   Replace synchronous capability probes with bounded asynchronous execution, keep
   explicit pending/failure status, deduplicate concurrent probes. Run web tests
   serially and verify a real HTTP startup while a probe remains pending. Commit.
2. Release packaging (`tools/build_release.sh`, packaging tests and artifact checker).
   Reproduce private-state inclusion with fake token fixtures in a temporary repo.
   Select tracked source, include the generated bundle explicitly, and check both
   tar/zip contents. Promote unpack/install/boot/HTTP verification into a repeatable
   tool; wire it into CI/release. Run targeted tests and unpacked artifact proof.
3. AETHER COPY inputs (`aether/deploy/Dockerfile`, structural validator).
   Demonstrate absent sources, fix paths against declared repo-root context, add
   the source validator to smoke. Do not claim a Docker image build. Commit.
4. Final verification and closeout. Run implicated web/security/product/native
   suites and smoke; review the full diff, resolve substantive findings, publish
   final evidence. Push and create one PR; squash-merge using its full exact SHA.
   Re-fetch, prove merged contents, reconcile the canonical checkout only if safe,
   record retained work and remaining owners in #93. No tag/deployment implied.

## Execution record

- Read-only baseline: main equals origin/main; CI 40204288708 has 64/7/1.
- Previous diagnostic 40201130670 does eventually show a 3939 listener; prior
  permanent-stall conclusion is superseded. Synchronous ghci-before-listen ordering
  is confirmed; hosted causality remains to be verified.
- Existing local tar and zip each contain 233 runtime token paths; values unread.
- Prior untracked Gemini plan remains preserved in the canonical checkout.
- Task 1: three provider regressions failed on the base and now pass. Serial web
  suite: 150/150. Probes use bounded asynchronous children, registry-local state,
  and shared in-flight refreshes. No provider or measurement gate removed.
