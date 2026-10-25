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
# macOS tar otherwise adds AppleDouble sidecars alongside the release root.
export COPYFILE_DISABLE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(git describe --tags --always --dirty 2>/dev/null || echo "0.0.0-dev")}"
NAME="alchemical-synthesizer"
SLUG="${NAME}-${VERSION}"
DIST="${ROOT}/dist"
STAGE="${DIST}/${SLUG}"

echo "=== Building ${SLUG} ==="

# The workbench bundle is a build artefact (gitignored) that the served page
# loads as its entry module (/workbench/vendor/workbench.js). Refuse to pack a
# release whose workbench page would 404 on its own script.
WB_BUNDLE="brahma/web/public/workbench/vendor/workbench.js"
if [ ! -s "${ROOT}/${WB_BUNDLE}" ] || [ -L "${ROOT}/${WB_BUNDLE}" ]; then
  echo "ERROR: ${WB_BUNDLE} is missing — the packaged workbench page would 404." >&2
  echo "Build it first: (cd brahma/web && npm install && npm run build:workbench)" >&2
  exit 1
fi

rm -rf "$DIST"
mkdir -p "$STAGE"

# Package committed source, never arbitrary ignored or untracked working state
# (in particular .runtime agent tokens, .env files, and local media). Ignore
# host-global attributes: a host's `tests export-ignore` must not strip our tests.
git -c core.attributesFile=/dev/null archive --format=tar HEAD | tar -xf - -C "$STAGE"
# This is the sole generated runtime asset, built explicitly before packaging.
mkdir -p "${STAGE}/$(dirname "$WB_BUNDLE")"
cp "${ROOT}/${WB_BUNDLE}" "${STAGE}/${WB_BUNDLE}"

# The pre-flight check above is only half the contract: prove the staged tree
# actually carries the bundle, so a future exclude pattern cannot silently
# strip it again.
if [ ! -s "${STAGE}/${WB_BUNDLE}" ]; then
  echo "ERROR: ${WB_BUNDLE} did not survive staging — check the tar exclude list." >&2
  exit 1
fi

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

# SBOM — SPDX 2.3 inventory of top-level components and their provenance.
( cd "$STAGE" && cat > "${SLUG}.spdx" <<SPDX
SPDXVersion: SPDX-2.3
DataLicense: CC0-1.0
SPDXID: SPDXRef-DOCUMENT
DocumentName: alchemical-synthesizer
DocumentNamespace: https://github.com/4444J99/alchemical-synthesizer/build/${VERSION}
Creator: Tool: build_release.sh
Created: ${BUILT_AT}

PackageName: alchemical-synthesizer
SPDXID: SPDXRef-PKG-brahma
PackageVersion: ${VERSION}
PackageDownloadLocation: https://github.com/4444J99/alchemical-synthesizer/releases/tag/${VERSION}
FilesAnalyzed: false
LicenseConcluded: MIT
LicenseInfoInFile: MIT
PackageSummary: Brahma Meta-Rack — modular alchemical synthesizer
PackageDescription: SuperCollider DSP engine, Pure Data performance UI, Node.js/p5.js Visual Cortex, Forge production pipeline, AETHER living radio deploy unit.

Relationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-PKG-brahma
SPDX
)

# Provenance attestation — signed-by-commit metadata for reproducibility.
cat > "$STAGE/PROVENANCE.json" <<EOF
{
  "schema": "https://github.com/4444J99/alchemical-synthesizer/provenance/v1",
  "version": "${VERSION}",
  "commit": "${COMMIT}",
  "built_at": "${BUILT_AT}",
  "builder": "${USER:-unknown}",
  "host": "$(hostname 2>/dev/null || echo unknown)",
  "components": {
    "supercollider_scd": ${SCD_COUNT},
    "supercollider_sc": ${SC_CLASS_COUNT},
    "pure_data_patches": ${PD_COUNT}
  },
  "artifacts": [
    "${SLUG}.tar.gz",
    "${SLUG}.zip"
  ],
  "checksums_file": "SHA256SUMS.txt",
  "sbom": "${SLUG}.spdx"
}
EOF

# Move SBOM + provenance into dist root alongside checksums.
mv "$STAGE/${SLUG}.spdx" "$DIST/${SLUG}.spdx" 2>/dev/null || true
mv "$STAGE/PROVENANCE.json" "$DIST/PROVENANCE.json" 2>/dev/null || true

# Clean the staging directory; keep only the packaged artifacts.
rm -rf "$STAGE"

echo "=== Artifacts ==="
( cd "$DIST" && ls -lh "${SLUG}.tar.gz" "${SLUG}.zip" SHA256SUMS.txt "${SLUG}.spdx" PROVENANCE.json )
echo
cat "$DIST/SHA256SUMS.txt"
echo "=== Done: dist/${SLUG}.{tar.gz,zip} ==="
