#!/usr/bin/env python3
"""Source-bound native/module/material comparisons with explicit coverage limits."""
from __future__ import annotations

import argparse
import array
from contextlib import redirect_stdout
import html
import json
import math
from pathlib import Path
import shutil
import sys
import time
import uuid
import wave

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from forge import assimilate, materials
from forge.assimilate import sha256


def pcm(path):
    path = Path(path)
    if not path.is_file() or path.stat().st_size > 32 * 1024 * 1024:
        raise ValueError("Missing or oversized comparison audio")
    with wave.open(str(path), "rb") as stream:
        if stream.getsampwidth() != 2 or stream.getcomptype() != "NONE":
            raise ValueError("Comparison requires PCM16 audio")
        rate, channels, frames = stream.getframerate(), stream.getnchannels(), stream.getnframes()
        values = array.array("h", stream.readframes(frames))
        if sys.byteorder != "little":
            values.byteswap()
        if not frames or len(values) != frames * channels:
            raise ValueError("Invalid comparison audio length")
    return values, rate, channels, frames


def compare_audio(first, second):
    a, rate, channels, frames = pcm(first)
    b, other_rate, other_channels, other_frames = pcm(second)
    if rate != other_rate or channels != other_channels or abs(frames - other_frames) / rate > .025:
        raise ValueError("Comparison audio rate, channels or duration mismatch")
    count = min(len(a), len(b))
    energy_a = sum(value * value for value in a[:count]) / count
    energy_b = sum(value * value for value in b[:count]) / count
    rms_a, rms_b = math.sqrt(energy_a), math.sqrt(energy_b)
    delta = math.sqrt(sum((x - y) ** 2 for x, y in zip(a[:count], b[:count])) / count) / 32768
    shape = None if not rms_a or not rms_b else math.sqrt(sum(
        (x / rms_a - y / rms_b) ** 2 for x, y in zip(a[:count], b[:count])) / count)
    silent_a, silent_b = max(abs(value) for value in a) <= 32, max(abs(value) for value in b) <= 32
    return {"status": "silent" if silent_a and silent_b else "silence_transition" if silent_a != silent_b else "compared",
            "frames_compared": count // channels, "sample_rate": rate, "channels": channels,
            "rms_delta": delta, "shape_delta": shape, "first_rms": rms_a / 32768, "second_rms": rms_b / 32768,
            "normalization": "raw PCM delta; shape delta independently removes each signal's RMS gain"}


def load_audition(directory, donor_sha256):
    directory = Path(directory).resolve()
    try:
        manifest = json.loads((directory / "manifest.json").read_text())
    except (OSError, ValueError) as error:
        raise ValueError("Missing or invalid audition manifest") from error
    if manifest.get("schema") != "brahma.donor-audition.v1" or manifest.get("donor", {}).get("sha256") != donor_sha256:
        raise ValueError("Audition donor/source identity mismatch")
    for key, digest in [("original", donor_sha256), ("stereo", manifest["donor"].get("stereo_sha256"))]:
        location = manifest["donor"].get(key)
        if not isinstance(location, str):
            raise ValueError("Missing audition source identity")
        source = (directory / location).resolve()
        if not source.is_relative_to(directory) or not source.is_file() or sha256(source) != digest:
            raise ValueError("Audition source hash integrity mismatch")
    for item in manifest.get("modules", []):
        if item.get("status") not in ("rendered", "silent"):
            continue
        if item["status"] == "silent" and "output" not in item and item.get("render_exit_code") == 0:
            retained = directory / (item["name"] + ".wav")
            values, _, _, _ = pcm(retained)
            if max(abs(value) for value in values) > 32:
                raise ValueError("Retained output contradicts silent measurement")
            item["output"] = retained.name
            item["output_sha256"] = sha256(retained)
            item["output_identity"] = "measured_from_retained_legacy_silent_audio"
        if item.get("output") != item["name"] + ".wav":
            raise ValueError("Invalid comparison output path")
        output = (directory / item["output"]).resolve()
        if not output.is_relative_to(directory) or not output.is_file():
            raise ValueError("Missing comparison output")
        if sha256(output) != item.get("output_sha256"):
            raise ValueError("Comparison output hash integrity mismatch")
    manifest["directory"] = directory
    return manifest


