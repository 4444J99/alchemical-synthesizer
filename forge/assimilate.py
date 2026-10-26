#!/usr/bin/env python3
"""Feed a local song or YouTube recording into the existing native Brahma rack.

Original media and outputs stay in a unique directory under forge/out. Catalogue
coverage is explicit: --all auditions processors, source-driven generators,
and controls applied to the donor; infrastructure remains listed with its role.
No audio device is opened. Native SynthDefs are extracted from the current source,
compiled once, then rendered serially by scsynth with private buffers per module.
"""
from __future__ import annotations

import argparse
import array
import hashlib
import html
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
import uuid
import wave
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from forge import materials
SC = ROOT / 'brahma/sc'
CONTROL_SPECS = json.loads((ROOT / 'forge/native-controls.json').read_text())
DEADLINE: float | None = None
DEFAULT_MODULES = ['mnemosyne_voice_stereo', 'protean_hound_stereo',
                   'chrysalid_siren_stereo', 'ossuary_monk_stereo',
                   'janiform_child_stereo', 'octahedron_slicer', 'octahedron_timestretch']
# Audition settings, not replacement DSP. All named controls belong to the native
# definitions. The full settings are written into each render's provenance.
PRESETS = {
    'mnemosyne_voice_stereo': {'age': .65, 'erosion': .5, 'recallOffset': .002},
    'protean_hound_stereo': {'sensitivity': .3, 'chaos': .7, 'aggression': .7},
    'chrysalid_siren_stereo': {'grainDensity': 28, 'identityBlur': .25, 'formantShift': -5},
    'ossuary_monk_stereo': {'impactThreshold': .02, 'relicDecay': .7, 'gravity': .2},
    'ossuary_monk': {'impactThreshold': .02, 'relicDecay': .7, 'gravity': .2},
    'janiform_child_stereo': {'symmetry': .85, 'causalDrift': .03},
    'octahedron_slicer': {'numSlices': 8, 'sliceIndex': 2, 'rate': .8, 'loop': 1},
    'octahedron_timestretch': {'rate': .5, 'pitch': 1.3},
    'solve_spectral_freeze': {'freeze': 1},
    'solve_pitch_shift': {'semitones': -7},
    'nucleus_freeze': {'freeze': 1},
    'relinquished_bc': {'equipState': 1, 'equipTrig': 1},
}


def mask_source(source: str) -> str:
    """Blank comments/string contents while retaining offsets and delimiters."""
    pattern = r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''
    return re.sub(pattern, lambda m: ''.join('\n' if c == '\n' else ' ' for c in m[0]), source)


def extract_modules(source: str, filename: str) -> list[dict]:
    masked = mask_source(source)
    modules = []
    for match in re.finditer(r'SynthDef\s*\(\s*\\(\w+)\s*,\s*\{', masked):
        start = match.start(); cursor = masked.index('(', start); depth = 0; end = None
        for pos in range(cursor, len(masked)):
            if masked[pos] == '(':
                depth += 1
            elif masked[pos] == ')':
                depth -= 1
                if depth == 0:
                    end = pos + 1; break
        if end is None:
            raise ValueError(f'Unbalanced SynthDef {match[1]} in {filename}')
        code = masked[start:end]
        params_match = re.search(r'\{\s*\|([^|]*)\|', code)
        params = re.findall(r'(?:^|,)\s*(\w+)\s*(?==|,|$)', params_match[1]) if params_match else []
        # Read actual signal-input operations, not merely an unused inBus argument.
        inputs = sorted(set(re.findall(r'In(?:Feedback)?\.ar\(\s*(\w+)', code)) & set(params))
        input_channels = {name: int(width) for name, width in
                          re.findall(r'In(?:Feedback)?\.ar\(\s*(\w+)\s*,\s*(\d+)\s*\)', code) if name in inputs}
        buffers = [p for p in params if re.fullmatch(r'buf(?:num\d*|L|R)?', p)]
        outputs = sorted(set(re.findall(r'(?:Out|ReplaceOut|OffsetOut)\.ar\(\s*(\w+)', code)) & set(params))
        control_inputs = sorted(set(re.findall(r'In(?:Feedback)?\.kr\(\s*(\w+)', code)) & set(params))
        control_outputs = sorted(set(re.findall(r'(?:Out|ReplaceOut|OffsetOut)\.kr\(\s*(\w+)', code)) & set(params))
        has_audio = bool(re.search(r'(?:Out|ReplaceOut|OffsetOut)\.ar\(', code))
        if re.search(r'DiskOut|VDiskIn|DiskIn|SoundIn|SendReply|SendTrig', code):
            role = 'infrastructure'
        elif re.search(r'VOsc|Osc(?:N)?\.ar', code) and buffers:
            role = 'wavetable_generator'
        elif has_audio and buffers:
            role = 'buffer_processor'
        elif has_audio and inputs:
            role = 'audio_processor'
        elif has_audio:
            role = 'sound_generator'
        else:
            role = 'control_utility'
        if filename.startswith(('07_', '10_', '11_', '12_', '13_', '14_', '28_', '30_', '31_', '32_')):
            role = 'infrastructure'
        modules.append({'name': match[1], 'file': filename, 'params': params,
                        'audio_inputs': inputs, 'audio_input_channels': input_channels,
                        'buffer_inputs': buffers, 'audio_outputs': outputs,
                        'control_inputs': control_inputs, 'control_outputs': control_outputs,
                        'role': role, 'definition': source[start:end],
                        'definition_sha256': hashlib.sha256(source[start:end].encode()).hexdigest()})
    return modules


