"""Exercise release contents in a disposable checkout, including local private state."""
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="brahma-release-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ["tools", "brahma/sc", "brahma/pd", "brahma/web/public/workbench/src"]:
            (self.root / name).mkdir(parents=True)
        for name in ["build_release.sh", "build-workbench.mjs"]:
            shutil.copy2(ROOT / "tools" / name, self.root / "tools" / name)
        (self.root / "brahma/web/package.json").write_text('{"name":"release-fixture"}')
        (self.root / "brahma/web/public/workbench/src/main.js").write_text('console.log("release fixture");')
        (self.root / "brahma/sc/loader.scd").write_text('// fixture\n')
        (self.root / "brahma/pd/main.pd").write_text('#N canvas 0 0 100 100 10;\n')
        (self.root / "README.md").write_text("release fixture\n")
        (self.root / ".gitignore").write_text("node_modules/\ndist/\n.env*\n.runtime/\nout/\ndata/\n.wrangler/\n")
        self.run_command(["git", "init", "-q"])
        self.run_command(["git", "add", "."])
        self.run_command(["git", "-c", "user.name=Release Test", "-c", "user.email=test@example.invalid",
                          "commit", "-qm", "fixture"])
        os.symlink(ROOT / "brahma/web/node_modules", self.root / "brahma/web/node_modules")

    def run_command(self, command, check=True):
        return subprocess.run(command, cwd=self.root, capture_output=True, text=True, check=check, timeout=30)

    def test_archive_contains_bundle_and_excludes_untracked_runtime_state(self):
        private = [".env", ".env.production", "brahma/web/.runtime/agent-token-3000",
                   "product/data/accounts.json", "out/private.json", ".wrangler/cache.json"]
        for name in private:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("SYNTHETIC_PRIVATE_SENTINEL")
        self.run_command(["bash", "tools/build_release.sh", "v0.0.0-test"])
        with tarfile.open(self.root / "dist/alchemical-synthesizer-v0.0.0-test.tar.gz") as archive:
            names = [m.name.split("/", 1)[-1].removeprefix("./") for m in archive.getmembers()]
            for name in private:
                self.assertNotIn(name, names, f"local-only state leaked: {name}")
            self.assertIn("brahma/web/public/workbench/vendor/workbench.js", names)
            self.assertIn("tools/build-workbench.mjs", names)
        checked = subprocess.run(["sha256sum", "-c", "SHA256SUMS.txt"], cwd=self.root / "dist",
                                 capture_output=True, text=True, timeout=10)
        self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_invalid_version_fails_before_touching_existing_output(self):
        (self.root / "dist").mkdir()
        marker = self.root / "dist/keep"
        marker.write_text("existing artifact")
        for version in ["../invalid/version", "v" + "a" * 300]:
            with self.subTest(version=version):
                result = self.run_command(["bash", "tools/build_release.sh", version], check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(marker.exists(), "invalid version removed existing output")


if __name__ == "__main__":
    unittest.main()
