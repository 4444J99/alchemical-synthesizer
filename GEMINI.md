# Alchemical Synthesizer (Brahma) - Instructional Context

## Project Overview
The **Alchemical Synthesizer**, also known as the **Brahma Meta-Rack**, is a modular synthesis organism designed to **absorb**, **mutate**, and **re-express** the identities of other systems. It is not a fixed instrument but a parasitic–symbiotic apparatus whose identity is contingent on contact.

### Core Philosophy
- **Absorption:** Ingesting external sonic DNA through contact.
- **Mutation:** Antagonistic recombination of captured traits.
- **Fusion:** Binding multiple identities into a "perfect form."
- **Evolution:** Geometric growth in complexity via non-destructive stacking.

### Main Technologies
- **SuperCollider (SC):** High-fidelity DSP engine, trait registries, and state machines.
- **Pure Data (Pd):** Performance interface, virtual patching, and macro-control.
- **OSC:** Bidirectional communication between the UI (Pd) and the Engine (SC).
- **Python:** Automated specimen validation and dataset management.

---

## Architecture & Infrastructure

### 1. The Brahma metaRack
The macro-container that provides global timing, energy budgets, and the virtual backplane for inter-module infection.
- **Backplane:** Simulated I2C-style bus (`BRIDGE__DOMAIN_ROUTER__v1`) for 32-byte metadata transfer.
- **Registry:** Managed by **Adam Kadmon**, the ontological integrator that enforces canonical trait schemas.

### 2. The 7-Stage Organism Model
Every primary module (e.g., **Relinquished**) adheres to a strict stage specification:
1.  **IA (Input Assimilation):** Normalization and protection.
2.  **EG (Equip Gating):** Single-equip constraint state machine.
3.  **BC (Binding Core):** Signal capture and "wearing."
4.  **AE (Analysis Extraction):** Spectral and temporal trait derivation.
5.  **TE (Transmutation Engine):** Operator-based transformation.
6.  **PR (Protection/Reflection):** Sacrificial buffering and retaliation.
7.  **RR (Release Router):** Final routing and bypass logic.

### 3. Key Organisms
- **Proteus:** The Form-Knower; perfect observation and high-fidelity emulation.
- **Typhon:** The Accumulator; multiplicative stacking of cumulative traits.
- **Janus:** The Gate; dual-faced concurrency and arbitration between worlds.
- **Agent Smith:** Deterministic signal intelligence; homogeneity enforcement.
- **Ditto:** The Morphic Substrate; imitation under imperfect cognition.
- **Sampler Creatures:** Mnemosyne (Archive), Protean Hound (Fragments), Chrysalid Siren (Vocals), Ossuary Monk (Impact), Janiform Child (Time).

---

## Building and Running

### 1. Booting the System
1.  **Launch SuperCollider.**
2.  **Open and Execute `brahma/sc/loader.scd`.** This script loads all SynthDefs, Classes (Adam Kadmon, FSAP, BridgeRouter), and operational engines in the correct order.
3.  **Launch Pure Data.**
4.  **Open `brahma/pd/main.pd`.** This is the master patching surface.

### 2. Operational Workflows
- **Absorption Ritual:** Feed audio into a module's IA stage, trigger an EQUIP pulse, and observe the trait extraction in the AE stage.
- **A/B Testing:** Use `brahma/sc/12_test_bench.scd` to run side-by-side comparisons of different mutation algorithms.
- **NRT Rendering:** Use `brahma/sc/13_nrt_renderer.scd` for high-volume offline specimen generation.

### 3. Automation & Validation
- **Validate Audio:** Run `python3 forge/validate_audio.py path/to/specimen.wav` to ensure the viability of a recorded specimen.

---

## Development Conventions

### Coding Style
- **SC Side:** Use snake_case for SynthDef arguments and CamelCase for Class names. Ensure all SynthDefs include an `outBus` and `inBus` for modular routing.
- **Pd Side:** Follow the 14HP/18HP/24HP faceplate standardization using the provided abstractions (`faceplate_14.pd`, etc.).
- **Metadata:** All inter-module communication must conform to the 32-byte `MetaPacket` structure defined in the Bridge protocol.

