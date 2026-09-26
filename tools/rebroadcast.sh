#!/usr/bin/env bash
# ============================================================================
#  rebroadcast.sh — push the sovereign AETHER stream to YouTube/Twitch (RTMP).
# ----------------------------------------------------------------------------
#  AETHER plan §5.5, "Reach": a ONE-WAY re-broadcast LURE. The sovereign HLS
#  stream (out/live) stays the home; this re-encodes it to FLV/RTMP and pushes it
#  to a rented platform to pull listeners back. Converges the remote-broadcast
#  contract (bitrate ladder + audio chain) in deploy/aether/rebroadcast.json.
#
#  The stream is audio-first; RTMP platforms require a video track, so ffmpeg
#  SYNTHESIZES a live visualizer from the audio (showspectrum / showwaves /
#  showcqt) — no separate video render needed.
#
#  The stream KEY is an organ-owned credential: read from env RTMP_KEY, NEVER
#  recited or stored. Absent key -> the tool refuses (except --dry-run).
#
#  Usage:
#    RTMP_KEY=xxxx tools/rebroadcast.sh --target youtube [--input out/live/stream.m3u8]
#    RTMP_KEY=xxxx tools/rebroadcast.sh --target twitch  [--mode showwaves]
#    tools/rebroadcast.sh --target custom --url rtmp://host/app  (key via RTMP_KEY)
#    tools/rebroadcast.sh --dry-run out/rebroadcast-preview.flv  # local encode, no push, no key
#
#  Exit: 0 ok · 2 usage · 3 ffmpeg missing · 4 no stream key (non-dry-run)
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACT="$HERE/deploy/aether/rebroadcast.json"

TARGET=""
CUSTOM_URL=""
INPUT=""
MODE=""
DRYRUN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target)  TARGET="$2"; shift 2;;
    --url)     CUSTOM_URL="$2"; shift 2;;
    --input)   INPUT="$2"; shift 2;;
    --mode)    MODE="$2"; shift 2;;
    --dry-run) DRYRUN="${2:-$HERE/out/rebroadcast-preview.flv}"; shift 2;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "rebroadcast: unknown arg $1" >&2; exit 2;;
  esac
done

command -v ffmpeg >/dev/null 2>&1 || { echo "rebroadcast: ffmpeg required" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "rebroadcast: python3 required (reads the contract)" >&2; exit 3; }

# Load the contract into shell vars (env-var pattern; no stdin/quote hazards).
eval "$(CONTRACT_PATH="$CONTRACT" TARGET="$TARGET" MODE_OVERRIDE="$MODE" python3 - <<'PY'
import json, os
c = json.load(open(os.environ["CONTRACT_PATH"]))
v, a, vis = c["video"], c["audio"], c["visualizer"]
tgt = os.environ.get("TARGET", "")
url = c.get("targets", {}).get(tgt, {}).get("url", "")
mode = os.environ.get("MODE_OVERRIDE") or vis.get("mode", "showspectrum")
import shlex
values = {
    "C_TURL": url, "C_MODE": mode,
    "C_ACCENT": vis.get("accent", "0x7ba7ff"),
    "C_COLOR": vis.get("color", "intensity"),
    "C_VBIT": v["bitrate"], "C_VMAX": v["maxrate"], "C_VBUF": v["bufsize"],
    "C_FPS": v["fps"], "C_W": v["width"], "C_H": v["height"], "C_GOP": v["gop"],
    "C_PIX": v["pix_fmt"], "C_VCODEC": v["codec"], "C_PRESET": v["preset"],
    "C_ABIT": a["bitrate"], "C_ASR": a["samplerate"], "C_ACH": a["channels"],
}
for key, value in values.items():
    print(key + "=" + shlex.quote(str(value)))
PY
)"

# Build the audio->video visualizer filter for the chosen mode.
case "${MODE:-$C_MODE}" in
  showwaves)    VF="[0:a]showwaves=s=${C_W}x${C_H}:mode=cline:colors=${C_ACCENT}[v]";;
  showcqt)      VF="[0:a]showcqt=s=${C_W}x${C_H}[v]";;
  showspectrum|*) VF="[0:a]showspectrum=s=${C_W}x${C_H}:mode=combined:color=${C_COLOR}:slide=scroll[v]";;
esac

# Resolve the RTMP destination (unless a local dry-run).
if [ -z "$DRYRUN" ]; then
  RTMP_URL="$CUSTOM_URL"
  [ -z "$RTMP_URL" ] && RTMP_URL="$C_TURL"
  if [ -z "$RTMP_URL" ]; then
    echo "rebroadcast: no target — use --target youtube|twitch or --url rtmp://..." >&2; exit 2
  fi
  if [ -z "${RTMP_KEY:-}" ]; then
    echo "rebroadcast: RTMP_KEY not set. The stream key is an organ-owned credential —" >&2
    echo "  provide it via env (never in chat/repo): RTMP_KEY=xxxx tools/rebroadcast.sh ..." >&2
    exit 4
  fi
  DEST="${RTMP_URL%/}/${RTMP_KEY}"
  echo "rebroadcast: pushing to ${RTMP_URL%/}/*** (key hidden) mode=${MODE:-$C_MODE}" >&2
fi

# Input: the live HLS playlist by default; a test tone if none (for dry-run).
IN_ARGS=()
if [ -n "$INPUT" ]; then
  IN_ARGS=(-re -i "$INPUT")
elif [ -n "$DRYRUN" ]; then
  IN_ARGS=(-f lavfi -i "sine=frequency=220:duration=1:sample_rate=${C_ASR}")
else
  DEFAULT_IN="$HERE/out/live/stream.m3u8"
  [ -f "$DEFAULT_IN" ] || { echo "rebroadcast: no --input and no live stream at $DEFAULT_IN" >&2; exit 2; }
  IN_ARGS=(-re -i "$DEFAULT_IN")
fi

# Common encode chain (bitrate ladder + audio chain from the contract).
ENC=(-map "[v]" -map 0:a
  -c:v "$C_VCODEC" -preset "$C_PRESET" -pix_fmt "$C_PIX" -r "$C_FPS" -g "$C_GOP"
  -b:v "$C_VBIT" -maxrate "$C_VMAX" -bufsize "$C_VBUF"
  -c:a aac -b:a "$C_ABIT" -ar "$C_ASR" -ac "$C_ACH")

if [ -n "$DRYRUN" ]; then
  mkdir -p "$(dirname "$DRYRUN")"
  echo "rebroadcast: DRY RUN — local encode (1s) to $DRYRUN (no push, no key needed)" >&2
  ffmpeg -hide_banner -loglevel error -y "${IN_ARGS[@]}" \
    -filter_complex "$VF" "${ENC[@]}" -t 1 -f flv "$DRYRUN"
  if [ -s "$DRYRUN" ]; then echo "rebroadcast: dry-run OK -> $DRYRUN"; exit 0; else echo "rebroadcast: dry-run FAILED" >&2; exit 1; fi
fi

exec ffmpeg -hide_banner -loglevel warning "${IN_ARGS[@]}" \
  -filter_complex "$VF" "${ENC[@]}" -f flv "$DEST"
