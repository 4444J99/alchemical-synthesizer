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
#   5. Web endpoint — Visual Cortex boots, serves HTTP 200, and answers MCP on both
#                     wires (HTTP /mcp + stdio bridge) with the role-scoped tool list
#                     (needs npm deps)
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

# Share this invocation's install output with boot diagnostics, never another run.
NPM_LOG="$(mktemp "${TMPDIR:-/tmp}/brahma-npm.XXXXXX")" || exit 1
trap 'rm -f -- "$NPM_LOG"' EXIT

echo "=== [1/6] Structure ==="
req_files=(
  "brahma/sc/loader.scd"
  "brahma/web/server.js"
  "brahma/web/bin/brahma-mcp.js"
  "brahma/web/lib/mcp/server.js"
  "brahma/web/lib/mcp/client.js"
  "brahma/web/public/instrument/sample-project.js"
  "brahma/web/public/instrument/sample-audio.js"
  "brahma/web/public/instrument/sample-controls.js"
  "docs/agent-clients.md"
  "brahma/ableton/src/index.js"
  "forge/validate_audio.py"
  "forge/assimilate.py"
  "brahma/sc/32_donor_rack.scd"
  "forge/native-controls.json"
  "forge/materials.json"
  "forge/materials.py"
  "forge/compare.py"
  "brahma/web/public/instrument/material-model.js"
  "brahma/web/public/instrument/material-controls.js"
  "brahma/web/public/instrument/material-vessels.css"
  "tools/verify-material-vessels.cjs"
  "forge/sketch.py"
  "tools/verify-song-sketch.cjs"
  "brahma/web/public/instrument/native-controls.js"
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
  # Native sample service tests require brahma/web deps (express), but [5/6]
  # installs them only after this section runs, so on a clean checkout the
  # [3/6] gate fails with MODULE_NOT_FOUND before it ever reaches [5/6].
  # Install here first; [5/6] skips reinstall when node_modules already exists.
  if [ ! -d brahma/web/node_modules ]; then
    echo "  ... installing web deps early for [3/6] (npm ci/install)"
    ( cd brahma/web && { npm ci --no-audit --no-fund >"$NPM_LOG" 2>&1 \
        || npm install --no-audit --no-fund >"$NPM_LOG" 2>&1; } )
  fi
  for js in brahma/web/server.js brahma/web/bin/brahma-mcp.js \
            brahma/web/lib/mcp/server.js brahma/web/lib/mcp/client.js \
            brahma/web/public/sketch.js \
            brahma/web/public/tree/video.js aether/web/listener/aether.js \
            brahma/web/public/instrument/pattern.js brahma/web/public/instrument/instrument.js \
            brahma/web/public/instrument/sample-project.js brahma/web/public/instrument/sample-audio.js \
            brahma/web/public/instrument/sample-controls.js \
            brahma/web/public/instrument/native-controls.js \
            brahma/web/public/instrument/material-model.js brahma/web/public/instrument/material-controls.js \
            tools/verify-material-vessels.cjs \
            tools/verify-song-sketch.cjs \
            aether/deploy/serve.js aether/deploy/worker.mjs forge/render_video.mjs; do
    [ -f "$js" ] || continue
    if node --check "$js" >/dev/null 2>&1; then ok "node --check $js"; else bad "node --check $js"; fi
  done
  # The tracker/sampler instrument's brain (pattern.js) is pure + node-testable.
  if [ -f brahma/web/public/instrument/pattern.js ]; then
    if node brahma/web/public/instrument/pattern.js --self-test >/tmp/brahma_pattern.log 2>&1; then ok "instrument pattern.js --self-test"; else bad "instrument pattern.js --self-test"; tail -8 /tmp/brahma_pattern.log; fi
  fi
  if node --test brahma/web/test/sample-project.test.js >/tmp/brahma_sample_project.log 2>&1; then
    ok "sample project contracts (audio integrity, bounds, pattern references)"
  else
    bad "sample project contracts (see /tmp/brahma_sample_project.log)"; tail -12 /tmp/brahma_sample_project.log
  fi
  if node --test brahma/web/test/native-samples.test.js >/tmp/brahma_native_samples.log 2>&1; then
    ok "native sample service admission, authorization, cancellation and integrity contracts"
  else
    bad "native sample service contracts"; tail -12 /tmp/brahma_native_samples.log
  fi
  if node --test brahma/web/test/materials.test.js >/tmp/brahma_materials_node.log 2>&1; then
    ok "material model and Node/Python resolution parity"
  else
    bad "material model contracts"; tail -12 /tmp/brahma_materials_node.log
  fi
else
  skip "node not installed — JS syntax"
fi

echo "=== [4/6] Python audio validator ==="
if command -v python3 >/dev/null 2>&1; then
  if python3 -m unittest tools.tests.test_materials tools.tests.test_material_comparison >/tmp/brahma_materials_python.log 2>&1; then
    ok "material and source-bound comparison contracts"
  else
    bad "material comparison contracts"; tail -12 /tmp/brahma_materials_python.log
  fi
  if python3 -m unittest discover -s tools/tests -p 'test_assimilate.py' >/tmp/brahma_assimilate.log 2>&1; then
    ok "donor assimilation contracts (native integration separately opt-in)"
  else
    bad "donor assimilation contracts"; tail -12 /tmp/brahma_assimilate.log
  fi
  if python3 -m unittest discover -s tools/tests -p 'test_sketch.py' >/tmp/brahma_sketch.log 2>&1; then
    ok "portable native song sketch contracts"
  else
    bad "portable native song sketch contracts"; tail -12 /tmp/brahma_sketch.log
  fi
  TONE="$(mktemp -d)/test_tone.wav"
  if python3 tools/gen_test_tone.py "$TONE" >/dev/null 2>&1 \
     && python3 forge/validate_audio.py "$TONE" >/tmp/brahma_validator.log 2>&1; then
    ok "validate_audio.py accepts generated tone"
  else
    bad "validate_audio.py (see /tmp/brahma_validator.log)"; tail -8 /tmp/brahma_validator.log
  fi
  # M3: the measurement mode the agent loop depends on. Proves the flag is wired and
  # that a real tone measures as sound rather than coming back empty.
  if [ -f forge/analyze_audio.py ] && command -v ffmpeg >/dev/null 2>&1; then
    if python3 forge/analyze_audio.py "$TONE" --summary-json /tmp/brahma_summary.json >/tmp/brahma_summary.log 2>&1 \
       && python3 -c 'import json,sys; d=json.load(open("/tmp/brahma_summary.json")); sys.exit(0 if d.get("verdict")=="non_silent" and d.get("peak_dbfs") is not None else 1)'; then
      ok "analyze_audio.py --summary-json measures a real tone"
    else
      bad "analyze_audio.py --summary-json (see /tmp/brahma_summary.log)"; tail -5 /tmp/brahma_summary.log
    fi
  else
    skip "ffmpeg not installed — audio summary"
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
    ( cd brahma/web && { npm ci --no-audit --no-fund >"$NPM_LOG" 2>&1 \
        || npm install --no-audit --no-fund >"$NPM_LOG" 2>&1; } )
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
    # A fixed agent token makes the MCP surface testable end to end. The gateway writes
    # it to brahma/web/.runtime/agent-token-<port> (0600); the stdio bridge below reads
    # that file, so this proves the handoff the four clients rely on.
    SMOKE_AGENT_TOKEN="smoke-agent-token-0001"
    # exec, so $! is node's own PID rather than a subshell: the teardown below has
    # to actually release the port, or the next run fails with EADDRINUSE.
    ( cd brahma/web && exec env PORT=$PORT BRAHMA_AGENT_TOKEN="$SMOKE_AGENT_TOKEN" node server.js >/tmp/brahma_web.log 2>&1 ) &
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
    # Snapshot the process before teardown. A 000 means either "died" or "never
    # bound", and those need different fixes; killing first destroys the evidence
    # and makes the liveness message below meaningless.
    if kill -0 "$WEB_PID" 2>/dev/null; then
      if command -v ss >/dev/null 2>&1; then
        listening="$(ss -ltn 2>/dev/null | grep -c ":${PORT} " || true)"
      else
        listening="$(lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null | grep -c LISTEN || true)"
      fi
      probe_state="alive ($(ps -o stat= -p "$WEB_PID" 2>/dev/null | tr -d ' ')), listening=${listening:-?}"
    else
      probe_state="gone"
    fi
    api="$(curl -q -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/api/modules" 2>/dev/null || echo 000)"
    wb="$(curl -q -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/workbench/" 2>/dev/null || echo 000)"
    wbsrc="$(curl -q -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/workbench/source.json" 2>/dev/null || echo 000)"
    # The agent loop must refuse an unauthenticated caller. A 200 here would mean the
    # approval boundary is open to anything that can reach loopback.
    agent_anon="$(curl -q -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/api/agent/providers" 2>/dev/null || echo 000)"
    # MCP: same boundary, both wires. The agent tool list must offer propose and must
    # NOT offer accept/run — that is the structural gate, not a policy note.
    mcp_anon="$(curl -q -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
      "http://127.0.0.1:${PORT}/mcp" 2>/dev/null || echo 000)"
    curl -q -s -X POST -H 'content-type: application/json' \
      -H "authorization: Bearer ${SMOKE_AGENT_TOKEN}" \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
      "http://127.0.0.1:${PORT}/mcp" >/tmp/brahma_mcp_tools.json 2>/dev/null
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
      | ( cd "$ROOT" && BRAHMA_GATEWAY_URL="http://127.0.0.1:${PORT}" node brahma/web/bin/brahma-mcp.js ) \
      >/tmp/brahma_mcp_stdio.json 2>/tmp/brahma_mcp_stdio.err
    if [ "$code" = "200" ] && [ "$api" = "200" ]; then
      ok "Visual Cortex served / (200) and /api/modules (200)"; web_ok=1
    else
      bad "Visual Cortex boot (/ = $code, /api/modules = $api; see /tmp/brahma_web.log)"
      echo "=== brahma_web.log ==="
      cat /tmp/brahma_web.log 2>/dev/null || echo "(no log)"
      # A server that answers 000 leaves a one-line log and no explanation. Capture
      # the facts that distinguish the causes: whether the process survived, whether
      # it ever took the port, whether the dependency tree and its native binding
      # are real, and how the install ended.
      echo "=== boot diagnostics ==="
      echo "server: ${probe_state:-unknown}"
      echo "node: $(node -v 2>&1)"
      echo "web modules: $(ls brahma/web/node_modules 2>/dev/null | wc -l | tr -d ' ')"
      echo "require osc: $( ( cd brahma/web && node -e 'require("osc"); console.log("ok")' ) 2>&1 | tail -2 | tr '\n' ' ')"
      tail -3 "$NPM_LOG" 2>/dev/null | sed 's/^/npm: /'
      echo "=== end diagnostics ==="
    fi
    if [ "$wb" = "200" ] && [ "$wbsrc" = "200" ]; then
      ok "workbench page + source offer served (200/200)"
    else
      bad "workbench served (/workbench/ = $wb, source.json = $wbsrc)"
    fi
    if [ "$agent_anon" = "401" ]; then
      ok "agent API refuses unauthenticated callers (401)"
    else
      bad "agent API auth gate (expected 401, got $agent_anon)"
    fi
    if [ "$mcp_anon" = "401" ]; then
      ok "MCP endpoint refuses unauthenticated callers (401)"
    else
      bad "MCP auth gate (expected 401, got $mcp_anon)"
    fi
    if python3 -c 'import json,sys; d=json.load(open("/tmp/brahma_mcp_tools.json")); n=[t["name"] for t in d["result"]["tools"]]; sys.exit(0 if "brahma_propose_pattern" in n and "brahma_accept" not in n and "brahma_run" not in n else 1)' >/dev/null 2>&1; then
      ok "MCP agent tools: propose yes, accept/run no"
    else
      bad "MCP agent tool list is wrong (see /tmp/brahma_mcp_tools.json)"
    fi
    if grep -q '"brahma-workbench"' /tmp/brahma_mcp_stdio.json 2>/dev/null; then
      ok "stdio MCP bridge handshake (initialize → brahma-workbench)"
    else
      bad "stdio MCP bridge failed (see /tmp/brahma_mcp_stdio.err)"
    fi
    # The launch URL must point at the page that can actually claim the token.
    if grep -q "/workbench/#t=" /tmp/brahma_web.log 2>/dev/null; then
      ok "human launch URL targets /workbench/#t="
    else
      bad "human launch URL does not target the workbench (see /tmp/brahma_web.log)"
    fi
    # Teardown last, so every check above reads a live server and the failure
    # diagnostics can still see the process.
    kill "$WEB_PID" >/dev/null 2>&1; wait "$WEB_PID" 2>/dev/null
  else
    if [ "$STRICT" = "1" ]; then bad "could not install web deps (offline?)"; else skip "web deps unavailable (offline) — endpoint boot"; fi
    tail -8 "$NPM_LOG" 2>/dev/null | sed 's/^/npm: /'
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
  for py in forge/sketch.py forge/assimilate.py forge/rip.py forge/stemforge.py forge/analyze_audio.py forge/validate_audio.py tools/gen_test_tone.py aether/tools/tune.py aether/tools/cellcycle.py aether/tools/hls_append.py; do
    [ -f "$py" ] || continue
    if python3 -m py_compile "$py" >/tmp/brahma_pyc.log 2>&1; then ok "py_compile $py"; else bad "py_compile $py (see /tmp/brahma_pyc.log)"; tail -5 /tmp/brahma_pyc.log; fi
  done
  # AETHER Broadcast: the generator organism and the transport plane each carry
  # their own executable predicate (deterministic assertions). These prove the
  # live-radio muscle, not just that the files parse.
  if [ -f aether/tools/cellcycle.py ]; then
    if python3 aether/tools/cellcycle.py --self-test >/tmp/brahma_cellcycle.log 2>&1; then ok "cellcycle.py --self-test"; else bad "cellcycle.py --self-test"; tail -8 /tmp/brahma_cellcycle.log; fi
  fi
  if [ -f aether/tools/hls_append.py ]; then
    if python3 aether/tools/hls_append.py --self-test >/tmp/brahma_hls.log 2>&1; then ok "hls_append.py --self-test"; else bad "hls_append.py --self-test"; tail -8 /tmp/brahma_hls.log; fi
  fi
  # AETHER Ω (Ouroboros): the submission queue + the lineage ledger authorities.
  if [ -f aether/tools/ingest_queue.py ]; then
    if python3 aether/tools/ingest_queue.py --self-test >/tmp/brahma_q.log 2>&1; then ok "ingest_queue.py --self-test"; else bad "ingest_queue.py --self-test"; tail -8 /tmp/brahma_q.log; fi
  fi
  if [ -f aether/tools/lineage.py ]; then
    if python3 aether/tools/lineage.py --self-test >/tmp/brahma_lin.log 2>&1; then ok "lineage.py --self-test"; else bad "lineage.py --self-test"; tail -8 /tmp/brahma_lin.log; fi
  fi
  # AETHER source registry: must parse, and EVERY station must carry a license
  # (a source with no license tag could silently slip the publish-safety guard).
  if [ -f aether/stations.json ]; then
    if python3 -c 'import json,sys; d=json.load(open("aether/stations.json")); s=d.get("stations",[]); sys.exit(0 if s and all(x.get("license") and x.get("url") and x.get("name") for x in s) else 1)' >/dev/null 2>&1; then
      ok "stations.json: all sources carry name+url+license"
    else
      bad "stations.json: malformed or a source is missing name/url/license"
    fi
    # tune.py --list must run against the registry without error.
    if python3 aether/tools/tune.py --list >/dev/null 2>&1; then ok "tune.py --list"; else bad "tune.py --list"; fi
  fi
