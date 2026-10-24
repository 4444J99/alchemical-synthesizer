#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# render-pattern.sh — render a *pattern* (note events) to a WAV, headless.
#
# This is the sibling of bounce.sh, not a replacement: bounce.sh re-expresses an
# existing audio file; this renders note events that were never audio. Both drive
# brahma/sc/13_nrt_renderer.scd through scsynth -N with no audio device and no GUI.
#
#   Usage:  forge/render-pattern.sh <pattern.json|score.txt> <output.wav> [duration_seconds]
#
# JSON form (either {"events":[...]} or a bare array):
#   {"events": [
#     {"time": 0.0,  "note": 60, "vel": 0.8, "dur": 0.5},
#     {"time": 0.5,  "note": 64, "vel": 0.8, "dur": 0.5}
#   ]}
#
# Plain-score form (one event per line, whitespace separated):
#   <time_seconds> <midi_note> <velocity 0..1> <duration_seconds>
#
# Exit codes: 0 ok · 2 usage/input · 3 SuperCollider or python3 missing · 4 render failed
set -euo pipefail

IN="${1:?usage: render-pattern.sh <pattern.json|score.txt> <output.wav> [duration]}"
OUT="${2:?usage: render-pattern.sh <pattern.json|score.txt> <output.wav> [duration]}"
DUR="${3:-}"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
RENDERER="$HERE/brahma/sc/13_nrt_renderer.scd"

[ -f "$IN" ]       || { echo "render-pattern: no such input: $IN" >&2; exit 2; }
[ -f "$RENDERER" ] || { echo "render-pattern: renderer missing: $RENDERER" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "render-pattern: python3 required" >&2; exit 3; }

find_bin(){ # $1=name $2..=candidate absolute paths
  local n="$1"; shift
  if command -v "$n" >/dev/null 2>&1; then command -v "$n"; return 0; fi
  local c; for c in "$@"; do [ -x "$c" ] && { echo "$c"; return 0; }; done
  return 1
}
SCLANG="$(find_bin sclang \
  /Applications/SuperCollider/SuperCollider.app/Contents/MacOS/sclang \
  /Applications/SuperCollider.app/Contents/MacOS/sclang \
  /usr/local/bin/sclang /opt/homebrew/bin/sclang || true)"
SCSYNTH="$(find_bin scsynth \
  /Applications/SuperCollider/SuperCollider.app/Contents/Resources/scsynth \
  /Applications/SuperCollider.app/Contents/Resources/scsynth \
  /usr/local/bin/scsynth /opt/homebrew/bin/scsynth || true)"
if [ -z "$SCLANG" ] || [ -z "$SCSYNTH" ]; then
  echo "render-pattern: SuperCollider not found (need sclang + scsynth). Install SuperCollider 3.13+." >&2
  exit 3
fi

mkdir -p "$(dirname "$OUT")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
score="$work/pattern.score"

# --- normalize input to the plain score the renderer reads -------------------
# sclang has no JSON parser in this build, so conversion happens here, once.
python3 - "$IN" "$score" <<'PY'
import json, sys

src, dst = sys.argv[1], sys.argv[2]

with open(src, "r", encoding="utf-8") as fh:
    raw = fh.read()

events = None
if src.lower().endswith(".json") or raw.lstrip().startswith(("{", "[")):
    data = json.loads(raw)
    events = data.get("events") if isinstance(data, dict) else data
    if not isinstance(events, list):
        sys.stderr.write("render-pattern: JSON has no events array\n")
        sys.exit(2)
    rows = []
    for e in events:
        rows.append((
            float(e.get("time", 0.0)),
            float(e["note"]),
            float(e.get("vel", 0.8)),
            float(e.get("dur", 0.5)),
        ))
else:
    rows = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 4:
            continue
        rows.append((float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])))

if not rows:
    sys.stderr.write("render-pattern: no events to render\n")
    sys.exit(2)

rows.sort(key=lambda r: r[0])
with open(dst, "w", encoding="utf-8") as fh:
    fh.write("# brahma pattern score v1\n")
    for t, note, vel, dur in rows:
        fh.write(f"{t:.4f} {note:g} {vel:.4f} {dur:.4f}\n")

end = max(t + d for t, _, _, d in rows)
PY

# First line of stdout is "<event_count> <last_event_end>"; also tail the file so the
# numbers come from the score actually written, not from a parallel computation.
n_events="$(grep -vc '^#' "$score" || true)"
end_time="$(python3 - "$score" <<'PY'
import sys
rows = [l.split() for l in open(sys.argv[1]) if not l.startswith("#") and l.strip()]
print(f"{max(float(r[0]) + float(r[3]) for r in rows):.4f}")
PY
)"

if [ -z "$DUR" ]; then
  DUR="$(python3 -c "print(max(2.0, $end_time + 1.5))")"
fi

# --- write and run the sclang driver -----------------------------------------
driver="$work/driver.scd"
cat > "$driver" <<SCD
Server.program = "$SCSYNTH";
"$RENDERER".load;
~nrt_renderer.renderPattern("$score", "$OUT", ${DUR}.asFloat, true);
SCD

echo "render-pattern: sclang=$SCLANG" >&2
echo "render-pattern: ${n_events} events, rendering ${DUR}s -> $OUT" >&2

timeout_bin="$(command -v timeout || command -v gtimeout || true)"
limit=$(( ${DUR%.*} * 4 + 60 ))
if [ -n "$timeout_bin" ]; then
  "$timeout_bin" "$limit" "$SCLANG" "$driver" || true
else
  "$SCLANG" "$driver" &
  pid=$!
  ( sleep "$limit"; kill "$pid" 2>/dev/null || true ) & watcher=$!
  wait "$pid" 2>/dev/null || true
  kill "$watcher" 2>/dev/null || true
fi

rm -f "$OUT.osc" 2>/dev/null || true
if [ -s "$OUT" ]; then
  dur_out="$(python3 - "$OUT" <<'PY'
import sys, wave
try:
    with wave.open(sys.argv[1], "rb") as w:
        print(f"{w.getnframes() / w.getframerate():.2f}")
except Exception:
    print("?")
PY
)"
  echo "render-pattern: OK -> $OUT (${dur_out}s)"
else
  echo "render-pattern: FAILED — no output produced (see sclang output above)" >&2
  exit 4
fi
