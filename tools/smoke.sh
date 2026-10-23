#!/usr/bin/env bash
#
# smoke.sh — the user smoke path for the Alchemical Synthesizer.
#
# Verifies the rack is installable and runnable without a full SuperCollider /
# Pure Data / Ableton Live setup. Used both as a one-command user check
# (`make smoke`) and as the CI "shipped-test" (.github/workflows/ci.yml).
#
# Checks, in order:
#   1. Structure    — key entry points present, SynthDef file count sane
#   2. Extension    — Ableton "Brahma Bridge" zero-dependency smoke test (node)
#   3. JS syntax    — Visual Cortex server + sketch parse cleanly (node --check)
#   4. Validator    — Python audio validator accepts a generated test tone
#   5. Web endpoint — Visual Cortex boots and serves HTTP 200 (needs npm deps)
#
# Exit code is non-zero if any *required* check fails. The web endpoint check
# is skipped (not failed) when dependencies can't be installed offline, unless
# --strict is passed.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP  $1"; SKIP=$((SKIP+1)); }

echo "=== [1/6] Structure ==="
req_files=(
  "brahma/sc/loader.scd"
  "brahma/web/server.js"
  "brahma/ableton/src/index.js"
  "forge/validate_audio.py"
  "README.md"
)
for f in "${req_files[@]}"; do
  [ -f "$f" ] && ok "exists: $f" || bad "missing: $f"
done
scd_count="$(find brahma/sc -name '*.scd' | wc -l | tr -d ' ')"
if [ "$scd_count" -ge 60 ]; then ok "SynthDef files: ${scd_count} (>= 60)"; else bad "SynthDef files: ${scd_count} (< 60)"; fi

echo "=== [2/6] Ableton extension smoke (node) ==="
if command -v node >/dev/null 2>&1; then
  if node brahma/ableton/test/smoke.js >/tmp/brahma_ext_smoke.log 2>&1; then
    ok "brahma/ableton/test/smoke.js"
  else
    bad "brahma/ableton/test/smoke.js (see /tmp/brahma_ext_smoke.log)"; tail -5 /tmp/brahma_ext_smoke.log
  fi
else
  skip "node not installed — extension smoke"
fi

echo "=== [3/6] JS syntax (node --check) ==="
if command -v node >/dev/null 2>&1; then
  for js in brahma/web/server.js brahma/web/public/sketch.js \
            brahma/web/public/tree/video.js brahma/web/public/aether/aether.js \
            brahma/web/public/instrument/pattern.js brahma/web/public/instrument/instrument.js \
            deploy/aether/serve.js deploy/aether/worker.mjs forge/render_video.mjs; do
    [ -f "$js" ] || continue
    if node --check "$js" >/dev/null 2>&1; then ok "node --check $js"; else bad "node --check $js"; fi
  done
  # The tracker/sampler instrument's brain (pattern.js) is pure + node-testable.
  if [ -f brahma/web/public/instrument/pattern.js ]; then
    if node brahma/web/public/instrument/pattern.js --self-test >/tmp/brahma_pattern.log 2>&1; then ok "instrument pattern.js --self-test"; else bad "instrument pattern.js --self-test"; tail -8 /tmp/brahma_pattern.log; fi
  fi
else
  skip "node not installed — JS syntax"
fi

echo "=== [4/6] Python audio validator ==="
if command -v python3 >/dev/null 2>&1; then
  TONE="$(mktemp -d)/test_tone.wav"
  if python3 tools/gen_test_tone.py "$TONE" >/dev/null 2>&1 \
     && python3 forge/validate_audio.py "$TONE" >/tmp/brahma_validator.log 2>&1; then
    ok "validate_audio.py accepts generated tone"
  else
    bad "validate_audio.py (see /tmp/brahma_validator.log)"; tail -8 /tmp/brahma_validator.log
  fi
  rm -f "$TONE"
else
  skip "python3 not installed — validator"
fi

