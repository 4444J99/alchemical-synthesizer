# Native SuperCollider reconciliation

Scope: complete the existing crash recovery after parallel PRs86/87 landed, retaining their provenance/transmutation/backplane APIs. No new paid services.

Observed current-main defects: the private headless receive-port fix was omitted; reconciled AdamKadmon/BridgeRouter/TransmutationEngine source could not compile; native JSON scalar strings bypassed typed schema fields. Installed class links still pointed at that reconciled worktree.

Changes: restore the sandbox receive-port fix; use native class state/initClass and correct method/variable syntax; retain provenance logging, directory contract loading, peer health, and transmutation operators; decode typed JSON range/boolean fields; preserve measurement proof only for an unchanged same-substrate identity. Correct loader contract path. Native harness selects this checkout's classes without loading a conflicting installed copy and retains FluCoMa.

Validation: full147/147 web suite, zero skips; native Phase A metrics/contracts/FSAP; real FluCoMa1.0.10 Buffer analysis and stereo8192-frame bound; new class-runtime checks for provenance, JSON types, nested transforms, stale-proof rejection, peer status and TTL expiry. Run native tests serially on private ports. Independent review performed; important stale-evidence and loader-path findings corrected.

Ruling: keep canonical trait keys and substrate axis labels from the parallel implementation. Non-audio contracts retain their configured measured-evidence requirement. Changed transmutation output is a proxy until remeasured and cannot reuse donor evidence for FSAP acceptance. This does not claim live multi-host or full artistic transmutation acceptance.

Preservation: retain the original recovery worktree. Switch installed Brahma source links only after this source is pushed and native tests pass, then verify IDE class compilation. PR88 owns integration; report merged, installed, and observed separately.
