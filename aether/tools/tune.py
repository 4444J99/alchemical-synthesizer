#!/usr/bin/env python3
"""
tune.py — capture a slice of live/free web audio into a Forge-ready WAV.

Brahma "listens": it samples the world's live audio — internet-radio streams
(Icecast/Shoutcast/HLS) and free/public-domain archives — and hands the capture
to the Forge (rip -> per-stem creatures -> re-express). This is the input mouth
of the AETHER phase: a radio that eats radio and dreams its own.

Every capture is license-aware. The station registry (stations.json) tags each
source with a `license`, and every capture writes a provenance sidecar
(<out>.source.json) so a later PUBLISH step can *prove* the material is
clearable instead of trusting memory. RIGHTS POSTURE — whether a given source
may be published or sold — is a human-gated decision (see ROADMAP); this tool
records the license and can refuse to hand publish-unsafe material to an
automated pipeline (--publish-safe-only), but it never decides policy for you.

Design notes:
  * stdlib only (+ ffmpeg on PATH), py3.14-safe — same constraint as
    forge/analyze_audio.py / forge/stemforge.py (no venv).
  * ffmpeg reads http/icecast/hls URLs directly; the --reconnect input options
    let a flaky stream self-heal mid-capture.
  * Output is stereo 44.1 kHz PCM by default — the same shape ingest.sh emits,
    so a capture flows straight into `make rip` / `make track`.

Usage:
    python3 forge/tune.py --list
    python3 forge/tune.py --station somafm-dronezone [--secs 30] [--out out/tuned/x.wav]
    python3 forge/tune.py --url https://host/stream --license cc0 \
                          [--attribution "..."] [--secs 30] [--out ...]

Exit codes: 0 ok · 2 usage · 3 ffmpeg missing · 4 capture failed · 5 unknown station
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

# Licenses under which captured material is safe to PUBLISH/SELL without further
# clearance: public-domain, CC0, CC-BY (attribution required), or your own work.
# Everything else — copyrighted radio, share-alike/non-commercial variants,
# unknown — is capture-for-R&D only until YOU clear it. The rights posture is a
# human-gated atom; this set only encodes the mechanical license->safety map.
PUBLISH_SAFE = frozenset({"public-domain", "cc0", "cc-by", "own"})

DEFAULT_SECS = 30
SR = 44100
CHANNELS = 2  # stereo, matching ingest.sh's primary output


def repo_root() -> str:
    """The repo root: tune.py lives in <root>/tools/."""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def find_ffmpeg() -> str | None:
    """Locate ffmpeg on PATH or in the usual Homebrew/local prefixes."""
    hit = shutil.which("ffmpeg")
    if hit:
        return hit
    for cand in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"):
        if os.path.exists(cand):
            return cand
    return None


def load_stations() -> list[dict]:
    """Load the source registry (stations.json at repo root). Missing/empty is OK."""
    path = os.path.join(repo_root(), "stations.json")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return list(data.get("stations", []))


def is_publish_safe(license_tag: str) -> bool:
    return (license_tag or "").strip().lower() in PUBLISH_SAFE


def cmd_list(stations: list[dict]) -> int:
    if not stations:
        print("tune: no stations registered (stations.json missing or empty).")
        return 0
    print(f"AETHER source registry — {len(stations)} station(s):\n")
    for s in stations:
        lic = s.get("license", "unknown")
        safe = "PUBLISH-SAFE" if is_publish_safe(lic) else "R&D-only"
        seen = "✓" if s.get("verified") else "·"
        print(f"  {seen} {s['name']:<26} [{lic:<17}] {safe:<12} {s.get('kind','?')}")
        if s.get("notes"):
            print(f"      {s['notes']}")
    print("\n  ✓ = a capture has been verified from this URL   · = unverified seed")
    print("  Rights posture is human-gated — PUBLISH-SAFE reflects the license tag only.")
    return 0


def _is_network_url(url: str) -> bool:
    """True for protocols where ffmpeg's -reconnect options are valid. They are
    HTTP(S)/stream-only; passing them for a local file makes ffmpeg exit with
    'Option not found', so we scope them (also lets the Ouroboros absorb a
    file:// or local-path donor)."""
    return url.lower().startswith(
        ("http://", "https://", "rtmp://", "rtmps://", "rtsp://", "srt://", "hls://", "ftp://"))


def capture(ffmpeg: str, url: str, out: str, secs: int) -> None:
    """Pull `secs` seconds from `url` into a stereo 44.1 kHz WAV at `out`."""
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    # input reconnection (must precede -i): a dropped stream re-dials. Only valid
    # for network inputs — omitted for local files.
    reconnect = ["-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "5"] \
        if _is_network_url(url) else []
    cmd = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        *reconnect,
        "-i", url,
        "-t", str(secs),
        "-ac", str(CHANNELS), "-ar", str(SR), "-c:a", "pcm_s16le",
        out,
    ]
    subprocess.run(cmd, check=True)


def write_provenance(out: str, meta: dict) -> str:
    """Write <out>.source.json so a later publish step can prove the license."""
    side = out + ".source.json"
    with open(side, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)
        fh.write("\n")
    return side


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Capture free/streaming web audio into a Forge-ready WAV.")
    ap.add_argument("--list", action="store_true", help="list the source registry and exit")
    ap.add_argument("--station", help="capture from a named station in stations.json")
    ap.add_argument("--url", help="capture from an arbitrary stream/file URL")
    ap.add_argument("--secs", type=int, default=DEFAULT_SECS, help=f"seconds to capture (default {DEFAULT_SECS})")
    ap.add_argument("--out", help="output WAV path (default out/tuned/<name>.wav)")
    ap.add_argument("--license", default="unknown", help="license tag for a --url source (e.g. cc0, public-domain)")
    ap.add_argument("--attribution", default="", help="attribution string for a --url source")
    ap.add_argument("--publish-safe-only", action="store_true",
                    help="refuse to capture sources whose license is not publish-safe")
    args = ap.parse_args(argv)

    stations = load_stations()

    if args.list:
        return cmd_list(stations)

    if not args.station and not args.url:
        ap.error("give --station <name>, --url <url>, or --list")

    # Resolve the source: a registry station, or an ad-hoc --url.
    if args.station:
        match = next((s for s in stations if s.get("name") == args.station), None)
        if not match:
            print(f"tune: unknown station '{args.station}' (try --list)", file=sys.stderr)
            return 5
        url = args.url or match["url"]
        name = match["name"]
        license_tag = match.get("license", "unknown")
        attribution = match.get("attribution", "")
        kind = match.get("kind", "stream")
    else:
        url = args.url
        name = "url-capture"
        license_tag = args.license
        attribution = args.attribution
        kind = "stream"

    safe = is_publish_safe(license_tag)
    if args.publish_safe_only and not safe:
        print(f"tune: REFUSED — '{name}' license '{license_tag}' is not publish-safe "
              f"(and --publish-safe-only was set). Rights posture is human-gated.", file=sys.stderr)
        return 2

    ffmpeg = find_ffmpeg()
    if not ffmpeg:
        print("tune: ffmpeg is required (brew install ffmpeg)", file=sys.stderr)
        return 3

    out = args.out or os.path.join(repo_root(), "out", "tuned", f"{name}.wav")

    banner = "PUBLISH-SAFE" if safe else "R&D-ONLY (license not cleared for publish)"
    print(f"tune: listening to '{name}' [{license_tag}] — {banner}", file=sys.stderr)
    print(f"tune: {args.secs}s from {url}", file=sys.stderr)

    try:
        capture(ffmpeg, url, out, args.secs)
    except subprocess.CalledProcessError as exc:
        print(f"tune: capture failed (ffmpeg exit {exc.returncode}) — bad URL or offline?", file=sys.stderr)
        return 4

    meta = {
        "tool": "tune.py",
        "source_url": url,
        "station": name,
        "kind": kind,
        "license": license_tag,
        "attribution": attribution,
        "captured_secs": args.secs,
        "sample_rate": SR,
        "channels": CHANNELS,
        "publish_safe": safe,
        "note": "Rights posture is human-gated; publish_safe reflects the license tag only, not clearance.",
    }
    side = write_provenance(out, meta)

    size = os.path.getsize(out) if os.path.exists(out) else 0
    print(f"tune: {out} ({size} bytes) + provenance {side}", file=sys.stderr)
    print(out)  # stdout: the WAV path, for pipelines (-> make rip / make track)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
