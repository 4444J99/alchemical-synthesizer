#!/usr/bin/env bash
# Install all recursive source-owned SC classes, then verify a real file driver.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verify=(--verify)
arguments=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-recompile) verify=(); shift ;;
    --extensions-dir)
      [ "$#" -ge 2 ] || { echo "--extensions-dir requires a path" >&2; exit 2; }
      arguments+=(--extensions-dir "$2"); shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--no-recompile] [--extensions-dir PATH]"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
exec python3 "$ROOT/tools/install-brahma-classes.py" --apply "${verify[@]}" "${arguments[@]}"