echo "=== [5/6] Web endpoint boot ==="
web_ok=0
if command -v node >/dev/null 2>&1; then
  if [ ! -d brahma/web/node_modules ]; then
    echo "  ... installing web deps (npm ci/install)"
    ( cd brahma/web && { npm ci --no-audit --no-fund >/tmp/brahma_npm.log 2>&1 \
        || npm install --no-audit --no-fund >/tmp/brahma_npm.log 2>&1; } )
  fi
  if [ -d brahma/web/node_modules ]; then
    # The workbench bundle is a build artefact (gitignored). Boot without it and the
    # page is broken, so the gate that claims the workbench works must build it first.
    if ( cd brahma/web && npm run --silent build:workbench >/tmp/brahma_wb_build.log 2>&1 ); then
      ok "workbench bundle built (public/workbench/vendor/workbench.js)"
    else
      bad "workbench bundle build failed (see /tmp/brahma_wb_build.log)"
    fi

    PORT=3939
    # exec, so $! is node's own PID rather than a subshell: the teardown below has
    # to actually release the port, or the next run fails with EADDRINUSE.
    ( cd brahma/web && exec env PORT=$PORT node server.js >/tmp/brahma_web.log 2>&1 ) &
    WEB_PID=$!
    # curl -q ignores ~/.curlrc. A user config carrying --http2 makes curl send an
    # h2c Upgrade header, which this server answers 400 — a harness must not depend
    # on the operator's aliases.
    # Wait up to ~5s for the server to answer.
    for _ in $(seq 1 25); do
      if curl -q -fsS "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then break; fi
      sleep 0.2
    done
    code="$(curl -q -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/" 2>/dev/null || echo 000)"
    api="$(curl -q -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/api/modules" 2>/dev/null || echo 000)"
    kill "$WEB_PID" >/dev/null 2>&1; wait "$WEB_PID" 2>/dev/null
    if [ "$code" = "200" ] && [ "$api" = "200" ]; then
      ok "Visual Cortex served / (200) and /api/modules (200)"; web_ok=1
    else
      bad "Visual Cortex boot (/ = $code, /api/modules = $api; see /tmp/brahma_web.log)"
    fi
  else
    if [ "$STRICT" = "1" ]; then bad "could not install web deps (offline?)"; else skip "web deps unavailable (offline) — endpoint boot"; fi
  fi
else
  skip "node not installed — web endpoint"
fi

# The licence boundary is enforced, not just described.
if bash tools/check-workbench-licence.sh >/tmp/brahma_licence.log 2>&1; then
  ok "workbench licence boundary clean (AGPL subtree isolated)"
else
  bad "workbench licence boundary violated (see /tmp/brahma_licence.log)"
fi

echo "=== [6/6] Forge tools syntax (py_compile + bash -n) ==="
if command -v python3 >/dev/null 2>&1; then
  for py in forge/rip.py forge/stemforge.py forge/analyze_audio.py forge/validate_audio.py tools/gen_test_tone.py forge/tune.py tools/cellcycle.py tools/hls_append.py; do
    [ -f "$py" ] || continue
    if python3 -m py_compile "$py" >/tmp/brahma_pyc.log 2>&1; then ok "py_compile $py"; else bad "py_compile $py (see /tmp/brahma_pyc.log)"; tail -5 /tmp/brahma_pyc.log; fi
  done
  # AETHER Broadcast: the generator organism and the transport plane each carry
  # their own executable predicate (deterministic assertions). These prove the
  # live-radio muscle, not just that the files parse.
  if [ -f tools/cellcycle.py ]; then
    if python3 tools/cellcycle.py --self-test >/tmp/brahma_cellcycle.log 2>&1; then ok "cellcycle.py --self-test"; else bad "cellcycle.py --self-test"; tail -8 /tmp/brahma_cellcycle.log; fi
  fi
  if [ -f tools/hls_append.py ]; then
    if python3 tools/hls_append.py --self-test >/tmp/brahma_hls.log 2>&1; then ok "hls_append.py --self-test"; else bad "hls_append.py --self-test"; tail -8 /tmp/brahma_hls.log; fi
  fi
  # AETHER Ω (Ouroboros): the submission queue + the lineage ledger authorities.
  if [ -f tools/ingest_queue.py ]; then
    if python3 tools/ingest_queue.py --self-test >/tmp/brahma_q.log 2>&1; then ok "ingest_queue.py --self-test"; else bad "ingest_queue.py --self-test"; tail -8 /tmp/brahma_q.log; fi
  fi
  if [ -f tools/lineage.py ]; then
    if python3 tools/lineage.py --self-test >/tmp/brahma_lin.log 2>&1; then ok "lineage.py --self-test"; else bad "lineage.py --self-test"; tail -8 /tmp/brahma_lin.log; fi
  fi
  # AETHER source registry: must parse, and EVERY station must carry a license
  # (a source with no license tag could silently slip the publish-safety guard).
  if [ -f stations.json ]; then
    if python3 -c 'import json,sys; d=json.load(open("stations.json")); s=d.get("stations",[]); sys.exit(0 if s and all(x.get("license") and x.get("url") and x.get("name") for x in s) else 1)' >/dev/null 2>&1; then
      ok "stations.json: all sources carry name+url+license"
    else
      bad "stations.json: malformed or a source is missing name/url/license"
    fi
    # tune.py --list must run against the registry without error.
    if python3 forge/tune.py --list >/dev/null 2>&1; then ok "tune.py --list"; else bad "tune.py --list"; fi
  fi
else
  skip "python3 not installed — Forge py syntax"
fi
for sh in forge/forge.sh forge/bounce.sh forge/ingest.sh forge/setup-demucs.sh \
          forge/videotrack.sh forge/setup-video.sh forge/package.sh tools/broadcast.sh \
          tools/r2_sync.sh tools/rebroadcast.sh deploy/aether/entrypoint.sh tools/smoke.sh; do
  [ -f "$sh" ] || continue
  if bash -n "$sh" >/dev/null 2>&1; then ok "bash -n $sh"; else bad "bash -n $sh"; fi
