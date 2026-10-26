import array
import importlib.util
import json
import pathlib
import tempfile
import unittest
import wave

ROOT = pathlib.Path(__file__).resolve().parents[2]


def pcm(path, samples):
    values = array.array("h", samples)
    import sys
    if sys.byteorder != "little":
        values.byteswap()
    with wave.open(str(path), "wb") as stream:
        stream.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
        stream.writeframes(values.tobytes())


class MaterialComparisonTest(unittest.TestCase):
    def model(self):
        filename = ROOT / "forge/compare.py"
        self.assertTrue(filename.exists(), "native comparison tool must exist")
        spec = importlib.util.spec_from_file_location("material_comparison", filename)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_waveform_measurement_distinguishes_silence_gain_and_actual_shape(self):
        tool = self.model()
        with tempfile.TemporaryDirectory() as directory:
            a, b, c = [pathlib.Path(directory) / name for name in ("a.wav", "b.wav", "c.wav")]
            pcm(a, [0, 1000, -1000, 0] * 2000)
            pcm(b, [0, 2000, -2000, 0] * 2000)
            pcm(c, [0] * 8000)
            result = tool.compare_audio(a, b)
            self.assertAlmostEqual(result["rms_delta"], 1000 / 32768 / 2 ** .5)
            self.assertAlmostEqual(result["shape_delta"], 0)
            self.assertEqual(tool.compare_audio(c, c)["status"], "silent")
            pcm(c, [0] * 100)
            with self.assertRaisesRegex(ValueError, "duration|length"):
                tool.compare_audio(a, c)

    def test_manifest_integrity_rejects_changed_or_missing_outputs_and_wrong_donor(self):
        tool = self.model()
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            pcm(root / "voice.wav", [0, 1000, -1000, 0] * 2000)
            pcm(root / "source.wav", [0, 1000, -1000, 0] * 2000)
            pcm(root / "original.wav", [0, 1000, -1000, 0] * 2000)
            donor_hash = tool.sha256(root / "original.wav")
            manifest = {"schema": "brahma.donor-audition.v1", "donor": {"sha256": donor_hash,
                        "original": "original.wav", "stereo": "source.wav", "stereo_sha256": tool.sha256(root / "source.wav")}, "compile_exit_code": 0,
                        "modules": [{"name": "voice", "status": "rendered", "output": "voice.wav",
                                     "render_exit_code": 0, "output_sha256": tool.sha256(root / "voice.wav")}]}
            (root / "manifest.json").write_text(json.dumps(manifest))
            self.assertEqual(tool.load_audition(root, donor_hash)["donor"]["sha256"], donor_hash)
            with self.assertRaisesRegex(ValueError, "donor|source"):
                tool.load_audition(root, "b" * 64)
            pcm(root / "voice.wav", [0] * 8000)
            with self.assertRaisesRegex(ValueError, "hash|integrity"):
                tool.load_audition(root, donor_hash)
            (root / "voice.wav").unlink()
            with self.assertRaisesRegex(ValueError, "missing|output"):
                tool.load_audition(root, donor_hash)
            pcm(root / "voice.wav", [0, 1000, -1000, 0] * 2000)
            pcm(root / "source.wav", [0] * 8000)
            with self.assertRaisesRegex(ValueError, "source|donor|integrity|hash"):
                tool.load_audition(root, donor_hash)

    def test_legacy_silent_audio_is_preserved_and_measured_without_becoming_a_pass(self):
        tool = self.model()
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for name in ["original.wav", "source.wav", "voice.wav"]:
                pcm(root / name, [0] * 8000)
            digest = tool.sha256(root / "source.wav")
            manifest = {"schema": "brahma.donor-audition.v1", "donor": {"sha256": digest,
                        "original": "original.wav", "stereo": "source.wav", "stereo_sha256": digest},
                        "modules": [{"name": "voice", "status": "silent", "render_exit_code": 0}]}
            (root / "manifest.json").write_text(json.dumps(manifest))
            result = tool.load_audition(root, digest)["modules"][0]
            self.assertEqual(result["status"], "silent")
            self.assertEqual(result["output_sha256"], tool.sha256(root / "voice.wav"))

    def test_ledger_preserves_every_native_role_and_never_claims_original_behavior_from_audio(self):
        tool = self.model()
        catalog = [{"name": "ditto_morphic_core", "role": "audio_processor", "file": "05_ditto.scd", "definition_sha256": "a" * 64},
                   {"name": "unmapped", "role": "control_utility", "file": "fixture.scd", "definition_sha256": "b" * 64},
                   {"name": "meter", "role": "infrastructure", "file": "11_metrics.scd", "definition_sha256": "c" * 64}]
        ledger = tool.build_ledger(catalog, {})
        self.assertEqual([row["name"] for row in ledger], [item["name"] for item in catalog])
        self.assertTrue(ledger[0]["material_mapping"]["supported"])
        self.assertFalse(ledger[1]["material_mapping"]["supported"])
        self.assertTrue(all(row["original_behavior_acceptance"] == "not_measured" for row in ledger))
        self.assertEqual(ledger[2]["signal_status"], "requires_patch")

    def test_reused_native_stage_cannot_mislabel_material_renders_or_missing_selected_results(self):
        tool = self.model()
        catalog = [{"name": "ditto_morphic_core", "role": "audio_processor", "definition_sha256": "a" * 64}]
        item = {**catalog[0], "status": "rendered", "parameter_overrides": {}, "parameters": {"inBus": 4, "outBus": 8}}
        tool.validate_native_reuse(catalog, {"modules": [item]}, {"ditto_morphic_core"})
        with self.assertRaisesRegex(ValueError, "missing|selected"):
            tool.validate_native_reuse(catalog, {"modules": []}, {"ditto_morphic_core"})
        for changed in [{"material": {"phase": "gas"}}, {"parameter_overrides": {"observe": .9}}]:
            with self.assertRaisesRegex(ValueError, "native|default|material"):
                tool.validate_native_reuse(catalog, {"modules": [{**item, **changed}]}, {"ditto_morphic_core"})
