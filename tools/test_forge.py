#!/usr/bin/env python3
"""Forge wrapper regressions with offline process fixtures.

Run: python3 tools/test_forge.py
Set BRAHMA_FORGE_NATIVE=1 to include real SuperCollider NRT and ffmpeg checks.
Native renders open no audio device. Python's standard library is sufficient for
the default wrapper tests; the fake executables model only external processes.
"""

from __future__ import annotations

import array
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
import wave


ROOT = Path(__file__).resolve().parents[1]
WRAPPERS = ("bounce.sh", "render-pattern.sh")

FAKE_SCLANG = r'''#!/usr/bin/env python3
import os, pathlib, re, sys, wave
pathlib.Path(os.environ["FORGE_TEST_CALLED"]).touch()
mode = os.environ.get("FORGE_TEST_MODE", "valid")
if mode == "fail":
    sys.exit(23)
if mode == "missing":
    sys.exit(0)
source = pathlib.Path(sys.argv[-1]).read_text()
if "BRAHMA_RENDER_OUTPUT" in os.environ:
    output = os.environ["BRAHMA_RENDER_OUTPUT"]
    duration = float(os.environ["BRAHMA_RENDER_DURATION"])
    kind = "specimen" if "renderSpecimen" in source else "pattern"
else:
    # Baseline wrapper interface, so the regressions run before the fix as well.
    match = re.search(r'render(Specimen|Pattern)\("[^"]*", "([^"]*)", ([0-9.]+)\.asFloat', source)
    if match is None:
        sys.exit(24)
    kind, output, duration = match.groups()
    duration = float(duration)
tail = 0.6 if kind.lower() == "specimen" else 1.2
output = pathlib.Path(output)
if mode == "corrupt":
    output.write_bytes(b"this is not a WAV")
else:
    channels = 1 if mode == "mono" else 2
    rate = 22050 if mode == "rate" else 44100
    frames = round(rate * (duration + tail))
    if mode == "short":
        frames //= 2
    with wave.open(str(output), "wb") as audio:
        audio.setnchannels(channels)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        audio.writeframes(b"\x01\x00" * frames * channels)
    if mode == "truncated":
        output.write_bytes(output.read_bytes()[:-100])
sys.exit(23 if mode == "fail_after_write" else 0)
'''

FAKE_FFMPEG = r'''#!/usr/bin/env python3
import shutil, sys
shutil.copyfile(sys.argv[sys.argv.index("-i") + 1], sys.argv[-1])
'''

FAKE_FFPROBE = r'''#!/usr/bin/env python3
import sys, wave
with wave.open(sys.argv[-1], "rb") as audio:
    print(audio.getnframes() / audio.getframerate())
'''


def executable(path: Path, source: str) -> None:
    path.write_text(source, encoding="utf-8")
    path.chmod(0o755)


def tone(path: Path, seconds: float = 1.0) -> None:
    samples = array.array("h")
    for i in range(round(44100 * seconds)):
        value = round(8000 * math.sin(i * 2 * math.pi * 440 / 44100))
        samples.extend((value, value))
    if sys.byteorder != "little":
        samples.byteswap()
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(44100)
        audio.writeframes(samples.tobytes())


