#!/usr/bin/env python3
"""Start the requested local tiers and supervise their process groups."""
import argparse
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def stop_group(process):
    """Only called for children launched here with start_new_session=True."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    # The leader may have exited while a descendant ignored SIGTERM.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=2)
    reader = getattr(process, "log_reader", None)
    if reader is not None:
        reader.join(timeout=2)


def launch(command, cwd, env, log):
    with log.open("wb") as output:
        return subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                stdout=output, stderr=subprocess.STDOUT,
                                start_new_session=True)


def launch_web(command, cwd, env, log):
    # The generated human capability belongs in the user's terminal handoff,
    # never in a persisted log. Keep the owned startup banner in the log for
    # readiness, while forwarding only this particular line directly.
    output = log.open("wb")
    try:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   start_new_session=True)
    except BaseException:
        output.close()
        raise

    def capture():
        with output, process.stdout:
            for line in process.stdout:
                if line.startswith(b"--- WORKBENCH (human): "):
                    if not env.get("BRAHMA_HUMAN_TOKEN"):
                        print(line.decode(errors="replace").rstrip(), flush=True)
                    line = b"--- HUMAN ROLE: generated launch link forwarded to local terminal ---\n"
                output.write(line)
                output.flush()

    process.log_reader = threading.Thread(target=capture, daemon=True)
    process.log_reader.start()
    return process


def run_setup(command, cwd, env, log, timeout=180):
    process = launch(command, cwd, env, log)
    try:
        code = process.wait(timeout=timeout)
        if code:
            raise RuntimeError(f"setup exited {code}: {command[0]}; see {log}")
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"setup timed out: {command[0]}; see {log}") from None
    finally:
        stop_group(process)


def wait_ready(process, log, check, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        code = process.poll()
        if code is not None:
            raise RuntimeError(f"process exited {code} before readiness; see {log}")
        result = check(log.read_text(errors="replace"))
        if result and process.poll() is None:
            return result
        time.sleep(0.05)
    raise RuntimeError(f"readiness timed out; see {log}")


def web_ready(output):
    # This banner is read from this child's newly created private log. An HTTP
    # 200 from a previous/unrelated server cannot establish our child's startup.
    match = re.search(r"VISUAL CORTEX ONLINE: (http://127\.0\.0\.1:\d+)", output)
    if not match:
        return None
    base = match.group(1)
    try:
        for endpoint in ("/workbench/", "/workbench/vendor/workbench.js"):
            with urllib.request.urlopen(base + endpoint, timeout=1) as response:
                if response.status != 200 or not response.read(1):
                    return None
    except (OSError, urllib.error.URLError):
        return None
    return base


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for tier in ("sc", "web", "pd"):
        parser.add_argument(f"--no-{tier}", action="store_true")
    parser.add_argument("--port", type=int, default=3000)
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error("--port must be between 0 and 65535 (0 selects a free port)")
    logs = Path(tempfile.mkdtemp(prefix="brahma-start-"))
    env = dict(os.environ)
    env.setdefault("BRAHMA_RUNTIME_DIR", str(logs / "runtime"))
    children = []

    def shutdown(signum, _frame):
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)
    print(f"=== Alchemical Synthesizer — local start ===\nLogs: {logs}", flush=True)
    try:
        sc = shutil.which("sclang")
        if args.no_sc or not sc:
            print("[1/3] SC: skipped", flush=True)
        else:
            log = logs / "sc.log"
            process = launch([sc, "-D", str(ROOT / "brahma/sc/loader.scd")], ROOT, env, log)
            children.append(("SC", process))
            wait_ready(process, log, lambda text: "BRAHMA SYSTEM ONLINE" in text, 30)
            print("[1/3] SC: initialization banner observed", flush=True)

        if args.no_web:
            print("[2/3] Web: skipped", flush=True)
        else:
            web = ROOT / "brahma/web"
            if not (web / "node_modules").is_dir():
                run_setup(["npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund"],
                          web, env, logs / "npm.log")
            run_setup(["node", str(ROOT / "tools/build-workbench.mjs")],
                      ROOT, env, logs / "build.log")
            log = logs / "web.log"
            web_env = dict(env, PORT=str(args.port), HOST="127.0.0.1")
            process = launch_web(["node", "server.js"], web, web_env, log)
            children.append(("Web", process))
            base = wait_ready(process, log, web_ready, 20)
            print(f"[2/3] Web: online {base}/workbench/", flush=True)

        pd = shutil.which("pd")
        if args.no_pd or not pd:
            print("[3/3] Pd: skipped", flush=True)
        else:
            process = launch([pd, str(ROOT / "brahma/pd/main.pd")], ROOT, env, logs / "pd.log")
            children.append(("Pd", process))
            print("[3/3] Pd: launched; device acceptance remains interactive", flush=True)

        if not children:
            return 0
        print("Requested tiers started. Press Ctrl-C to stop their process groups.", flush=True)
        while True:
            for name, process in children:
                if process.poll() is not None:
                    raise RuntimeError(f"{name} exited {process.returncode}; stopping the other tiers; see {logs}")
            time.sleep(0.1)
    finally:
        for _name, process in reversed(children):
            stop_group(process)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"BRAHMA START: {error}", file=sys.stderr)
        sys.exit(1)
