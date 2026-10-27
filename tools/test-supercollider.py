#!/usr/bin/env python3
"""Run one native SC file with supported 3.13 configuration and bounded cleanup."""
import argparse
import json
import math
import os
from pathlib import Path
import selectors
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time


def default_sclang():
    configured = os.environ.get("SCLANG_PATH")
    if configured:
        return configured
    found = shutil.which("sclang")
    if found:
        return found
    for bundle in (Path("/Applications/SuperCollider.app"), Path("/Applications/SuperCollider/SuperCollider.app")):
        candidate = bundle / "Contents/MacOS/sclang"
        if candidate.is_file():
            return str(candidate)
    return None


def stop_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        pass
    # The leader can exit while descendants retain its group or stdout pipe.
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    proc.wait()


def run(args, config):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    command = [args.sclang, "-D", "-u", str(port), "-l", str(config), str(args.script.resolve())]
    env = dict(os.environ)
    if sys.platform.startswith("linux"):
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        if os.geteuid() == 0:
            env.setdefault("QTWEBENGINE_DISABLE_SANDBOX", "1")
    print(f"SC test: {args.script.name}; private UDP port={port}; deadline={args.timeout}s", flush=True)
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            start_new_session=True, env=env)
    output = bytearray()
    failure = None
    deadline = time.monotonic() + args.timeout
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while selector.get_map():
                if time.monotonic() >= deadline:
                    failure = (124, "deadline")
                    break
                for key, _ in selector.select(timeout=0.1):
                    data = os.read(key.fd, 65536)
                    if not data:
                        selector.unregister(key.fileobj)
                        continue
                    if len(output) + len(data) > 262144:
                        failure = (125, "output limit")
                        break
                    output.extend(data)
                if failure:
                    break
        if failure is None:
            try:
                proc.wait(timeout=max(0.01, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                failure = (124, "deadline")
    finally:
        stop_group(proc)
        proc.stdout.close()
    text = output.decode(errors="replace")
    print(text[-65536:])
    if failure:
        print(f"FAIL: native SC test exceeded {failure[1]}", file=sys.stderr)
        return failure[0]
    return proc.returncode if proc.returncode else (0 if "BRAHMA_TEST_PASS" in text and "FAIL:" not in text and "ERROR:" not in text else 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", type=Path)
    parser.add_argument("--timeout", type=float, default=25)
    parser.add_argument("--sclang", default=default_sclang())
    parser.add_argument("--core-only", action="store_true")
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1] / "brahma/sc")
    args = parser.parse_args()
    if not args.sclang:
        parser.error("sclang is required; install SuperCollider or set SCLANG_PATH")
    if not math.isfinite(args.timeout) or args.timeout <= 0 or not args.script.is_file():
        parser.error("provide an existing script and a positive timeout")
    source = args.source.resolve()
    extension_roots = [Path.home() / "Library/Application Support/SuperCollider/Extensions",
                       Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "SuperCollider/Extensions"]
    includes, excludes = [], []
    if not args.core_only:
        installed = [root / "Brahma" for root in extension_roots if (root / "Brahma").exists()]
        if not any(path.resolve() == source for path in installed):
            includes.append(source)
        excludes.extend(path for path in installed if path.resolve() != source)
        # A prior installer exposed six separate aliases. Exclude those aliases
        # while selecting the complete checkout, without editing user extensions.
        for root in extension_roots:
            excludes.extend(root / path.name for path in source.rglob("*.sc") if (root / path.name).exists())
    with tempfile.TemporaryDirectory(prefix="brahma-sc-run-") as directory:
        config = Path(directory) / "sclang.yaml"
        config.write_text("includePaths: " + json.dumps([str(path) for path in includes]) + "\n"
                          "excludePaths: " + json.dumps([str(path) for path in excludes]) + "\n"
                          "excludeDefaultPaths: false\npostInlineWarnings: false\n")
        try:
            return run(args, config)
        except OSError as error:
            print(f"FAIL: cannot run sclang: {error}", file=sys.stderr)
            return 2


if __name__ == "__main__":
    sys.exit(main())