def catalogue(directory: Path = SC) -> list[dict]:
    return [item for path in sorted(directory.glob('[0-9][0-9]_*.scd'))
            for item in extract_modules(path.read_text(), path.name)]


def validate_controls(module: str, values: dict) -> dict:
    if module not in {item['name'] for item in catalogue()}:
        raise ValueError('Unknown native module')
    if not isinstance(values, dict):
        raise ValueError('Controls must be an object')
    specs = CONTROL_SPECS.get(module, {})
    for name, value in values.items():
        if name not in specs:
            raise ValueError('Unsupported native control: ' + name)
        _, minimum, maximum, step, _ = specs[name]
        if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or not minimum <= value <= maximum:
            raise ValueError('Native control outside range: ' + name)
        if step == 1 and int(value) != value:
            raise ValueError('Native control must be an integer: ' + name)
    return dict(values)


def sc_string(value: str) -> str:
    if '\x00' in value:
        raise ValueError('NUL is not allowed in native paths')
    return json.dumps(value, ensure_ascii=False)


def sha256(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run(command: list[str], log: Path, timeout: float = 120) -> int:
    """Bound the whole process group, disk log and wall time; preserve evidence."""
    started = time.monotonic()
    if DEADLINE is not None:
        timeout = min(timeout, DEADLINE - started)
        if timeout <= 0:
            raise ValueError('Overall render deadline reached; earlier results are preserved')
    with log.open('wb') as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True, preexec_fn=lambda: os.nice(10))
        reason = None
        try:
            while process.poll() is None:
                if time.monotonic() - started > timeout:
                    reason = 124; break
                if log.stat().st_size > 2 * 1024 * 1024:
                    reason = 125; break
                time.sleep(.05)
        finally:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL); process.wait()
                except ProcessLookupError:
                    process.wait()
        if reason:
            return reason
        return process.returncode