### Invariants
- **Single-Equip:** A module core may only bind one donor identity at a time.
- **Lossless Stacking:** In FSAP-compliant modules, no prior absorption may be degraded during accumulation.
- **Safety First:** The `IMMUNE` governor must be the final node before any output to prevent recursive collapse.

---

## TODO / Roadmap
- [ ] Implement actual `FluidBuf` analysis in `MetricCollector`. (blocked: Fluid Corpus Manipulation UGens not installed on this host)
- [x] Expand `AdamKadmon` to include a full JSON-based contract system. (brahma/sc/AdamKadmon.sc: loadContract, contractNames, validateTraitMap with contract-scoped ranges)
- [x] Create 3D visualizations for trait maps in a browser-based overlay. (brahma/web/public/tree/tree-renderer.js: radar-chart trait-map overlay on organism pick)

<!-- ORGANVM:AUTO:START -->
## System Context (auto-generated — do not edit)

**Organ:** ORGAN-II (Art) | **Tier:** standard | **Status:** GRADUATED
**Org:** `organvm-ii-poiesis` | **Repo:** `alchemical-synthesizer`

### Edges
- **Produces** → `unspecified`: creative-artifact
- **Consumes** ← `ORGAN-I`: theory-artifact

### Siblings in Art
`core-engine`, `performance-sdk`, `example-generative-music`, `metasystem-master`, `example-choreographic-interface`, `showcase-portfolio`, `archive-past-works`, `case-studies-methodology`, `learning-resources`, `example-generative-visual`, `example-interactive-installation`, `example-ai-collaboration`, `docs`, `a-mavs-olevm`, `a-i-council--coliseum` ... and 16 more

### Governance
- Consumes Theory (I) concepts, produces artifacts for Commerce (III).

*Last synced: 2026-10-24T14:40:54Z*

## Active Handoff Protocol

If `.conductor/active-handoff.md` exists, **READ IT FIRST** before doing any work.
It contains constraints, locked files, conventions, and completed work from the
originating agent. You MUST honor all constraints listed there.

Handoff files should include metadata at the top:
- `created_at`: UTC ISO-8601 timestamp
- `expires_at`: UTC ISO-8601 timestamp, normally within 48h of creation

If the handoff says "CROSS-VERIFICATION REQUIRED", your self-assessment will
NOT be trusted. A different agent will verify your output against these constraints.

## Session Review Protocol

At the end of each session that produces or modifies files:
1. Run `organvm session review --latest` to get a session summary
2. Check for unimplemented plans: `organvm session plans --project .`
3. Export significant sessions: `organvm session export <id> --slug <slug>`
4. Run `organvm prompts distill --dry-run` to detect uncovered operational patterns

Transcripts are on-demand (never committed):
- `organvm session transcript <id>` — conversation summary
- `organvm session transcript <id> --unabridged` — full audit trail
- `organvm session prompts <id>` — human prompts only


## System Library

Plans: 269 indexed | Chains: 5 available | SOPs: 81 active
Discover: `organvm plans search <query>` | `organvm chains list` | `organvm sop lifecycle`
Library: `meta-organvm/praxis-perpetua/library/`


## Active Directives