else
  skip "python3 not installed — Forge py syntax"
fi
for sh in forge/forge.sh forge/bounce.sh forge/render-pattern.sh forge/ingest.sh forge/setup-demucs.sh \
          forge/videotrack.sh forge/setup-video.sh forge/package.sh aether/tools/broadcast.sh \
          aether/tools/r2_sync.sh aether/tools/rebroadcast.sh aether/deploy/entrypoint.sh tools/smoke.sh; do
  [ -f "$sh" ] || continue
  if bash -n "$sh" >/dev/null 2>&1; then ok "bash -n $sh"; else bad "bash -n $sh"; fi
done
# AETHER Reach: the RTMP re-broadcast contract must parse, and the encode pipeline
# (audio -> visualizer video -> FLV) must actually produce a stream (dry-run, no
# push, no key). Uses showwaves (most portable ffmpeg filter).
if [ -f aether/deploy/rebroadcast.json ] && command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import json,sys; c=json.load(open("aether/deploy/rebroadcast.json")); sys.exit(0 if c.get("targets") and c.get("video") and c.get("audio") else 1)' >/dev/null 2>&1; then
    ok "rebroadcast.json valid (targets + video + audio)"
  else
    bad "rebroadcast.json malformed or missing targets/video/audio"
  fi
fi
if [ -f aether/tools/rebroadcast.sh ] && command -v ffmpeg >/dev/null 2>&1; then
  RB="$(mktemp -d)/preview.flv"
  if bash aether/tools/rebroadcast.sh --dry-run "$RB" --mode showwaves >/tmp/brahma_rb.log 2>&1 && [ -s "$RB" ]; then
    ok "rebroadcast.sh --dry-run encodes a FLV (audio->visualizer->flv)"
  else
    bad "rebroadcast.sh --dry-run (see /tmp/brahma_rb.log)"; tail -5 /tmp/brahma_rb.log
  fi
  rm -f "$RB"
