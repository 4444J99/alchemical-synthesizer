#!/usr/bin/env bash
# ============================================================================
#  broadcast.sh — Brahma's living radio: the segmented-NRT -> live-HLS loop.
# ----------------------------------------------------------------------------
#  The AETHER "Broadcast" increment (docs/AETHER-BROADCAST-PLAN.md §5.1). Ties
#  the three planes together into one continuous, evolving performance:
#
#    1. GENERATOR  tools/cellcycle.py advances the METABOLISM organism one
#                  segment (carrying state forward) and emits its genome.
#    2. RENDER     the genome's segment is produced. Three tiers, degrading
#                  gracefully so the stream NEVER goes silent:
#                    a. SuperCollider present + a donor source  -> bounce.sh
#                       Brahma-re-expresses it (true NRT re-expression).
#                    b. a donor source but no SC  -> trim/loop the donor.
#                    c. no source at all          -> synthesize a genome-reactive
#                       tone (pitch per creature, tremolo by entropy).
#    3. TRANSPORT  tools/hls_append.py rolls the chunk into a LIVE HLS playlist
#                  (no #EXT-X-ENDLIST) with a rolling window. Static files =
#                  sovereign, self-hostable (R2/Pages/a plain dir), no RTMP push.
#
#  The organism's provisional inner life (coherence/entropy — NOT real
#  measurements, per docs/logos/pragma.md) is written to <out>/telemetry.json
#  for the theatron player overlay, and every folded donor is recorded in the
#  lineage (the stream is a lineage, not a loop).
#
#  Usage:
#    tools/broadcast.sh [--out DIR] [--source tuned.wav] [--segments N]
#                       [--seconds S] [--seed K] [--period P] [--list-size L]
#                       [--abr 160k] [--no-nrt] [--finalize]
#
#    make broadcast                         # forever, self-generating tone
#    make broadcast SOURCE=out/tuned/x.wav  # fold a tune capture in
#    tools/broadcast.sh --segments 4 --seconds 2   # bounded local proof
#
#  --segments 0 (default) streams forever; a positive N bounds it (CI/local
#  proof). --finalize stamps #EXT-X-ENDLIST on exit (archive the run as VOD).
#
#  Exit: 0 ok · 2 usage · 3 ffmpeg missing
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"   # repo root
OUT="$HERE/out/live"
SOURCE=""
SEGMENTS=0            # 0 = forever
SECONDS_OVERRIDE=""   # cap/override the organism's per-segment seconds
SEED=1
PERIOD=12
LIST_SIZE=6
ABR="160k"
NO_NRT=0
FINALIZE=0
OUROBOROS=0           # --ouroboros: re-feed own output as input ("consume you back")
SUBMIT_DIR=""         # Ω queue: viewer submissions a creature eats live

while [ $# -gt 0 ]; do
  case "$1" in
    --out)        OUT="$2"; shift 2;;
    --source)     SOURCE="$2"; shift 2;;
    --segments)   SEGMENTS="$2"; shift 2;;
    --seconds)    SECONDS_OVERRIDE="$2"; shift 2;;
    --seed)       SEED="$2"; shift 2;;
    --period)     PERIOD="$2"; shift 2;;
    --list-size)  LIST_SIZE="$2"; shift 2;;
    --abr)        ABR="$2"; shift 2;;
    --no-nrt)     NO_NRT=1; shift;;
    --ouroboros)  OUROBOROS=1; shift;;
    --submit-dir) SUBMIT_DIR="$2"; shift 2;;
    --finalize)   FINALIZE=1; shift;;
    -h|--help)    grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "broadcast: unknown arg $1" >&2; exit 2;;
  esac
done

command -v ffmpeg  >/dev/null 2>&1 || { echo "broadcast: ffmpeg required (brew install ffmpeg)" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "broadcast: python3 required" >&2; exit 3; }

PLAYLIST="$OUT/stream.m3u8"
STATE="$OUT/organism.json"
TELEMETRY="$OUT/telemetry.json"
LINEAGE="$OUT/lineage.json"                       # Ω: the stream is a lineage, not a loop
[ -z "$SUBMIT_DIR" ] && SUBMIT_DIR="$OUT/queue"   # Ω: viewer submissions land here
PREV_WAV=""                                        # last output, for the Ouroboros self-feed
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

# --- locate SuperCollider (same discovery as bounce.sh) ---
find_sc(){ command -v sclang >/dev/null 2>&1 && return 0
  for c in /Applications/SuperCollider/SuperCollider.app/Contents/MacOS/sclang \
           /Applications/SuperCollider.app/Contents/MacOS/sclang \
           /usr/local/bin/sclang /opt/homebrew/bin/sclang; do
    [ -x "$c" ] && return 0; done; return 1; }
