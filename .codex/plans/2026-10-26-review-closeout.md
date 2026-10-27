# Sampling and vessel review closeout

Goal: resolve the six open review findings on the owned sampling stack, verify
the integrated result, and publish it through the existing PR and merge rails.

- Reproduce the original/current chop and synth-only meter defects in a real
  browser; preserve retained slice metadata and avoid creating idle audio contexts.
- Reproduce the chop-pad transport/engine switch defect and stop transport before
  a pad changes engines.
- Verify donor-gated generator lifecycle with a source containing a silent gap;
  preserve donor dynamics without prematurely freeing an ADSR voice.
- Correct the two historical verification records from observed source evidence,
  keeping their prior measurements distinct from any new run.
- Run implicated browser, Node, Python and native checks, independently review
  the changed behavior, publish and submit the verified head. Keep original audio,
  the unrelated hardening branch and stash, and the retained checkout intact.

## Observed review fixes

The six findings in PRs #97–#99 and #102 were checked against source. A/B
audition uses the selected current chop's range without mutating the retained
original; synth-only vessels read the active renderer without starting audio
while idle. A chop stops an OSC transport before switching, while an already
local loop keeps playing. Three browser regressions failed before the fixes;
the local-loop preservation regression caught and corrected an overbroad stop.

The installed SuperCollider silent-gap regression failed before the donor gate
fix and passed afterward for Prima Materia and Ouroboros: both resume after a
1.6-second pause and follow the silent portion. The full catalogue's earlier
measurements remain historical, not a rerun of the revised rack. Reconstructed
fixture audio was byte-identical to the retained original (SHA-256
`8f4ba3ecae02b84d95199eb1901c8cea8fbb761ae87eae11f11d3a7a72eec39d`).
The browser receipt now specifies its working directory.

The independent review also found that comparison reuse checked definition and
source hashes but not the renderer. Comparisons now reject mismatched or missing
native-rack and assimilation implementation hashes; historical audio remains
available as historical evidence. A focused regression failed before the check
and passed afterward, including rejection of the retained older renderer.

Fresh verification: web unit suite 174 passed with one opt-in skip; browser E2E
20 passed; material/assimilation/sketch Python suite 29 passed including both
installed-native tests; strict smoke 107 passed. Details and review disposition
stay in this owner; private audio remains in the retained checkout.
