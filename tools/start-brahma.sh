#!/usr/bin/env bash
# Portable entry point; Python owns subprocess groups and readiness checks.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT/tools/start-brahma.py" "$@"
