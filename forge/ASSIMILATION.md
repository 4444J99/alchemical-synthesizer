# Feed a song through Brahma

Run from the repository root. Install FFmpeg and SuperCollider (`sclang` and
`scsynth`); YouTube input additionally uses yt-dlp, or uv to run yt-dlp.

```sh
python3 forge/assimilate.py song.wav --start 30 --duration 8 --all
python3 forge/assimilate.py 'https://www.youtube.com/watch?v=VIDEO_ID' --all
python3 forge/assimilate.py song.wav --start 0 --module mnemosyne_voice_stereo
python3 forge/assimilate.py --catalogue
```

Open `index.html` in the printed `DONOR_DIRECTORY`. Listen to the original excerpt,
filter module names, and compare individual renders. Starting one player pauses
the others. Each output WAV can also be loaded into the existing `/instrument/`
sample track, chopped, sequenced, saved in a portable project, or used in a DAW.

```text
Full original (copied, hashed, retained)
                |
      Bounded stereo/mono excerpt
                |
     +----------+------------+-------------+
     |                       |             |
 Audio/buffer DSP     Donor-driven voices  Control utilities
     |                pitch/envelope/     applied to donor
     |                waveform tables     amplitude
     +-----------------------+-------------+
                             |
           Per-module WAV + measurements + provenance
                             |
                 Private listening index
```

The catalogue reads actual literal SynthDefs from numbered native source files.
The current rack has 245 definitions: 224 standalone audition paths and 21
infrastructure/non-routable definitions listed as `requires_patch`. Language-side
sequencers, live routing, hardware capture, and dynamically generated definitions
are not standalone SynthDefs and are outside this offline catalogue.

Audio processors receive native mono or stereo inputs; buffer processors receive
private donor buffers. Generators use donor pitch/envelope controls where exposed,
plus envelope modulation at the output; wavetable generators receive donor-derived
tables. Control utilities modulate the donor's amplitude. Multiple-input processors
receive the same donor at each input, not separate stems. Multiple-output modules
audition the canonical output, or the first declared output name in sorted order.
These are defined audition patches, not every possible routing or parameter state.

`manifest.json` records source and definition hashes, bindings, parameters,
measurements, exit codes, and explicit failures. Non-silence and duration checks
establish a valid render, not musical quality, perceptual difference, or a finished
arrangement. Random native DSP remains stochastic; exact rerender identity is not
promised. Failed runs and earlier renders remain available for diagnosis.

Full originals, download metadata and derived audio stay under ignored `forge/out/`.
Each run uses a new private directory and checks original hashes after processing.
No audio device is opened. This does not install a live rack or broadcast material.
The browser now offers background native render/apply controls and saves recipes.
Real-time SC sample transfer and shared live-rack transport remain in #95.

Sources are limited to 64 MiB. Excerpts may be 1-600 seconds; default is 8 seconds
starting at 30 seconds. Disk admission reserves the estimated selected render size
with a 1 GiB minimum. `--deadline` sets the overall budget (default 600 seconds,
maximum 3600); each child process also has a deadline and a bounded diagnostic log.
Exit 0 means selected eligible renders passed; 1 means a render failed validation;
2 means admission or execution was interrupted. Inspect `requires_patch` entries
even on exit 0. `--out` relocates private results; do not point it at public assets.

Run contracts with `python3 -m unittest discover -s tools/tests -p test_assimilate.py`.
Set `RUN_NATIVE_DONOR_TESTS=1` to include installed SuperCollider integration.

## Material vessels and comparisons

The instrument's five vessels each retain their own module, base controls and
optional material state. The initial palette is water, silica, iron and air;
positive mixture fractions sum to one. Material phase is solid, liquid or gas,
separate from oscillator phase and the composition's READABLE/CLUSTER/DISPERSAL
arc. Amount zero preserves base controls. The model is an artistic response
mapping, not a scientific simulation of chemistry.

`materials.json` owns normalized material/phase properties and 26 explicit
organism-to-control mappings. `materials.py` and the browser's `material-model.js`
validate/resolve the same state; parity tests cover them. A model SHA-256 binds
both this library and `native-controls.json`. Native recipes retain canonical
material, base controls, effective controls and this hash. Existing projects
without material fields still open; saved historical audio retains its original
model identity. New renders use the current model and require matching receipts.

```sh
python3 forge/assimilate.py song.wav --start 0 --duration 2 --module ditto_morphic_core --material-json '{"schema":"brahma.material-state.v1","modelVersion":1,"phase":"gas","amount":1,"composition":[{"id":"water","fraction":1}]}'
python3 forge/compare.py song.wav --duration 2 --deadline 300
python3 forge/compare.py song.wav --all --duration 2 --deadline 900
```

Without `--all`, comparison selects Relinquished, Agent Smith, Ditto and Typhon;
repeat `--module NAME` to select others. `--all` auditions every native definition
and compares every mapped module. All 245 definitions remain in `ledger.json`.
The stages are native defaults, neutral material controls, repeated neutral,
and solid/liquid/gas water responses. The private `index.html` provides the same
original excerpt and each output. Raw PCM RMS difference includes gain changes;
shape difference removes each signal's RMS gain for measurement only. Playback
is not loudness-normalized. Compare repeated-neutral variability before
attributing a difference to material in stochastic DSP.

Comparison checks original, normalized donor, output and native definition
hashes. `--reuse-native PATH` can retain a prior native-default audition of the
same source/timing; selected results and their hashes are checked before copying
it into the new run. Earlier evidence is preserved. Excerpts are 1–30 seconds,
the source is at most 64 MiB, and a hard process deadline bounds each native run.
`stages_complete` means stages ran; silent, failed, unmapped and patch-required
results stay explicit. Original-behavior acceptance remains `not_measured`:
non-silence or waveform difference cannot prove absorption, memory or role copying.

Run `node tools/verify-material-vessels.cjs PRIVATE_PROJECT.brahma.json` for an
installed Chrome → authenticated local service → SuperCollider check. It creates
three phase-specific projects and measured loop WAVs, verifies save/reopen and
original restoration, captures desktop/mobile views, and records a receipt in a
new private directory beside the input. It preserves the input and stops its
temporary browser/server. See [observed results](../docs/verification/material-vessels-20261026.md).
