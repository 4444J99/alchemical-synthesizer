#!/usr/bin/env bash
#
# start-brahma.sh — layered start of the Alchemical Synthesizer Meta-Rack.
#
# Tiers start in dependency order, each with a health check before the next.
# Any tier can be skipped (SC absent -> web-only mode; Pd absent -> no Pd).
#
# Usage:
#   tools/start-brahma.sh [--no-sc] [--no-web] [--no-pd] [--port 3000]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NO_SC=0; NO_WEB=0; NO_PD=0; WEB_PORT=3000
while [ $# -gt 0 ]; do
  case "$1" in
    --no-sc)   NO_SC=1; shift ;;
    --no-web)  NO_WEB=1; shift ;;
    --no-pd)   NO_PD=1; shift ;;
    --port)    WEB_PORT="${2:-}"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--no-sc] [--no-web] [--no-pd] [--port N]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

PIDS=()

cleanup() {
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

# --- Tier 1: SuperCollider engine -------------------------------------------
start_sc() {
  if [ "$NO_SC" -eq 1 ]; then
    echo "[1/3] SC: skipped (--no-sc)"
    return 0
  fi
  if ! command -v sclang >/dev/null 2>&1; then
    echo "[1/3] SC: skipped (sclang not on PATH — web-only mode)"
    return 0
  fi
  echo "[1/3] SC: launching brahma/sc/loader.scd ..."
  sclang brahma/sc/loader.scd >/tmp/brahma-sc.log 2>&1 &
  local sc_pid=$!
  PIDS+=("$sc_pid")

  # Wait for the online banner (up to 30 s).
  local waited=0
  while [ "$waited" -lt 30 ]; do
    if grep -q 'BRAHMA SYSTEM ONLINE' /tmp/brahma-sc.log 2>/dev/null; then
      echo "[1/3] SC: online (brahma-sc.log)"
      return 0
    fi
    if ! kill -0 "$sc_pid" 2>/dev/null; then
      echo "[1/3] SC: sclang exited early — see /tmp/brahma-sc.log" >&2
      return 1
    fi
    sleep 1; waited=$((waited + 1))
  done
  echo "[1/3] SC: timed out waiting for ONLINE banner — see /tmp/brahma-sc.log" >&2
  return 1
}

# --- Tier 2: Visual Cortex web server ---------------------------------------
start_web() {
  if [ "$NO_WEB" -eq 1 ]; then
    echo "[2/3] Web: skipped (--no-web)"
    return 0
  fi
  if [ ! -d "$ROOT/brahma/web/node_modules" ]; then
    echo "[2/3] Web: installing deps (first run)..."
    ( cd "$ROOT/brahma/web" && npm install --ignore-scripts --no-audit --no-fund >/tmp/brahma-web-npm.log 2>&1 ) || {
      echo "[2/3] Web: npm install failed — see /tmp/brahma-web-npm.log" >&2
      return 1
    }
  fi
  echo "[2/3] Web: launching Visual Cortex on :$WEB_PORT ..."
  ( cd "$ROOT/brahma/web" && PORT="$WEB_PORT" npm start >/tmp/brahma-web.log 2>&1 ) &
  local web_pid=$!
  PIDS+=("$web_pid")

  local waited=0
  while [ "$waited" -lt 20 ]; do
    if curl -sf "http://127.0.0.1:${WEB_PORT}/" >/dev/null 2>&1; then
      echo "[2/3] Web: online http://127.0.0.1:${WEB_PORT}/"
      return 0
    fi
    if ! kill -0 "$web_pid" 2>/dev/null; then
      echo "[2/3] Web: web process exited early — see /tmp/brahma-web.log" >&2
      return 1
    fi
    sleep 1; waited=$((waited + 1))
  done
  echo "[2/3] Web: timed out — see /tmp/brahma-web.log" >&2
  return 1
}

# --- Tier 3: Pure Data ------------------------------------------------------
start_pd() {
  if [ "$NO_PD" -eq 1 ]; then
    echo "[3/3] Pd: skipped (--no-pd)"
    return 0
  fi
  if ! command -v pd >/dev/null 2>&1; then
    echo "[3/3] Pd: skipped (pd not on PATH)"
    return 0
  fi
  echo "[3/3] Pd: opening brahma/pd/main.pd ..."
  pd "$ROOT/brahma/pd/main.pd" >/tmp/brahma-pd.log 2>&1 &
  local pd_pid=$!
  PIDS+=("$pd_pid")
  echo "[3/3] Pd: launched (pid $pd_pid)"
}

# --- Run --------------------------------------------------------------------
echo "=== Alchemical Synthesizer — layered start ==="
start_sc
start_web
start_pd
echo
echo "All requested tiers launched. Press Ctrl-C to stop everything."
echo "Logs: /tmp/brahma-sc.log /tmp/brahma-web.log /tmp/brahma-pd.log"
echo "Visual Cortex: http://127.0.0.1:${WEB_PORT}/"
wait