def build_ledger(catalogue, runs, root=None):
    root = Path(root).resolve() if root else None
    indices = {label: {item["name"]: item for item in run["modules"]} for label, run in runs.items()}
    rows = []
    for module in catalogue:
        name = module["name"]
        row = {"name": name, "role": module["role"], "file": module["file"], "definition_sha256": module["definition_sha256"],
               "material_mapping": materials.describe(name), "original_behavior_acceptance": "not_measured",
               "signal_status": "requires_patch" if module["role"] == "infrastructure" else "not_measured", "runs": [], "comparisons": {}}
        for label, index in indices.items():
            item = index.get(name)
            if not item:
                continue
            if item.get("definition_sha256") != module["definition_sha256"]:
                raise ValueError("Native definition changed: " + name)
            if label == "native":
                row["signal_status"] = item["status"]
            entry = {"label": label, "status": item["status"], "params": item.get("parameters", {}),
                     "material": item.get("material"), "base_params": item.get("base_params"), "reason": item.get("reason", ""),
                     "peak_dbfs": item.get("peak_dbfs"), "rms_dbfs": item.get("rms_dbfs")}
            if item.get("status") in ("rendered", "silent"):
                output = runs[label]["directory"] / item["output"]
                entry["output"] = str(output.relative_to(root)) if root and output.is_relative_to(root) else str(output)
                base = indices.get("baseline", {}).get(name)
                if label != "baseline" and base and base.get("status") in ("rendered", "silent"):
                    row["comparisons"][label] = compare_audio(runs["baseline"]["directory"] / base["output"], output)
            row["runs"].append(entry)
        row["interpretation"] = "Signal response and material control changes only. Compare the repeated baseline for stochastic variability; original mimicry/retention acceptance requires organism-specific tests."
        rows.append(row)
    return rows


def validate_renderer_identity(run):
    if (run.get("implementation_sha256") != sha256(Path(assimilate.__file__)) or
            run.get("native_rack_sha256") != sha256(assimilate.SC / "32_donor_rack.scd")):
        raise ValueError("Audition renderer implementation or native rack changed; rerender the comparison")


def validate_native_reuse(catalogue, run, selected):
    validate_renderer_identity(run)
    by_name = {item["name"]: item for item in run["modules"]}
    if not selected <= by_name.keys():
        raise ValueError("Reused native audition is missing selected definitions")
    for module in catalogue:
        if module["name"] not in selected:
            continue
        item = by_name[module["name"]]
        if item.get("definition_sha256") != module["definition_sha256"]:
            raise ValueError("Reused native definition changed: " + module["name"])
        if item.get("status") == "not_selected":
            raise ValueError("Reused native audition is missing a selected result")
        if item.get("material") is not None or item.get("overrides"):
            raise ValueError("Reused native stage must use native defaults, without material or overrides")


