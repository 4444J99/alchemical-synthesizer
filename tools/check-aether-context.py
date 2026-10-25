#!/usr/bin/env python3
"""Check local COPY sources in AETHER's declared repo-root Docker build context.

This proves source availability, not an image build or deployment.
"""
from pathlib import Path
import shlex
import sys


def check(root):
    dockerfile = root / "aether/deploy/Dockerfile"
    text = dockerfile.read_text().replace("\\\n", " ")
    sources = []
    for number, line in enumerate(text.splitlines(), 1):
        words = shlex.split(line, comments=True)
        if not words or words[0].upper() != "COPY":
            continue
        # The current Dockerfile uses plain local COPY. Fail on a changed syntax
        # until the validator understands it, rather than silently missing inputs.
        if len(words) < 3 or any(w.startswith(("--", "[")) for w in words[1:]):
            raise ValueError(f"unsupported COPY syntax at logical line {number}")
        for source in words[1:-1]:
            candidate = root / source
            if not candidate.resolve().is_relative_to(root.resolve()):
                raise ValueError(f"COPY source escapes build context: {source}")
            if not candidate.exists():
                raise ValueError(f"missing COPY source: {source}")
            sources.append(source)
    if not sources:
        raise ValueError("no local COPY sources found")
    print(f"AETHER COPY context: PASS ({len(sources)} sources; image build not performed)")


if __name__ == "__main__":
    try:
        check(Path(__file__).resolve().parents[1])
    except (OSError, ValueError) as error:
        print(f"AETHER COPY context: FAIL: {error}", file=sys.stderr)
        sys.exit(1)