def binary(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    app = Path('/Applications/SuperCollider/SuperCollider.app/Contents')
    for path in [app / 'MacOS' / name, app / 'Resources' / name]:
        if path.is_file():
            return str(path)
    raise ValueError(f'{name} is required')


def youtube_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme != 'https' or parsed.username or parsed.password:
        raise ValueError('Use an HTTPS YouTube video URL')
    if parsed.hostname in ('youtube.com', 'www.youtube.com', 'music.youtube.com'):
        video = parse_qs(parsed.query).get('v', [''])[0]
    elif parsed.hostname == 'youtu.be':
        video = parsed.path.strip('/')
    else:
        raise ValueError('Only YouTube video URLs are supported; use a local file otherwise')
    if not re.fullmatch(r'[A-Za-z0-9_-]{11}', video):
        raise ValueError('A single YouTube video ID is required')
    return 'https://www.youtube.com/watch?v=' + video


def admit(source: str, destination: Path, start: float, duration: float) -> dict:
    original_dir = destination / 'original'; original_dir.mkdir(mode=0o700)
    origin = {'kind': 'local'}
    if source.startswith(('https:', 'http:')):
        url = youtube_url(source)
        downloader = [binary('yt-dlp')] if shutil.which('yt-dlp') else [binary('uv'), 'tool', 'run', '--from', 'yt-dlp', 'yt-dlp']
        code = run(downloader + ['--ignore-config', '--no-playlist', '--no-overwrites', '--no-progress',
            '--max-filesize', '64M', '--socket-timeout', '15', '--retries', '1', '--fragment-retries', '1',
            '--write-info-json', '-f', 'bestaudio', '-o', str(original_dir / '%(id)s.%(ext)s'), '--', url],
            destination / 'acquisition.log', 150)
        if code:
            raise ValueError(f'Acquisition failed (exit {code}); see acquisition.log')
        candidates = [p for p in original_dir.iterdir() if p.suffix in ('.webm', '.m4a', '.opus', '.mp3', '.ogg')]
        if len(candidates) != 1:
            raise ValueError('Acquisition did not produce one audio source')
        original = candidates[0]; origin = {'kind': 'youtube', 'url': url}
    else:
        incoming = Path(source).expanduser().resolve(strict=True)
        if not incoming.is_file() or incoming.stat().st_size > 64 * 1024 * 1024:
            raise ValueError('Source must be a regular file of at most 64 MiB')
        original = original_dir / incoming.name
        shutil.copy2(incoming, original)
        origin['name'] = incoming.name
        metadata = incoming.with_suffix('.info.json')
        if metadata.is_file() and metadata.stat().st_size < 5 * 1024 * 1024:
            info = json.loads(metadata.read_text())
            origin['title'] = str(info.get('title', incoming.name))
            origin['artist'] = str(info.get('artist') or info.get('uploader') or '')
            origin['url'] = str(info.get('webpage_url', ''))
    digest = sha256(original)
    ffmpeg = binary('ffmpeg')
    for name, channels in [('source.wav', 2), ('source.mono.wav', 1)]:
        code = run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-n', '-ss', str(start),
                    '-i', str(original), '-t', str(duration), '-ac', str(channels), '-ar', '44100',
                    '-c:a', 'pcm_s16le', str(destination / name)], destination / (name + '.log'), 60)
        if code:
            raise ValueError(f'Audio normalization failed (exit {code})')
    measurement = measure_audio(destination / 'source.wav', duration)
    if measurement['status'] != 'rendered':
        raise ValueError('Source excerpt is ' + measurement['status'] + '; choose another start/duration')
    if sha256(original) != digest:
        raise ValueError('Original source changed during admission')
    return {'id': 'sha256:' + digest, 'sha256': digest, 'origin': origin,
            'original': str(original.relative_to(destination)), 'start_seconds': start,
            'duration_seconds': duration, 'stereo': 'source.wav', 'mono': 'source.mono.wav',
            'stereo_sha256': sha256(destination / 'source.wav'), 'measurement': measurement}


def measure_audio(path: Path, expected: float) -> dict:
    try:
        with wave.open(str(path), 'rb') as wav:
            channels, width, rate, frames = wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes()
            duration = frames / rate
            if width != 2 or channels != 2 or abs(duration - expected) > .025:
                return {'status': 'invalid_duration', 'duration_seconds': duration, 'channels': channels}
            peak = 0; squares = 0; count = 0
            while chunk := wav.readframes(16384):
                values = array.array('h', chunk)
                if sys.byteorder != 'little':
                    values.byteswap()
                if values:
                    peak = max(peak, max(abs(v) for v in values))
                    squares += sum(v * v for v in values); count += len(values)
            if count != frames * channels:
                return {'status': 'truncated_audio'}
            rms = math.sqrt(squares / max(1, count)) / 32768
            return {'status': 'rendered' if peak > 32 else 'silent', 'frames': frames,
                    'duration_seconds': duration, 'peak_dbfs': 20 * math.log10(max(peak / 32768, 1e-12)),
                    'rms_dbfs': 20 * math.log10(max(rms, 1e-12))}
    except (OSError, EOFError, wave.Error) as exc:
        return {'status': 'invalid_audio', 'error': str(exc)}


