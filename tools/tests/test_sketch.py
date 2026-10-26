import importlib.util
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[2]


class SketchContracts(unittest.TestCase):
    def test_sketch_embeds_original_native_palette_and_real_drum_files(self):
        path = ROOT / 'forge/sketch.py'
        self.assertTrue(path.is_file(), 'Forge needs a portable sketch builder')
        spec = importlib.util.spec_from_file_location('sketch', path)
        import sys
        sys.path.insert(0, str(ROOT / 'forge'))
        app = importlib.util.module_from_spec(spec); spec.loader.exec_module(app)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for index, name in enumerate(['source', 'chrysalid_siren_stereo', 'kick808', 'snare', 'hihatClosed']):
                with wave.open(str(root / (name + '.wav')), 'wb') as wav:
                    wav.setparams((2, 2, 44100, 0, 'NONE', 'not compressed'))
                    wav.writeframes(bytes([index + 1, 1, index + 1, 1]) * 88200)
            manifest = {'compile_exit_code': 0, 'donor': {'origin': {'title': 'Synthetic donor'}, 'stereo': 'source.wav',
                'stereo_sha256': hashlib.sha256((root / 'source.wav').read_bytes()).hexdigest()},
                'native_rack_sha256': 'b' * 64, 'modules': [{'name': 'chrysalid_siren_stereo',
                    'status': 'rendered', 'render_exit_code': 0, 'output': 'chrysalid_siren_stereo.wav',
                    'output_sha256': hashlib.sha256((root / 'chrysalid_siren_stereo.wav').read_bytes()).hexdigest(),
                    'definition_sha256': 'a' * 64, 'parameters': {'grainDensity': 28, 'outBus': 8}}]}
            project = app.build_project(manifest, root, root)
            self.assertEqual(project['scene']['steps'], 32)
            self.assertEqual(len(project['scene']['grid']), 5)
            self.assertEqual(len(project['sources']), 5)
            self.assertEqual(len(project['sources'][0]['slices']), 8)
            self.assertEqual(project['sources'][1]['recipe']['parentId'], project['sources'][0]['id'])
            self.assertEqual(project['sources'][1]['recipe']['params'], {'grainDensity': 28})
            for track in range(5):
                self.assertTrue(any(project['scene']['grid'][track]))
            self.assertEqual(project['trackSources'][2:], [s['id'] for s in project['sources'][2:]])
            with self.assertRaises(ValueError):
                app.build_project({**manifest, 'modules': [{**manifest['modules'][0], 'status': 'silent'}]}, root, root)
            for bad in [{**manifest, 'compile_exit_code': 1},
                        {**manifest, 'modules': [{**manifest['modules'][0], 'render_exit_code': 1}]}]:
                with self.assertRaises(ValueError):
                    app.build_project(bad, root, root)
            with (root / 'source.wav').open('r+b') as donor:
                donor.seek(100); donor.write(b'\x01\x03')
            with self.assertRaisesRegex(ValueError, 'donor|Donor|hash'):
                app.build_project(manifest, root, root)


if __name__ == '__main__':
    unittest.main()
