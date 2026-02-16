#!/usr/bin/env python3
"""Brahma Audio Specimen Validator.

Checks WAV/AIFF files for silence, clipping, DC offset, and spectral diversity.
Uses only the Python standard library + the 'wave' module for broad compatibility.
For richer analysis, install soundfile and numpy (optional).
"""

import argparse
import math
import struct
import sys
import wave
from pathlib import Path

# Thresholds
RMS_SILENCE_THRESHOLD = 0.001    # below this → effectively silent
PEAK_CLIP_THRESHOLD = 0.99       # above this → likely clipping
DC_OFFSET_THRESHOLD = 0.05       # abs mean above this → DC offset present
SPECTRAL_BINS_MIN = 4            # minimum distinct amplitude bins for diversity


def _read_samples(filepath: str) -> tuple[list[float], int]:
    """Read a WAV file and return normalised float samples + sample rate."""
    with wave.open(filepath, "rb") as wf:
        n_channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        framerate = wf.getframerate()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)

    if sampwidth == 1:
        fmt = f"<{n_frames * n_channels}B"
        max_val = 128.0
        offset = 128  # 8-bit WAV is unsigned
    elif sampwidth == 2:
        fmt = f"<{n_frames * n_channels}h"
        max_val = 32768.0
        offset = 0
    elif sampwidth == 3:
        # 24-bit: unpack manually
        samples = []
        for i in range(0, len(raw), 3):
            val = int.from_bytes(raw[i : i + 3], "little", signed=True)
            samples.append(val / 8388608.0)
        return samples, framerate
    elif sampwidth == 4:
        fmt = f"<{n_frames * n_channels}i"
        max_val = 2147483648.0
        offset = 0
    else:
        raise ValueError(f"Unsupported sample width: {sampwidth}")

    unpacked = struct.unpack(fmt, raw)
    samples = [(s - offset) / max_val for s in unpacked]
    return samples, framerate


def check_silence(samples: list[float]) -> tuple[bool, float]:
    """Return (passed, rms_value). Fails if RMS is below threshold."""
    if not samples:
        return False, 0.0
    rms = math.sqrt(sum(s * s for s in samples) / len(samples))
    return rms >= RMS_SILENCE_THRESHOLD, rms


def check_clipping(samples: list[float]) -> tuple[bool, float]:
    """Return (passed, peak_value). Fails if peak exceeds threshold."""
    if not samples:
        return True, 0.0
    peak = max(abs(s) for s in samples)
    return peak <= PEAK_CLIP_THRESHOLD, peak


def check_dc_offset(samples: list[float]) -> tuple[bool, float]:
    """Return (passed, mean_value). Fails if abs(mean) exceeds threshold."""
    if not samples:
        return True, 0.0
    mean = sum(samples) / len(samples)
    return abs(mean) <= DC_OFFSET_THRESHOLD, mean


def check_spectral_diversity(samples: list[float], n_bins: int = 16) -> tuple[bool, int]:
    """Rough spectral diversity via amplitude histogram.

    Quantises sample amplitudes into bins and counts how many are occupied.
    Returns (passed, occupied_bin_count).
    """
    if not samples:
        return False, 0
    bins = [0] * n_bins
    for s in samples:
        idx = min(int((s + 1.0) / 2.0 * n_bins), n_bins - 1)
        bins[idx] += 1
    occupied = sum(1 for b in bins if b > 0)
    return occupied >= SPECTRAL_BINS_MIN, occupied


def validate_audio(filepath: str) -> bool:
    """Run all checks on an audio file. Returns True if specimen is viable."""
    path = Path(filepath)
    print(f"--- Validating Audio Specimen: {path.name} ---")

    if not path.exists():
        print("ERROR: File not found.")
        return False

    suffix = path.suffix.lower()
    if suffix not in (".wav", ".wave"):
        print(f"WARNING: Only WAV files fully supported (got {suffix}). Attempting anyway.")

    try:
        samples, sr = _read_samples(str(path))
    except Exception as e:
        print(f"ERROR: Could not read audio: {e}")
        return False

    duration = len(samples) / sr if sr else 0
    print(f"  Format: {sr} Hz, {len(samples)} samples, {duration:.2f}s")

    all_pass = True

    passed, rms = check_silence(samples)
    status = "PASS" if passed else "FAIL"
    print(f"  CHECK Silence:    {status}  (RMS={rms:.6f}, threshold={RMS_SILENCE_THRESHOLD})")
    all_pass &= passed

    passed, peak = check_clipping(samples)
    status = "PASS" if passed else "FAIL"
    print(f"  CHECK Clipping:   {status}  (peak={peak:.6f}, threshold={PEAK_CLIP_THRESHOLD})")
    all_pass &= passed

    passed, mean = check_dc_offset(samples)
    status = "PASS" if passed else "FAIL"
    print(f"  CHECK DC Offset:  {status}  (mean={mean:.6f}, threshold={DC_OFFSET_THRESHOLD})")
    all_pass &= passed

    passed, bins = check_spectral_diversity(samples)
    status = "PASS" if passed else "FAIL"
    print(f"  CHECK Diversity:  {status}  (bins={bins}/16, min={SPECTRAL_BINS_MIN})")
    all_pass &= passed

    result = "SPECIMEN VIABLE" if all_pass else "SPECIMEN REJECTED"
    print(f"  Result: {result}")
    return all_pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Brahma Audio Specimen Validator")
    parser.add_argument("file", type=str, help="Path to WAV file")
    args = parser.parse_args()

    success = validate_audio(args.file)
    sys.exit(0 if success else 1)