def module_args(module: dict) -> dict:
    args = {}
    for name in module['audio_inputs']:
        args[name] = (6 if name.endswith('Mid') else 7 if name.endswith('Side') else
                      2 if module.get('audio_input_channels', {}).get(name) == 2 else
                      3 if name.endswith('R') else 2 if name.endswith('L') else 4)
    for name in module['buffer_inputs']:
        args[name] = ({'bufnum': 16, 'bufnum2': 18}.get(name, 16) if module['role'] == 'wavetable_generator'
                      else {'bufL': 2, 'bufR': 3}.get(name, 1))
    for name in module['control_inputs']:
        if name in ('iaClipBus', 'teSatBus'):
            args[name] = 7
        elif re.search(r'trig|clock|sync|gate', name, re.I) or module['name'].startswith(('horologium', 'daemon_', 'sibyl_')):
            args[name] = 3
        elif re.search(r'Tone|Pitch', name):
            args[name] = 1
        elif 'Noise' in name:
            args[name] = 2
        elif name.endswith(('2', 'B')):
            args[name] = 5
        else:
            args[name] = 0
    for index, name in enumerate(module['audio_outputs']):
        args[name] = 8 if name in ('out', 'outBus') else 16 + index * 8
    control_outputs = sorted(module['control_outputs'], key=lambda name: (name not in ('out', 'outBus'), name))
    for index, name in enumerate(control_outputs):
        args[name] = 16 + index
    args.update({key: value for key, value in PRESETS.get(module['name'], {}).items() if key in module['params']})
    if module.get('overrides'):
        args.update(validate_controls(module['name'], module['overrides']))
    return args


def module_maps(module: dict) -> dict:
    maps = {}
    for name in module['params']:
        if re.fullmatch(r'cv\d*|pressure|velocity|vel|amp', name):
            maps[name] = 0
        if re.fullmatch(r'strike\d*|trig|trigger', name):
            maps[name] = 3
        if module['role'] in ('sound_generator', 'wavetable_generator') and name in ('freq', 'frequency'):
            maps[name] = 4
        if module['role'] in ('sound_generator', 'wavetable_generator', 'control_utility') and name == 'gate':
            maps[name] = 6
    return maps


def compile_scores(modules: list[dict], destination: Path, duration: float) -> int:
    driver = destination / 'compile.scd'
    jobs = []
    for item in modules:
        args = module_args(item); item['parameters'] = args; item['control_maps'] = module_maps(item)
        pairs = '[' + ', '.join('\\' + key + ', ' + str(value) for key, value in args.items()) + ']'
        maps = '[' + ', '.join('\\' + key + ', ' + str(value) for key, value in item['control_maps'].items()) + ']'
        stem = item['name']; codefile = destination / (stem + '.native.scd')
        codefile.write_text(item['definition'])
        outputs = item['audio_outputs'] or item['control_outputs']
        output_bus = args.get('outBus', args.get('out', next(iter([args[p] for p in outputs]), 8)))
        mode = {'control_utility': 2, 'sound_generator': 1, 'wavetable_generator': 3}.get(item['role'], 0)
        jobs.append('try { ~donor_rack.writeScore(' + ', '.join([
            sc_string(str(codefile)), pairs, sc_string(str(destination / 'source.wav')),
            sc_string(str(destination / 'source.mono.wav')), sc_string(str(destination / (stem + '.osc'))),
            str(duration), str(output_bus), maps, str(mode)]) + '); } { |err| ("DONOR_COMPILE_FAILED ' + stem + '").postln; err.reportError; };')
    jobfile = destination / 'compile-jobs.scd'
    jobfile.write_text('\n'.join(jobs) + '\n')
    # Interpret one job per function: a rack-wide function exceeds sclang's
    # literal/selector table even though each individual definition is valid.
    body = ['(', sc_string(str(SC / '32_donor_rack.scd')) + '.load;',
            'File.readAllString(' + sc_string(str(jobfile)) + ').split($\\n).do({ |line| if(line.notEmpty) { line.interpret; }; });',
            '"DONOR_COMPILE_DONE".postln;', '0.exit;', ')']
    driver.write_text('\n'.join(body) + '\n')
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
    return run([binary('sclang'), '-D', '-u', str(port), str(driver)], destination / 'compile.log', 90)


