#!/usr/bin/env python3
"""Create a private portable sketch from a validated donor run and native Golem presets."""
from __future__ import annotations
import argparse
import base64
import json
from pathlib import Path
import socket
import time
import uuid
import wave
import assimilate as native

DRUMS = ('kick808', 'snare', 'hihatClosed')
PALETTE = ('chrysalid_siren_stereo', 'mnemosyne_voice_stereo', 'solve_pitch_shift')


def source(path: Path, name: str, slices: list | None = None) -> dict:
    with wave.open(str(path), 'rb') as wav:
        if wav.getsampwidth() != 2 or wav.getnchannels() != 2:
            raise ValueError('Sketch requires stereo PCM16 WAV')
        duration = wav.getnframes() / wav.getframerate()
        rate, channels = wav.getframerate(), wav.getnchannels()
    digest = native.sha256(path)
    return {'id': 'sha256:' + digest, 'sha256': digest, 'name': name,
            'mime': 'audio/wav', 'data': base64.b64encode(path.read_bytes()).decode(),
            'duration': duration, 'sampleRate': rate, 'channels': channels,
            'slices': slices or [{'start': duration * i / 8, 'end': duration * (i + 1) / 8} for i in range(8)]}


def build_project(manifest: dict, directory: Path, drum_directory: Path) -> dict:
    if manifest.get('compile_exit_code') != 0:
        raise ValueError('Donor compilation did not pass validation')
    donor_path = directory / manifest['donor']['stereo']
    if donor_path.resolve().parent != directory.resolve():
        raise ValueError('Donor must be inside its audition directory')
    if native.sha256(donor_path) != manifest['donor'].get('stereo_sha256'):
        raise ValueError('Donor excerpt hash mismatch')
    title = manifest['donor']['origin'].get('title', 'Song donor')
    original = source(donor_path, title + ' / original')
    sources = [original]
    for name in PALETTE:
        item = next((m for m in manifest['modules'] if m['name'] == name), None)
        if item is None and name != PALETTE[0]:
            continue
        if not item or item['status'] != 'rendered' or item.get('render_exit_code') != 0 or item['output'] != name + '.wav':
            raise ValueError('Native palette source did not pass validation: ' + name)
        output = directory / item['output']
        if native.sha256(output) != item['output_sha256']:
            raise ValueError('Native palette output hash mismatch')
        rendered = source(output, title + ' / ' + name, original['slices'])
        rendered['recipe'] = {'schema': 'brahma.native-recipe.v1', 'parentId': original['id'], 'module': name,
            'params': {key: value for key, value in item['parameters'].items() if key in native.CONTROL_SPECS.get(name, {})},
            'inputSha256': original['sha256'], 'definitionSha256': item['definition_sha256'],
            'rackSha256': manifest['native_rack_sha256']}
        sources.append(rendered)
    drums = [source(drum_directory / (name + '.wav'), 'Golem / ' + name,
                    [{'start': 0, 'end': min(.9, source_duration(drum_directory / (name + '.wav')))}]) for name in DRUMS]
    sources.extend(drums)
    grid = [[None] * 32 for _ in range(5)]
    def put(track, step, asset, chop, velocity, length=0, note=60):
        grid[track][step] = {'note': note, 'vel': velocity, 'cmd': 'OV' if length else '',
                            'amt': length, 'sampleId': asset['id'], 'slice': chop}
    for i, step in enumerate([0, 4, 8, 12, 16, 20, 24, 28]):
        put(0, step, original, [0, 1, 2, 1, 4, 5, 6, 7][i], .55, 2)
    for i, step in enumerate([2, 10, 18, 26, 30]):
        put(1, step, sources[1], [2, 3, 5, 6, 7][i], .35, 1, 60 if i < 4 else 67)
    for step in [0, 6, 8, 16, 22, 24]:
        put(2, step, drums[0], 0, .8 if step % 8 == 0 else .6, 1)
    for step in [4, 12, 20, 28]:
        put(3, step, drums[1], 0, .65, 1)
    for step in range(0, 32, 2):
        put(4, step, drums[2], 0, .35 if step % 4 else .5)
    return {'schema': 'brahma.sample-project.v1', 'name': title + ' - Brahma sketch',
            'tempo': 92, 'phase': 'manual', 'cycle': 0, 'scene': {'steps': 32, 'tracks': 5, 'grid': grid},
            'trackSources': [original['id'], sources[1]['id']] + [s['id'] for s in drums], 'sources': sources}


