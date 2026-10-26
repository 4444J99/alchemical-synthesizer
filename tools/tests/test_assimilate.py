import importlib.util
import array
import json
import math
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
import wave
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('assimilate', ROOT / 'forge/assimilate.py')
app = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(app)


def fixture(path, seconds=2):
    samples = array.array('h')
    for i in range(int(seconds * 44100)):
        envelope = .3 + .7 * ((i // 11025) % 2)
        samples.extend(int(10000 * envelope * math.sin(i * 2 * math.pi * freq / 44100)) for freq in (220, 330))
    if sys.byteorder != 'little':
        samples.byteswap()
    with wave.open(str(path), 'wb') as wav:
        wav.setparams((2, 2, 44100, 0, 'NONE', 'not compressed'))
        wav.writeframes(samples.tobytes())


class DonorContracts(unittest.TestCase):
    def test_extract_ignores_comments_and_preserves_nested_native_definition(self):
        source = r'''// SynthDef(\fake, { })
        SynthDef(\real, { |inBus=0, outBus=0| var text="fake ) }";
          Out.ar(outBus, LPF.ar(In.ar(inBus, 1), 1000)); }).add;
        /* SynthDef(\also_fake, {}) */'''
        entries = app.extract_modules(source, 'fixture.scd')
        self.assertEqual([m['name'] for m in entries], ['real'])
        self.assertEqual(entries[0]['audio_inputs'], ['inBus'])
        self.assertEqual(entries[0]['role'], 'audio_processor')
        self.assertTrue(entries[0]['definition'].endswith('})'))

    def test_buffer_readers_and_non_audio_utilities_have_distinct_roles(self):
        modules = app.extract_modules(r'''
        SynthDef(\sample, { |buf=0, outBus=0| Out.ar(outBus, PlayBuf.ar(1, buf)); });
        SynthDef(\clock, { |outBus=0| Out.kr(outBus, Impulse.kr(2)); });
        SynthDef(\tone, { |outBus=0, freq=440| Out.ar(outBus, SinOsc.ar(freq)); });
        ''', 'fixture.scd')
        self.assertEqual([m['role'] for m in modules], ['buffer_processor', 'control_utility', 'sound_generator'])

    def test_native_paths_are_string_literals_not_interpolated_source(self):
        self.assertEqual(app.sc_string('a"\\b\n'), '"a\\"\\\\b\\n"')
        with self.assertRaises(ValueError):
            app.sc_string('bad\x00path')

    def test_measurement_rejects_silence_and_truncated_duration(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'silent.wav'
            with wave.open(str(path), 'wb') as wav:
                wav.setparams((2, 2, 8000, 0, 'NONE', 'not compressed'))
                wav.writeframes(b'\0' * 32000)
            self.assertEqual(app.measure_audio(path, 1)['status'], 'silent')
            self.assertEqual(app.measure_audio(path, 2)['status'], 'invalid_duration')

    def test_catalogue_includes_every_literal_synthdef_once_per_source(self):
        catalog = app.catalogue(ROOT / 'brahma/sc')
        names = {m['name'] for m in catalog}
        for name in ['mnemosyne_voice', 'chrysalid_siren_stereo', 'janiform_child',
                     'octahedron_slicer', 'solve_vocoder', 'crucible_compressor', 'prima_materia']:
            self.assertIn(name, names)
        self.assertEqual(len({(m['file'], m['name']) for m in catalog}), len(catalog))
        self.assertGreater(len(catalog), 200)

    def test_stereo_buffers_without_defaults_both_receive_private_bindings(self):
        item = app.extract_modules(r'SynthDef(\x, { |outBus=0, bufL, bufR, age=0| Out.ar(outBus, [PlayBuf.ar(1, bufL), PlayBuf.ar(1, bufR)]); });', 'fixture.scd')[0]
        self.assertEqual(item['buffer_inputs'], ['bufL', 'bufR'])
        self.assertEqual(app.module_args(item), {'bufL': 2, 'bufR': 3, 'outBus': 8})

    def test_youtube_admission_accepts_one_video_and_rejects_other_hosts(self):
        self.assertEqual(app.youtube_url('https://youtu.be/USQ697oqkaw?t=30'),
                         'https://www.youtube.com/watch?v=USQ697oqkaw')
        for value in ['https://youtube.com.evil.test/watch?v=USQ697oqkaw',
                      'file:///etc/passwd', 'https://youtube.com/playlist?list=abc']:
            with self.assertRaises(ValueError):
                app.youtube_url(value)

    def test_catalogue_batch_does_not_compile_one_oversized_native_function(self):
        modules = app.catalogue(ROOT / 'brahma/sc')
        selected = [m for m in modules if m['role'] in ('audio_processor', 'buffer_processor')]
        with tempfile.TemporaryDirectory() as directory:
            destination = pathlib.Path(directory)
            with patch.object(app, 'run', return_value=0), patch.object(app, 'binary', return_value='sclang'):
                self.assertEqual(app.compile_scores(selected, destination, 2), 0)
            self.assertLess(len((destination / 'compile.scd').read_text()), 1000)
            self.assertEqual(len((destination / 'compile-jobs.scd').read_text().splitlines()), len(selected))

    def test_source_controls_feed_closed_gates_and_pitch_following_generators(self):
        by_name = {m['name']: m for m in app.catalogue()}
        self.assertEqual(app.module_maps(by_name['vactrol_classic'])['cv'], 0)
        self.assertEqual(app.module_maps(by_name['prima_materia'])['freq'], 4)
        self.assertIn('outBus', by_name['aqua_lfo']['control_outputs'])
        self.assertEqual(app.module_args(by_name['relinquished_te'])['cvEnvBus'], 0)

    def test_stereo_and_mid_side_inputs_use_the_corresponding_source_channels(self):
        by_name = {m['name']: m for m in app.catalogue()}
        self.assertEqual(app.module_args(by_name['aether_width'])['inBus'], 2)
        self.assertEqual(app.module_args(by_name['octahedron_crossfader'])['inBusB'], 2)
        decoded = app.module_args(by_name['aether_ms_decode'])
        self.assertEqual((decoded['inBusMid'], decoded['inBusSide']), (6, 7))

    def test_control_outputs_never_alias_event_pulses_and_envelope(self):
        module = next(m for m in app.catalogue() if m['name'] == 'nigredo_function')
        args = app.module_args(module)
        self.assertEqual(args['outBus'], 16)
        self.assertEqual(len({args[p] for p in module['control_outputs']}), len(module['control_outputs']))

    def test_admission_preserves_source_even_with_output_like_basename(self):
        try:
            app.binary('ffmpeg')
        except ValueError:
            self.skipTest('ffmpeg unavailable')
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / 'source.wav'
            fixture(source)
            before = app.sha256(source)
            destination = root / 'output'; destination.mkdir()
            result = app.admit(str(source), destination, 0, 1)
            self.assertEqual(result['sha256'], before)
            self.assertEqual(app.sha256(source), before)
            self.assertEqual(app.sha256(destination / result['original']), before)
            self.assertEqual(result['measurement']['status'], 'rendered')
            self.assertEqual(result['original'], 'original/source.wav')

    def test_html_escapes_metadata_and_does_not_offer_failed_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = pathlib.Path(directory)
            app.audition_html({'donor': {'origin': {'title': '<script>bad()</script>'},
                'start_seconds': 0, 'duration_seconds': 1}, 'modules': [
                    {'name': 'broken', 'role': 'audio_processor', 'status': 'render_failed', 'output': 'bad.wav'}]}, destination)
            result = (destination / 'index.html').read_text()
            self.assertIn('&lt;script&gt;bad()', result)
            self.assertNotIn('src="bad.wav"', result)

    def test_expired_deadline_never_starts_a_child(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(app, 'DEADLINE', 0), patch.object(app.subprocess, 'Popen') as child:
            with self.assertRaisesRegex(ValueError, 'deadline'):
                app.run(['never-start'], pathlib.Path(directory) / 'log')
            child.assert_not_called()

    def test_cli_rejects_nonfinite_and_excessive_budgets_before_creating_output(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = pathlib.Path(directory) / 'unused'
            for flag, value in [('--duration', 'nan'), ('--duration', '601'), ('--start', '-1'), ('--deadline', 'inf')]:
                result = subprocess.run([sys.executable, str(ROOT / 'forge/assimilate.py'),
                    'missing.wav', '--out', str(destination), flag, value], capture_output=True)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(destination.exists())

    @unittest.skipUnless(os.environ.get('RUN_NATIVE_DONOR_TESTS') == '1', 'set RUN_NATIVE_DONOR_TESTS=1 for installed SC integration')
    def test_native_stream_buffer_generator_control_and_spectral_paths(self):
        with tempfile.TemporaryDirectory(prefix='donor-native-') as directory:
            root = pathlib.Path(directory)
            source = root / 'donor "quoted".wav'
            fixture(source)
            before = app.sha256(source)
            names = ['mnemosyne_voice_stereo', 'octahedron_slicer', 'solve_spectral_filter',
                     'relinquished_bc', 'vactrol_classic', 'prima_materia', 'aqua_lfo',
                     'aether_width', 'aether_ms_decode', 'athanor_noise']
            command = [sys.executable, str(ROOT / 'forge/assimilate.py'), str(source),
                       '--start', '0', '--duration', '2', '--out', str(root / 'results')]
            for name in names:
                command += ['--module', name]
            result = subprocess.run(command, capture_output=True, text=True, timeout=150)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            manifests = list((root / 'results').glob('*/manifest.json'))
            self.assertEqual(len(manifests), 1)
            manifest = json.loads(manifests[0].read_text())
            outputs = [m for m in manifest['modules'] if m['status'] == 'rendered']
            self.assertEqual({m['name'] for m in outputs}, set(names))
            self.assertEqual(app.sha256(source), before)
            for item in outputs:
                self.assertEqual(item['render_exit_code'], 0)
                self.assertEqual(app.sha256(manifests[0].parent / item['output']), item['output_sha256'])
                if item['name'] in ('aether_width', 'aether_ms_decode'):
                    with wave.open(str(manifests[0].parent / item['output']), 'rb') as wav:
                        data = array.array('h', wav.readframes(wav.getnframes()))
                    left, right = data[::2], data[1::2]
                    self.assertGreater(sum(abs(v) for v in right), 1000)
                    self.assertNotEqual(left, right)


if __name__ == '__main__':
    unittest.main()
