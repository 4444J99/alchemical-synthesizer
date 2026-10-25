"""Exercise the real packer with private-state fixtures, never real credentials."""
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "brahma/web/public/workbench/vendor/workbench.js"


class ReleasePackagingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="brahma-package-test-")
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        self.env = {**os.environ, "COPYFILE_DISABLE": "1"}
        self.run_cmd("git", "init", "-q")
        self.run_cmd("git", "config", "user.name", "Packaging Test")
        self.run_cmd("git", "config", "user.email", "test@example.invalid")
        self.write("tools/build_release.sh", (ROOT / "tools/build_release.sh").read_text())
        self.write("brahma/sc/tests/example.scd", '"native test".postln;\n')
        self.write("brahma/sc/Example.sc", "Example {}\n")
        self.write("brahma/pd/example.pd", "#N canvas 0 0 100 100 10;\n")
        self.write("brahma/web/public/workbench/index.html", '<script src="vendor/workbench.js"></script>\n')
        self.write(".gitignore", "dist/\n.runtime/\n.env\nvendor/\n")
        self.run_cmd("git", "add", ".")
        self.run_cmd("git", "commit", "-qm", "fixture")
        # Host export-ignore must not silently remove the native test suite.
        attrs = Path(self.tmp.name) / "attributes"
        attrs.write_text("tests export-ignore\n")
        self.run_cmd("git", "config", "core.attributesFile", str(attrs))
        self.write(BUNDLE, 'console.log("fixture workbench");\n')
        self.write("brahma/web/.runtime/agent-token-test", "FAKE_TEST_TOKEN\n")
        self.write(".env", "FAKE_TEST_SECRET=value\n")
        self.write("untracked-private-note.txt", "DO_NOT_SHIP\n")

    def write(self, name, content):
        target = self.repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def run_cmd(self, *args, check=True):
        return subprocess.run(args, cwd=self.repo, env=self.env, text=True,
                              capture_output=True, check=check, timeout=60)

    def test_archives_include_runtime_assets_but_not_private_working_state(self):
        result = self.run_cmd("bash", "tools/build_release.sh", "fixture", check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with tarfile.open(self.repo / "dist/alchemical-synthesizer-fixture.tar.gz") as archive:
            tar_names = archive.getnames()
        with zipfile.ZipFile(self.repo / "dist/alchemical-synthesizer-fixture.zip") as archive:
            zip_names = archive.namelist()
        for names in (tar_names, zip_names):
            names = {name.split("/", 1)[1].removeprefix("./") for name in names if "/" in name}
            self.assertIn(BUNDLE, names)
            self.assertIn("brahma/sc/tests/example.scd", names)
            self.assertNotIn("brahma/web/.runtime/agent-token-test", names)
            self.assertNotIn(".env", names)
            self.assertNotIn("untracked-private-note.txt", names)

    def test_missing_or_empty_bundle_fails_before_touching_existing_dist(self):
        self.write("dist/preserved.txt", "previous build\n")
        for empty in (False, True):
            with self.subTest(empty=empty):
                (self.repo / BUNDLE).unlink(missing_ok=True)
                if empty:
                    self.write(BUNDLE, "")
                result = self.run_cmd("bash", "tools/build_release.sh", "fixture", check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("build:workbench", result.stderr)
                self.assertEqual((self.repo / "dist/preserved.txt").read_text(), "previous build\n")


if __name__ == "__main__":
    unittest.main()
