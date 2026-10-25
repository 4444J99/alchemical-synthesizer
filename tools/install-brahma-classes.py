#!/usr/bin/env python3
"""Expose the source-owned Brahma classes to native and XDG SuperCollider launches."""
import argparse
import os
from pathlib import Path
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--apply", action="store_true", help="create missing links; existing different content is never replaced")
parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1] / "brahma/sc")
args = parser.parse_args()
source = args.source.resolve()
if not (source / "BrahmaMetrics.sc").is_file():
    parser.error("source must contain the repaired Brahma classes")
xdg = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "SuperCollider/Extensions"
roots = [xdg]
if sys.platform == "darwin":
    roots.insert(0, Path.home() / "Library/Application Support/SuperCollider/Extensions")
for root in dict.fromkeys(roots):
    destination = root / "Brahma"
    if destination.is_symlink() and destination.resolve() == source:
        print(f"OK {destination} -> {source}")
    elif destination.exists() or destination.is_symlink():
        raise SystemExit(f"Refusing to replace existing content: {destination}")
    elif args.apply:
        root.mkdir(parents=True, exist_ok=True)
        destination.symlink_to(source, target_is_directory=True)
        print(f"CREATED {destination} -> {source}")
    else:
        print(f"WOULD CREATE {destination} -> {source}")
