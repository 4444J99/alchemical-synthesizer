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
