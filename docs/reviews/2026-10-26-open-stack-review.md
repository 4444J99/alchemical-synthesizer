# Open sampling and instrument stack — review snapshot, 2026-10-26

## Scope and status

The main-based hardening branch incorporates upstream through
`e27f020306273c697a6c7909ca1c7c4e3ea5e9c2`. Six additional PRs are open as a stack.
They contain substantial sampling, native donor processing and instrument work;
the next step is to reconcile and verify that existing implementation.

This review inventories all six heads, checks their review/CI records, follows
four material findings into the current source, and reproduces two PR102 failures
with its actual callbacks. It does not establish whole-stack browser, native
audio, perceptual or release acceptance. These findings remain open in the stack;
the main hardening branch does not silently include or merge those feature branches.

The public metadata snapshot began at **2026-10-26 17:50:37 UTC**. Exact heads,
checks, review timestamps, source hashes and the main history inventory are in
[history evidence](2026-10-26-history-evidence.json).

## Stack and available verification

| PR | Inspected head | Contribution | Base | Actions at this head |
|---|---|---|---|---|
| [97](https://github.com/4444J99/alchemical-synthesizer/pull/97) | `52b5760` | Sampling review and verification receipts | main | Full CI passed |
| [98](https://github.com/4444J99/alchemical-synthesizer/pull/98) | `2822695` | Import, chops, sequencing, portable projects and WAV export | PR97 | None observed |
| [99](https://github.com/4444J99/alchemical-synthesizer/pull/99) | `60d7ec7` | Native donor/module auditions and listening indexes | PR98 | None observed |
| [100](https://github.com/4444J99/alchemical-synthesizer/pull/100) | `3b971f8` | Playable song sketches and transformation controls | PR99 | None observed |
| [101](https://github.com/4444J99/alchemical-synthesizer/pull/101) | `0082092` | Original organisms and material-universe reconciliation | PR100 | None observed |
| [102](https://github.com/4444J99/alchemical-synthesizer/pull/102) | `de89004` | Material vessels, comparisons, controls and meters | PR101 | None observed |

PR97's full run is [40322074083](https://github.com/4444J99/alchemical-synthesizer/actions/runs/40322074083).
The other five inspected heads show Semgrep success and Sourcery skipped, which
do not constitute the repository's executable acceptance gates. The prior
`pull_request.branches: [main, master]` filter excluded stacked base branches.
The hardening branch removes that filter. Existing PR heads still need the updated
workflow and an actual triggering event; changing a workflow is not a retrospective pass.

## Findings that should block completion claims

### 1. Chop audition can change the engine underneath a running OSC transport

At PR98 head `2822695`, `sample-controls.js` calls `bridge.local()` to audition a
chop. In `instrument.js`, `localEngine()` changes the adapter without stopping the
running transport. A synth-only grid already playing through OSC can therefore
continue with a different backend when a local chop is auditioned.

This follows the [existing review finding](https://github.com/4444J99/alchemical-synthesizer/pull/98#discussion_r4377301888)
and remains present in the inspected source. The desired ownership rule must be
explicit: stop the sequencer before changing its engine, or audition locally while
leaving the sequencer's engine unchanged.

**Required regression:** Import a donor, start a synth-only grid through OSC,
audition a chop, and assert the selected rule at both transports. Verify that Stop
still owns every active voice. This review did not execute that full transport case.

### 2. Donor silence can permanently free a native generator before audio resumes

At PR99 head `60d7ec7`, `forge/assimilate.py` maps a generator's gate to donor-envelope
control bus 6. `32_donor_rack.scd` drops that envelope during pauses. A one-shot
ADSR generator with a freeing done action can finish its release and disappear
before the next donor phrase.

The wiring matches the [existing review finding](https://github.com/4444J99/alchemical-synthesizer/pull/99#discussion_r4377677460).
An output file with the expected total duration and a nonzero initial peak does
not prove the second phrase rendered.

**Required regression:** Use tone → silence longer than the generator release →
tone, then measure both tone windows. Hold a render-lifetime gate separately from
donor amplitude, or deliberately recreate the generator when the envelope resumes.
Native resumption behavior was not executed in this supplementary review.

### 3. A/B audition compares different time spans after editing a transformed chop

At PR102 head `de89004`, the comparison callback selects the original source's
retained slice for original audition and the current source's edited slice for
current audition. This confirms the [existing review finding](https://github.com/4444J99/alchemical-synthesizer/pull/102#discussion_r4380458712).

The isolated fixture uses original metadata **0–4 seconds** and a current chop
edited to **1–2 seconds**. Actual original audition requested duration **4 seconds**.
An A/B judgement is then confounded by different material, not just transformation.

**Required regression:** Both auditions use the selected current time range,
including any necessary source-time mapping, while original metadata remains
unchanged. Assert the requested ranges and test the audible result separately.

### 4. Vessel meters can remain zero during synth-only playback

At the same PR102 head, the controls retain a separate lazy renderer reference.
Synth-only Play initializes the instrument's renderer, while the meter callback
still sees the controls' uninitialized reference. This confirms the
[existing review finding](https://github.com/4444J99/alchemical-synthesizer/pull/102#discussion_r4380458718).

The exact callback returned **RMS 0 / peak 0** while the active fixture renderer
reported **RMS 0.4 / peak 0.7**. The controls had not requested the existing renderer.

**Required regression:** Start synth-only playback on a fresh page and observe
meter activity before any sample import/open action. Expose the existing renderer
without constructing an audio context merely for an idle animation frame.

## Executable evidence and integration order

The PR102 callback fixture was executed by the history reviewer and independently
rerun by the root reviewer. Both desired-contract assertions failed. Source bytes
were matched against the fetched Git object at the exact PR head; SHA-256:
`57fa77ff830907a54d7fa23bf996127adf1a09ec668ca94c96ede7ddc5b6a59b`.

The [reproduction record](2026-10-26-open-stack-reproduction.json) separates observed
values from expectations. The [manual probe](probes/pr102-callbacks.cjs) accepts the
inspected `sample-controls.js` as its argument and deliberately exits nonzero when
these contracts fail. It is review evidence, not part of the main branch's green
test count. Its DOM/audio stubs do not establish real-browser or audible acceptance.

Reconcile the stack against the hardened foundation, resolve these findings, then
run full native/browser/archive gates on each resulting head. Pay particular
attention to overlapping `server.js`, CI, smoke and README changes. Preserve human
playback authority, truthful measurement provenance and verified artifact completion
when combining the sampling UI with the existing workbench and Foundry.

The original goal remains useful: one donor enters, a selected organism transforms
it, the listener can make a fair before/after comparison, and a completed artifact
retains ownership and provenance. The current stack is progress toward that goal;
the acceptance sequence above is what makes the result assessable.