fi
# AETHER 24/7 sovereign host (deploy/aether): the container deploy unit must be
# structurally sound even though the image build + wrangler deploy are gated.
if [ -f aether/deploy/wrangler.toml ] && command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import tomllib,sys; d=tomllib.load(open("aether/deploy/wrangler.toml","rb")); sys.exit(0 if d.get("name") and d.get("containers") and d.get("r2_buckets") else 1)' >/dev/null 2>&1; then
    ok "aether/deploy/wrangler.toml valid (name + containers + r2_buckets)"
  else
    bad "aether/deploy/wrangler.toml malformed or missing containers/r2_buckets"
  fi
fi
if [ -f aether/deploy/Dockerfile ]; then
  if grep -q '^FROM ' aether/deploy/Dockerfile && grep -q '^ENTRYPOINT' aether/deploy/Dockerfile; then
    ok "aether/deploy/Dockerfile has FROM + ENTRYPOINT"
  else
    bad "aether/deploy/Dockerfile missing FROM or ENTRYPOINT"
  fi
  if python3 tools/check-aether-context.py >/tmp/brahma_docker_context.log 2>&1; then
    ok "AETHER Dockerfile COPY sources exist in the declared build context"
  else
    bad "AETHER Dockerfile COPY sources (see /tmp/brahma_docker_context.log)"
    cat /tmp/brahma_docker_context.log
  fi
