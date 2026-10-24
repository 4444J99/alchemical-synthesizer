#!/usr/bin/env bash
#
# build_release.sh — package the Alchemical Synthesizer into distributable
# artifacts. Produces a versioned tarball + zip of the rack (SuperCollider,
# Pure Data, web, Ableton extension, tools, docs) plus a build manifest and
# SHA-256 checksums under dist/.
#
# Usage:
#   tools/build_release.sh [VERSION]
#
# VERSION defaults to `git describe --tags --always` (e.g. v1.0.0 or a short
# SHA). Called by .github/workflows/release.yml on tag pushes; also runnable
# locally (`make dist`).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(git describe --tags --always --dirty 2>/dev/null || echo "0.0.0-dev")}"
NAME="alchemical-synthesizer"
SLUG="${NAME}-${VERSION}"
DIST="${ROOT}/dist"
STAGE="${DIST}/${SLUG}"

echo "=== Building ${SLUG} ==="

rm -rf "$DIST"
mkdir -p "$STAGE"

# Copy the working tree, excluding VCS internals, build output, and installed
# dependencies / vendored binaries (these are reconstructed on the user side).
tar \
  --exclude='./.git' \
  --exclude='./dist' \
  --exclude='*/node_modules' \
  --exclude='*/__pycache__' \
  --exclude='*.pyc' \
  --exclude='*/.pytest_cache' \
  --exclude='*/vendor' \
  --exclude='*.tgz' \
  --exclude='*.abletonextension' \
  -cf - -C "$ROOT" . | tar -xf - -C "$STAGE"

# Build manifest — records exactly what shipped, for reproducibility.
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SCD_COUNT="$(find "$STAGE/brahma/sc" -name '*.scd' 2>/dev/null | wc -l | tr -d ' ')"
SC_CLASS_COUNT="$(find "$STAGE/brahma/sc" -name '*.sc' 2>/dev/null | wc -l | tr -d ' ')"
PD_COUNT="$(find "$STAGE/brahma/pd" -name '*.pd' 2>/dev/null | wc -l | tr -d ' ')"

cat > "$STAGE/BUILD_MANIFEST.txt" <<EOF
Alchemical Synthesizer (Brahma Meta-Rack) — Build Manifest
==========================================================
version:        ${VERSION}
commit:         ${COMMIT}
built_at:       ${BUILT_AT}

components:
  supercollider: ${SCD_COUNT} .scd files, ${SC_CLASS_COUNT} .sc classes (brahma/sc/)
  pure_data:     ${PD_COUNT} patches (brahma/pd/)
  web:           Visual Cortex (brahma/web/)  -> npm install && npm start
  ableton:       Brahma Bridge extension (brahma/ableton/)
  tools:         audio validation + smoke (tools/)

quick start:
  1. SuperCollider: open brahma/sc/loader.scd, evaluate
  2. Web:           cd brahma/web && npm install && npm start  (http://localhost:3000)
  3. Pure Data:     open brahma/pd/main.pd
  4. Smoke test:    bash tools/smoke.sh

See README.md and CLAUDE.md for full documentation.
EOF

# Package: tarball + zip.
mkdir -p "$DIST"
( cd "$DIST" && tar -czf "${SLUG}.tar.gz" "${SLUG}" )
( cd "$DIST" && zip -qr "${SLUG}.zip" "${SLUG}" )

# Checksums.
( cd "$DIST" && sha256sum "${SLUG}.tar.gz" "${SLUG}.zip" > "SHA256SUMS.txt" )

# Clean the staging directory; keep only the packaged artifacts.
rm -rf "$STAGE"

echo "=== Artifacts ==="
( cd "$DIST" && ls -lh "${SLUG}.tar.gz" "${SLUG}.zip" SHA256SUMS.txt )
echo
cat "$DIST/SHA256SUMS.txt"
echo "=== Done: dist/${SLUG}.{tar.gz,zip} ==="