def audition_html(manifest: dict, destination: Path) -> None:
    esc = html.escape
    rows = []
    for item in manifest['modules']:
        status = item['status']
        audio = f'<audio controls preload="none" src="{esc(item["output"])}"></audio>' if status == 'rendered' else ''
        rows.append(f'<article data-role="{esc(item["role"])}"><h3>{esc(item["name"])}</h3>'
                    f'<p>{esc(item["role"])} / {esc(status)}</p>{audio}'
                    f'<small>{esc(item.get("reason", ""))}</small></article>')
    title = manifest['donor']['origin'].get('title') or manifest['donor']['origin'].get('name', manifest['donor']['origin'].get('url', 'Song donor'))
    text = '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
    text += '<title>Brahma - Song assimilation</title><style>body{background:#080b15;color:#e5e8f3;font:16px system-ui;max-width:1100px;margin:2rem auto;padding:1rem}h1{color:#98b5ff}audio{width:100%}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:1rem}article{padding:1rem;border:1px solid #303650;border-radius:12px}small{color:#b8c1d5}input{padding:.6rem;width:80%;margin:1rem 0}a{color:#9cbcff}</style>'
    text += f'<h1>Brahma - Song assimilation</h1><p>{esc(title)}</p><p>Original excerpt: {manifest["donor"]["start_seconds"]:g}s start, {manifest["donor"]["duration_seconds"]:g}s duration. Original media preserved.</p><audio controls preload="none" src="source.wav"></audio>'
    text += '<p>Each playable result uses the named native module. Other roles and failures remain visible. Outputs are audition excerpts, not a finished arrangement.</p><input aria-label="Filter modules" placeholder="Find a module or result" id="filter"><main>' + ''.join(rows) + '</main>'
    text += '<script>document.querySelector("#filter").addEventListener("input",e=>document.querySelectorAll("article").forEach(x=>x.hidden=!x.textContent.toLowerCase().includes(e.target.value.toLowerCase())));document.addEventListener("play",e=>{if(e.target.tagName==="AUDIO")document.querySelectorAll("audio").forEach(a=>{if(a!==e.target)a.pause()})},true)</script>'
    (destination / 'index.html').write_text(text)