fi
[ -f aether/deploy/README.md ] && ok "exists: aether/deploy/README.md" || bad "missing: aether/deploy/README.md"
for scd in brahma/sc/13_nrt_renderer.scd brahma/sc/14_stem_voices.scd; do
  [ -f "$scd" ] && ok "exists: $scd" || bad "missing: $scd"
done
[ -f brahma/web/public/tree/video.js ] && ok "exists: brahma/web/public/tree/video.js" || bad "missing: brahma/web/public/tree/video.js"
# AETHER theatron player: the live-broadcast surface must ship with the runtime.
[ -f aether/web/listener/index.html ] && ok "exists: aether/web/listener/index.html" || bad "missing: aether/web/listener/index.html"
[ -f aether/web/listener/aether.js ] && ok "exists: aether/web/listener/aether.js" || bad "missing: aether/web/listener/aether.js"
# AETHER playable instrument (tracker-brained, Ableton-bodied).
[ -f brahma/web/public/instrument/index.html ] && ok "exists: brahma/web/public/instrument/index.html" || bad "missing: brahma/web/public/instrument/index.html"
# AETHER Ω integration: seed a submission (a local donor), run a short broadcast
# with --ouroboros, and assert the lineage ledger records the absorption. Proves
# the whole consume-you-back wire (queue pop -> tune -> render -> lineage).
if command -v ffmpeg >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 \
   && [ -f aether/tools/broadcast.sh ] && [ -f aether/tools/ingest_queue.py ]; then
  OB="$(mktemp -d)"; OBLIVE="$OB/live"
  ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=330:duration=2" -ac 2 -ar 44100 "$OB/donor.wav" >/dev/null 2>&1
  python3 aether/tools/ingest_queue.py add --url "$OB/donor.wav" --license cc0 --dir "$OBLIVE/queue" >/dev/null 2>&1
  bash aether/tools/broadcast.sh --out "$OBLIVE" --submit-dir "$OBLIVE/queue" --ouroboros --segments 3 --seconds 1 --list-size 3 >/tmp/brahma_ob.log 2>&1
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
