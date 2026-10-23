#!/usr/bin/env python3
"""
analyze_audio.py — turn a rendered track into a per-frame visual envelope.

The Visual Cortex (brahma/web) reacts to an `organisms` inlet, not to audio.
This tool bridges the gap: it decodes any audio file (via ffmpeg) and emits a
per-video-frame envelope JSON that `tree/video.js` maps onto the Tree of Life —
loudness lights the whole cosmos, spectral bands light vessels bottom-to-top
(bass -> Malkuth/root, treble -> Keter/crown), flatness stirs the coronas, and
onsets fire the Lightning Flash.

Design notes:
  * stdlib only (+ ffmpeg on PATH) so it runs under the machine's Python 3.14
    with no venv, exactly like forge/stemforge.py.
  * The measures — RMS, log-spaced band energies, spectral flatness — mirror the
    engine's own analysis SynthDef (relinquished_ae: env / tone / noise).

Usage:
    python3 forge/analyze_audio.py TRACK.wav --out env.json [--fps 30] [--bands 12]

Exit codes: 0 ok · 2 usage · 3 ffmpeg missing / decode failed
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import struct
import subprocess
import sys

# Analysis is done on a downsampled mono stream: 22050 Hz covers 0..11 kHz,
# plenty for a visual envelope, and keeps the pure-Python FFT cheap.
ANALYSIS_SR = 22050
FFT_SIZE = 1024                      # power of two; ~21.5 Hz/bin at 22050 Hz
EPS = 1e-12


def find_ffmpeg() -> str | None:
    """Locate ffmpeg on PATH or in the usual Homebrew/local prefixes."""
    hit = shutil.which("ffmpeg")
    if hit:
        return hit
    for cand in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"):
        if os.path.exists(cand):
            return cand
    return None


def decode_mono_f32(ffmpeg: str, path: str) -> list[float]:
    """Decode `path` to mono float32 PCM at ANALYSIS_SR and return the samples."""
    cmd = [
        ffmpeg, "-v", "error", "-i", path,
        "-ac", "1", "-ar", str(ANALYSIS_SR), "-f", "f32le", "-",
    ]
    proc = subprocess.run(cmd, capture_output=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr.decode("utf-8", "replace"))
        raise RuntimeError(f"ffmpeg decode failed for {path}")
    raw = proc.stdout
    n = len(raw) // 4
    if n == 0:
        raise RuntimeError(f"no audio samples decoded from {path}")
    return list(struct.unpack("<%df" % n, raw[: n * 4]))


# ------------------------------------------------------------------ DSP kernels
def _hann(n: int) -> list[float]:
    if n == 1:
        return [1.0]
    return [0.5 - 0.5 * math.cos(2.0 * math.pi * i / (n - 1)) for i in range(n)]


def _fft(re: list[float], im: list[float]) -> None:
    """In-place iterative radix-2 Cooley-Tukey FFT. len(re) must be a power of 2."""
    n = len(re)
    # bit-reversal permutation
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            re[i], re[j] = re[j], re[i]
            im[i], im[j] = im[j], im[i]
    # butterflies
    length = 2
    while length <= n:
        ang = -2.0 * math.pi / length
        wr, wi = math.cos(ang), math.sin(ang)
        half = length >> 1
        for start in range(0, n, length):
            cr, ci = 1.0, 0.0
            for k in range(half):
                a = start + k
                b = a + half
                tr = cr * re[b] - ci * im[b]
                ti = cr * im[b] + ci * re[b]
                re[b] = re[a] - tr
                im[b] = im[a] - ti
                re[a] += tr
                im[a] += ti
                cr, ci = cr * wr - ci * wi, cr * wi + ci * wr
        length <<= 1


def _log_band_edges(n_bins: int, n_bands: int) -> list[tuple[int, int]]:
    """Split usable FFT bins [1..n_bins) into n_bands log-spaced [lo, hi) ranges."""
    lo_bin, hi_bin = 1, n_bins
    edges = []
    for band in range(n_bands):
        f0 = lo_bin * (hi_bin / lo_bin) ** (band / n_bands)
        f1 = lo_bin * (hi_bin / lo_bin) ** ((band + 1) / n_bands)
        a = max(1, int(round(f0)))
        b = max(a + 1, int(round(f1)))
        edges.append((a, min(b, hi_bin)))
    return edges


# --------------------------------------------------------------------- analysis
def analyze(samples: list[float], fps: int, n_bands: int) -> dict:
    total = len(samples)
    duration = total / ANALYSIS_SR
    n_frames = max(1, int(math.ceil(duration * fps)))
    hop = ANALYSIS_SR / fps

    win = _hann(FFT_SIZE)
    half = FFT_SIZE // 2
    band_edges = _log_band_edges(half, n_bands)

    raw = []                         # per-frame {rms, bands[], flat, energy}
    for f in range(n_frames):
        center = int(round(f * hop))
        start = center - half
        re = [0.0] * FFT_SIZE
        im = [0.0] * FFT_SIZE
        sq = 0.0
        for i in range(FFT_SIZE):
            idx = start + i
            s = samples[idx] if 0 <= idx < total else 0.0
            sq += s * s
            re[i] = s * win[i]
        rms = math.sqrt(sq / FFT_SIZE)

        _fft(re, im)
        power = [re[k] * re[k] + im[k] * im[k] for k in range(half)]

        bands = []
        for (a, b) in band_edges:
            acc = 0.0
            for k in range(a, b):
                acc += power[k]
            bands.append(math.sqrt(acc / max(1, b - a)))

        # spectral flatness = geometric mean / arithmetic mean of the spectrum
        log_sum = 0.0
        lin_sum = 0.0
        cnt = 0
        for k in range(1, half):
            p = power[k] + EPS
            log_sum += math.log(p)
            lin_sum += p
            cnt += 1
        geo = math.exp(log_sum / cnt)
        arith = lin_sum / cnt
        flat = max(0.0, min(1.0, geo / (arith + EPS)))

        raw.append({"rms": rms, "bands": bands, "flat": flat, "energy": lin_sum})

    # ---- normalize to 0..1 so the visual mapping is device-independent -------
    rms_max = max((r["rms"] for r in raw), default=0.0) or 1.0
    band_max = max((max(r["bands"]) for r in raw), default=0.0) or 1.0

    # onset = half-wave-rectified energy rise, normalized by its own peak
    onsets = [0.0] * n_frames
    for f in range(1, n_frames):
        onsets[f] = max(0.0, raw[f]["energy"] - raw[f - 1]["energy"])
    onset_max = max(onsets, default=0.0) or 1.0

    def r4(x: float) -> float:
        return round(x, 4)

    env = []
    for f, r in enumerate(raw):
        env.append({
            "rms": r4(min(1.0, r["rms"] / rms_max)),
            "bands": [r4(min(1.0, b / band_max)) for b in r["bands"]],
            "flat": r4(r["flat"]),
            "onset": r4(min(1.0, onsets[f] / onset_max)),
        })

    return {
        "version": 1,
        "fps": fps,
        "sr": ANALYSIS_SR,
        "frames": n_frames,
        "duration": round(duration, 3),
        "bands": n_bands,
        "env": env,
    }


def summarize(samples: list[float], window_s: float = 0.05, silence_db: float = -50.0) -> dict:
    """Summary metrics for a render — the numbers an agent needs to know whether
    the thing it asked for actually produced sound.

    Deliberately reports *measurements*, not judgements: peak/rms in dBFS, the
    fraction of windows below the silence floor, clipping, and a plain verdict
    string. A non-silent verdict means samples were measured above the floor; it
    does not mean anyone heard anything.
    """
    total = len(samples)
    duration = total / ANALYSIS_SR if total else 0.0

    peak = max((abs(s) for s in samples), default=0.0)
    sq = sum(s * s for s in samples)
    rms = math.sqrt(sq / total) if total else 0.0
    clipped = sum(1 for s in samples if abs(s) >= 0.999)
    zc = sum(1 for i in range(1, total) if (samples[i] >= 0.0) != (samples[i - 1] >= 0.0))

    win = max(1, int(ANALYSIS_SR * window_s))
    windows = [samples[i:i + win] for i in range(0, total, win)]
    floor = 10.0 ** (silence_db / 20.0)
    active = 0
    for w in windows:
        if w and math.sqrt(sum(x * x for x in w) / len(w)) > floor:
            active += 1

    def db(x: float) -> float | None:
        return round(20.0 * math.log10(x), 2) if x > 0 else None

    return {
        "version": 1,
        "analysis_sr": ANALYSIS_SR,
        "duration_s": round(duration, 3),
        "peak_linear": round(peak, 6),
        "peak_dbfs": db(peak),
        "rms_linear": round(rms, 6),
        "rms_dbfs": db(rms),
        "clipped_samples": clipped,
        "clipped_ratio": round(clipped / total, 6) if total else 0.0,
        "zero_crossing_rate": round(zc / max(1, total - 1), 6),
        "window_s": window_s,
        "silence_floor_dbfs": silence_db,
        "windows": len(windows),
        "active_windows": active,
        "silence_ratio": round(1.0 - (active / len(windows)), 4) if windows else 1.0,
        "non_silent_seconds": round(active * window_s, 3),
        "verdict": "non_silent" if active > 0 else "silent",
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Audio -> per-frame visual envelope JSON")
    ap.add_argument("track", help="input audio file (wav/mp3/aiff/...)")
    ap.add_argument("--out", help="output envelope JSON path (envelope mode)")
    ap.add_argument("--summary-json", help="output summary metrics JSON path (measurement mode)")
    ap.add_argument("--fps", type=int, default=30, help="video frame rate (default 30)")
    ap.add_argument("--bands", type=int, default=12, help="spectral bands (default 12)")
    args = ap.parse_args(argv)

    if args.fps < 1 or args.fps > 120:
        sys.stderr.write("analyze_audio: --fps must be 1..120\n")
        return 2
    if args.bands < 3 or args.bands > 64:
        sys.stderr.write("analyze_audio: --bands must be 3..64\n")
        return 2
    if not os.path.exists(args.track):
        sys.stderr.write(f"analyze_audio: no such file: {args.track}\n")
        return 2
    if not args.out and not args.summary_json:
        sys.stderr.write("analyze_audio: nothing to do — pass --out and/or --summary-json\n")
        return 2

    ffmpeg = find_ffmpeg()
    if not ffmpeg:
        sys.stderr.write("analyze_audio: ffmpeg not found on PATH (brew install ffmpeg)\n")
        return 3

    try:
        samples = decode_mono_f32(ffmpeg, args.track)
        result = analyze(samples, args.fps, args.bands) if args.out else None
        summary = summarize(samples) if args.summary_json else None
    except RuntimeError as e:
        sys.stderr.write(f"analyze_audio: {e}\n")
        return 3

    if result is not None:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(result, fh, separators=(",", ":"))

        sys.stderr.write(
            f"analyze_audio: {args.track} -> {args.out} "
            f"({result['frames']} frames @ {args.fps}fps, {result['duration']}s, "
            f"{args.bands} bands)\n"
        )

    if summary is not None:
        os.makedirs(os.path.dirname(os.path.abspath(args.summary_json)), exist_ok=True)
        with open(args.summary_json, "w", encoding="utf-8") as fh:
            json.dump(summary, fh, separators=(",", ":"))

        sys.stderr.write(
            f"analyze_audio: {args.track} -> {args.summary_json} "
            f"({summary['verdict']}, peak {summary['peak_dbfs']} dBFS, "
            f"rms {summary['rms_dbfs']} dBFS, silence {summary['silence_ratio']})\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