HAVE_SC=0; find_sc && HAVE_SC=1

if [ -n "$SOURCE" ] && [ ! -f "$SOURCE" ]; then
  echo "broadcast: no such source: $SOURCE" >&2; exit 2
fi

# Announce the render tier honestly.
if [ -n "$SOURCE" ] && [ "$HAVE_SC" = 1 ] && [ "$NO_NRT" = 0 ]; then
  echo "broadcast: render tier = NRT re-expression (SuperCollider + donor)" >&2
elif [ -n "$SOURCE" ]; then
  echo "broadcast: render tier = donor passthrough (no SuperCollider; folding source)" >&2
else
  echo "broadcast: render tier = self-generated genome-reactive tone (no donor)" >&2
fi
echo "broadcast: live HLS -> $PLAYLIST  (window=$LIST_SIZE, seed=$SEED, period=$PERIOD)" >&2

# Pitch per creature for the self-generated tier (A-minor-ish palette).
creature_freq(){ case "$1" in
  mnemosyne)        echo 110.0;;   # A2
  protean-hound)    echo 146.83;;  # D3
  chrysalid-siren)  echo 220.0;;   # A3
  ossuary-monk)     echo 82.41;;   # E2
  janiform-child)   echo 329.63;;  # E4
  *)                echo 174.61;;  # F3
esac; }

# Merge one genome into telemetry.json (rolling lineage of the last 16 segments).
update_telemetry(){ # $1=genome-json  $2=render_tier
  GENOME_JSON="$1" RENDER_TIER="$2" TELEMETRY="$TELEMETRY" python3 - <<'PY'
import json, os
g = json.loads(os.environ["GENOME_JSON"])
g["render_tier"] = os.environ.get("RENDER_TIER", "")
path = os.environ["TELEMETRY"]
try:
    with open(path, encoding="utf-8") as fh:
        t = json.load(fh)
except (OSError, ValueError):
    t = {"now": None, "recent": [], "count": 0,
         "note": "coherence/fidelity/entropy are PROVISIONAL inner-life indicators, not measurements."}
t["now"] = g
t["recent"] = (t.get("recent", []) + [g])[-16:]
t["count"] = t.get("count", 0) + 1
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(t, fh, indent=2)
os.replace(tmp, path)  # atomic — the player never reads a torn telemetry file
PY
}

i=0
while :; do
  [ "$SEGMENTS" != 0 ] && [ "$i" -ge "$SEGMENTS" ] && break

  # 1. GENERATOR: advance the organism one segment.
  GENOME="$(python3 "$HERE/tools/cellcycle.py" --state "$STATE" --seed "$SEED" --period "$PERIOD")" || {
    echo "broadcast: organism step failed" >&2; break; }
  eval "$(GENOME_JSON="$GENOME" python3 - <<'PY'
import os, json
g = json.loads(os.environ["GENOME_JSON"])
print(f"G_SEG={g['segment']}")
print(f"G_SECS={g['seconds']}")
print(f"G_CREATURE={g['creature']}")
print(f"G_PHASE={g['phase']}")
print(f"G_ENT={g['entropy']}")
print(f"G_FID={g['fidelity']}")
print(f"G_EPOCH={g['epoch']}")
PY
)"

  SECS="${SECONDS_OVERRIDE:-$G_SECS}"
  SEG_WAV="$WORK/seg_$G_SEG.wav"

  # 1.5 ABSORB (Ω): decide this segment's donor. A viewer submission (a creature
  # eats it live) takes priority; else the Ouroboros self-feed re-eats our own
  # last output; else the default --source (may be empty -> self-generated tone).
  SEG_SOURCE="$SOURCE"
  ABSORB_SOURCE=""            # non-empty -> record a lineage entry for this segment
  ABSORB_LICENSE="unknown"
  SUB="$(python3 "$HERE/tools/ingest_queue.py" pop --dir "$SUBMIT_DIR" 2>/dev/null || true)"
  if [ -n "$SUB" ]; then
    eval "$(SUB_JSON="$SUB" python3 - <<'PY'
