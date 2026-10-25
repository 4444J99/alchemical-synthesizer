#!/usr/bin/env python3
"""Run one native SC test on a private UDP port with a hard process deadline."""
import argparse
import os
from pathlib import Path
import signal
import selectors
import socket
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", type=Path)
    parser.add_argument("--timeout", type=int, default=25)
    parser.add_argument("--sclang", default=os.environ.get("SCLANG_PATH", "/Applications/Supercollider/SuperCollider.app/Contents/MacOS/sclang"))
    parser.add_argument("--core-only", action="store_true")
    args = parser.parse_args()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    root = Path(__file__).resolve().parents[1]
    command = [args.sclang, "-D", "-u", str(port)]
    if not args.core_only:
        command += ["--include-path", str(root / "brahma/sc")]
    command.append(str(args.script.resolve()))
    print(f"SC test: {args.script.name}; private UDP port={port}; deadline={args.timeout}s", flush=True)
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            start_new_session=True, preexec_fn=lambda: os.nice(10))
    output = bytearray()
    failure = None
    deadline = time.monotonic() + args.timeout
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
    if failure:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        print(output[-65536:].decode(errors="replace"))
        print(f"FAIL: native SC test exceeded {failure[1]}", file=sys.stderr)
        return failure[0]
    proc.wait(timeout=max(1, deadline - time.monotonic()))
    output = output.decode(errors="replace")
    print(output[-65536:])
    return proc.returncode if proc.returncode else (0 if "BRAHMA_TEST_PASS" in output and "FAIL:" not in output and "ERROR:" not in output else 1)


if __name__ == "__main__":
    sys.exit(main())
