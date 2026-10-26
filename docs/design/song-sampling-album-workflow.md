# Song sampling in the existing Alchemical Synthesizer

Status: broader integration direction, grounded in the 2026-10-26 system review.
The user authorized the browser load/save slice on 2026-10-26. That slice now
implements local import, editable chops, sample sequencing, embedded portable
projects, and loop WAV export; see the README and sample-load-save plan/evidence.
Forge now provides [native song assimilation](../../forge/ASSIMILATION.md):
preserved local/YouTube donors, bounded module auditions, and a listening index.
The instrument now sends short sounds to Forge for native transformations and
applies the result to future notes while its browser sequence keeps playing.
Portable projects retain original excerpts, transformed audio, recipes and chops;
the starter sketch includes actual rendered Golem presets on that transport.
Real-time SC buffer transfer, the separate live Golem sequencer, live modular
routing, and album arrangement below remain unfinished. Render validation with
selected songs does not establish musical acceptance.

The [original-organism and material reconciliation](mimicry-material-universe.md)
connects this workflow to the original ChatGPT designs, the Claude drum machine,
Universal Node Network, and related musical/visual sources. It defines the shared
transparent-vessel/material direction, preserves each organism's distinct mimicry,
and separates audible module auditions from behavioral verification. Material
processing and full organism acceptance remain implementation work.

## Intent

Use selected songs as sample material for an album. Import audio, choose useful
passages, transform them through the existing modular synth, play and sequence
them alongside drums and other instruments, and save reproducible compositions.
Sampling is the central operation. Stem separation is an optional aid, not a
prerequisite for chopping a record or preserving a recognizable phrase.

```text
Song selections + local audio
             |
     Library and audition
             |
     Manual chops / loops ------ optional stem separation
             |                            |
             +----- sample assets --------+
                          |
        Brahma slice / stretch / grain / reverse / effects
                          |
        Sequencer + Golem drums + other synth voices
                          |
                 Save / reopen / render
                          |
                Album tracks and stems
```

## Reuse the existing system

| Responsibility | Existing owner | Integration needed |
| --- | --- | --- |
| Decode and normalize source audio | `forge/ingest.sh` | Batch selections, stable source IDs, collision-safe destinations |
| Optional stem extraction | `forge/rip.py` | Show actual engine and quality; keep original source available |
| Source and recipe provenance | `forge/rip.py`, `forge/forge.sh`, `forge/stemforge.py` | Extend identities to clips, slices, transformations, and sessions |
| Slice, loop, stretch, and crossfade | `brahma/sc/25_elektron_octatrack.scd` | Buffer loading, allocation, acknowledgements, release, and sample bindings |
| Granular, tape, reverse, resonant processing | `brahma/sc/05_sampler_creatures*.scd`, `14_stem_voices.scd` | Expose the appropriate live/offline controls consistently |
| Pattern editing and commands | `brahma/web/public/instrument/pattern.js` | Sample and slice references per event, arrangement, persistence |
| Authenticated control and live scheduling | `brahma/web/public/workbench/`, `31_live_gateway.scd` | Reuse session/approval boundaries and extend the event contract |
| Drums | Golem (`brahma/sc/15_*`, web Golem surface) | Shared transport and saved routing with sample tracks |
| Offline production | Forge and Brahma NRT renderers | Render the same saved sample arrangement used in performance |
| Broadcasting | AETHER | Optional downstream use of completed output; not required to compose |

## Proposed working behavior

1. Add local songs or a playlist manifest. Playlist entries describe selections;
   missing audio remains an explicit unresolved item. A streaming URL is not
   assumed to be a downloadable audio file.
2. Audition a waveform and set start/end points or evenly divided slices. Keep
   manual editing first; automatic onset slicing can add suggestions later.
3. Bind slices to pads or tracks. Audition the original and processed sound.
   Expose pitch, playback rate, loop, reverse, grain controls, envelopes, and
   routing only where their engine behavior exists and is measured.
4. Sequence those slices with Golem and other Brahma voices on one transport.
   Preserve source tempo and clip timing separately from project tempo. Distinct
   pitch and time controls use a time-stretch voice; a playback-rate control alone
   must not be labeled independent pitch/time stretching.
5. Save a session with source hashes, relative asset references, slice boundaries,
   pattern events, tempo, routing, processing parameters, and random seeds.
   Reopening must report missing assets and restore the actual playable state.
6. Render a track or separate stems with a receipt tying output to the saved
   session. Preserve input files and earlier takes; do not overwrite by basename.

Source audio and personal library metadata stay in the existing private media
workflow. Git contains code, schemas, synthetic fixtures, and sanitized evidence.
Existing provenance can record source information; recognition or processing
intensity does not establish a publication status.

## Implementation approaches

| Approach | Advantage | Limitation |
| --- | --- | --- |
| Extend the existing instrument and authenticated workbench with one shared sample/event contract | Reuses sequencer, modular engine, drums, and safety controls | Requires repairing the current UI-to-engine and persistence gaps |
| Forge batch processing first, then manual import into an external DAW | Fast route to processed album material using working NRT tools | Does not satisfy playing and sequencing samples inside this synth |
| Build a separate sampler application | Independent interface | Duplicates the existing transport, session, and engine integrations |

Recommendation: the first approach, with Forge as its file-processing backend.
The browser load/save milestone extends the existing instrument with a shared
live/offline WebAudio renderer. Native controls now connect it to Forge's measured
background renders; immediate live-rack parameter control is a later integration.
Do not create a second sampler application or make AETHER a prerequisite.

## First acceptance slice

One supplied audio file becomes eight editable chops. A performer can audition
them, play them, sequence them with a Golem drum pattern, route them through one
existing transformation, save, reopen, and export an audible WAV. A real engine
acknowledgement and measured output are required; an open socket or successful
HTTP response is insufficient.

Verify with a synthetic stereo fixture first, then with the performer's selected
song for musical acceptance. Preserve exact slice boundaries and source hashes
across save/reopen. Verify stop releases voices and buffer replacement cannot
overwrite the source or leave the previous sample sounding.

The first slice does not require album-wide AI generation, automatic downloading,
cloud deployment, paid providers, or stem separation. Later album organization
builds on saved sessions and shared source identities.
