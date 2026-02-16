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
- **Pure Data** (Vanilla v0.54+) — optional, for performance UI and visual patching
- **Node.js** (v18+) — optional, for Visual Cortex web visualization

### Installation
```bash
git clone https://github.com/4444J99/alchemical-synthesizer.git
cd alchemical-synthesizer
```

### SuperCollider Class Files
The `.sc` class files must be installed for the SC class compiler:
```bash
# Find your SC Extensions directory (platform-dependent):
# In SuperCollider: Platform.userExtensionDir
# macOS default: ~/Library/Application Support/SuperCollider/Extensions/
# Linux default: ~/.local/share/SuperCollider/Extensions/

SC_EXT=$(sclang -e 'Platform.userExtensionDir.postln; 0.exit' 2>/dev/null | tail -1)

for f in AdamKadmon BridgeRouter FSAP BrahmaScale BrahmaMPE BrahmaModBus; do
    ln -s "$(pwd)/brahma/sc/${f}.sc" "${SC_EXT}/"
done
```
Then recompile the class library in SC IDE (Cmd+Shift+L).

### Running the Ritual
1.  Launch **SuperCollider** and evaluate `brahma/sc/loader.scd` (Cmd+Return).
    - Expected: `--- BRAHMA SYSTEM ONLINE ---`
    - A demo patch auto-plays: Prima Materia + MOIRAI melody + Euclidean rhythm + Lorenz modulation + reverb
2.  Launch **Visual Cortex** (optional):
    ```bash
    cd brahma/web && npm install && npm start
    ```
    - `http://localhost:3000` — real-time organism visualization
    - `http://localhost:3000/cortex` — Canvas web patching UI (module browser, drag-drop, cable routing)
    - `http://localhost:3000/golem` — Golem percussion web UI (sequencer, mixer, patchbay)
3.  Launch **Pure Data** (optional):
    - `brahma/pd/main.pd` — master control surface with OSC bridge
    - `brahma/pd/canvas/brahma_canvas.pd` — Pd-native visual patching via GOP abstractions

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
| Organisms (Proteus, Relinquished, Typhon, etc.) | 24 |
| Golem Percussion (drums, FX, LFO) | 11 |
| Make Noise Clones | 34 |
| Effects (FX) | 49 |
| Standard Modular | 58 |
| Elektron Machine Emulations | 11 |
| Generative Algorithms | 9 |
| Interaction Controllers | 9 |
| Infrastructure (patch bay, safety, arbitration) | 8 |
| **Total SynthDefs** | **223** |

### Infrastructure

- **Patch Bay**: Universal CV routing via BrahmaModBus (256-bus pool, audio/control rate)
- **CHRONOS**: Full-featured master sequencer (128 tracks, 8 scenes, morph, undo/redo, song mode)
- **Module Registry**: Dynamic SynthDef registration with OSC-addressable create/set/free lifecycle
- **Microtonality**: 16 built-in scales, Scala file import, arbitrary N-TET, custom ratios
- **MIDI/MPE**: 16-voice MPE with per-note expression, MIDI learn, clock sync
- **IMMUNE Governor**: Safety limiter deployed on hardware outputs
- **Presets**: Save/load/morph with project management and undo history
- **Recording**: Multi-track capture, punch-in/out, bounce, WAV export
- **Visual Cortex**: Real-time browser visualization via OSC-to-WebSocket bridge
- **PD Bridge**: Bidirectional SC↔PD communication via OSC (ports 57120/57121)

---

## Control Surfaces

The system offers three ways to interact, all connected via OSC:

| Surface | Technology | Entry Point |
| :--- | :--- | :--- |
| **SC IDE** | SuperCollider | `brahma/sc/loader.scd` |
| **Web Canvas** | Browser (p5.js) | `http://localhost:3000/cortex` |
| **PD Canvas** | Pure Data (GOP) | `brahma/pd/canvas/brahma_canvas.pd` |

The **Web Canvas** provides a Max/MSP-style module browser with drag-drop patching and cable routing. The **PD Canvas** uses Graph-On-Parent abstractions for Pd-native visual patching with a module palette, routing, and parameter control.

---

## Technology Stack

- **SuperCollider** (`brahma/sc/`): DSP engine, ~20,000 LOC across 60+ `.scd` files and 6 `.sc` classes
- **Pure Data** (`brahma/pd/`): Performance UI and visual patching, 12 patches (8 core + 4 canvas abstractions)
- **Node.js + p5.js** (`brahma/web/`): Visual Cortex organism viz, Canvas patching UI, Golem percussion UI (~3,000 LOC)
- **Python** (`tools/`): Audio specimen validation
- **OSC**: Bidirectional glue (ports 57120, 57121, 57122)

---

## Development Phases

| Phase | Name | Scope |
| :--- | :--- | :--- |
| **0** | Foundation | Infrastructure, organisms, classes, 7-stage signal path, safety governor |
| **1** | Expansion | 10 synthesis engines, 49 FX, modular suite, Make Noise clones, Elektron emulations, generative systems |
| **2** | Vivification | Module registry, voice manager, Cortex UI, DAEMON-CHRONOS bridge, presets, recording |
| **3** | Canvas (Web) | Browser-based visual patching — module browser, drag-drop canvas, cable routing, parameter editors |
| **3B** | Canvas (Pd) | Pd-native visual patching via GOP abstractions — brahma_module, brahma_route, brahma_palette, brahma_canvas |

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
