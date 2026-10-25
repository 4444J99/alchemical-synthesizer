import pathlib
import subprocess
import sys
import tempfile
import unittest


class RunnerBounds(unittest.TestCase):
    def test_output_flood_is_stopped_before_it_can_report_success(self):
        with tempfile.TemporaryDirectory() as directory:
            fake = pathlib.Path(directory) / "fake-sclang"
            fake.write_text("#!/usr/bin/env python3\nimport sys\nsys.stdout.write('A' * 300000 + '\\nBRAHMA_TEST_PASS\\n')\n")
            fake.chmod(0o700)
            script = pathlib.Path(directory) / "test.scd"
            script.write_text("")
            runner = pathlib.Path(__file__).resolve().parents[1] / "test-supercollider.py"
            result = subprocess.run([sys.executable, str(runner), str(script), "--sclang", str(fake), "--core-only"], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 125)
            self.assertIn("output limit", result.stderr)
            self.assertLess(len(result.stdout), 66000)


if __name__ == "__main__":
    unittest.main()
