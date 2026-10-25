"""The artifact checker must reject unsafe or incomplete archives before boot."""
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

CHECK = Path(__file__).resolve().parents[1] / "check-release-artifact.py"
BUNDLE = "brahma/web/public/workbench/vendor/workbench.js"
REQUIRED = [BUNDLE, "brahma/web/public/workbench/index.html", "brahma/web/server.js",
            "brahma/web/package-lock.json", "brahma/sc/tests/phase_a.scd",
            "brahma/sc/tests/class_runtime.scd", "brahma/sc/tests/flucoma_buffer.scd"]


class ArtifactCheckTests(unittest.TestCase):
    def check(self, extra=None, omit=None, link=False):
        results = []
        with tempfile.TemporaryDirectory(prefix="brahma-archive-check-") as tmp:
            names = [f"release/{name}" for name in REQUIRED if name != omit]
            if extra:
                names.append(extra)
            for ext in ("tar.gz", "zip"):
                with self.subTest(format=ext):
                    archive = Path(tmp) / f"fixture.{ext}"
                    if ext == "tar.gz":
                        with tarfile.open(archive, "w:gz") as out:
                            for name in names:
                                info = tarfile.TarInfo(name)
                                info.size = 1
                                if link and name == extra:
                                    info.type = tarfile.SYMTYPE
                                    info.linkname = "../../outside"
                                    info.size = 0
                                out.addfile(info, io.BytesIO(b"x"))
                    else:
                        with zipfile.ZipFile(archive, "w") as out:
                            for name in names:
                                info = zipfile.ZipInfo(name)
                                if link and name == extra:
                                    info.create_system = 3
                                    info.external_attr = 0o120777 << 16
                                out.writestr(info, b"../../outside" if link and name == extra else b"x")
                    result = subprocess.run(["python3", str(CHECK), str(archive), "--structure-only"],
                                            capture_output=True, text=True, timeout=10)
                    results.append(result)
        return results

    def test_complete_archives_pass_structure_check(self):
        for result in self.check():
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_bundle_fails(self):
        for result in self.check(omit=BUNDLE):
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(BUNDLE, result.stderr)

    def test_private_state_path_is_rejected(self):
        for result in self.check(extra="release/brahma/web/.runtime/agent-token-test"):
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("private", result.stderr)

    def test_traversal_and_links_are_rejected(self):
        for extra, link in (("release/../../outside", False), ("release/link", True)):
            for result in self.check(extra=extra, link=link):
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unsafe", result.stderr)


if __name__ == "__main__":
    unittest.main()
