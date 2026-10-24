#!/usr/bin/env python3
"""
hls_append.py — append one finished segment to a live/rolling HLS playlist.

This is the transport plane's core operation for the AETHER broadcast
(docs/AETHER-BROADCAST-PLAN.md §2, "Distribution plane"). The convergence map
(§3) noted that etceter4's transcode-video.js produces **VOD-only** HLS
(`-hls_playlist_type vod`, a finite playlist ending in #EXT-X-ENDLIST). The plan
calls to "flip vod -> event/rolling." That flip lives here:

  * Each call transcodes ONE segment media file (wav/mp4) into an MPEG-TS chunk.
  * It then rewrites the .m3u8 as a LIVE playlist: a rolling window of the last
    N chunks, an incrementing #EXT-X-MEDIA-SEQUENCE, and crucially NO
    #EXT-X-ENDLIST — the single tag whose absence tells a player "keep polling,
    this stream is still alive." Evicted chunks are deleted.

Why per-segment (not one long ffmpeg): the generator emits evolving segments at
its own pace, from different renderers (SuperCollider NRT when present, a
fallback when not — see tools/broadcast.sh). Per-segment chunking lets the loop
crash and resume, keeps each chunk independent, and makes the "liveness" logic
transparent and testable. HLS is then just static files: sovereign, self-hostable
on R2/Pages/a plain dir — no RTMP push to a rented platform.

stdlib only (+ ffmpeg/ffprobe on PATH), py3.14-safe. State for the rolling
window lives in <playlist>.state.json alongside the playlist.

Usage:
    python3 tools/hls_append.py --playlist out/live/stream.m3u8 --input seg.wav
    python3 tools/hls_append.py --playlist out/live/stream.m3u8 --input seg.mp4 --kind video
    python3 tools/hls_append.py --playlist out/live/stream.m3u8 --end     # finalize (VOD)
    python3 tools/hls_append.py --self-test

Exit codes: 0 ok · 2 usage · 3 ffmpeg/ffprobe missing · 4 transcode failed · 1 self-test failed
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys

DEFAULT_LIST_SIZE = 6      # rolling window: how many chunks a live player can seek back over
DEFAULT_ABR = "160k"       # audio bitrate for AAC in the TS chunks


def _which(name: str) -> str | None:
    hit = shutil.which(name)
    if hit:
        return hit
    for cand in (f"/opt/homebrew/bin/{name}", f"/usr/local/bin/{name}", f"/usr/bin/{name}"):
        if os.path.exists(cand):
            return cand
    return None


def probe_duration(ffprobe: str, path: str) -> float:
    """Segment duration in seconds (float). Falls back to 0.0 on failure."""
    try:
        out = subprocess.run(
            [ffprobe, "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nk=1:nw=1", path],
            capture_output=True, text=True, check=True).stdout.strip()
        return float(out)
    except (subprocess.CalledProcessError, ValueError):
        return 0.0


def transcode_chunk(ffmpeg: str, src: str, dst_ts: str, kind: str, abr: str) -> None:
    """Transcode a segment media file into an MPEG-TS chunk for HLS.

    Audio -> AAC in MPEG-TS (the classic audio-only HLS chunk; HLS.js plays it).
    Video -> H.264 + AAC in MPEG-TS. Chunks are self-contained so the playlist
    can drop old ones without breaking playback of the live window."""
    if kind == "video":
        cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", src,
               "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
               "-c:a", "aac", "-b:a", abr, "-f", "mpegts", dst_ts]
    else:
        cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", src,
               "-c:a", "aac", "-b:a", abr, "-vn", "-f", "mpegts", dst_ts]
    subprocess.run(cmd, check=True)


def _load_state(playlist: str, list_size: int) -> dict:
    path = playlist + ".state.json"
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            st = json.load(fh)
            st["list_size"] = list_size  # allow reconfig between runs
            return st
    return {"total_added": 0, "list_size": list_size, "window": []}


def _save_state(playlist: str, st: dict) -> None:
    path = playlist + ".state.json"
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(st, fh, indent=2)
    os.replace(tmp, path)


def render_playlist(st: dict, ended: bool = False) -> str:
    """Serialize the rolling window as an HLS media playlist.

    LIVE = no #EXT-X-ENDLIST. `ended=True` appends it to finalize as VOD (used
    when a broadcast is deliberately stopped and archived)."""
    window = st["window"]
    target = max(1, math.ceil(max((s["dur"] for s in window), default=1.0)))
    media_seq = st["total_added"] - len(window)
    lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:3",
        f"#EXT-X-TARGETDURATION:{target}",
        f"#EXT-X-MEDIA-SEQUENCE:{media_seq}",
    ]
    for seg in window:
        lines.append(f"#EXTINF:{seg['dur']:.3f},")
        lines.append(seg["file"])
    if ended:
        lines.append("#EXT-X-ENDLIST")
    return "\n".join(lines) + "\n"


def _write_playlist(playlist: str, text: str) -> None:
    tmp = playlist + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, playlist)  # atomic: a polling player never reads a torn playlist


def append(playlist: str, input_path: str, kind: str, list_size: int, abr: str,
           ffmpeg: str, ffprobe: str) -> dict:
    """Transcode `input_path` into a new chunk and roll it into the live playlist.
    Returns the updated state dict."""
    out_dir = os.path.dirname(os.path.abspath(playlist))
    os.makedirs(out_dir, exist_ok=True)
    st = _load_state(playlist, list_size)

    idx = st["total_added"]
    chunk_name = f"seg_{idx:05d}.ts"
    chunk_path = os.path.join(out_dir, chunk_name)
    transcode_chunk(ffmpeg, input_path, chunk_path, kind, abr)
    dur = probe_duration(ffprobe, chunk_path)

    st["window"].append({"file": chunk_name, "dur": dur})
    st["total_added"] = idx + 1

    # Trim to the rolling window; delete evicted chunks so the dir stays bounded.
    while len(st["window"]) > st["list_size"]:
        old = st["window"].pop(0)
        old_path = os.path.join(out_dir, old["file"])
        try:
            os.remove(old_path)
        except OSError:
            pass

    _write_playlist(playlist, render_playlist(st))
    _save_state(playlist, st)
    return st


def finalize(playlist: str, list_size: int) -> None:
    """Stamp #EXT-X-ENDLIST so the current playlist becomes a finite VOD."""
    st = _load_state(playlist, list_size)
    _write_playlist(playlist, render_playlist(st, ended=True))