def write_index(ledger, destination, original_audio):
    esc = lambda value: html.escape(str(value), quote=True)
    cards = []
    for row in ledger:
        players = []
        for run in row["runs"]:
            if "output" in run:
                players.append('<div><b>' + esc(run["label"]) + '</b><audio controls preload="none" src="' + esc(run["output"]) + '"></audio><small>' +
                               esc(run["status"]) + ' · RMS ' + esc(run["rms_dbfs"]) + ' dBFS</small></div>')
        details = esc(json.dumps(row["comparisons"], indent=2))
        cards.append('<article data-name="' + esc(row["name"]) + '"><h2>' + esc(row["name"]) + '</h2><p>' + esc(row["role"]) + ' · ' + esc(row["signal_status"]) +
                     '</p><p>' + esc(row["material_mapping"]["claim"]) + '</p><div class="players">' + ''.join(players) + '</div><details><summary>Measurements</summary><pre>' +
                     details + '</pre></details><small>Original behavior acceptance: not measured</small></article>')
    document = '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Brahma · Module comparisons</title><style>' + \
        'body{background:#060c12;color:#dbe8e8;font:15px system-ui;max-width:1200px;margin:40px auto;padding:20px}h1,h2,a{color:#8fe1ce}article{border:1px solid #26414a;border-radius:18px;padding:24px;margin:20px 0}.players{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:18px}audio{width:100%;display:block;margin:8px 0}small{color:#a7b8c0}input{padding:12px;min-width:250px}pre{white-space:pre-wrap}summary{padding:12px 0;cursor:pointer}</style>' + \
        '<h1>Same donor. Different organisms and matter.</h1><p>Listen to original audio, native defaults, neutral material controls, a repeated neutral run, and solid/liquid/gas responses. No playback loudness normalization is applied. Random processes can differ between identical runs.</p>' + \
        '<audio controls preload="none" src="' + esc(original_audio) + '"></audio><p><a href="ledger.json">Source-bound comparison ledger</a></p><input id="filter" aria-label="Filter modules" placeholder="Find a module">' + ''.join(cards) + \
        '<script>document.addEventListener("play",e=>{if(e.target.tagName==="AUDIO")document.querySelectorAll("audio").forEach(a=>{if(a!==e.target)a.pause()})},true);document.querySelector("#filter").oninput=e=>document.querySelectorAll("article").forEach(a=>{a.hidden=!a.dataset.name.includes(e.target.value.toLowerCase())})</script></html>'
    (destination / "index.html").write_text(document)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--out", type=Path, default=ROOT / "forge/out/comparisons")
    parser.add_argument("--start", type=float, default=0)
    parser.add_argument("--duration", type=float, default=2)
    parser.add_argument("--deadline", type=float, default=900)
    parser.add_argument("--module", action="append", default=[])
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--reuse-native", type=Path, help="verified existing native-default audition; copy into the new comparison instead of rerendering it")
    args = parser.parse_args()
    if not args.source.is_file() or args.source.stat().st_size > 64 * 1024 * 1024:
        parser.error("Comparison requires a local source of at most 64 MiB")
    if not math.isfinite(args.start) or args.start < 0 or not math.isfinite(args.duration) or not 1 <= args.duration <= 30 or not math.isfinite(args.deadline) or not 1 <= args.deadline <= 3600:
        parser.error("Use a nonnegative start, 1–30 second duration, and 1–3600 second deadline")
    catalog = assimilate.catalogue()
    selected = set(args.module or ["relinquished_te", "agent_smith_identity", "ditto_morphic_core", "typhon_layer"])
    if selected - {item["name"] for item in catalog}:
        parser.error("Unknown native module")
    mapped = [item["name"] for item in catalog if (args.all or item["name"] in selected) and materials.describe(item["name"])["supported"]]
    args.out.mkdir(parents=True, exist_ok=True, mode=0o700)
    if shutil.disk_usage(args.out).free < 1024 ** 3:
        parser.error("Comparison requires 1 GiB free space")
    destination = args.out.resolve() / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
    destination.mkdir(mode=0o700)
    end = time.monotonic() + args.deadline
    original_hash, runs = sha256(args.source), {}
    print("COMPARISON_DIRECTORY " + str(destination), flush=True)
    stages = [("native", None), ("baseline", "off"), ("repeat", "off"), ("solid", "solid"), ("liquid", "liquid"), ("gas", "gas")]
    try:
        for label, phase in stages:
            if label == "native" and args.reuse_native:
                prior = load_audition(args.reuse_native, original_hash)
                validate_native_reuse(catalog, prior, {item["name"] for item in catalog} if args.all else selected)
                if prior["donor"].get("start_seconds") != args.start or prior["donor"].get("duration_seconds") != args.duration:
                    raise ValueError("Reused donor excerpt timing differs")
                build_ledger(catalog, {"native": prior})
                target = destination / "native" / "retained"
                shutil.copytree(prior["directory"], target)
                runs["native"] = load_audition(target, original_hash)
                print("native: reused validated retained audition", flush=True)
                continue
            remaining = end - time.monotonic()
            if remaining <= 1:
                raise ValueError("Comparison deadline reached; earlier evidence preserved")
            if phase is not None and not mapped:
                continue
            command = ["assimilate.py", str(args.source.resolve()), "--start", str(args.start), "--duration", str(args.duration),
                       "--deadline", str(min(remaining, 3600)), "--out", str(destination / label)]
            if phase is None and args.all:
                command.append("--all")
            else:
                for name in mapped if phase is not None else sorted(selected):
                    command.extend(["--module", name])
            if phase is not None:
                state = {"schema": "brahma.material-state.v1", "modelVersion": 1, "phase": "liquid" if phase == "off" else phase,
                         "amount": 0 if phase == "off" else 1, "composition": [{"id": "water", "fraction": 1}]}
                command.extend(["--material-json", json.dumps(state)])
            original_argv = sys.argv
            log = destination / (label + ".log")
            try:
                sys.argv = command
                with log.open("w") as stream, redirect_stdout(stream):
                    code = assimilate.main()
            finally:
                sys.argv = original_argv
            lines = log.read_text().splitlines()
            result = json.loads(lines[-1])
            run = load_audition(result["directory"], original_hash)
            validate_renderer_identity(run)
            for previous in runs.values():
                validate_renderer_identity(previous)
            if runs and run["donor"]["stereo_sha256"] != next(iter(runs.values()))["donor"]["stereo_sha256"]:
                raise ValueError("Normalized donor differs between runs")
            runs[label] = run
            print(label + ": exit=" + str(code) + " directory=" + str(run["directory"]), flush=True)
            rows = build_ledger(catalog, runs, destination)
            report = {"schema": "brahma.module-comparison.v1", "source_sha256": original_hash,
                      "model_sha256": materials.MODEL_SHA256, "catalogue_count": len(catalog), "modules": rows,
                      "original_behavior_acceptance": "not_measured", "stages_complete": False}
            (destination / "ledger.json").write_text(json.dumps(report, indent=2) + "\n")
        rows = build_ledger(catalog, runs, destination)
        report = {"schema": "brahma.module-comparison.v1", "source_sha256": original_hash,
                  "model_sha256": materials.MODEL_SHA256, "catalogue_count": len(catalog), "modules": rows,
                  "original_behavior_acceptance": "not_measured", "stages_complete": True}
        (destination / "ledger.json").write_text(json.dumps(report, indent=2) + "\n")
        original_audio = str((runs["native"]["directory"] / "source.wav").relative_to(destination))
        write_index(rows, destination, original_audio)
        print(json.dumps({"directory": str(destination), "catalogue_count": len(catalog), "mapped_modules_compared": len(mapped), "stages": list(runs)}))
        return 0
    except (OSError, ValueError, wave.Error) as error:
        (destination / "failure.json").write_text(json.dumps({"error": str(error)}) + "\n")
        print("Comparison incomplete: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