| Scope | Phase | Name | Description |
|-------|-------|------|-------------|
| system | any | prompting-standards | Prompting Standards |
| system | any | research-standards-bibliography | APPENDIX: Research Standards Bibliography |
| system | any | phase-closing-and-forward-plan | METADOC: Phase-Closing Commemoration & Forward Attack Plan |
| system | any | research-standards | METADOC: Architectural Typology & Research Standards |
| system | any | sop-ecosystem | METADOC: SOP Ecosystem — Taxonomy, Inventory & Coverage |
| system | any | autonomous-content-syndication | SOP: Autonomous Content Syndication (The Broadcast Protocol) |
| system | any | autopoietic-systems-diagnostics | SOP: Autopoietic Systems Diagnostics (The Mirror of Eternity) |
| system | any | background-task-resilience | background-task-resilience |
| system | any | cicd-resilience-and-recovery | SOP: CI/CD Pipeline Resilience & Recovery |
| system | any | community-event-facilitation | SOP: Community Event Facilitation (The Dialectic Crucible) |
| system | any | context-window-conservation | context-window-conservation |
| system | any | conversation-to-content-pipeline | SOP — Conversation-to-Content Pipeline |
| system | any | cross-agent-handoff | SOP: Cross-Agent Session Handoff |
| system | any | cross-channel-publishing-metrics | SOP: Cross-Channel Publishing Metrics (The Echo Protocol) |
| system | any | data-migration-and-backup | SOP: Data Migration and Backup Protocol (The Memory Vault) |
| system | any | document-audit-feature-extraction | SOP: Document Audit & Feature Extraction |
| system | any | domain-architecture-and-dns | SOP: Domain Architecture & DNS Governance (The Concentric Circles) |
| system | any | dynamic-lens-assembly | SOP: Dynamic Lens Assembly |
| system | any | essay-publishing-and-distribution | SOP: Essay Publishing & Distribution |
| system | any | formal-methods-applied-protocols | SOP: Formal Methods Applied Protocols |
| system | any | formal-methods-master-taxonomy | SOP: Formal Methods Master Taxonomy (The Blueprint of Proof) |
| system | any | formal-methods-tla-pluscal | SOP: Formal Methods — TLA+ and PlusCal Verification (The Blueprint Verifier) |
| system | any | generative-art-deployment | SOP: Generative Art Deployment (The Gallery Protocol) |
| system | any | markdown-hygiene-and-linting | SOP: Markdown Hygiene and Linting |
| system | any | market-gap-analysis | SOP: Full-Breath Market-Gap Analysis & Defensive Parrying |
| system | any | mcp-server-fleet-management | SOP: MCP Server Fleet Management (The Server Protocol) |
| system | any | multi-agent-swarm-orchestration | SOP: Multi-Agent Swarm Orchestration (The Polymorphic Swarm) |
| system | any | network-testament-protocol | SOP: Network Testament Protocol (The Mirror Protocol) |
| system | any | open-source-licensing-and-ip | SOP: Open Source Licensing and IP (The Commons Protocol) |
| system | any | performance-interface-design | SOP: Performance Interface Design (The Stage Protocol) |
| system | any | pitch-deck-rollout | SOP: Pitch Deck Generation & Rollout |
| system | any | polymorphic-agent-testing | SOP: Polymorphic Agent Testing (The Adversarial Protocol) |
| system | any | promotion-and-state-transitions | SOP: Promotion & State Transitions |
| system | any | public-private-classification | SOP: Public/Private Classification |
| system | any | recursive-study-feedback | SOP: Recursive Study & Feedback Loop (The Ouroboros) |
| system | any | repo-onboarding-and-habitat-creation | SOP: Repo Onboarding & Habitat Creation |
| system | any | research-backend-routing | SOP: Research Backend Routing |
| system | any | research-to-implementation-pipeline | SOP: Research-to-Implementation Pipeline (The Gold Path) |
| system | any | security-and-accessibility-audit | SOP: Security & Accessibility Audit |
| system | any | session-as-seed | SOP: Session-as-Seed (The Black-Hole Geometry of Sessions) |
| system | any | session-self-critique | session-self-critique |
| system | any | smart-contract-audit-and-legal-wrap | SOP: Smart Contract Audit and Legal Wrap (The Ledger Protocol) |
| system | any | source-evaluation-and-bibliography | SOP: Source Evaluation & Annotated Bibliography (The Refinery) |
| system | any | stranger-test-protocol | SOP: Stranger Test Protocol |
| system | any | strategic-foresight-and-futures | SOP: Strategic Foresight & Futures (The Telescope) |
| system | any | styx-pipeline-traversal | SOP: Styx Pipeline Traversal (The 7-Organ Transmutation) |
| system | any | system-dashboard-telemetry | SOP: System Dashboard Telemetry (The Panopticon Protocol) |
| system | any | the-descent-protocol | the-descent-protocol |
| system | any | the-membrane-protocol | the-membrane-protocol |
| system | any | theoretical-concept-versioning | SOP: Theoretical Concept Versioning (The Epistemic Protocol) |
| system | any | theory-to-concrete-gate | theory-to-concrete-gate |
| system | any | triangulation-protocol | triangulation-protocol |
| system | any | typological-hermeneutic-analysis | SOP: Typological & Hermeneutic Analysis (The Archaeology) |

