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
