#!/usr/bin/env python3
"""
ingest_queue.py — the Ouroboros submission queue: viewers feed the organism.

AETHER plan §5.6 (the Ω). A viewer submits a stream URL; it lands here as a
pending submission; the broadcast loop pops it and a creature eats it live
(tune.py captures it -> broadcast folds it in as a donor). "Output re-enters as
input" — the consume-you-back loop closes here.

This is the single authority for the queue so both sides agree on the format:
  * the intake surface (deploy/aether/serve.js POST /submit, or `add` below)
    ENQUEUES a submission;
  * tools/broadcast.sh POPS the oldest pending submission each segment.

FIFO by zero-padded filename. Popped files move to <dir>/consumed/ (an audit
trail + the raw material for the lineage). License is recorded, never enforced
as clearance — rights posture stays human-gated (same stance as tune.py).

stdlib only, py3.14-safe. Usage:
    python3 tools/ingest_queue.py add --url URL [--license cc0] [--attribution ..] [--kind audio] [--dir D]
    python3 tools/ingest_queue.py pop  [--dir D]     # prints the popped submission JSON (empty if none)
    python3 tools/ingest_queue.py list [--dir D]     # JSONL of pending submissions
    python3 tools/ingest_queue.py --self-test

Exit: 0 ok · 2 usage · 1 self-test failed
"""
from __future__ import annotations

import argparse
import json
import os
import sys

DEFAULT_DIR = os.path.join("out", "live", "queue")


def _seq_next(qdir: str) -> int:
    """Monotonic sequence for FIFO filenames, persisted in <dir>/.seq."""
    seqfile = os.path.join(qdir, ".seq")
    n = 0
    if os.path.exists(seqfile):
        try:
            n = int(open(seqfile, encoding="utf-8").read().strip() or "0")
        except (ValueError, OSError):
            n = 0
    n += 1
    tmp = seqfile + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(str(n))
    os.replace(tmp, seqfile)
    return n


def add(qdir: str, url: str, license_tag: str = "unknown", attribution: str = "",
        kind: str = "audio") -> dict:
    """Enqueue a submission. Returns the stored record."""
    os.makedirs(qdir, exist_ok=True)
    seq = _seq_next(qdir)
    rec = {
        "id": f"sub_{seq:05d}",
        "seq": seq,
        "url": url,
        "license": (license_tag or "unknown").strip().lower(),
        "attribution": attribution or "",
        "kind": kind or "audio",   # audio now; substrate-agnostic seam for later
    }
    path = os.path.join(qdir, f"sub_{seq:05d}.json")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(rec, fh, indent=2)
    os.replace(tmp, path)
    return rec


def _pending(qdir: str) -> list[str]:
    if not os.path.isdir(qdir):
        return []
    files = [f for f in os.listdir(qdir) if f.startswith("sub_") and f.endswith(".json")]
    return sorted(files)  # zero-padded → lexical == numeric == FIFO


def list_pending(qdir: str) -> list[dict]:
    out = []
    for f in _pending(qdir):
        try:
            out.append(json.load(open(os.path.join(qdir, f), encoding="utf-8")))
        except (OSError, ValueError):
            continue
    return out


def pop(qdir: str) -> dict | None:
    """Pop the oldest pending submission; move it to consumed/ (audit trail)."""
    files = _pending(qdir)
    if not files:
        return None
    src = os.path.join(qdir, files[0])
    try:
        rec = json.load(open(src, encoding="utf-8"))
    except (OSError, ValueError):
        os.remove(src)
        return None
    consumed = os.path.join(qdir, "consumed")
    os.makedirs(consumed, exist_ok=True)
    try:
        os.replace(src, os.path.join(consumed, files[0]))
    except OSError:
        try:
            os.remove(src)
        except OSError:
            pass
    return rec


def _self_test() -> int:
    import tempfile
    fails = []
    d = tempfile.mkdtemp(prefix="ingestq_")
    try:
        qdir = os.path.join(d, "queue")
        if pop(qdir) is not None:
            fails.append("pop on empty queue should return None")
        a = add(qdir, "http://a/stream", "cc0", "", "audio")
        b = add(qdir, "http://b/stream", "public-domain")
        if a["id"] == b["id"]:
            fails.append("ids not unique")
        if len(list_pending(qdir)) != 2:
            fails.append(f"expected 2 pending, got {len(list_pending(qdir))}")
        first = pop(qdir)
        if not first or first["url"] != "http://a/stream":
            fails.append(f"FIFO broken: expected a first, got {first}")
        second = pop(qdir)
        if not second or second["url"] != "http://b/stream":
            fails.append(f"FIFO broken: expected b second, got {second}")
        if pop(qdir) is not None:
            fails.append("queue should be empty after two pops")
        consumed = os.listdir(os.path.join(qdir, "consumed"))
        if len(consumed) != 2:
            fails.append(f"consumed/ should hold 2 audited files, has {len(consumed)}")
    finally:
        import shutil
        shutil.rmtree(d, ignore_errors=True)
    if fails:
        print("ingest_queue self-test: FAIL")
        for f in fails:
            print("  - " + f)
        return 1
    print("ingest_queue self-test: PASS (add, FIFO pop, list, consumed audit trail)")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="The Ouroboros submission queue.")
    ap.add_argument("cmd", nargs="?", choices=["add", "pop", "list"], help="queue command")
    ap.add_argument("--url")
    ap.add_argument("--license", default="unknown")
    ap.add_argument("--attribution", default="")
    ap.add_argument("--kind", default="audio")
    ap.add_argument("--dir", default=DEFAULT_DIR)
    ap.add_argument("--self-test", dest="self_test", action="store_true")
    args = ap.parse_args(argv)

    if args.self_test:
        return _self_test()
    if not args.cmd:
        ap.error("give a command: add | pop | list (or --self-test)")

    if args.cmd == "add":
        if not args.url:
            ap.error("add requires --url")
        rec = add(args.dir, args.url, args.license, args.attribution, args.kind)
        print(json.dumps(rec))
        return 0
    if args.cmd == "pop":
        rec = pop(args.dir)
        if rec:
            print(json.dumps(rec))
        return 0
    if args.cmd == "list":
        for rec in list_pending(args.dir):
            print(json.dumps(rec))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