def source_duration(path: Path) -> float:
    with wave.open(str(path), 'rb') as wav:
        return wav.getnframes() / wav.getframerate()


def render_drums(destination: Path) -> None:
    destination.mkdir(mode=0o700)
    definitions = {m['name']: m for m in native.catalogue()}
    for name in ('drum_subtractive', 'drum_noise'):
        (destination / (name + '.scd')).write_text(definitions[name]['definition'])
    script = '''(
var definitions, master;
PATTERNS.load;
definitions = Dictionary.new;
[\\drum_subtractive, \\drum_noise].do({ |name| definitions[name] = File.readAllString(ROOT +/+ (name.asString ++ ".scd")).interpret; });
master = SynthDef(\\sketch_drum_master, { ReplaceOut.ar(0, Limiter.ar(LeakDC.ar(In.ar(8, 1)) ! 2, 0.8, 0.005)); });
[\\kick808, \\snare, \\hihatClosed].do({ |name|
 var preset = ~golem_patterns.factory[name], definition;
 definition = definitions[preset[\\synthDef]];
 Score([
  [0, [\\d_recv, definition.asBytes]], [0, [\\d_recv, master.asBytes]],
  [0, [\\s_new, preset[\\synthDef], 1000, 1, 1] ++ preset[\\args].asPairs ++ [\\outBus, 8, \\velocity, 0.8, \\gate, 1]],
  [0, [\\s_new, \\sketch_drum_master, 1001, 1, 1]],
  [0.12, [\\n_set, 1000, \\gate, 0]], [0.999, [\\g_freeAll, 1]], [1, [\\c_set, 0, 0]]
 ]).write(ROOT +/+ (name.asString ++ ".osc"));
});
0.exit;
)
'''.replace('PATTERNS', native.sc_string(str(native.SC / '15_golem_patterns.scd'))).replace('ROOT', native.sc_string(str(destination)))
    driver = destination / 'compile.scd'; driver.write_text(script)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
    if native.run([native.binary('sclang'), '-D', '-u', str(port), str(driver)], destination / 'compile.log', 90):
        raise ValueError('Golem preset compilation failed')
    for name in DRUMS:
        output = destination / (name + '.wav')
        code = native.run([native.binary('scsynth'), '-N', str(destination / (name + '.osc')), '_', str(output),
                           '44100', 'WAV', 'int16', '-o', '2', '-i', '0', '-a', '64'], destination / (name + '.log'), 30)
        if code or native.measure_audio(output, 1)['status'] != 'rendered':
            raise ValueError('Golem preset render failed: ' + name)
    (destination / 'provenance.json').write_text(json.dumps({'presets': list(DRUMS),
        'factory_sha256': native.sha256(native.SC / '15_golem_patterns.scd'),
        'definitions': {n: definitions[n]['definition_sha256'] for n in ('drum_subtractive', 'drum_noise')},
        'outputs': {n: native.sha256(destination / (n + '.wav')) for n in DRUMS}}, indent=2) + '\n')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--out', type=Path, default=native.ROOT / 'forge/out/sketches')
    args = parser.parse_args()
    if not args.manifest.is_file():
        parser.error('provide a validated donor manifest')
    args.out.mkdir(parents=True, exist_ok=True, mode=0o700)
    if native.shutil.disk_usage(args.out).free < 1024 ** 3:
        parser.error('at least 1 GiB free space is required')
    destination = args.out.resolve() / (time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
    destination.mkdir(mode=0o700)
    native.DEADLINE = time.monotonic() + 180
    render_drums(destination / 'golem')
    project = build_project(json.loads(args.manifest.read_text()), args.manifest.resolve().parent, destination / 'golem')
    output = destination / 'song-sketch.brahma.json'
    output.write_text(json.dumps(project, separators=(',', ':')) + '\n')
    validation = "const fs=require('node:fs'),m=require(process.argv[1]);m.deserialize(fs.readFileSync(process.argv[2],'utf8')).then(p=>console.log(p.sources.length+' sources validated')).catch(e=>{console.error(e.message);process.exitCode=1});"
    if native.run([native.binary('node'), '-e', validation, str(native.ROOT / 'brahma/web/public/instrument/sample-project.js'), str(output)], destination / 'validation.log', 20):
        raise ValueError('Sketch project validation failed')
    print(json.dumps({'directory': str(destination), 'project': str(output), 'sources': len(project['sources']), 'tempo': project['tempo']}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
