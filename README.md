# Alchemical Synthesizer (Brahma)

![License](https://img.shields.io/github/license/4444J99/alchemical-synthesizer)
![Stars](https://img.shields.io/github/stars/4444J99/alchemical-synthesizer)
![Issues](https://img.shields.io/github/issues/4444J99/alchemical-synthesizer)
![Last Commit](https://img.shields.io/github/last-commit/4444J99/alchemical-synthesizer)

> **The Brahma Meta-Rack**: A modular alchemical synthesizer designed to absorb, mutate, and re-express the identities of other systems.

---

## Motivation

Traditional synthesizers are fixed voices. The **Alchemical Synthesizer** is a parasitic-symbiotic apparatus. It acquires sonic DNA through contact, records structural traits rather than surface timbre, and recombines those traits under systemic stress.

Modelled after **Rogue (X-Men)** and **The Thing (John Carpenter)**, this instrument is not a tool, but an ethics of contamination.

---

## Architecture: The 7-Stage Organism

Every module in the Brahma Meta-Rack adheres to a strict biological signal path:

```mermaid
graph LR
    IA[Assimilation] --> EG[Gating]
    EG --> BC[Binding Core]
    BC --> AE[Extraction]
    AE --> TE[Transmutation]
    TE --> PR[Protection]
    PR --> RR[Release]
```

1.  **IA (Input Assimilation):** Normalization and protection.
2.  **EG (Equip Gating):** Single-equip constraint state machine.
3.  **BC (Binding Core):** Signal capture and "wearing."
4.  **AE (Analysis Extraction):** Spectral and temporal trait derivation.
5.  **TE (Transmutation Engine):** Operator-based transformation.
6.  **PR (Protection/Reflection):** Sacrificial buffering and retaliation.
7.  **RR (Release Router):** Final routing and bypass logic.

---

## Quick Start

### Prerequisites
- **SuperCollider** (v3.13+)
- **Pure Data** (Vanilla v0.54+) — optional, for performance UI
- **Node.js** (v18+) — optional, for Visual Cortex web visualization

### Installation
```bash
git clone https://github.com/4444J99/alchemical-synthesizer.git
cd alchemical-synthesizer
```

### SuperCollider Class Files
The `.sc` class files must be installed for the SC class compiler:
```bash
# Find your SC Extensions directory:
# In SuperCollider: Platform.userExtensionDir
# Then symlink the class files:
ln -s $(pwd)/brahma/sc/AdamKadmon.sc ~/Library/Application\ Support/SuperCollider/Extensions/
ln -s $(pwd)/brahma/sc/BridgeRouter.sc ~/Library/Application\ Support/SuperCollider/Extensions/
ln -s $(pwd)/brahma/sc/FSAP.sc ~/Library/Application\ Support/SuperCollider/Extensions/
ln -s $(pwd)/brahma/sc/BrahmaScale.sc ~/Library/Application\ Support/SuperCollider/Extensions/
ln -s $(pwd)/brahma/sc/BrahmaMPE.sc ~/Library/Application\ Support/SuperCollider/Extensions/
ln -s $(pwd)/brahma/sc/BrahmaModBus.sc ~/Library/Application\ Support/SuperCollider/Extensions/
```
Then recompile the class library in SC IDE (Cmd+Shift+L).

### Running the Ritual
1.  Launch **SuperCollider** and evaluate `brahma/sc/loader.scd` (Cmd+Return).
    - Expected: `--- BRAHMA SYSTEM ONLINE ---`
2.  Launch **Visual Cortex** (optional):
    ```bash
    cd brahma/web && npm install && npm start
    ```
    - Open `http://localhost:3000` to see real-time organism visualization
3.  Launch **Pure Data** and open `brahma/pd/main.pd` (optional, for performance UI).

---

## System Overview

### Organisms

| Name | Role | Philosophy |
| :--- | :--- | :--- |
| **Proteus** | The Form-Knower | High-fidelity emulation and observation |
| **Relinquished** | The Parasite | Single-source binding and reflection |
| **Typhon** | The Accumulator | Geometric growth through lossless stacking |
| **Agent Smith** | The Enforcer | Self-replicating signal homogeneity |
| **Ditto** | The Mimic | Identity duplication |
| **Golem** | Percussion Organism | Complete drum machine with sequencer, FX, and web UI |

### Synthesis Engines (10)

| Engine | Type | Character |
| :--- | :--- | :--- |
| **Prima Materia** | Subtractive | Classic analog-style with hard sync, ring mod, unison |
| **Azoth** | FM (4-operator) | DX7-class with 8 algorithms, per-operator envelopes |
| **Quintessence** | Additive (32 harmonics) | Spectral morphing with stretch/spread control |
| **Ouroboros** | Wavetable | Dual-table morphing with position FM |
| **Chrysopoeia** | Phase Distortion | CZ-style with 8 PD waveforms, DCW envelope |
| **Homunculus** | Physical Modeling | Pluck, bow, blow, modal, membrane models |
| **Buchlaeus** | West Coast | Complex oscillator with through-zero FM and wavefolding |
| **Logos** | Formant | 5-formant vowel synthesis with choir mode |
| **Tetramorph** | Vector | 4-corner XY crossfade with 6 source types |
| **Nebula** | Granular | Cloud synthesis with freeze, spray, and buffer grains |

### Module Counts

| Category | Count |
| :--- | :--- |
| Synthesis Engines | 10 |
| Make Noise Clones | ~30 modules |
| Effects (FX) | 46 |
| Standard Modular Modules | ~53 |
| Elektron Machine Emulations | ~15 |
| Generative Algorithms | 9 |
| Interaction Controllers | ~10 |
| **Total SynthDefs** | **~234** |

### Infrastructure

- **Patch Bay**: Universal CV routing via BrahmaModBus (256-bus pool, audio/control rate)
- **CHRONOS**: Full-featured master sequencer (128 tracks, 8 scenes, morph, undo/redo, song mode)
- **Microtonality**: 16 built-in scales, Scala file import, arbitrary N-TET, custom ratios
- **MIDI/MPE**: 16-voice MPE with per-note expression, MIDI learn, clock sync
- **IMMUNE Governor**: Safety limiter deployed on hardware outputs
- **Visual Cortex**: Real-time browser visualization via OSC-to-WebSocket bridge

---

## Technology Stack

- **SuperCollider** (`brahma/sc/`): DSP engine, ~18,000 LOC across 60+ files
- **Pure Data** (`brahma/pd/`): Performance UI, 8 patches
- **Node.js + p5.js** (`brahma/web/`): Visual Cortex browser visualization
- **Python** (`tools/`): Audio specimen validation
- **OSC**: Bidirectional glue (ports 57120, 57121, 57122)

---

## Development & Standards

This project follows the **Minimal Root Philosophy** and **Fidelity Stacking Absorption Protocol (FSAP)**.

- **DSP Core**: SuperCollider (`brahma/sc/`)
- **UI Surface**: Pure Data (`brahma/pd/`)
- **Ontology**: Adam Kadmon (`brahma/sc/AdamKadmon.sc`)

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation, coding conventions, and development tasks.

---

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](.github/CONTRIBUTING.md) for details on our "Ethics of Contamination" and development workflow.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

*"Mastery does not come from precision but from learning when to let the instrument consume you back."*
