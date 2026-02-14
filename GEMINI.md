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
- **Validate Audio:** Run `python3 scripts/validate_audio.py path/to/specimen.wav` to ensure the viability of a recorded specimen.

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
- [ ] Implement actual `FluidBuf` analysis in `MetricCollector`.
- [ ] Expand `AdamKadmon` to include a full JSON-based contract system.
- [ ] Create 3D visualizations for trait maps in a browser-based overlay.