import os, json
s = json.loads(os.environ["SUB_JSON"])
import shlex
print("SUB_URL=" + shlex.quote(str(s.get("url", ""))))
print("SUB_LIC=" + shlex.quote(str(s.get("license", "unknown"))))
PY
)"
    TUNED="$WORK/sub_$G_SEG.wav"
    if python3 "$HERE/forge/tune.py" --url "$SUB_URL" --license "$SUB_LIC" \
         --secs "$SECS" --out "$TUNED" >/dev/null 2>&1 && [ -s "$TUNED" ]; then
      SEG_SOURCE="$TUNED"; ABSORB_SOURCE="$SUB_URL"; ABSORB_LICENSE="$SUB_LIC"
      echo "  ⟳ absorbing submission: $SUB_URL [$SUB_LIC]" >&2
    else
      echo "  ⚠ submission unreachable, skipping: $SUB_URL" >&2
    fi
  fi
  if [ -z "$ABSORB_SOURCE" ] && [ "$OUROBOROS" = 1 ] && [ -n "$PREV_WAV" ] && [ -s "$PREV_WAV" ] \
     && [ $(( G_SEG % 3 )) -eq 2 ]; then
    # "output re-enters as input" — the organism eats its own prior expression.
    SEG_SOURCE="$PREV_WAV"; ABSORB_SOURCE="ouroboros:self"; ABSORB_LICENSE="own"
    echo "  ∞ ouroboros: re-eating own output" >&2
  fi

  # 2. RENDER: produce this segment (graceful tiers) from SEG_SOURCE.
  RENDER_TIER="tone"
  if [ -n "$SEG_SOURCE" ] && [ "$HAVE_SC" = 1 ] && [ "$NO_NRT" = 0 ]; then
    if bash "$HERE/forge/bounce.sh" "$SEG_SOURCE" "$SEG_WAV" "$SECS" >/dev/null 2>&1; then
      RENDER_TIER="nrt"
    fi
  fi
  if [ ! -s "$SEG_WAV" ] && [ -n "$SEG_SOURCE" ]; then
    # donor passthrough: take SECS from the source (loop if shorter).
    if ffmpeg -hide_banner -loglevel error -y -stream_loop -1 -i "$SEG_SOURCE" \
         -t "$SECS" -ac 2 -ar 44100 -c:a pcm_s16le "$SEG_WAV" >/dev/null 2>&1; then
      RENDER_TIER="donor"
    fi
  fi
  if [ ! -s "$SEG_WAV" ]; then
    # self-generated genome-reactive tone: pitch per creature, tremolo by entropy.
    FREQ="$(creature_freq "$G_CREATURE")"
    DEPTH="$(python3 -c "print(min(0.95, max(0.0, float('$G_ENT'))))")"
    ffmpeg -hide_banner -loglevel error -y \
      -f lavfi -i "sine=frequency=$FREQ:duration=$SECS:sample_rate=44100" \
      -af "tremolo=f=6:d=$DEPTH,volume=0.6" -ac 2 "$SEG_WAV" >/dev/null 2>&1 || {
        # last-ditch: a bare sine so the stream still lives.
        ffmpeg -hide_banner -loglevel error -y \
          -f lavfi -i "sine=frequency=$FREQ:duration=$SECS:sample_rate=44100" \
          -ac 2 "$SEG_WAV" >/dev/null 2>&1; }
    RENDER_TIER="tone"
  fi
  if [ ! -s "$SEG_WAV" ]; then
    echo "broadcast: segment $G_SEG produced no audio; skipping" >&2
    i=$((i+1)); continue
  fi

  # 3. TRANSPORT: roll the chunk into the live HLS playlist.
  python3 "$HERE/tools/hls_append.py" --playlist "$PLAYLIST" --input "$SEG_WAV" \
    --kind audio --list-size "$LIST_SIZE" --abr "$ABR" >/dev/null || {
      echo "broadcast: hls append failed for segment $G_SEG" >&2; }

  update_telemetry "$GENOME" "$RENDER_TIER"

  # Ω LINEAGE: record what this segment absorbed (a lineage, not a loop).
  if [ -n "$ABSORB_SOURCE" ]; then
    python3 "$HERE/tools/lineage.py" append --file "$LINEAGE" \
      --id "seg_$G_SEG" --epoch "$G_EPOCH" --fidelity "$G_FID" \
      --source "$ABSORB_SOURCE" --license "$ABSORB_LICENSE" --creature "$G_CREATURE" \
      >/dev/null 2>&1 || true
  fi

  # Keep this output as the Ouroboros seed for a later segment, then release.
  if [ "$OUROBOROS" = 1 ]; then
    cp -f "$SEG_WAV" "$WORK/prev.wav" 2>/dev/null && PREV_WAV="$WORK/prev.wav"
  fi
  rm -f "$SEG_WAV"

  echo "  seg $G_SEG  $G_PHASE/$G_CREATURE  ${SECS}s  tier=$RENDER_TIER" >&2
  i=$((i+1))
done

if [ "$FINALIZE" = 1 ]; then
  python3 "$HERE/tools/hls_append.py" --playlist "$PLAYLIST" --end --list-size "$LIST_SIZE" >/dev/null
  echo "broadcast: finalized $PLAYLIST as VOD" >&2
fi
echo "broadcast: $i segment(s) streamed -> $PLAYLIST" >&2
