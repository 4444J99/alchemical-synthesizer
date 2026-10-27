# Material vessels: observed implementation

Observed 2026-10-26 on macOS with installed Chrome, FFmpeg and SuperCollider.
Scope: the existing browser instrument and bounded Forge native render path.
This is local runtime evidence; it does not claim a deployed live rack or complete
acceptance of every original organism design. The [design contract](../design/mimicry-material-universe.md)
and [issue #95](https://github.com/4444J99/alchemical-synthesizer/issues/95) retain
the remaining organism behavior and integration requirements.

The catalogue and material-phase measurements below are historical observations
of the rack at the time of the original run. A subsequent review fix changed the
donor rack's generator-gate handling. That change was tested with a silent-gap
fixture for Prima Materia and Ouroboros; the complete catalogue and every
material phase have not been rerendered after that change.

## Working path

Five per-track glass vessels retain a module, base controls and optional material.
Water, silica, iron and air mix to 100%; solid/liquid/gas and influence resolve
through 26 explicit native profiles. Invalid, unsupported or stale requests leave
the current sound intact. The same model resolves in browser, service and Python.
Rendering applies a completed sound while the loop plays. Original/current chop
auditions and restoration preserve the original source. Project save/reopen keeps
material state, base and effective controls, model identity and source lineage.
Measured per-track waveform/energy drives the glass and clears after Stop.

## Native comparison evidence

Both runs retain the full 245-definition denominator. The first uses a two-second
synthetic probe; the second uses a retained two-second song excerpt. Each has an
original-audio player, native defaults, neutral material controls, repeated neutral,
and solid/liquid/gas water responses. Earlier interrupted evidence is retained.

| Measurement | Synthetic probe | Retained song excerpt |
|---|---:|---:|
| Native non-silent renders | 220 | 4 selected core organisms |
| Native silent renders | 4 | 0 selected |
| Definitions requiring coordinated patches | 21 | 21 listed |
| Material profiles rendered in each of five stages | 26 | 4 |
| Total retained native WAV results | 354 | 24 |

Four silent synthetic outputs remain `silent`: `chaos_oracle`,
`horologium_divider`, `pneuma_onset`, `daemon_clock_divider_random`.
The catalogue keeps unmapped modules and patch-dependent definitions visible.
All 26 mapped synthetic profiles produced retained native results in every
material stage. Nucleus is explicitly silent in gas: its native `freeze=0` state
records into the buffer with muted output. The other 25 gas renders are
non-silent; neutral, repeat, solid and liquid have 26 non-silent renders each.
The native CLI reports that silent gas result with exit 1; `stages_complete`
records that the comparison ran, and does not convert it into an audio pass.

For the song, Relinquished, Agent Smith and Typhon had zero repeated-neutral PCM
difference and nonzero differences in all three phases. Ditto's repeated neutral
already varied (RMS delta 0.047770); solid, liquid and gas deltas were 0.303437,
0.057576 and 0.046337. Its stochastic variation makes waveform difference alone
insufficient to establish an isolated material effect. Actual effective controls
and material receipts were independently checked. No run labels waveform change
as proof of memory, retained identity, trait copying or full original mimicry.

## Real browser and song

`tools/verify-material-vessels.cjs` opened the existing portable song sketch,
rendered Ditto with 50% water / 50% silica in each phase through authenticated
HTTP and installed SuperCollider, applied it while playing, and saved/reopened
each project. Three output hashes differed. Exported loop RMS was -19.60 dBFS
(solid), -26.03 dBFS (liquid), and -26.80 dBFS (gas). The input project hash stayed
unchanged and original restoration passed. Desktop 1440px and mobile 390px views
were visually inspected; the mobile page had no horizontal document overflow.
The step grid retains its own horizontal scrolling region.

The [sanitized machine receipt](material-vessels-20261026.json) contains hashes,
controls and measurements. Audio, projects, listening indexes and screenshots
remain private under ignored `forge/out/`; no media is published in this change.

## Verification commands

```sh
npm test --prefix brahma/web
npm run test:e2e --prefix brahma/web
python3 -m unittest tools.tests.test_materials tools.tests.test_material_comparison tools.tests.test_assimilate tools.tests.test_sketch
bash tools/smoke.sh --strict
```

Observed: web 174 passed / 1 opt-in installed-native skipped; browser 16 passed;
Python 26 passed / 1 opt-in installed-native skipped; strict smoke 107 passed,
0 failed, 0 skipped. The separate installed native runs above supplied runtime
evidence beyond those unit-suite skips.

Native integration is opt-in in ordinary unit runs and was measured separately
by the native comparison and real browser acceptance above. These measurements
establish signal rendering, versioned control response and portable state. Full
organism-specific fidelity/retention acceptance and live modular routing remain
separate requirements.

## Independent review and dispositions

One fresh whole-branch reviewer found three Important issues and no Critical or
Minor issues. All three were reproduced RED, then corrected and verified GREEN:
the reused-native check now reads the producer's canonical `overrides` field;
fractional mixtures and influence survive real-browser reopening and resaving
exactly; Nucleus persistence can switch its native integer playback/recording
gate instead of remaining invariant at the default. The model hash changed and
the native comparisons and real-song browser acceptance were refreshed. Earlier
private measurements remain retained. No second review replaced the regression
tests or final suite.

Execution decisions and their costs:

- The existing design approval authorized continuous implementation. The initial
  palette and per-vessel defaults are editable; a different artistic choice
  would require changing those defaults.
- Portable state uses optional fields and retains historical rendered recipes.
  Future schema migrations must preserve that distinction.
- Full original mimicry/memory/retention and coordinated patches remain with
  #95. Those behaviors need their own implementation and acceptance.
- Material properties remain an artistic model. Scientific simulation would
  require a separate DSP model.
- Local runtime evidence does not establish performer listening acceptance or
  production deployment. Both still need their own observation.
- The executor reran the full implicated suites after fixes; the reviewer did
  not launch duplicate services. Tests remain bounded behavioral evidence and
  cannot replace artistic acceptance.
