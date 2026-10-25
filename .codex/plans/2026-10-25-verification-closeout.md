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
- Added a real HTTP regression with ghci held pending: current code serves provider
  status in 178 ms; the identical test loading the original provider module fails
  its 5-second bind deadline. This supersedes the old runner-console blocker.
- Task 2: fake-private-state and empty-bundle regressions failed then passed.
  Six packaging/checker tests pass. A real unpacked tar at 99e171e installed from
  its lockfile and served /, /workbench/, source.json and the 955078-byte bundle
  (hash matched); zip structure also passes. No private runtime members remain.
- Task 3: COPY validator failed on deploy/aether/serve.js, then passed for all six
  sources after correcting the Dockerfile. No Docker image build performed.
- The previous untracked Gemini plan is copied byte-for-byte into this branch as
  historical evidence. Its earlier permanent-stall and completeness assertions
  are superseded by this plan; its original file remains untouched.
- Independent read-only review (base..223ebce plus ffmpeg workflow setup): no
  Critical/Important findings. Minor negative-runtime-check and same-registry
  refresh coverage suggestions are retained under #93; they do not invalidate
  the executed artifact proof. No second review loop is scheduled.
- Additional lifecycle regression: SIGTERM with a pending ghci probe failed its
  shutdown deadline; server shutdown now aborts registry discovery, and the real
  HTTP/startup/shutdown regression passes. This method is used by production
  closeServer, not a test-only cleanup API.
- Full local gates: web 151/151, security 12/12, product 21/21, native phase_a /
  class_runtime / flucoma_buffer all BRAHMA_TEST_PASS; smoke 75/0/0. Native runner
  pins this checkout's classes without touching SC Extensions symlinks.