done
# AETHER Reach: the RTMP re-broadcast contract must parse, and the encode pipeline
# (audio -> visualizer video -> FLV) must actually produce a stream (dry-run, no
# push, no key). Uses showwaves (most portable ffmpeg filter).
if [ -f deploy/aether/rebroadcast.json ] && command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import json,sys; c=json.load(open("deploy/aether/rebroadcast.json")); sys.exit(0 if c.get("targets") and c.get("video") and c.get("audio") else 1)' >/dev/null 2>&1; then
    ok "rebroadcast.json valid (targets + video + audio)"
  else
    bad "rebroadcast.json malformed or missing targets/video/audio"
  fi
fi
if [ -f tools/rebroadcast.sh ] && command -v ffmpeg >/dev/null 2>&1; then
  RB="$(mktemp -d)/preview.flv"
  if bash tools/rebroadcast.sh --dry-run "$RB" --mode showwaves >/tmp/brahma_rb.log 2>&1 && [ -s "$RB" ]; then
    ok "rebroadcast.sh --dry-run encodes a FLV (audio->visualizer->flv)"
  else
    bad "rebroadcast.sh --dry-run (see /tmp/brahma_rb.log)"; tail -5 /tmp/brahma_rb.log
  fi
  rm -f "$RB"
fi
# AETHER 24/7 sovereign host (deploy/aether): the container deploy unit must be
# structurally sound even though the image build + wrangler deploy are gated.
if [ -f deploy/aether/wrangler.toml ] && command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import tomllib,sys; d=tomllib.load(open("deploy/aether/wrangler.toml","rb")); sys.exit(0 if d.get("name") and d.get("containers") and d.get("r2_buckets") else 1)' >/dev/null 2>&1; then
    ok "deploy/aether/wrangler.toml valid (name + containers + r2_buckets)"
  else
    bad "deploy/aether/wrangler.toml malformed or missing containers/r2_buckets"
  fi
fi
if [ -f deploy/aether/Dockerfile ]; then
  if grep -q '^FROM ' deploy/aether/Dockerfile && grep -q '^ENTRYPOINT' deploy/aether/Dockerfile; then
    ok "deploy/aether/Dockerfile has FROM + ENTRYPOINT"
  else
    bad "deploy/aether/Dockerfile missing FROM or ENTRYPOINT"
  fi
fi
[ -f deploy/aether/README.md ] && ok "exists: deploy/aether/README.md" || bad "missing: deploy/aether/README.md"
for scd in brahma/sc/13_nrt_renderer.scd brahma/sc/14_stem_voices.scd; do
  [ -f "$scd" ] && ok "exists: $scd" || bad "missing: $scd"
done
[ -f brahma/web/public/tree/video.js ] && ok "exists: brahma/web/public/tree/video.js" || bad "missing: brahma/web/public/tree/video.js"
# AETHER theatron player: the live-broadcast surface must ship with the runtime.
[ -f brahma/web/public/aether/index.html ] && ok "exists: brahma/web/public/aether/index.html" || bad "missing: brahma/web/public/aether/index.html"
[ -f brahma/web/public/aether/aether.js ] && ok "exists: brahma/web/public/aether/aether.js" || bad "missing: brahma/web/public/aether/aether.js"
# AETHER playable instrument (tracker-brained, Ableton-bodied).
[ -f brahma/web/public/instrument/index.html ] && ok "exists: brahma/web/public/instrument/index.html" || bad "missing: brahma/web/public/instrument/index.html"
# AETHER Ω integration: seed a submission (a local donor), run a short broadcast
# with --ouroboros, and assert the lineage ledger records the absorption. Proves
# the whole consume-you-back wire (queue pop -> tune -> render -> lineage).
if command -v ffmpeg >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 \
   && [ -f tools/broadcast.sh ] && [ -f tools/ingest_queue.py ]; then
  OB="$(mktemp -d)"; OBLIVE="$OB/live"
  ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=330:duration=2" -ac 2 -ar 44100 "$OB/donor.wav" >/dev/null 2>&1
  python3 tools/ingest_queue.py add --url "$OB/donor.wav" --license cc0 --dir "$OBLIVE/queue" >/dev/null 2>&1
  bash tools/broadcast.sh --out "$OBLIVE" --submit-dir "$OBLIVE/queue" --ouroboros --segments 3 --seconds 1 --list-size 3 >/tmp/brahma_ob.log 2>&1
  if [ -f "$OBLIVE/lineage.json" ] && python3 -c 'import json,sys; d=json.load(open("'"$OBLIVE"'/lineage.json")); sys.exit(0 if d.get("entries") else 1)' >/dev/null 2>&1; then
    ok "Ouroboros: submission absorbed + lineage recorded"
  else
    bad "Ouroboros integration (see /tmp/brahma_ob.log)"; tail -5 /tmp/brahma_ob.log
  fi
  rm -rf "$OB"
fi

echo
echo "=== Summary: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped ==="
if [ "$FAIL" -gt 0 ]; then
  echo "SMOKE: FAIL"
  exit 1
fi
echo "SMOKE: PASS"
