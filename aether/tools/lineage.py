#!/usr/bin/env python3
"""
lineage.py — the AETHER lineage ledger: the stream is a lineage, not a loop.

AETHER plan §7 (honesty ledger) + §5.6 (Ω): "every absorbed sample carries
lineage (id, epoch, fidelity, parent). The stream is a lineage, not a loop."
This appends one entry per absorbed donor (a viewer submission, or the
Ouroboros self-consumption where output re-enters as input) to a JSON ledger the
lineage browser reads.

Fields per entry:
  id        the broadcast segment id that absorbed it
  epoch     the organism's life at absorption
  fidelity  provisional (see docs/logos/pragma.md) — how faithfully reproduced
  source    the donor: a submitted URL, "ouroboros:self", or a station name
  license   the donor's license tag (recorded, not clearance)
  creature  which of the five ate it
  parent    the prior lineage entry's id (or "genesis")

stdlib only, py3.14-safe. Flags (no JSON-in-arg quoting hazards). Usage:
    python3 tools/lineage.py append --file out/live/lineage.json \
        --id 12 --epoch 1 --fidelity 0.62 --source http://x --license cc0 \
        --creature chrysalid-siren --parent sub_00003
    python3 tools/lineage.py list --file out/live/lineage.json
    python3 tools/lineage.py --self-test

Exit: 0 ok · 2 usage · 1 self-test failed
"""
from __future__ import annotations

import argparse
import json
import os
import sys


def _load(path: str) -> dict:
    if os.path.exists(path):
        try:
            return json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError):
            pass
    return {"entries": [],
            "note": "fidelity is PROVISIONAL (docs/logos/pragma.md); license is recorded, not clearance."}


def _save(path: str, data: dict) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    os.replace(tmp, path)  # atomic — the lineage browser never reads a torn file


def append(path: str, entry: dict) -> dict:
    data = _load(path)
    # parent defaults to the last entry's id (the chain), or genesis.
    if not entry.get("parent"):
        entry["parent"] = data["entries"][-1]["id"] if data["entries"] else "genesis"
    data["entries"].append(entry)
    # keep the ledger bounded on disk; a real archive can persist more.
    if len(data["entries"]) > 5000:
        data["entries"] = data["entries"][-5000:]
    _save(path, data)
    return entry


def _self_test() -> int:
    import tempfile, shutil
    fails = []
    d = tempfile.mkdtemp(prefix="lineage_")
    try:
        path = os.path.join(d, "lineage.json")
        e1 = append(path, {"id": "seg_1", "epoch": 0, "fidelity": 0.8, "source": "http://a",
                           "license": "cc0", "creature": "mnemosyne"})
        if e1["parent"] != "genesis":
            fails.append(f"first entry parent should be genesis, got {e1['parent']}")
        e2 = append(path, {"id": "seg_2", "epoch": 0, "fidelity": 0.5, "source": "ouroboros:self",
                           "license": "own", "creature": "ossuary-monk"})
        if e2["parent"] != "seg_1":
            fails.append(f"second entry should chain to seg_1, got {e2['parent']}")
        data = _load(path)
        if len(data["entries"]) != 2:
            fails.append(f"expected 2 entries, got {len(data['entries'])}")
        if "PROVISIONAL" not in data["note"]:
            fails.append("ledger dropped the provisional honesty note")
        # explicit parent is honored
        e3 = append(path, {"id": "seg_3", "epoch": 1, "fidelity": 0.6, "source": "http://c",
                           "license": "cc-by", "creature": "chrysalid-siren", "parent": "seg_1"})
        if e3["parent"] != "seg_1":
            fails.append("explicit parent not honored")
    finally:
        shutil.rmtree(d, ignore_errors=True)
    if fails:
        print("lineage self-test: FAIL")
        for f in fails:
            print("  - " + f)
        return 1
    print("lineage self-test: PASS (append, parent chaining, provisional note, bounded)")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="The AETHER lineage ledger.")
    ap.add_argument("cmd", nargs="?", choices=["append", "list"])
    ap.add_argument("--file", default=os.path.join("out", "live", "lineage.json"))
    ap.add_argument("--id"); ap.add_argument("--epoch", type=int, default=0)
    ap.add_argument("--fidelity", type=float, default=0.0)
    ap.add_argument("--source", default=""); ap.add_argument("--license", default="unknown")
    ap.add_argument("--creature", default=""); ap.add_argument("--parent", default="")
    ap.add_argument("--self-test", dest="self_test", action="store_true")
    args = ap.parse_args(argv)

    if args.self_test:
        return _self_test()
    if not args.cmd:
        ap.error("give a command: append | list (or --self-test)")

    if args.cmd == "append":
        if not args.id:
            ap.error("append requires --id")
        entry = append(args.file, {
            "id": args.id, "epoch": args.epoch, "fidelity": args.fidelity,
            "source": args.source, "license": args.license,
            "creature": args.creature, "parent": args.parent or None,
        })
        print(json.dumps(entry))
        return 0
    if args.cmd == "list":
        for e in _load(args.file)["entries"]:
            print(json.dumps(e))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