class ForgeFixture(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="brahma-forge-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        executable(self.bin / "sclang", FAKE_SCLANG)
        executable(self.bin / "scsynth", "#!/bin/sh\nexit 0\n")
        executable(self.bin / "ffmpeg", FAKE_FFMPEG)
        executable(self.bin / "ffprobe", FAKE_FFPROBE)
        self.food = self.work / "food.wav"
        tone(self.food)
        self.pattern = self.work / "pattern.json"
        self.pattern.write_text(json.dumps({"events": [
            {"time": 0.0, "note": 60, "vel": 0.8, "dur": 0.25}
        ]}))
        self.dest = self.work / "published"
        self.dest.mkdir()
        self.output = self.dest / "result.wav"
        self.called = self.work / "sclang-called"
        self.env = dict(os.environ, PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
                        FORGE_TEST_CALLED=str(self.called),
                        BRAHMA_SUPERVISED_PROCESS_GROUP="1")

    def run_wrapper(self, wrapper: str, mode: str = "valid", duration: str | None = "1",
                    *, output: Path | None = None, extra_env: dict | None = None,
                    timeout: float = 15) -> subprocess.CompletedProcess:
        command = ["bash", str(ROOT / "forge" / wrapper),
                   str(self.food if wrapper == "bounce.sh" else self.pattern),
                   str(output or self.output)]
        if duration is not None:
            command.append(duration)
        env = dict(self.env, FORGE_TEST_MODE=mode)
        env.update(extra_env or {})
        process = subprocess.Popen(command, cwd=self.work, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, start_new_session=True)
        try:
            stdout, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, _ = process.communicate()
            self.fail(f"{wrapper} timed out:\n{stdout}")
        return subprocess.CompletedProcess(command, process.returncode, stdout)

    def assert_wav(self, path: Path, duration: float) -> None:
        with wave.open(str(path), "rb") as audio:
            self.assertEqual((audio.getnchannels(), audio.getframerate(), audio.getsampwidth()),
                             (2, 44100, 2))
            self.assertAlmostEqual(audio.getnframes() / 44100, duration, delta=128 / 44100)
            data = audio.readframes(audio.getnframes())
            self.assertEqual(len(data), audio.getnframes() * 4)
            self.assertTrue(any(data))


class ForgeWrapperTests(ForgeFixture):
    def test_failed_process_does_not_accept_or_replace_existing_output(self) -> None:
        for wrapper in WRAPPERS:
            for mode in ("fail", "missing", "fail_after_write"):
                with self.subTest(wrapper=wrapper, mode=mode):
                    self.output.write_bytes(b"previous successful artifact")
                    result = self.run_wrapper(wrapper, mode)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertNotIn("OK ->", result.stdout)
                    self.assertEqual(self.output.read_bytes(), b"previous successful artifact")

    def test_only_valid_expected_wav_is_published(self) -> None:
        for wrapper in WRAPPERS:
            for mode in ("corrupt", "mono", "rate", "short", "truncated"):
                with self.subTest(wrapper=wrapper, mode=mode):
                    self.output.write_bytes(b"old")
                    result = self.run_wrapper(wrapper, mode)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertEqual(self.output.read_bytes(), b"old")

    def test_success_replaces_output_and_supports_fractional_duration(self) -> None:
        for wrapper, expected in (("bounce.sh", 1.35), ("render-pattern.sh", 1.95)):
            with self.subTest(wrapper=wrapper):
                self.output.write_bytes(b"old")
                result = self.run_wrapper(wrapper, duration="0.75")
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn("OK ->", result.stdout)
                self.assert_wav(self.output, expected)
                self.assertEqual(list(self.dest.iterdir()), [self.output])

    def test_default_duration_uses_audio_frames_or_pattern_end(self) -> None:
        tone(self.food, seconds=0.75)
        for wrapper, expected in (("bounce.sh", 1.35), ("render-pattern.sh", 3.2)):
            with self.subTest(wrapper=wrapper):
                result = self.run_wrapper(wrapper, duration=None)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assert_wav(self.output, expected)

    def test_without_coreutils_timeout_success_and_failure_remain_checked(self) -> None:
        # A minimal PATH exercises the macOS-compatible Python fallback without
        # changing production timeout controls or waiting through a long render.
        for name in ("bash", "python3", "dirname", "mkdir", "mktemp", "rm", "uname", "cat"):
            (self.bin / name).symlink_to(shutil.which(name))
        for wrapper in WRAPPERS:
            for mode, expected_status in (("valid", 0), ("fail", 23)):
                with self.subTest(wrapper=wrapper, mode=mode):
                    self.output.write_bytes(b"old")
                    result = self.run_wrapper(wrapper, mode, extra_env={
                        "PATH": str(self.bin), "BRAHMA_SUPERVISED_PROCESS_GROUP": "0"
                    })
                    self.assertEqual(result.returncode, expected_status, result.stdout)
                    if expected_status:
                        self.assertEqual(self.output.read_bytes(), b"old")
                    else:
                        self.assert_wav(self.output, 1.6 if wrapper == "bounce.sh" else 2.2)

    def test_invalid_duration_is_rejected_before_render(self) -> None:
        for wrapper in WRAPPERS:
            for duration in ("0", "-1", "nan", "inf", "1e100", "1;0.exit"):
                with self.subTest(wrapper=wrapper, duration=duration):
                    self.called.unlink(missing_ok=True)
                    self.output.write_bytes(b"old")
                    result = self.run_wrapper(wrapper, duration=duration)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertFalse(self.called.exists(), result.stdout)
                    self.assertEqual(self.output.read_bytes(), b"old")

    def test_timeout_exit_is_not_masked(self) -> None:
        executable(self.bin / "timeout", "#!/bin/sh\nexit 124\n")
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                self.output.write_bytes(b"old")
                result = self.run_wrapper(wrapper)
                self.assertEqual(result.returncode, 124, result.stdout)
                self.assertEqual(self.output.read_bytes(), b"old")

    def test_supervised_render_keeps_foreground_timeout(self) -> None:
        executable(self.bin / "timeout", r'''#!/usr/bin/env python3
import os, sys
if sys.argv[1] != "--foreground":
    sys.exit(91)
args = sys.argv[2:]
while args[0].startswith("--"):
    args.pop(0)
args.pop(0)
os.execv(args[0], args)
''')
        result = self.run_wrapper("render-pattern.sh", extra_env={
            "BRAHMA_SUPERVISED_PROCESS_GROUP": "1"
        })
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assert_wav(self.output, 2.2)

    def test_invalid_pattern_numbers_and_incomplete_rows_are_rejected(self) -> None:
        for score in ("-1 60 0.8 0.25", "0 nan 0.8 0.25", "0 60 inf 0.25",
                      "0 60 0.8 -1", "0 60 0.8 0.25\n0.5 64 0.5"):
            with self.subTest(score=score):
                self.pattern = self.work / "pattern.score"
                self.pattern.write_text(score)
                self.called.unlink(missing_ok=True)
                result = self.run_wrapper("render-pattern.sh")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(self.called.exists(), result.stdout)


@unittest.skipUnless(os.environ.get("BRAHMA_FORGE_NATIVE") == "1",
                     "set BRAHMA_FORGE_NATIVE=1 for real SuperCollider/ffmpeg NRT checks")
class ForgeNativeTests(ForgeFixture):
    def setUp(self) -> None:
        super().setUp()
        from dsp.test_dsp import class_library, sc_binary
        sclang = sc_binary("sclang")
        scsynth = sc_binary("scsynth")
        for name in ("ffmpeg", "ffprobe"):
            real = shutil.which(name)
            self.assertIsNotNone(real, f"{name} is required for native Forge checks")
            (self.bin / name).unlink()
            (self.bin / name).symlink_to(real)
        config = self.work / "sclang.yaml"
        config.write_text("includePaths:\n"
                          f"  - {json.dumps(str(class_library(sclang)))}\n"
                          "excludePaths: []\nexcludeDefaultPaths: true\n")
        executable(self.bin / "sclang", "#!/usr/bin/env python3\n"
                   "import os, sys\n"
                   f"os.execv({sclang!r}, [{sclang!r}, '-a', '-l', {str(config)!r}] + sys.argv[1:])\n")
        (self.bin / "scsynth").unlink()
        (self.bin / "scsynth").symlink_to(scsynth)
        self.env.update(QT_QPA_PLATFORM="offscreen", QTWEBENGINE_DISABLE_SANDBOX="1")

    def test_native_renders_accept_literal_unusual_paths(self) -> None:
        quoted_bin = self.work / "bin 'quote\" $(touch BIN_EXECUTED)"
        self.bin.rename(quoted_bin)
        self.bin = quoted_bin
        self.env["PATH"] = f"{self.bin}{os.pathsep}{os.environ['PATH']}"
        unusual = self.work / "literal 'quote\" $(touch PATH_EXECUTED) `touch PATH_EXECUTED` \\ path"
        unusual.mkdir()
        self.food = unusual / "input 'sound\".wav"
        tone(self.food)
        self.pattern = unusual / "notes 'score\".json"
        self.pattern.write_text('[{"time":0,"note":60,"vel":0.8,"dur":0.25}]')
        for wrapper, expected in (("bounce.sh", 1.35), ("render-pattern.sh", 1.95)):
            with self.subTest(wrapper=wrapper):
                output = unusual / (wrapper + " 'output\".wav")
                result = self.run_wrapper(wrapper, duration="0.75", output=output, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assert_wav(output, expected)
        self.assertFalse(list(self.work.rglob("PATH_EXECUTED")))
        self.assertFalse(list(self.work.rglob("BIN_EXECUTED")))

    def test_native_server_failure_propagates_callback_status(self) -> None:
        (self.bin / "scsynth").unlink()
        executable(self.bin / "scsynth", "#!/bin/sh\nexit 19\n")
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                self.output.write_bytes(b"old")
                result = self.run_wrapper(wrapper, timeout=30)
                self.assertEqual(result.returncode, 19, result.stdout)
                self.assertEqual(self.output.read_bytes(), b"old")


if __name__ == "__main__":
    unittest.main(verbosity=2)
