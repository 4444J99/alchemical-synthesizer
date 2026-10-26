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
# Exit codes: 0 ok; nonzero on invalid input, missing tools, or render failure.
# Renderer and timeout process failures retain their original exit status.
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

# Stage next to the destination so publication is atomic and failed attempts
# leave any existing output untouched.
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
case "$SCLANG" in /*) ;; *) SCLANG="$PWD/$SCLANG" ;; esac
case "$SCSYNTH" in /*) ;; *) SCSYNTH="$PWD/$SCSYNTH" ;; esac
out_dir="${OUT%/*}"
mkdir -p -- "${out_dir:-/}"
work="$(mktemp -d "${out_dir:-/}/.brahma-render.XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT
score="$work/pattern.score"

# --- normalize input to the plain score the renderer reads -------------------
# Validate numeric values before creating OSC events or calculating a timeout.
metadata="$(python3 - "$IN" "$score" "$DUR" <<'PY'
import json, math, sys

src, dst, requested = sys.argv[1:]

try:
    with open(src, "r", encoding="utf-8") as fh:
        raw = fh.read()
    rows = []
    if src.lower().endswith(".json") or raw.lstrip().startswith(("{", "[")):
        data = json.loads(raw)
        events = data.get("events") if isinstance(data, dict) else data
        if not isinstance(events, list):
            raise ValueError("JSON has no events array")
        for event in events:
            if not isinstance(event, dict):
                raise ValueError("each event must be an object")
            rows.append(tuple(float(value) for value in (
                event.get("time", 0), event["note"],
                event.get("vel", 0.8), event.get("dur", 0.5))))
    else:
        for line in raw.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) != 4:
                raise ValueError("score rows must contain time, note, velocity, duration")
            rows.append(tuple(map(float, parts)))
    if not rows:
        raise ValueError("no events to render")
    for time, note, velocity, length in rows:
        if not all(map(math.isfinite, (time, note, velocity, length))):
            raise ValueError("event numbers must be finite")
        if time < 0 or not 0 <= note <= 127 or not 0 <= velocity <= 1 or length <= 0:
            raise ValueError("events need time >= 0, MIDI note 0..127, velocity 0..1, duration > 0")
    end = max(time + length for time, _, _, length in rows)
    duration = float(requested) if requested else max(2.0, end + 1.5)
    # Stereo PCM16 at 44.1kHz must fit RIFF's 32-bit data-size field.
    if not math.isfinite(duration) or not 0 < duration < (2**32 - 4096) / 176400 - 1.2:
        raise ValueError("duration must be positive, finite, and fit a PCM16 RIFF WAV")
    if duration < end:
        raise ValueError("duration must cover the end of the last event")
    rows.sort(key=lambda row: row[0])
    with open(dst, "w", encoding="utf-8") as fh:
        fh.write("# brahma pattern score v1\n")
        for row in rows:
            fh.write(" ".join(format(value, ".17g") for value in row) + "\n")
except (OSError, ValueError, TypeError, KeyError) as error:
    sys.stderr.write(f"render-pattern: invalid input: {error}\n")
    sys.exit(2)
print(f"{len(rows)} {duration:.17g} {math.ceil(duration * 4 + 60)}")
PY
)"
read -r n_events DUR limit <<< "$metadata"

# --- write and run the sclang driver -----------------------------------------
# Do not interpolate paths or numbers into SC source. Score.recordNRT itself
# builds a shell command, so its output/OSC filenames are fixed relative names
# inside the private staging directory; paths remain literal filesystem data.
export BRAHMA_RENDER_SCSYNTH="$SCSYNTH" BRAHMA_RENDERER="$RENDERER"
export BRAHMA_RENDER_INPUT="$score" BRAHMA_RENDER_OUTPUT="render.wav"
export BRAHMA_RENDER_DURATION="$DUR"
driver="$work/driver.scd"
cat > "$driver" <<'SCD'
(
try {
    var renderer;
    Server.program = "BRAHMA_RENDER_SCSYNTH".getenv;
    Score.program = Server.program.shellQuote;
    renderer = File.readAllString("BRAHMA_RENDERER".getenv).compile;
    if(renderer.isNil) { Error("NRT renderer failed to compile").throw };
    renderer.value;
    ~nrt_renderer.renderPattern("BRAHMA_RENDER_INPUT".getenv,
        "BRAHMA_RENDER_OUTPUT".getenv, "BRAHMA_RENDER_DURATION".getenv.asFloat, true);
} { |error|
    error.reportError;
    1.exit;
};
)
SCD

echo "render-pattern: sclang=$SCLANG" >&2
echo "render-pattern: ${n_events} events, rendering ${DUR}s -> $OUT" >&2

timeout_bin="$(command -v timeout || command -v gtimeout || true)"
cd -- "$work"
driver="driver.scd"
if [ "$(uname -s)" = "Linux" ]; then
  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
fi
status=0
if [ -n "$timeout_bin" ]; then
  timeout_args=(--kill-after=5)
  if [ "${BRAHMA_SUPERVISED_PROCESS_GROUP:-0}" = "1" ]; then
    # The gateway owns this process group and its timeout. Keep descendants in
    # that group so cancellation reaches sclang, scsynth and the watchdog.
    timeout_args=(--foreground "${timeout_args[@]}")
  fi
  "$timeout_bin" "${timeout_args[@]}" "$limit" "$SCLANG" -D -u 0 "$driver" || status=$?
else
  python3 - "$limit" "$SCLANG" "$driver" <<'PY' || status=$?
import os, signal, subprocess, sys
own_group = os.environ.get("BRAHMA_SUPERVISED_PROCESS_GROUP") != "1"
child = subprocess.Popen([sys.argv[2], "-D", "-u", "0", sys.argv[3]],
                         start_new_session=own_group)
try:
    status = child.wait(timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    if own_group:
        os.killpg(child.pid, signal.SIGTERM)
    else:
        child.terminate()
    try:
        child.wait(timeout=5)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait()
    status = 124
finally:
    if own_group:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
sys.exit(status if status >= 0 else 128 - status)
PY
fi

if [ "$status" -ne 0 ]; then
  echo "render-pattern: FAILED — renderer exited with status $status" >&2
  exit "$status"
fi

python3 - "$work/render.wav" "$OUT" "$DUR" <<'PY'
import os, sys, wave
try:
    with wave.open(sys.argv[1], "rb") as audio:
        if (audio.getnchannels(), audio.getframerate(), audio.getsampwidth(), audio.getcomptype()) != (2, 44100, 2, "NONE"):
            raise ValueError("expected stereo 44.1kHz PCM16 WAV")
        frames = audio.getnframes()
        if frames <= 0 or abs(frames - (float(sys.argv[3]) + 1.2) * 44100) > 128:
            raise ValueError("render duration does not match the requested duration plus 1.2s tail")
        count = 0
        while chunk := audio.readframes(65536):
            count += len(chunk)
        if count != frames * 4:
            raise ValueError("truncated WAV sample data")
    os.replace(sys.argv[1], sys.argv[2])
except (OSError, ValueError, EOFError, wave.Error) as error:
    sys.exit(f"render-pattern: FAILED — {error}")
print(f"render-pattern: OK -> {sys.argv[2]} ({frames / 44100:.3f}s)")
PY
