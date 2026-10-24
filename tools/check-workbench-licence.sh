#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 4444J99
#
# check-workbench-licence.sh — enforce the AGPL boundary mechanically.
#
# The licence position is stated in prose in NOTICE, README and the workbench README.
# Prose does not fail a build, so this script checks the things that actually ship:
# SPDX headers, the full licence text, the notice, the source link, and that the
# workbench page graph does not reach into product/ or MIT-only Cortex assets.
#
# Exit codes: 0 clean · 1 violation · 2 missing prerequisite

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WB="$ROOT/brahma/web/public/workbench"
FAIL=0

pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

echo "=== Workbench licence boundary ==="

# 1. Full licence text present.
if [ -f "$ROOT/LICENSES/AGPL-3.0-or-later.txt" ] \
  && grep -q "GNU AFFERO GENERAL PUBLIC LICENSE" "$ROOT/LICENSES/AGPL-3.0-or-later.txt"; then
  pass "LICENSES/AGPL-3.0-or-later.txt present with licence text"
else
  fail "LICENSES/AGPL-3.0-or-later.txt missing or not the AGPL text"
fi

# 2. NOTICE names the bundled dependencies.
if [ -f "$ROOT/NOTICE" ] && grep -q "@strudel/core" "$ROOT/NOTICE" && grep -q "codemirror" "$ROOT/NOTICE"; then
  pass "NOTICE lists bundled dependencies"
else
  fail "NOTICE missing or does not list @strudel/core and codemirror"
fi

# 3. Every shipped workbench file carries the SPDX identifier.
missing=0
while IFS= read -r file; do
  if ! head -3 "$file" | grep -q "SPDX-License-Identifier: AGPL-3.0-or-later"; then
    fail "missing AGPL SPDX header: ${file#"$ROOT"/}"
    missing=$((missing + 1))
  fi
done < <(find "$WB" -type f \( -name '*.js' -o -name '*.html' -o -name '*.css' -o -name '*.mjs' \) \
  -not -path "*/vendor/*")
[ "$missing" -eq 0 ] && pass "every workbench source carries an AGPL SPDX header"

# 4. The page links its source offer.
if grep -q '/workbench/source.json' "$WB/index.html"; then
  pass "workbench page links /workbench/source.json"
else
  fail "workbench page does not link the source offer"
fi

# 5. The page graph must not reach product/ or the MIT p5 Cortex page.
# Looks for real references (src/href/import), not prose that merely names them.
if grep -rqE "(src|href)=['\"][^'\"]*(p5(\.min)?\.js|/cortex/|/product/)|from ['\"][^'\"]*product/|import\(['\"][^'\"]*product/" \
  "$WB" --include='*.js' --include='*.html' --exclude-dir=vendor; then
  fail "workbench page references product/, p5.js or the Cortex page"
else
  pass "workbench page graph excludes product/ and p5/Cortex assets"
fi

# 6. No build-time dependency may be imported by shipped source.
if grep -rqE "from ['\"]esbuild|from ['\"]puppeteer" "$WB/src" 2>/dev/null; then
  fail "workbench source imports a build/test-only dependency"
else
  pass "workbench source imports no build/test-only dependency"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "WORKBENCH LICENCE: PASS"
  exit 0
fi
echo "WORKBENCH LICENCE: FAIL ($FAIL)"
exit 1
