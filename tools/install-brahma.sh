#!/usr/bin/env bash
#
# install-brahma.sh — symlink the Brahma SuperCollider class files into the
# SC Extensions directory and trigger a class-library recompile.
#
# Usage:
#   tools/install-brahma.sh [--no-recompile]
#
# The six .sc classes live in brahma/sc/ and must be on SC's class path for
# sclang to compile the rack:
#   AdamKadmon, BridgeRouter, FSAP, BrahmaScale, BrahmaMPE, BrahmaModBus
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SC_CLASSES=(AdamKadmon BridgeRouter FSAP BrahmaScale BrahmaMPE BrahmaModBus)
NO_RECOMPILE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-recompile) NO_RECOMPILE=1; shift ;;
    --help|-h)
      echo "Usage: $0 [--no-recompile]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# --- Detect SC Extensions directory -----------------------------------------
SC_EXT=""
if command -v sclang >/dev/null 2>&1; then
  SC_EXT="$(sclang -e 'Platform.userExtensionDir.postln; 0.exit' 2>/dev/null | tail -1)"
fi

if [ -z "$SC_EXT" ]; then
  # Fall back to platform defaults.
  case "$(uname -s)" in
    Darwin) SC_EXT="$HOME/Library/Application Support/SuperCollider/Extensions" ;;
    Linux)  SC_EXT="$HOME/.local/share/SuperCollider/Extensions" ;;
    *)      echo "Cannot locate SC Extensions dir (sclang not found)." >&2; exit 3 ;;
  esac
fi

echo "SC Extensions dir: $SC_EXT"
mkdir -p "$SC_EXT"

# --- Symlink each class file ------------------------------------------------
for cls in "${SC_CLASSES[@]}"; do
  src="$ROOT/brahma/sc/${cls}.sc"
  dst="$SC_EXT/${cls}.sc"
  if [ ! -f "$src" ]; then
    echo "MISSING: $src (skipping $cls)" >&2
    continue
  fi
  if [ -L "$dst" ] || [ -e "$dst" ]; then
    if [ "$(readlink "$dst" 2>/dev/null || echo "")" = "$src" ]; then
      echo "OK:   $cls -> $src (already linked)"
      continue
    fi
    # Back up any pre-existing real file before overwriting.
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      mv "$dst" "${dst}.bak.$(date +%s)"
      echo "BACKED UP: existing $dst"
    fi
    ln -sf "$src" "$dst"
    echo "LINK: $cls -> $src"
  else
    ln -sf "$src" "$dst"
    echo "LINK: $cls -> $src"
  fi
done

# --- Recompile the class library --------------------------------------------
if [ "$NO_RECOMPILE" -eq 1 ]; then
  echo "Skipping recompile (--no-recompile). Run Cmd+Shift+L in SC IDE or evaluate Platform.recompileClassLibrary."
else
  if command -v sclang >/dev/null 2>&1; then
    echo "Recompiling SC class library..."
    if sclang -e 'Platform.recompileClassLibrary.postln; 0.exit' >/dev/null 2>&1; then
      echo "RECOMPILE OK"
    else
      echo "Recompile failed via sclang — recompile manually in the SC IDE (Cmd+Shift+L)." >&2
    fi
  else
    echo "sclang not on PATH — recompile manually in the SC IDE (Cmd+Shift+L)." >&2
  fi
fi

echo
echo "Done. Verify in SC IDE: (AdamKadmon != nil).postln  # should print true"