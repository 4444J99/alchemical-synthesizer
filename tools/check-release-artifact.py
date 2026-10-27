#!/usr/bin/env python3
"""Validate a release archive, then install, boot and check its actual HTTP assets.

Usage: python3 tools/check-release-artifact.py dist/release.tar.gz [--structure-only]
Accepts tar.gz or zip. No model calls, publication, or pre-existing processes used.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import socket
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import zipfile

BUNDLE = "brahma/web/public/workbench/vendor/workbench.js"
REQUIRED = (BUNDLE, "brahma/web/public/workbench/index.html", "brahma/web/server.js",
            "brahma/web/package-lock.json", "brahma/sc/tests/phase_a.scd",
            "brahma/sc/tests/class_runtime.scd", "brahma/sc/tests/flucoma_buffer.scd")
MAX_UNPACKED_BYTES = 256 * 1024 * 1024


def inspect_archive(artifact, destination=None):
    """Validate every member before extracting regular files and directories only."""
    is_zip = zipfile.is_zipfile(artifact)
    archive = zipfile.ZipFile(artifact) if is_zip else tarfile.open(artifact, "r:gz")
    with archive:
        members = archive.infolist() if is_zip else archive.getmembers()
        entries = []
        roots, files, seen = set(), {}, set()
        total = 0
        for member in members:
            name = member.filename if is_zip else member.name
            path = PurePosixPath(name)
            mode = member.external_attr >> 16 if is_zip else member.mode
            directory = member.is_dir() if is_zip else member.isdir()
            regular = stat.S_IFMT(mode) in (0, stat.S_IFREG) if is_zip else member.isfile()
            if (not path.parts or path.is_absolute() or ".." in path.parts or "\\" in name
                    or not (directory or regular) or path in seen):
                raise ValueError(f"unsafe archive member: {name}")
            seen.add(path)
            roots.add(path.parts[0])
            relative = PurePosixPath(*path.parts[1:])
            if any(p in {".git", ".runtime", ".wrangler", "node_modules", "__pycache__"}
                   or p == ".env" or (p.startswith(".env.") and p != ".env.example")
                   for p in relative.parts):
                raise ValueError(f"private/generated state in archive: {name}")
            size = member.file_size if is_zip else member.size
            total += size
            if total > MAX_UNPACKED_BYTES:
                raise ValueError("archive exceeds 256 MiB extraction limit")
            if not directory:
                files[str(relative)] = size
            entries.append((member, path, directory, mode))
        if len(roots) != 1:
            raise ValueError("archive must contain exactly one release root")
        for required in REQUIRED:
            if files.get(required, 0) <= 0:
                raise ValueError(f"missing or empty release asset: {required}")
        root = next(iter(roots))
        if destination is not None:
            for member, path, directory, mode in entries:
                target = destination.joinpath(*path.parts)
                if directory:
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    source = archive.open(member) if is_zip else archive.extractfile(member)
                    with source, target.open("wb") as output:
                        while chunk := source.read(1024 * 1024):
                            output.write(chunk)
                    target.chmod(0o755 if mode & 0o111 else 0o644)
        print(f"STRUCTURE PASS: {len(files)} files, bundle {files[BUNDLE]} bytes, no private state")
        return root


def stop_process_group(process):
    # The process is always started by this checker with start_new_session=True.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=10)


def run_bounded(command, cwd, env, timeout):
    process = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=timeout)
        if process.returncode:
            raise RuntimeError(f"{command[0]} exited {process.returncode}: "
                               + output.decode(errors="replace")[-2000:])
    finally:
        stop_process_group(process)


def verify_http(base, root, commit):
    for endpoint in ("/", "/workbench/", "/workbench/source.json", "/workbench/vendor/workbench.js",
                     "/api/modules", "/api/substrates/sound.json", "/aether/"):
        with urllib.request.urlopen(base + endpoint, timeout=5) as response:
            if response.status != 200:
                raise RuntimeError(f"{endpoint}: HTTP {response.status}")
            body = response.read(16 * 1024 * 1024)
        if not body:
            raise RuntimeError(f"empty response: {endpoint}")
        if endpoint.endswith("workbench.js"):
            expected = hashlib.sha256((root / BUNDLE).read_bytes()).digest()
            if hashlib.sha256(body).digest() != expected:
                raise RuntimeError("served bundle differs from the packaged bundle")
        if endpoint.endswith("source.json"):
            source = json.loads(body)
            if source.get("bundle") != "/workbench/vendor/workbench.js":
                raise RuntimeError("source offer does not name the shipped bundle")
            if source.get("commit") != commit:
                raise RuntimeError("archive source offer does not match the build manifest")
        print(f"HTTP PASS: {endpoint} -> 200 ({len(body)} bytes)")


def verify_runtime(root, scratch):
    manifest = (root / "BUILD_MANIFEST.txt").read_text()
    recorded = re.search(r"^commit:\s+([0-9a-f]{40})\s*$", manifest, re.MULTILINE)
    if not recorded:
        raise RuntimeError("build manifest must identify its source commit")
    commit = recorded.group(1)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("BRAHMA_") and k not in
           {"ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY", "NODE_OPTIONS"}}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        dirt_port = sock.getsockname()[1]
    env.update(PORT="0", HOST="127.0.0.1", BRAHMA_OSC_LISTEN_PORT="0",
               BRAHMA_COMMIT_SHA=commit,
               BRAHMA_OSC_SEND_PORT="9", BRAHMA_DIRT_PORT=str(dirt_port),
               BRAHMA_RUNTIME_DIR=str(scratch / "runtime"),
               BRAHMA_AGENT_TOKEN="artifact-check-agent-token",
               BRAHMA_HUMAN_TOKEN="artifact-check-human-token")
    web = root / "brahma/web"
    run_bounded(["npm", "ci", "--no-audit", "--no-fund"], web, env, 180)
    print("INSTALL PASS: unpacked lockfile dependencies")
    log_path = scratch / "server.log"
    with log_path.open("wb") as log:
        process = subprocess.Popen(["node", "server.js"], cwd=web, env=env,
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                output = log_path.read_text(errors="replace")
                match = re.search(r"VISUAL CORTEX ONLINE: (http://127\.0\.0\.1:\d+)", output)
                if match:
                    verify_http(match.group(1), root, commit)
                    return
                if process.poll() is not None:
                    raise RuntimeError(f"release server exited {process.returncode}: {output[-2000:]}")
                time.sleep(0.05)
            raise RuntimeError("release server failed to bind within 10 seconds")
        finally:
            stop_process_group(process)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--structure-only", action="store_true")
    args = parser.parse_args()
    if args.structure_only:
        inspect_archive(args.artifact)
    else:
        with tempfile.TemporaryDirectory(prefix="brahma-release-check-") as tmp:
            scratch = Path(tmp)
            root = inspect_archive(args.artifact, scratch)
            verify_runtime(scratch / root, scratch)
    print("RELEASE ARTIFACT: PASS")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, tarfile.TarError, zipfile.BadZipFile,
            subprocess.TimeoutExpired) as error:
        print(f"RELEASE ARTIFACT: FAIL: {error}", file=sys.stderr)
        sys.exit(1)
