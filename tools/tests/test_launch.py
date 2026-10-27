"""Launch acceptance with real local processes and synthetic tier executables."""
import http.server
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
FAKE_NODE = r'''
import http.server, os, pathlib, signal, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
if sys.argv[1].endswith("build-workbench.mjs"):
    if os.environ.get("TEST_BUILD_FAIL"):
        sys.exit(19)
    bundle = root / "brahma/web/public/workbench/vendor/workbench.js"
    bundle.parent.mkdir(parents=True, exist_ok=True)
    bundle.write_text("fixture built")
    sys.exit(0)
if os.environ.get("TEST_SERVER_FAIL"):
    sys.exit(42)
if os.environ.get("TEST_DESCENDANT"):
    child = subprocess.Popen([sys.executable, "-c", "import signal,time,pathlib; "
        "signal.signal(signal.SIGTERM,signal.SIG_IGN); p=pathlib.Path(" + repr(str(root / "heartbeat")) + "); "
        "exec('while True:\\n p.open(\\\"a\\\").write(\\\".\\\"); time.sleep(.01)')"])
    (root / "descendant.pid").write_text(str(child.pid))
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"fixture response")
    def log_message(self, *args): pass
server = http.server.ThreadingHTTPServer(("127.0.0.1", int(os.environ["PORT"])), Handler)
print("--- VISUAL CORTEX ONLINE: http://127.0.0.1:%d ---" % server.server_port, flush=True)
if not os.environ.get("BRAHMA_HUMAN_TOKEN"):
    print("--- WORKBENCH (human): http://127.0.0.1:%d/workbench/#t=fixture-human-token ---" % server.server_port, flush=True)
server.serve_forever()
'''


class LaunchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="brahma-launch-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        (self.root / "bin").mkdir()
        (self.root / "brahma/web/node_modules").mkdir(parents=True)
        for name in ("start-brahma.sh", "start-brahma.py"):
            shutil.copy2(ROOT / "tools" / name, self.root / "tools" / name)
        node = self.root / "bin/node"
        node.write_text(f"#!{sys.executable}\n" + FAKE_NODE)
        node.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"])
        self.env.pop("BRAHMA_HUMAN_TOKEN", None)
        self.command = ["bash", str(self.root / "tools/start-brahma.sh"), "--no-sc", "--no-pd"]

    def test_foreign_http_listener_cannot_mask_our_server_failure(self):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200); self.end_headers(); self.wfile.write(b"unrelated")
            def log_message(self, *args): pass
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = subprocess.run(self.command + ["--port", str(server.server_port)],
                                    env=dict(self.env, TEST_SERVER_FAIL="1"),
                                    capture_output=True, text=True, timeout=8)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("Web: online", result.stdout)
            self.assertIn("exited 42", result.stderr)
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=2)

    def test_missing_bundle_is_built_and_shutdown_stops_descendants(self):
        log = self.root / "launch.log"
        with log.open("w") as stream:
            process = subprocess.Popen(self.command + ["--port", "0"], env=dict(self.env, TEST_DESCENDANT="1"),
                                       stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 6
            heartbeat = self.root / "heartbeat"
            while "Web: online" not in log.read_text() or not heartbeat.exists():
                self.assertIsNone(process.poll(), log.read_text())
                self.assertLess(time.monotonic(), deadline, log.read_text())
                time.sleep(0.02)
            self.assertEqual((self.root / "brahma/web/public/workbench/vendor/workbench.js").read_text(),
                             "fixture built")
            self.assertIn("/workbench/#t=fixture-human-token", log.read_text())
            private_log = next(line.removeprefix("Logs: ") for line in log.read_text().splitlines()
                               if line.startswith("Logs: "))
            self.assertNotIn("fixture-human-token", (Path(private_log) / "web.log").read_text())
            process.terminate()
            self.assertEqual(process.wait(timeout=6), 143, log.read_text())
            size = heartbeat.stat().st_size
            time.sleep(0.08)
            self.assertEqual(heartbeat.stat().st_size, size, "descendant survived launcher shutdown")
        finally:
            if process.poll() is None:
                process.kill(); process.wait(timeout=2)
            pid_file = self.root / "descendant.pid"
            if pid_file.exists():
                try:
                    os.kill(int(pid_file.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_failed_build_never_launches_a_server(self):
        result = subprocess.run(self.command + ["--port", "0"], env=dict(self.env, TEST_BUILD_FAIL="1"),
                                capture_output=True, text=True, timeout=6)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("setup exited 19", result.stderr)
        self.assertNotIn("Web: online", result.stdout)

    def test_invalid_port_is_rejected_before_startup(self):
        result = subprocess.run(self.command + ["--port", "70000"], env=self.env,
                                capture_output=True, text=True, timeout=6)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--port must be", result.stderr)


if __name__ == "__main__":
    unittest.main()
