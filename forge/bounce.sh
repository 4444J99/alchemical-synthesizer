#!/usr/bin/env bash
# bounce.sh — Headless render: a song/stem/premix -> a Brahma-re-expressed WAV.
#
# Drives brahma/sc/13_nrt_renderer.scd through sclang + scsynth -N with NO audio
# device and NO GUI. This is the spine command behind `make render`.
#
#   Usage:  forge/bounce.sh <input.wav|mp3|...> <output.wav> [duration_seconds]
#   e.g.    forge/bounce.sh forge/recipes/heist/premix.wav out/heist.wav 12
#
# Locates SuperCollider whether or not it is on PATH (macOS app bundle included).
set -euo pipefail

IN="${1:?usage: bounce.sh <input> <output.wav> [duration]}"
OUT="${2:?usage: bounce.sh <input> <output.wav> [duration]}"
DUR="${3:-}"

HERE="$(cd "$(dirname "$0")/.." && pwd)"           # repo root
RENDERER="$HERE/brahma/sc/13_nrt_renderer.scd"

command -v ffmpeg  >/dev/null 2>&1 || { echo "bounce: ffmpeg required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "bounce: python3 required" >&2; exit 2; }
[ -f "$IN" ]       || { echo "bounce: no such input: $IN" >&2; exit 2; }
[ -f "$RENDERER" ] || { echo "bounce: renderer missing: $RENDERER" >&2; exit 2; }

# --- locate SuperCollider (PATH, then common macOS/Linux app-bundle paths) ---
find_bin(){ # $1=name  $2..=candidate absolute paths
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
  echo "bounce: SuperCollider not found (need sclang + scsynth). Install SuperCollider 3.13+." >&2
  exit 3
fi

# Stage on the destination filesystem: a failed render must never touch an
# existing artifact, and a verified result is published with one atomic rename.
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
case "$SCLANG" in /*) ;; *) SCLANG="$PWD/$SCLANG" ;; esac
case "$SCSYNTH" in /*) ;; *) SCSYNTH="$PWD/$SCSYNTH" ;; esac
out_dir="${OUT%/*}"
mkdir -p -- "${out_dir:-/}"
work="$(mktemp -d "${out_dir:-/}/.brahma-render.XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT

# --- normalize the food to stereo 44.1k WAV (renderer expects 2ch) ---
food="$work/food.wav"
ffmpeg -hide_banner -loglevel error -y -i "$IN" -ac 2 -ar 44100 -c:a pcm_s16le "$food"

# Keep fractions and reject non-finite/code-like input before starting sclang.
# The upper bound is the 32-bit RIFF data-size limit for stereo PCM16 at 44.1k.
metadata="$(python3 - "$DUR" "$food" <<'PY'
import math, sys, wave
try:
    if sys.argv[1]:
        duration = float(sys.argv[1])
    else:
        with wave.open(sys.argv[2], "rb") as audio:
            duration = audio.getnframes() / audio.getframerate()
    if not math.isfinite(duration) or not 0 < duration < (2**32 - 4096) / 176400 - 0.6:
        raise ValueError("duration must be positive, finite, and fit a PCM16 RIFF WAV")
except (ValueError, OSError, wave.Error) as error:
    sys.exit(f"bounce: invalid duration: {error}")
print(f"{duration:.17g} {math.ceil(duration * 4 + 60)}")
PY
)"
read -r DUR limit <<< "$metadata"

# Values travel as environment data, never interpolated SuperCollider source.
# Score.recordNRT uses shell quoting internally; fixed relative output names in
# the staging working directory also keep user paths out of that shell command.
export BRAHMA_RENDER_SCSYNTH="$SCSYNTH" BRAHMA_RENDERER="$RENDERER"
export BRAHMA_RENDER_INPUT="$food" BRAHMA_RENDER_OUTPUT="render.wav"
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
    ~nrt_renderer.renderSpecimen("BRAHMA_RENDER_INPUT".getenv,
        "BRAHMA_RENDER_OUTPUT".getenv, "BRAHMA_RENDER_DURATION".getenv.asFloat, true);
} { |error|
    error.reportError;
    1.exit;
};
)
SCD

echo "bounce: sclang=$SCLANG" >&2
echo "bounce: rendering ${DUR}s  $IN -> $OUT" >&2

# --- run sclang headless with a wall-clock safety timeout ---
timeout_bin="$(command -v timeout || command -v gtimeout || true)"
cd -- "$work"
# sclang's command-line file loading also requires a literal simple filename.
driver="driver.scd"
if [ "$(uname -s)" = "Linux" ]; then
  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
fi
status=0
if [ -n "$timeout_bin" ]; then
  timeout_args=(--kill-after=5)
  if [ "${BRAHMA_SUPERVISED_PROCESS_GROUP:-0}" = "1" ]; then
    timeout_args=(--foreground "${timeout_args[@]}")
  fi
  "$timeout_bin" "${timeout_args[@]}" "$limit" "$SCLANG" -D -u 0 "$driver" || status=$?
else
  # macOS without coreutils: bound the process without discarding its status.
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
  echo "bounce: FAILED — renderer exited with status $status" >&2
  exit "$status"
fi

# A nonempty file is insufficient: verify the complete expected PCM payload.
python3 - "$work/render.wav" "$OUT" "$DUR" <<'PY'
import os, sys, wave
try:
    with wave.open(sys.argv[1], "rb") as audio:
        if (audio.getnchannels(), audio.getframerate(), audio.getsampwidth(), audio.getcomptype()) != (2, 44100, 2, "NONE"):
            raise ValueError("expected stereo 44.1kHz PCM16 WAV")
        frames = audio.getnframes()
        if frames <= 0 or abs(frames - (float(sys.argv[3]) + 0.6) * 44100) > 128:
            raise ValueError("render duration does not match the requested duration plus 0.6s tail")
        count = 0
        while chunk := audio.readframes(65536):
            count += len(chunk)
        if count != frames * 4:
            raise ValueError("truncated WAV sample data")
    os.replace(sys.argv[1], sys.argv[2])
except (OSError, ValueError, EOFError, wave.Error) as error:
    sys.exit(f"bounce: FAILED — {error}")
print(f"bounce: OK -> {sys.argv[2]} ({frames / 44100:.3f}s)")
PY
