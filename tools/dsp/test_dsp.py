#!/usr/bin/env python3
"""Native SC language and offline DSP regressions; no audio device is opened.

Run: python3 tools/dsp/test_dsp.py
Requires SuperCollider 3.13+ (sclang and scsynth). The tests isolate the class
library, render float WAVs in a temporary directory, and fail on missing tools.
These checks do not establish full-loader or live hardware acceptance.
"""

from __future__ import annotations

import array
import json
import math
import os
from pathlib import Path
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = Path(__file__).resolve().parent


def sc_binary(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    for bundle in (Path("/Applications/SuperCollider.app"),
                   Path("/Applications/SuperCollider/SuperCollider.app")):
        for folder in ("MacOS", "Resources"):
            candidate = bundle / "Contents" / folder / name
            if candidate.is_file():
                return str(candidate)
    raise RuntimeError(f"{name} is required; install SuperCollider 3.13+")


def class_library(sclang: str) -> Path:
    binary = Path(sclang).resolve()
    candidates = (
        binary.parent.parent / "Resources" / "SCClassLibrary",
        binary.parent / "SCClassLibrary",
        binary.parent.parent / "share" / "SuperCollider" / "SCClassLibrary",
        Path("/usr/share/SuperCollider/SCClassLibrary"),
        Path("/usr/local/share/SuperCollider/SCClassLibrary"),
        Path("/opt/homebrew/share/SuperCollider/SCClassLibrary"),
    )
    for candidate in candidates:
        if candidate.is_dir():
            return candidate
    raise RuntimeError("Could not locate the installed SuperCollider class library")


def float_wav(path: Path) -> tuple[int, list[array.array]]:
    """Read scsynth's IEEE float WAV without a third-party audio dependency."""
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise AssertionError("NRT did not produce a RIFF/WAVE file")
    offset, fmt, samples = 12, None, None
    while offset + 8 <= len(data):
        kind, size = struct.unpack_from("<4sI", data, offset)
        payload = data[offset + 8:offset + 8 + size]
        if kind == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", payload)
        elif kind == b"data":
            samples = array.array("f")
            samples.frombytes(payload)
            if sys.byteorder != "little":
                samples.byteswap()
        offset += 8 + size + (size % 2)
    if fmt is None or samples is None or fmt[0] != 3 or fmt[5] != 32:
        raise AssertionError("Expected a 32-bit float NRT WAV")
    return fmt[2], [samples[channel::fmt[1]] for channel in range(fmt[1])]


class NativeDSPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sclang = sc_binary("sclang")
        cls.scsynth = sc_binary("scsynth")
        cls.temp = tempfile.TemporaryDirectory(prefix="brahma-dsp-")
        cls.work = Path(cls.temp.name)
        cls.config = cls.work / "sclang.yaml"
        cls.config.write_text(
            "includePaths:\n"
            f"  - {json.dumps(str(class_library(cls.sclang)))}\n"
            f"  - {json.dumps(str(ROOT / 'brahma/sc'))}\n"
            "excludePaths: []\nexcludeDefaultPaths: true\npostInlineWarnings: false\n"
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def run_sc(self, script: str, extra_env: dict[str, str] | None = None,
               marker: str = "DSP_PASS") -> str:
        env = dict(os.environ, BRAHMA_REPO_ROOT=str(ROOT),
                   BRAHMA_TEST_TMP=str(self.work), BRAHMA_SCSYNTH=self.scsynth)
        env.update(extra_env or {})
        if sys.platform.startswith("linux"):
            env.setdefault("QT_QPA_PLATFORM", "offscreen")
            if os.geteuid() == 0:
                # Trusted local scripts only; QtWebEngine otherwise refuses root.
                env.setdefault("QTWEBENGINE_DISABLE_SANDBOX", "1")
        command = [self.sclang, "-D", "-a", "-u", "0", "-l", str(self.config),
                   str(SCRIPTS / script)]
        process = subprocess.Popen(command, cwd=self.work, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, start_new_session=True)
        try:
            output, _ = process.communicate(timeout=40)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
            self.fail(f"{script} timed out:\n{output}")
        self.assertEqual(process.returncode, 0, f"{script} failed:\n{output}")
        self.assertIn(marker, output, output)
        return output

    def test_all_repository_scd_files_compile(self) -> None:
        self.run_sc("compile.scd")

    def test_metrics_distinguish_signal_and_unavailable_input(self) -> None:
        self.run_sc("metrics.scd")

    def test_telemetry_does_not_publish_uncaptured_measurements(self) -> None:
        self.run_sc("telemetry.scd")

    def test_trait_contracts_load_validate_and_normalize(self) -> None:
        self.run_sc("contracts.scd")

    def test_upstream_measured_traits_and_fsap_acceptance(self) -> None:
        self.run_sc(str(ROOT / "brahma/sc/tests/phase_a.scd"), marker="BRAHMA_TEST_PASS")

    def test_upstream_provenance_transmutation_and_bridge_lifecycle(self) -> None:
        self.run_sc(str(ROOT / "brahma/sc/tests/class_runtime.scd"), marker="BRAHMA_TEST_PASS")

    @unittest.skipUnless(os.environ.get("BRAHMA_DSP_DUMMY_AUDIO") == "1",
                         "set BRAHMA_DSP_DUMMY_AUDIO=1 for Linux dummy-JACK integration")
    def test_buffer_adapter_and_live_voice_lifecycle_on_dummy_server(self) -> None:
        # Opt-in Linux JACK backend only: never fall back to hardware audio.
        if not sys.platform.startswith("linux") or not shutil.which("jackd"):
            self.fail("Dummy-server integration requires Linux SuperCollider/JACK and jackd2")
        name = f"brahma-dsp-{os.getpid()}"
        env = dict(os.environ, JACK_DEFAULT_SERVER=name, JACK_NO_AUDIO_RESERVATION="1")
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        with (self.work / "jack.log").open("w") as log:
            jack = subprocess.Popen(
                ["jackd", "--no-realtime", "-n", name, "-d", "dummy", "-r", "44100", "-p", "256"],
                stdout=log, stderr=subprocess.STDOUT, env=env, start_new_session=True,
            )
            try:
                time.sleep(0.8)
                self.assertIsNone(jack.poll(), "dummy JACK failed to start")
                self.run_sc("live.scd", dict(JACK_DEFAULT_SERVER=name, JACK_NO_AUDIO_RESERVATION="1",
                                             BRAHMA_TEST_PORT=str(port)))
            finally:
                if jack.poll() is None:
                    os.killpg(jack.pid, signal.SIGTERM)
                    try:
                        jack.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(jack.pid, signal.SIGKILL)
                        jack.wait()

    def test_governor_bounds_both_outputs_and_quarantines_runaway(self) -> None:
        self.run_sc("immune.scd")
        sample_rate, channels = float_wav(self.work / "immune.wav")
        self.assertEqual(len(channels), 2)
        self.assertEqual(sample_rate, 44100)
        self.assertGreater(len(channels[0]), 44000)
        for channel in channels:
            self.assertTrue(all(math.isfinite(value) for value in channel))
            self.assertLessEqual(max(map(abs, channel)), 0.90001)
        # Channel 0 is runaway; after the gate settles it must become quiet.
        loud_tail = channels[0][int(sample_rate * 0.6):]
        self.assertLess(max(map(abs, loud_tail)), 0.001)
        # Channel 1 is safe: it must pass, without a duplicated dry signal.
        quiet_tail = channels[1][int(sample_rate * 0.6):]
        rms = math.sqrt(sum(x * x for x in quiet_tail) / len(quiet_tail))
        self.assertGreater(rms, 0.13)
        self.assertLess(rms, 0.15)


if __name__ == "__main__":
    unittest.main(verbosity=2)
