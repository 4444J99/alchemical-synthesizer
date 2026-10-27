import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "tools/install-brahma-classes.py"


class ClassInstallation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.extensions = self.root / "extensions"
        (self.source / "transmutation").mkdir(parents=True)
        self.extensions.mkdir()
        for relative in ("AdamKadmon.sc", "BrahmaMetrics.sc", "transmutation/TransmutationEngine.sc"):
            (self.source / relative).write_text("// fixture\n")

    def run_installer(self, *arguments):
        return subprocess.run([sys.executable, str(INSTALLER), "--source", str(self.source),
                               "--extensions-dir", str(self.extensions), *arguments],
                              capture_output=True, text=True, timeout=10)

    def test_recursive_directory_install_is_idempotent(self):
        first = self.run_installer("--apply")
        self.assertEqual(first.returncode, 0, first.stderr)
        link = self.extensions / "Brahma"
        self.assertEqual(link.resolve(), self.source.resolve())
        self.assertTrue((link / "transmutation/TransmutationEngine.sc").is_file())
        second = self.run_installer("--apply")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(list(self.extensions.iterdir()), [link])

    def test_only_owned_legacy_links_are_removed_after_preflight(self):
        legacy = self.extensions / "AdamKadmon.sc"
        legacy.symlink_to(self.source / "AdamKadmon.sc")
        result = self.run_installer("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(legacy.is_symlink())
        self.assertTrue((self.extensions / "Brahma").is_symlink())

    def test_foreign_class_prevents_all_mutation(self):
        owned = self.extensions / "AdamKadmon.sc"
        owned.symlink_to(self.source / "AdamKadmon.sc")
        foreign = self.extensions / "BrahmaMetrics.sc"
        foreign.write_text("user owned content\n")
        result = self.run_installer("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing", result.stderr)
        self.assertTrue(owned.is_symlink())
        self.assertEqual(foreign.read_text(), "user owned content\n")
        self.assertFalse((self.extensions / "Brahma").exists())

    def test_preview_leaves_legacy_links_and_destination_untouched(self):
        legacy = self.extensions / "AdamKadmon.sc"
        legacy.symlink_to(self.source / "AdamKadmon.sc")
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(legacy.is_symlink())
        self.assertFalse((self.extensions / "Brahma").exists())

    def test_foreign_class_in_linked_directory_prevents_all_mutation(self):
        legacy = self.extensions / "AdamKadmon.sc"
        legacy.symlink_to(self.source / "AdamKadmon.sc")
        foreign = self.root / "foreign-classes"
        foreign.mkdir()
        (foreign / "AdamKadmon.sc").write_text("foreign class\n")
        (self.extensions / "OtherClasses").symlink_to(foreign, target_is_directory=True)
        result = self.run_installer("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing", result.stderr)
        self.assertTrue(legacy.is_symlink())
        self.assertFalse((self.extensions / "Brahma").exists())

    def test_shell_entrypoint_verifies_a_file_driver_with_supported_flags(self):
        fake = self.root / "fake-sclang"
        fake.write_text("#!/usr/bin/env python3\nimport pathlib, sys\n"
                        "assert '-e' not in sys.argv\nassert '-l' in sys.argv\n"
                        "assert pathlib.Path(sys.argv[-1]).is_file()\n"
                        "assert 'BRAHMA_TEST_PASS' in pathlib.Path(sys.argv[-1]).read_text()\n"
                        "print('BRAHMA_TEST_PASS')\n")
        fake.chmod(0o755)
        result = subprocess.run(["bash", str(ROOT / "tools/install-brahma.sh"),
                                 "--extensions-dir", str(self.extensions)],
                                env={**os.environ, "SCLANG_PATH": str(fake)},
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("RECOMPILE OK", result.stdout)


if __name__ == "__main__":
    unittest.main()