def main() -> int:
    global DEADLINE
    def interrupted(*_):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', nargs='?', help='local audio or one HTTPS YouTube video URL')
    parser.add_argument('--out', type=Path, default=ROOT / 'forge/out/assimilation')
    parser.add_argument('--start', type=float, default=30)
    parser.add_argument('--duration', type=float, default=8)
    parser.add_argument('--deadline', type=float, default=600, help='overall wall-time budget in seconds (1-3600)')
    parser.add_argument('--module', action='append', default=[])
    parser.add_argument('--param', action='append', default=[], help='safe musical control NAME=VALUE for exactly one --module')
    parser.add_argument('--material-json', help='versioned material composition/phase JSON; source-owned mapping required')
    parser.add_argument('--all', action='store_true', help='render native audio/buffer, source-driven generator, and source-modulation paths')
    parser.add_argument('--catalogue', action='store_true', help='print every discovered module and interface role')
    args = parser.parse_args()
    catalog = catalogue()
    if args.catalogue:
        print(json.dumps([{**{k: v for k, v in item.items() if k != 'definition'},
                           'controls': CONTROL_SPECS.get(item['name'], {}),
                           'material': materials.describe(item['name'])} for item in catalog], indent=2)); return 0
    if not args.source:
        parser.error('provide a source or --catalogue')
    if not math.isfinite(args.start) or args.start < 0 or not math.isfinite(args.duration) or not 1 <= args.duration <= 600:
        parser.error('start must be nonnegative and duration between 1 and 600 seconds')
    if not math.isfinite(args.deadline) or not 1 <= args.deadline <= 3600:
        parser.error('deadline must be between 1 and 3600 seconds')
    DEADLINE = time.monotonic() + args.deadline
    selected = set(args.module or DEFAULT_MODULES)
    unknown = selected - {item['name'] for item in catalog}
    if unknown:
        parser.error('unknown modules: ' + ', '.join(sorted(unknown)))
    if args.param:
        if len(args.module) != 1 or args.all:
            parser.error('--param requires exactly one --module')
        try:
            values = {}
            for entry in args.param:
                key, value = entry.split('=', 1)
                if key in values:
                    raise ValueError('Duplicate native control: ' + key)
                values[key] = float(value)
            overrides = validate_controls(args.module[0], values)
            next(item for item in catalog if item['name'] == args.module[0])['overrides'] = overrides
        except ValueError as exc:
            parser.error(str(exc))
    if args.material_json is not None:
        try:
            if len(args.material_json) > 8192:
                raise ValueError('Material state exceeds size limit')
            state = materials.validate(json.loads(args.material_json))
            for item in catalog:
                if args.all or item['name'] in selected:
                    if item['name'] not in materials.LIBRARY['profiles']:
                        if not args.all:
                            raise ValueError('Unsupported material mapping: ' + item['name'])
                        item['material_unavailable'] = True
                        continue
                    base = {k: v for k, v in PRESETS.get(item['name'], {}).items() if k in CONTROL_SPECS.get(item['name'], {})}
                    base.update(item.get('overrides', {}))
                    resolved = materials.resolve(item['name'], base, state)
                    item['base_params'] = materials.base_controls(item['name'], base)
                    item['overrides'] = resolved['params']
                    item['material'] = resolved['material']
                    item['model_sha256'] = resolved['modelSha256']
        except (ValueError, TypeError) as exc:
            parser.error(str(exc))
    args.out.mkdir(parents=True, exist_ok=True, mode=0o700)
    render_count = sum(not item.get('material_unavailable') and item['role'] != 'infrastructure' and bool(item['audio_outputs'] or item['control_outputs'])
                       and (args.all or item['name'] in selected) for item in catalog)
    required_bytes = max(1024 ** 3, int((render_count + 2) * args.duration * 44100 * 4 * 1.2) + 128 * 1024 ** 2)
    if shutil.disk_usage(args.out).free < required_bytes:
        parser.error(f'at least {required_bytes / 1024 ** 3:.2f} GiB free space is required for this render')
    destination = args.out.resolve() / (time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
    destination.mkdir(mode=0o700)
    print('DONOR_DIRECTORY ' + str(destination), flush=True)
    try:
        donor = admit(args.source, destination, args.start, args.duration)
        public_catalog = [{k: v for k, v in item.items() if k != 'definition'} for item in catalog]
        candidates = []
        for item, record in zip(catalog, public_catalog):
            eligible = item['role'] != 'infrastructure' and (item['audio_outputs'] or item['control_outputs'])
            if item.get('material_unavailable'):
                record['status'] = 'requires_material_mapping'
                record['reason'] = 'No source-owned material mapping; original native capability remains available without material.'
            elif eligible and (args.all or item['name'] in selected):
                record['status'] = 'pending'; candidates.append(item)
            else:
                record['status'] = 'not_selected' if eligible else 'requires_patch'
                record['reason'] = '' if eligible else 'Infrastructure or a non-routable interface; needs its owning lifecycle, not a standalone donor audition.'
        compile_code = compile_scores(candidates, destination, args.duration)
        manifest = {'schema': 'brahma.donor-audition.v1', 'donor': donor,
                    'implementation_sha256': sha256(Path(__file__)),
                    'native_rack_sha256': sha256(SC / '32_donor_rack.scd'),
                    'compile_exit_code': compile_code, 'modules': public_catalog}
        for item, record in zip(catalog, public_catalog):
            if record['status'] != 'pending':
                continue
            score = destination / (item['name'] + '.osc')
            record['parameters'] = item['parameters']
            record['control_maps'] = item['control_maps']
            if not score.is_file() or compile_code:
                record['status'] = 'compile_failed'; record['reason'] = 'See compile.log'; continue
            output = destination / (item['name'] + '.wav'); log = destination / (item['name'] + '.render.log')
            code = run([binary('scsynth'), '-N', str(score), '_', str(output), '44100', 'WAV', 'int16',
                        '-o', '2', '-i', '0', '-a', '256', '-m', '65536'], log, max(30, args.duration * 2))
            logtext = log.read_text(errors='replace')
            result = measure_audio(output, args.duration)
            if code or re.search(r'FAILURE IN SERVER|Exception|ERROR', logtext):
                result['status'] = 'render_failed'; result['reason'] = 'See ' + log.name
            record.update(result); record['render_exit_code'] = code
            if result['status'] == 'rendered':
                record['output'] = output.name; record['output_sha256'] = sha256(output)
            print(item['name'] + ': ' + record['status'], flush=True)
            (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        if sha256(destination / donor['original']) != donor['sha256']:
            raise ValueError('Original source changed during processing')
        (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        audition_html(manifest, destination)
        counts = {s: sum(m['status'] == s for m in public_catalog) for s in sorted({m['status'] for m in public_catalog})}
        print(json.dumps({'directory': str(destination), 'results': counts}), flush=True)
        return 1 if any(m['status'] in ('compile_failed', 'render_failed', 'silent', 'invalid_duration', 'invalid_audio', 'truncated_audio') for m in public_catalog) else 0
    except (ValueError, OSError) as exc:
        (destination / 'failure.json').write_text(json.dumps({'error': str(exc)}, indent=2) + '\n')
        print('assimilation: ' + str(exc), file=sys.stderr); return 2
    except KeyboardInterrupt:
        (destination / 'failure.json').write_text(json.dumps({'error': 'Render cancelled; earlier results retained'}) + '\n')
        return 130


if __name__ == '__main__':
    raise SystemExit(main())
