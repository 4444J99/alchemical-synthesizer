#!/usr/bin/env python3
"""
cellcycle.py — the METABOLISM organism that conducts Brahma's live broadcast.

This is the one genuinely *new* muscle of the AETHER phase (see
docs/AETHER-BROADCAST-PLAN.md §2). Everything else in the broadcast pipeline is
converged from already-deployed machinery; this file is the generative source
that nobody in the ecosystem had wired to a live stream: a resident organism,
hosted *inside* Brahma (never Brahma itself — Brahma is the cosmos, per
docs/logos/telos.md), that drives a continuous, evolving performance.

It models the **Global Cell Cycle / METABOLISM** from the genesis design
(docs/design/alchemical-synthesis-Absorption-Fusion-Synth-Design.md,
"Layer A — the always-on chassis": timing, safety, metabolism):

  * A metabolic cycle walks the owner's own generative arc, from the ChatGPT
    tracker brainstorms (see AETHER-BROADCAST-PLAN §4, the sampler instrument):

        READABLE  -> CLUSTER  -> DISPERSAL  -> (rebirth, next epoch)

    i.e. "bulks up every ~32 bars, then sheds complexity." READABLE is linear
    and legible; CLUSTER redistributes into repeating dense clusters; DISPERSAL
    atomizes into fragments and collapses — then a new epoch begins amnesiac
    ("power-up initializes amnesia; power-down is death", docs/logos/pragma.md).

  * State is carried FORWARD between segments (epoch, phase, drift, lineage), so
    consecutive segmented-NRT renders form one continuous organism rather than
    disconnected clips. That continuity is what makes it a *stream*, not a
    playlist.

  * Each step emits a **genome**: the per-segment parameters a renderer consumes
    (duration, active creature, fidelity, density) plus the organism's
    **provisional inner-life indicators** (coherence / entropy).

THE HONESTY SEAM (docs/logos/pragma.md, non-negotiable): Coherence, Fidelity and
Entropy are NOT real measurements yet. They are provisional indicators of an
intended inner life. This module tags them as such (see PROVISIONAL) and the
player labels them provisional. The legible proof of the wedge is the
before/after specimen, not these numbers.

Design constraints (match forge/tune.py / forge/analyze_audio.py):
  * stdlib only, py3.14-safe (no venv, no third-party deps).
  * Deterministic given --seed, so it is testable and a run is reproducible.

Usage:
    python3 tools/cellcycle.py --self-test
    python3 tools/cellcycle.py --seed 7 --segments 12            # preview JSONL
    python3 tools/cellcycle.py --seed 7 --segments 12 --print    # human-readable
    python3 tools/cellcycle.py --state out/live/organism.json    # advance once, persist

Exit codes: 0 ok · 2 usage · 1 self-test failed
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

# The five anthropomorphized sampler creatures — the named intake organs for
# freshly-tuned web audio (docs/design/alchemical-synthesis-Anthropomorphized-
# Sampler-Creatures.md). The active creature rotates each segment.
CREATURES = ("mnemosyne", "protean-hound", "chrysalid-siren", "ossuary-monk", "janiform-child")

# The macro-phases of one metabolic cycle — the owner's generative arc.
PHASES = ("readable", "cluster", "dispersal")

# Indicators that are PROVISIONAL — intended inner life, not real measurement.
# Anything consuming a genome must treat these as labeled, not scientific.
PROVISIONAL = ("coherence", "fidelity", "entropy")

# Defaults chosen so a full cycle is legible in a short preview while still
# reading as "bulks up every ~32 bars then sheds" over a real broadcast.
DEFAULT_PERIOD = 12          # segments per full metabolic cycle (epoch)
DEFAULT_SEG_SECS = 12        # nominal seconds per rendered segment
SEG_SECS_MIN, SEG_SECS_MAX = 6, 24


def _lcg(seed: int) -> int:
    """A tiny deterministic PRNG step (numerical-recipes LCG). stdlib-only,
    reproducible across machines/Python versions — unlike hash()/random seeding
    subtleties. Returns the next 31-bit state."""
    return (seed * 1103515245 + 12345) & 0x7FFFFFFF


def _unit(state: int) -> float:
    """Map an LCG state to a float in [0, 1)."""
    return state / 0x7FFFFFFF


def phase_for(pos_in_cycle: float) -> tuple[str, float]:
    """Given position 0..1 within a metabolic cycle, return (phase, pos_in_phase).
    The three phases split the cycle into equal thirds."""
    idx = min(int(pos_in_cycle * len(PHASES)), len(PHASES) - 1)
    span = 1.0 / len(PHASES)
    pos_in_phase = (pos_in_cycle - idx * span) / span
    return PHASES[idx], max(0.0, min(1.0, pos_in_phase))


def _curve(phase: str, p: float) -> tuple[float, float, float]:
    """The shape of the cycle: (density, entropy, coherence) in [0,1] for a
    phase and position-within-phase `p`. These encode the arc's *character*:

      READABLE   linear/legible   -> low density rising, low entropy, high coherence
      CLUSTER    bulking, dense   -> density peaks, entropy rises, coherence mid
      DISPERSAL  atomize + shed   -> density falls, entropy peaks, coherence low

    Smooth (sinusoidal) so consecutive segments transition without jumps."""
    if phase == "readable":
        density = 0.15 + 0.35 * p                       # 0.15 -> 0.50, rising
        entropy = 0.10 + 0.10 * p                       # calm
        coherence = 0.90 - 0.15 * p                     # high, easing off
    elif phase == "cluster":
        density = 0.50 + 0.45 * math.sin(p * math.pi)   # bulges to ~0.95 mid-phase
        entropy = 0.20 + 0.45 * p                        # building disorder
        coherence = 0.70 - 0.30 * p                      # loosening
    else:  # dispersal
        density = 0.60 - 0.50 * p                        # shedding complexity
        entropy = 0.65 + 0.30 * math.sin(p * math.pi)    # peaks then collapses
        coherence = 0.40 - 0.30 * p                      # atomized
    clamp = lambda x: max(0.0, min(1.0, x))
    return clamp(density), clamp(entropy), clamp(coherence)


def new_state(seed: int, period: int = DEFAULT_PERIOD) -> dict:
    """Genesis state for a fresh organism. `segment` is -1 so the first step()
    advances to segment 0."""
    return {
        "seed": int(seed) & 0x7FFFFFFF,
        "rng": int(seed) & 0x7FFFFFFF,
        "period": max(3, int(period)),
        "segment": -1,      # global segment counter; step() increments first
        "epoch": 0,         # a "life"; increments each full cycle (rebirth = amnesia)
        "drift": 0.0,       # FSAP accumulation: "becomes more itself over time"
        "lineage": [],      # ids of donor captures folded in (set by broadcast.sh)
    }


def step(state: dict) -> tuple[dict, dict]:
    """Advance the organism one segment. Returns (new_state, genome).

    Pure and deterministic given `state` — the whole point is that a broadcast
    can crash and resume from the persisted state file with an identical future.
    """
    st = dict(state)
    st["segment"] = int(st.get("segment", -1)) + 1
    period = max(3, int(st.get("period", DEFAULT_PERIOD)))
    seg = st["segment"]

    # Epoch (a "life") turns over every full metabolic cycle. Crossing an epoch
    # boundary is a rebirth: amnesia by design (pragma.md).
    epoch = seg // period
    reborn = epoch != st.get("epoch", 0)
    st["epoch"] = epoch

    pos_in_cycle = (seg % period) / period
    phase, phase_pos = phase_for(pos_in_cycle)
    density, entropy, coherence = _curve(phase, phase_pos)

    # Advance the deterministic PRNG and derive this segment's fidelity as a
    # bounded random walk around a phase-appropriate centre. Fidelity N (0..1):
    # how faithfully the donor is reproduced vs transmuted (design corpus).
    rng = _lcg(int(st.get("rng", st["seed"])))
    st["rng"] = rng
    jitter = (_unit(rng) - 0.5) * 0.30
    fidelity_centre = 0.75 if phase == "readable" else (0.55 if phase == "cluster" else 0.35)
    fidelity = max(0.15, min(0.95, fidelity_centre + jitter))

    # FSAP: the instrument accumulates a slow "self" bias over its life, capped —
    # "the instrument becomes more itself over time" (lossless accumulation).
    st["drift"] = min(1.0, st.get("drift", 0.0) + 0.01)

    # Segment duration breathes with density (denser phases render a touch longer).
    seg_secs = int(round(SEG_SECS_MIN + (SEG_SECS_MAX - SEG_SECS_MIN) * density))
    seg_secs = max(SEG_SECS_MIN, min(SEG_SECS_MAX, seg_secs))

    creature = CREATURES[seg % len(CREATURES)]

    genome = {
        "segment": seg,
        "epoch": epoch,
        "reborn": reborn,
        "phase": phase,
        "phase_pos": round(phase_pos, 4),
        "creature": creature,
        "seconds": seg_secs,
        # provisional inner-life indicators (NOT real measurements)
        "fidelity": round(fidelity, 4),
        "density": round(density, 4),
        "entropy": round(entropy, 4),
        "coherence": round(coherence, 4),
        "drift": round(st["drift"], 4),
        "provisional": list(PROVISIONAL),
        "lineage": list(st.get("lineage", [])),
    }
    return st, genome


def osc_telemetry(genome: dict) -> str:
    """Render a genome as the organism-update OSC line the Web Cortex already
    speaks at 10 Hz: /brahma/organism/update [id] [type] [coherence] [entropy].
    (docs/logos/pragma.md). Values are PROVISIONAL."""
    return (f"/brahma/organism/update {genome['segment']} {genome['creature']} "
            f"{genome['coherence']} {genome['entropy']}")


def _load_state(path: str, seed: int, period: int) -> dict:
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    return new_state(seed, period)


def _save_state(path: str, state: dict) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)  # atomic — a reader never sees a half-written state


def _human(g: dict) -> str:
    bar = lambda v: "█" * int(round(v * 10)) + "·" * (10 - int(round(v * 10)))
    return (f"seg {g['segment']:>4}  e{g['epoch']}  {g['phase']:<9} "
            f"{g['creature']:<15} {g['seconds']:>2}s  "
            f"fid {bar(g['fidelity'])}  den {bar(g['density'])}  "
            f"ent {bar(g['entropy'])}  coh {bar(g['coherence'])}"
            + ("   ⟲ REBORN" if g["reborn"] else ""))


def _self_test() -> int:
    """Deterministic assertions — the executable predicate for this organism."""
    failures = []

    # 1. Determinism: same seed -> identical genome sequence.
    def run(seed, n):
        st = new_state(seed)
        out = []
        for _ in range(n):
            st, g = step(st)
            out.append(g)
        return out
    a, b = run(7, 24), run(7, 24)
    if a != b:
        failures.append("determinism: two runs with seed 7 diverged")

    # 2. Phase progression: first cycle visits all three phases in order.
    seq = run(3, DEFAULT_PERIOD)
    phases_seen = [g["phase"] for g in seq]
    if phases_seen[0] != "readable" or "cluster" not in phases_seen or "dispersal" not in phases_seen:
        failures.append(f"phase arc wrong: {phases_seen}")
    # order: readable indices all precede cluster, which precede dispersal
    order = {p: i for i, p in enumerate(PHASES)}
    if any(order[phases_seen[i]] > order[phases_seen[i + 1]] for i in range(len(phases_seen) - 1)):
        failures.append(f"phases out of order within a cycle: {phases_seen}")

    # 3. Epoch turns over + rebirth flag fires exactly at the boundary.
    long = run(5, DEFAULT_PERIOD * 2 + 1)
    if long[DEFAULT_PERIOD]["epoch"] != 1 or not long[DEFAULT_PERIOD]["reborn"]:
        failures.append("epoch/rebirth did not fire at the cycle boundary")
    if long[0]["epoch"] != 0 or long[0]["reborn"]:
        failures.append("segment 0 should be epoch 0 and not flagged reborn")

    # 4. All provisional indicators stay in [0,1]; duration within bounds.
    for g in long:
        for k in ("fidelity", "density", "entropy", "coherence", "drift"):
            if not (0.0 <= g[k] <= 1.0):
                failures.append(f"{k}={g[k]} out of [0,1] at seg {g['segment']}")
        if not (SEG_SECS_MIN <= g["seconds"] <= SEG_SECS_MAX):
            failures.append(f"seconds={g['seconds']} out of bounds at seg {g['segment']}")
        if g["provisional"] != list(PROVISIONAL):
            failures.append("genome dropped the provisional honesty tag")

    # 5. State persistence round-trips (resume yields the same next genome).
    st = new_state(11)
    st, _ = step(st); st, _ = step(st)
    snap = json.loads(json.dumps(st))          # simulate save/load
    _, g_from_live = step(dict(st))
    _, g_from_snap = step(dict(snap))
    if g_from_live != g_from_snap:
        failures.append("resume-from-state produced a different genome")

    # 6. Creatures rotate through all five.
    if {g["creature"] for g in run(1, len(CREATURES))} != set(CREATURES):
        failures.append("creature rotation did not cover all five")

    if failures:
        print("cellcycle self-test: FAIL")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"cellcycle self-test: PASS ({len(long)} segments, {long[-1]['epoch'] + 1} epochs exercised)")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="The METABOLISM organism that conducts Brahma's live broadcast.")
    ap.add_argument("--seed", type=int, default=1, help="deterministic seed for a fresh organism")
    ap.add_argument("--period", type=int, default=DEFAULT_PERIOD, help="segments per full metabolic cycle")
    ap.add_argument("--segments", type=int, help="emit N genomes (preview) instead of advancing state once")
    ap.add_argument("--state", help="persist/resume organism state at this path; advance ONE segment")
    ap.add_argument("--print", dest="human", action="store_true", help="human-readable output")
    ap.add_argument("--osc", action="store_true", help="also print the /brahma/organism/update OSC line")
    ap.add_argument("--self-test", dest="self_test", action="store_true", help="run deterministic assertions")
    args = ap.parse_args(argv)

    if args.self_test:
        return _self_test()

    # --state: advance exactly one segment and persist (the broadcast loop's call).
    if args.state:
        st = _load_state(args.state, args.seed, args.period)
        st, genome = step(st)
        _save_state(args.state, st)
        print(_human(genome) if args.human else json.dumps(genome))
        if args.osc:
            print(osc_telemetry(genome), file=sys.stderr)
        return 0

    # --segments: emit a preview sequence without persisting (design/testing).
    n = args.segments if args.segments else args.period
    st = new_state(args.seed, args.period)
    for _ in range(n):
        st, genome = step(st)
        print(_human(genome) if args.human else json.dumps(genome))
        if args.osc:
            print(osc_telemetry(genome), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
