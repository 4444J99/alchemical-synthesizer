# AETHER standalone acceptance

## Completed source consolidation

AETHER files already live under `aether/`. The previous `deploy/aether`, root
broadcast-tool, and `brahma/web/public/aether` move recipe is historical and must
not be run again. [MANIFEST.md](MANIFEST.md) is the current source map.

Source export and operational acceptance are separate results. A matching exported
tree does not prove its Docker context, optional Forge dependency, smoke command,
or cloud deployment works independently.

## Remaining gates

1. Decide the standalone render contract: the present container uses donor/tone
   rendering; Brahma/Forge NRT is an explicit optional integration.
2. Adapt the Docker build context for a repository where AETHER files are at its
   root. The monorepo command remains `docker build -f aether/deploy/Dockerfile .`.
3. Carry the host/listener/edge predicates into that repository and run a bounded
   ffmpeg broadcast with no monorepo path assumptions.
4. Build and run the actual image. Verify startup, listener, playlist, segments,
   operator-only intake, private queue exclusion, restart and shutdown.
5. Verify the cloud platform adapter, secret injection and optional R2 write path
   independently. The current base image does not supply the AWS CLI required by
   `r2_sync.sh`; do not report R2 durability from configuration alone.
6. Establish authenticated deployment and rollback against an identified target.
   Repository creation, pushes, visibility changes and deployment are separate
   actions governed by the current task's authorization.

A future history-preserving export may use `git subtree split --prefix=aether`
on a clean topic branch. Inspect any existing destination first, preserve unique
work, and compare exported tree IDs before updating it. Do not recreate a
repository or overwrite its history merely because an old recipe says to do so.

## Rollback

Keep the monorepo integration runnable until the independent target meets its
acceptance gates. A source-only branch does not change a running deployment.
Retain the prior deployed image/configuration until the replacement is validated.
