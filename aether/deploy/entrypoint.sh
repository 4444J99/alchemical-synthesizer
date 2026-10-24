#!/usr/bin/env bash
# ============================================================================
#  entrypoint.sh — run the AETHER generator + stream server together, 24/7.
# ----------------------------------------------------------------------------
#  Starts the broadcast loop (organism -> live HLS) in the background and the
#  dependency-free stream server in the foreground. If EITHER dies, we exit so
#  the container platform restarts the whole unit (a partial radio is no radio).
# ============================================================================
set -uo pipefail

LIVE="${AETHER_LIVE_DIR:-/live}"
mkdir -p "$LIVE"

echo "[aether] starting generator -> $LIVE"
# forever (--segments 0); fold a donor with AETHER_SOURCE, tune the organism
# with AETHER_SEED / AETHER_PERIOD. Seconds/window from env.
bash /app/tools/broadcast.sh --out "$LIVE" --segments 0 \
  ${AETHER_SOURCE:+--source "$AETHER_SOURCE"} \
  ${AETHER_SEED:+--seed "$AETHER_SEED"} \
  ${AETHER_PERIOD:+--period "$AETHER_PERIOD"} \
  ${AETHER_SECONDS:+--seconds "$AETHER_SECONDS"} \
  ${AETHER_LIST_SIZE:+--list-size "$AETHER_LIST_SIZE"} &
BROADCAST_PID=$!

# Optional: push segments to R2 for durability + CDN (creds via env; see
# tools/r2_sync.sh and deploy/aether/README.md). Off unless AETHER_R2=1.
if [ "${AETHER_R2:-0}" = "1" ]; then
  echo "[aether] R2 sync sidecar enabled"
  bash /app/tools/r2_sync.sh --dir "$LIVE" --watch &
  R2_PID=$!
fi

echo "[aether] starting stream server on :${PORT:-8080}"
node /app/serve.js &
SERVE_PID=$!

# Clean shutdown: on signal, stop children.
trap 'kill "$BROADCAST_PID" "$SERVE_PID" ${R2_PID:-} 2>/dev/null' INT TERM EXIT

# Exit as soon as either core process dies (platform will restart the unit).
wait -n "$BROADCAST_PID" "$SERVE_PID"
echo "[aether] a core process exited — shutting down for restart"