Linked skills: SOP-TRIADIC-REVIEW-PROTOCOL, cicd-resilience-and-recovery, continuous-learning-agent, evaluation-to-growth, genesis-dna, multi-agent-workforce-planner, promotion-and-state-transitions, quality-gate-baseline-calibration, repo-onboarding-and-habitat-creation, session-self-critique, structural-integrity-audit, the-membrane-protocol, triple-reference


**Prompting (Google)**: context 1M tokens (Gemini 1.5 Pro), format: markdown, thinking: thinking mode (thinkingConfig)


## Ecosystem Status

- **delivery**: 1/1 live, 0 planned
- **content**: 0/1 live, 0 planned
- **community**: 0/1 live, 0 planned

Run: `organvm ecosystem show alchemical-synthesizer` | `organvm ecosystem validate --organ II`


## Atomization Pipeline

Run `organvm atoms pipeline --write && organvm atoms fanout --write` to generate task queue.


## System Density (auto-generated)

AMMOI: 25% | Edges: 0 | Tensions: 0 | Clusters: 0 | Adv: 0 | Events(24h): 4365
Structure: 8 organs / 150 repos / 1654 components (depth 17) | Inference: 0% | Organs: META-ORGANVM:64%, ORGAN-I:53%, ORGAN-II:48%, ORGAN-III:55% +5 more
Last pulse: 2026-10-24T14:40:53 | Δ24h: vacuum | Δ7d: vacuum


## Dialect Identity (Trivium)

**Dialect:** AESTHETIC_FORM | **Classical Parallel:** Music | **Translation Role:** The Poetry — proves formal structures have sensory form

Strongest translations: III (structural), V (analogical), VI (analogical)

Scan: `organvm trivium scan II <OTHER>` | Matrix: `organvm trivium matrix` | Synthesize: `organvm trivium synthesize`


## Logos Documentation Layer

**Status:** MISSING | **Symmetry:** 0.5 (GHOST)

Nature demands a documentation counterpart. This formation maintains its narrative record in `docs/logos/`.

### The Tetradic Counterpart
- **[Telos (Idealized Form)](../docs/logos/telos.md)** — The dream and theoretical grounding.
- **[Pragma (Concrete State)](../docs/logos/pragma.md)** — The honest account of what exists.
- **[Praxis (Remediation Plan)](../docs/logos/praxis.md)** — The attack vectors for evolution.
- **[Receptio (Reception)](../docs/logos/receptio.md)** — The account of the constructed polis.

### Alchemical I/O
- **[Source & Transmutation](../docs/logos/alchemical-io.md)** — Narrative of inputs, process, and returns.



*Compliance: Implementation exists without record.*

<!-- ORGANVM:AUTO:END -->












## ⚡ Conductor OS Integration
This repository is a managed component of the ORGANVM meta-workspace.
- **Orchestration:** Use `conductor patch` for system status and work queue.
- **Lifecycle:** Follow the `FRAME -> SHAPE -> BUILD -> PROVE` workflow.
- **Governance:** Promotions are managed via `conductor wip promote`.
- **Intelligence:** Conductor MCP tools are available for routing and mission synthesis.