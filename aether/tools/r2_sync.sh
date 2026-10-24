#!/usr/bin/env bash
# ============================================================================
#  r2_sync.sh — push the live HLS dir to a Cloudflare R2 bucket (the write path
#  behind "R2 for segments"; the Worker in deploy/aether/worker.mjs is the read
#  path). Optional durability + CDN layer for the 24/7 host (AETHER plan §5.3).
#
#  R2 is S3-compatible, so this uses the `aws` CLI against the R2 endpoint. It is
#  the MECHANISM only — the credentials are organ-owned and NEVER recited here:
#  they arrive via env (the credential organ / a container secret), and this
#  script only reads them. If they are absent it exits cleanly (the container
#  still serves /live locally), so an un-provisioned deploy degrades, not breaks.
#
#  Required env (provisioned as container secrets, not pasted in chat):
#     R2_BUCKET            target bucket (e.g. aether-segments)
#     R2_ENDPOINT          https://<account>.r2.cloudflarestorage.com
#     AWS_ACCESS_KEY_ID    R2 access key id
#     AWS_SECRET_ACCESS_KEY R2 secret
#  Optional: R2_PREFIX (key prefix), AETHER_SYNC_INTERVAL (watch seconds, def 5)
#
#  Usage:  r2_sync.sh --dir /live [--watch]
# ============================================================================
set -uo pipefail

DIR="/live"
WATCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)   DIR="$2"; shift 2;;
    --watch) WATCH=1; shift;;
    *) echo "r2_sync: unknown arg $1" >&2; exit 2;;
  esac
done

# Degrade cleanly if unconfigured — the local /live stream still serves.
if [ -z "${R2_BUCKET:-}" ] || [ -z "${R2_ENDPOINT:-}" ] \
   || [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "r2_sync: R2 not configured (missing bucket/endpoint/credentials) — skipping (local /live still serves)." >&2
  exit 0
fi
if ! command -v aws >/dev/null 2>&1; then
  echo "r2_sync: aws CLI not found — cannot sync to R2 (local /live still serves)." >&2
  exit 0
fi

PREFIX="${R2_PREFIX:-}"
INTERVAL="${AETHER_SYNC_INTERVAL:-5}"
DEST="s3://${R2_BUCKET}/${PREFIX}"

sync_once() {
  # --size-only avoids re-uploading immutable .ts; the playlist is small + always synced.
  aws s3 sync "$DIR" "$DEST" --endpoint-url "$R2_ENDPOINT" \
      --no-progress --exact-timestamps --delete >/dev/null 2>&1 \
    || echo "r2_sync: a sync pass failed (will retry)" >&2
}

echo "r2_sync: $DIR -> $DEST (watch=$WATCH, interval=${INTERVAL}s)" >&2
if [ "$WATCH" = 1 ]; then
  while :; do sync_once; sleep "$INTERVAL"; done
else
  sync_once
fi