def _self_test() -> int:
    """End-to-end: synthesize tone chunks via ffmpeg, roll them through a live
    playlist, and assert the liveness/rolling-window invariants hold."""
    ffmpeg, ffprobe = _which("ffmpeg"), _which("ffprobe")
    if not ffmpeg or not ffprobe:
        print("hls_append self-test: SKIP (ffmpeg/ffprobe not on PATH)")
        return 0

    import tempfile
    failures = []
    tmp = tempfile.mkdtemp(prefix="hls_selftest_")
    try:
        playlist = os.path.join(tmp, "stream.m3u8")
        list_size = 3
        # Make a source tone once, reuse as each "segment".
        tone = os.path.join(tmp, "tone.wav")
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                        "-f", "lavfi", "-i", "sine=frequency=220:duration=1",
                        "-ac", "2", "-ar", "44100", tone], check=True)

        for i in range(5):  # add more than list_size to force eviction
            st = append(playlist, tone, "audio", list_size, DEFAULT_ABR, ffmpeg, ffprobe)
            text = open(playlist, encoding="utf-8").read()
            # Invariant 1: still LIVE while broadcasting (no ENDLIST).
            if "#EXT-X-ENDLIST" in text:
                failures.append(f"playlist finalized prematurely at add {i}")
            # Invariant 2: window never exceeds list_size.
            if len(st["window"]) > list_size:
                failures.append(f"window {len(st['window'])} exceeds list_size {list_size} at add {i}")
            # Invariant 3: media sequence tracks evictions.
            expected_seq = st["total_added"] - len(st["window"])
            if f"#EXT-X-MEDIA-SEQUENCE:{expected_seq}" not in text:
                failures.append(f"media-sequence wrong at add {i} (want {expected_seq})")

        # Invariant 4: exactly list_size chunks remain on disk (older ones deleted).
        ts_files = [f for f in os.listdir(tmp) if f.endswith(".ts")]
        if len(ts_files) != list_size:
            failures.append(f"expected {list_size} .ts on disk, found {len(ts_files)}: {sorted(ts_files)}")

        # Invariant 5: the live window points at the NEWEST chunks.
        st = _load_state(playlist, list_size)
        want = {f"seg_{i:05d}.ts" for i in range(5 - list_size, 5)}
        have = {s["file"] for s in st["window"]}
        if want != have:
            failures.append(f"window not the newest chunks: want {sorted(want)}, have {sorted(have)}")

        # Invariant 6: finalize() flips it to VOD.
        finalize(playlist, list_size)
        if "#EXT-X-ENDLIST" not in open(playlist, encoding="utf-8").read():
            failures.append("finalize() did not stamp #EXT-X-ENDLIST")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print("hls_append self-test: FAIL")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("hls_append self-test: PASS (live rolling window, eviction, media-sequence, VOD finalize)")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Append a segment to a live/rolling HLS playlist.")
    ap.add_argument("--playlist", help="path to the .m3u8 to maintain")
    ap.add_argument("--input", help="segment media file (wav/mp4) to append")
    ap.add_argument("--kind", choices=("audio", "video"), default="audio")
    ap.add_argument("--list-size", type=int, default=DEFAULT_LIST_SIZE, help="rolling window length")
    ap.add_argument("--abr", default=DEFAULT_ABR, help="audio bitrate (default 160k)")
    ap.add_argument("--end", action="store_true", help="finalize the playlist as VOD (#EXT-X-ENDLIST)")
    ap.add_argument("--self-test", dest="self_test", action="store_true")
    args = ap.parse_args(argv)

    if args.self_test:
        return _self_test()
    if not args.playlist:
        ap.error("--playlist is required")

    if args.end:
        finalize(args.playlist, args.list_size)
        print(f"hls_append: finalized {args.playlist} as VOD")
        return 0

    if not args.input:
        ap.error("give --input <segment> (or --end to finalize)")
    if not os.path.exists(args.input):
        print(f"hls_append: no such input: {args.input}", file=sys.stderr)
        return 2

    ffmpeg, ffprobe = _which("ffmpeg"), _which("ffprobe")
    if not ffmpeg or not ffprobe:
        print("hls_append: ffmpeg + ffprobe are required (brew install ffmpeg)", file=sys.stderr)
        return 3

    try:
        st = append(args.playlist, args.input, args.kind, args.list_size, args.abr, ffmpeg, ffprobe)
    except subprocess.CalledProcessError as exc:
        print(f"hls_append: transcode failed (ffmpeg exit {exc.returncode})", file=sys.stderr)
        return 4
    print(f"hls_append: +{args.kind} chunk (window={len(st['window'])}, total={st['total_added']}) -> {args.playlist}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
