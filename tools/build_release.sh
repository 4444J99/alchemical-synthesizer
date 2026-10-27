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
# Prevent macOS tar from adding AppleDouble sidecars.
export COPYFILE_DISABLE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(git describe --tags --always --dirty 2>/dev/null || echo "0.0.0-dev")}"
# A version is a label, never a path. Validate before deleting/replacing output.
if [[ ${#VERSION} -gt 100 || ! "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
  echo "build_release: invalid version label" >&2
  exit 2
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "build_release: run from a Git checkout (source allowlist required)" >&2
  exit 2
}

# Both archive formats accept only regular source files. In particular zip
# dereferences links by default: a tracked path replaced by a link must never
# import a private file from outside this checkout. Check ancestors as well, and
# do it before the builder writes its output or the old dist is removed.
python3 - <<'PY'
from pathlib import Path
import os, stat, subprocess
root = Path.cwd()
def validate(relative, required=True):
    path = root
    for component in Path(relative).parts:
        path = path / component
        if path.is_symlink():
            raise SystemExit(f"build_release: refusing symlinked source path: {relative}")
    if path.exists():
        if not stat.S_ISREG(path.stat().st_mode):
            raise SystemExit(f"build_release: source is not a regular file: {relative}")
    elif required:
        raise SystemExit(f"build_release: tracked source is missing: {relative}")
for name in subprocess.check_output(["git", "ls-files", "-z"]).split(b"\0"):
    if name:
        validate(os.fsdecode(name))
validate("brahma/web/public/workbench/vendor/workbench.js", required=False)
PY

# Ship the browser's executable asset as well as its corresponding source.
# Dependencies are installed explicitly by the caller/CI, never copied into dist.
WB_BUNDLE="brahma/web/public/workbench/vendor/workbench.js"
if [ -L "$WB_BUNDLE" ]; then
  echo "build_release: refusing a symlinked workbench bundle" >&2
  exit 2
fi
if ! node tools/build-workbench.mjs; then
  echo "build_release: workbench build failed; install locked dependencies and run npm run build:workbench" >&2
  exit 1
fi
if [ ! -s "$WB_BUNDLE" ] || [ -L "$WB_BUNDLE" ]; then
  echo "build_release: build:workbench did not produce a regular nonempty bundle" >&2
  exit 1
fi

NAME="alchemical-synthesizer"
SLUG="${NAME}-${VERSION}"
DIST="${ROOT}/dist"
STAGE="${DIST}/${SLUG}"

echo "=== Building ${SLUG} ==="

rm -rf "$DIST"
mkdir -p "$STAGE"

# Copy only versioned source paths. A normal working tree also contains runtime
# credentials, account stores and media; an ever-growing exclusion list cannot
# safely turn that whole directory into a release. Copy current tracked contents
# so a local dirty build is possible and label that state in the manifest.
git ls-files -z | tar \
  --exclude='.env' --exclude='.env.*' \
  --exclude='*/.runtime/*' \
  --exclude='*/node_modules' \
  --exclude='*/__pycache__' \
  --exclude='*.pyc' \
  --exclude='*/.pytest_cache' \
  --exclude='*.tgz' \
  --exclude='*.abletonextension' \
  --null --files-from=- -cf - | tar -xf - -C "$STAGE"
mkdir -p "$STAGE/brahma/web/public/workbench/vendor"
cp brahma/web/public/workbench/vendor/workbench.js "$STAGE/brahma/web/public/workbench/vendor/"

# Build manifest — records exactly what shipped, for reproducibility.
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
SOURCE_STATE="clean"
if ! git diff --quiet || ! git diff --cached --quiet; then SOURCE_STATE="modified"; fi
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SCD_COUNT="$(find "$STAGE/brahma/sc" -name '*.scd' 2>/dev/null | wc -l | tr -d ' ')"
SC_CLASS_COUNT="$(find "$STAGE/brahma/sc" -name '*.sc' 2>/dev/null | wc -l | tr -d ' ')"
PD_COUNT="$(find "$STAGE/brahma/pd" -name '*.pd' 2>/dev/null | wc -l | tr -d ' ')"

cat > "$STAGE/BUILD_MANIFEST.txt" <<EOF
Alchemical Synthesizer (Brahma Meta-Rack) — Build Manifest
==========================================================
version:        ${VERSION}
commit:         ${COMMIT}
source_state:   ${SOURCE_STATE} (tracked working-tree contents)
built_at:       ${BUILT_AT}

components:
  supercollider: ${SCD_COUNT} .scd files, ${SC_CLASS_COUNT} .sc classes (brahma/sc/)
  pure_data:     ${PD_COUNT} patches (brahma/pd/)
  web:           Visual Cortex + bundled workbench (brahma/web/) -> npm ci && npm start
  ableton:       Brahma Bridge extension (brahma/ableton/)
  tools:         audio validation + smoke (tools/)

quick start:
  1. SuperCollider: install the .sc classes as documented, then evaluate brahma/sc/loader.scd
  2. Web:           cd brahma/web && npm ci && npm start  (http://localhost:3000)
                    Set BRAHMA_COMMIT_SHA=${COMMIT} for archive source-revision reporting.
  3. Pure Data:     open brahma/pd/main.pd
  4. Smoke test:    bash tools/smoke.sh

See README.md and CLAUDE.md for full documentation.
EOF

# Package: tarball + zip.
mkdir -p "$DIST"
( cd "$DIST" && tar -czf "${SLUG}.tar.gz" "${SLUG}" )
( cd "$DIST" && zip -qr "${SLUG}.zip" "${SLUG}" )

# Top-level component inventory, not a dependency-complete SBOM or a conclusion
# about the combined distribution's license.
cat > "$DIST/${SLUG}.spdx" <<SPDX
SPDXVersion: SPDX-2.3
DataLicense: CC0-1.0
SPDXID: SPDXRef-DOCUMENT
DocumentName: alchemical-synthesizer
DocumentNamespace: https://github.com/4444J99/alchemical-synthesizer/build/${VERSION}/${COMMIT}
Creator: Tool: build_release.sh
Created: ${BUILT_AT}
CreatorComment: <text>Top-level source inventory only; transitive dependencies are not enumerated.</text>

PackageName: alchemical-synthesizer
SPDXID: SPDXRef-PKG-brahma
PackageVersion: ${VERSION}
PackageDownloadLocation: NOASSERTION
FilesAnalyzed: false
PackageLicenseConcluded: NOASSERTION
PackageLicenseDeclared: NOASSERTION
PackageLicenseComments: <text>The root LICENSE declares MIT. The included workbench has an explicit AGPL-3.0-or-later boundary; no combined-license conclusion is asserted.</text>
PackageCopyrightText: NOASSERTION

PackageName: brahma-workbench
SPDXID: SPDXRef-PKG-workbench
PackageVersion: ${VERSION}
PackageDownloadLocation: NOASSERTION
FilesAnalyzed: false
PackageLicenseConcluded: NOASSERTION
PackageLicenseDeclared: AGPL-3.0-or-later
PackageCopyrightText: NOASSERTION

Relationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-PKG-brahma
Relationship: SPDXRef-PKG-brahma CONTAINS SPDXRef-PKG-workbench
SPDX

# Unsigned build metadata. JSON encoding avoids interpolating unsafe host fields;
# archive hashes identify the actual bytes rather than implying a signature.
python3 - "$DIST" "$SLUG" "$VERSION" "$COMMIT" "$SOURCE_STATE" "$BUILT_AT" \
  "$SCD_COUNT" "$SC_CLASS_COUNT" "$PD_COUNT" <<'PY'
import hashlib, json, pathlib, sys
dist, slug, version, commit, state, built, scd, classes, pd = sys.argv[1:]
dist = pathlib.Path(dist)
record = {
    "schema": "https://github.com/4444J99/alchemical-synthesizer/provenance/v1",
    "version": version, "commit": commit, "source_state": state,
    "built_at": built, "builder": "tools/build_release.sh",
    "attestation": "unsigned build metadata",
    "components": {"supercollider_scd": int(scd), "supercollider_sc": int(classes),
                   "pure_data_patches": int(pd)},
    "artifacts": {name: hashlib.sha256((dist / name).read_bytes()).hexdigest()
                  for name in [slug + ".tar.gz", slug + ".zip"]},
    "checksums_file": "SHA256SUMS.txt", "sbom": slug + ".spdx"
}
(dist / "PROVENANCE.json").write_text(json.dumps(record, indent=2) + "\n")
PY

( cd "$DIST" && sha256sum "${SLUG}.tar.gz" "${SLUG}.zip" "${SLUG}.spdx" PROVENANCE.json > "SHA256SUMS.txt" )

# Clean the staging directory; keep only the packaged artifacts.
rm -rf "$STAGE"

echo "=== Artifacts ==="
( cd "$DIST" && ls -lh "${SLUG}.tar.gz" "${SLUG}.zip" "${SLUG}.spdx" PROVENANCE.json SHA256SUMS.txt )
echo
cat "$DIST/SHA256SUMS.txt"
echo "=== Done: dist/${SLUG}.{tar.gz,zip} ==="
