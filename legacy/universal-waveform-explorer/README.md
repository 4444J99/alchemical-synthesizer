# Aether Canvas — The Universal Waveform Explorer

[![CI](https://github.com/organvm-ii-poiesis/universal-waveform-explorer/actions/workflows/ci.yml/badge.svg)](https://github.com/organvm-ii-poiesis/universal-waveform-explorer/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/coverage-pending-lightgrey)](https://github.com/organvm-ii-poiesis/universal-waveform-explorer)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/organvm-ii-poiesis/universal-waveform-explorer/blob/main/LICENSE)
[![Organ II](https://img.shields.io/badge/Organ-II%20Poiesis-EC4899)](https://github.com/organvm-ii-poiesis)
[![Status](https://img.shields.io/badge/status-active-brightgreen)](https://github.com/organvm-ii-poiesis/universal-waveform-explorer)
[![TypeScript](https://img.shields.io/badge/lang-TypeScript-informational)](https://github.com/organvm-ii-poiesis/universal-waveform-explorer)


![CI](https://img.shields.io/github/actions/workflow/status/organvm-ii-poiesis/universal-waveform-explorer/ci.yml?branch=main&label=CI)
![License](https://img.shields.io/badge/license-MIT-blue)
![Organ](https://img.shields.io/badge/organ-II%20%C2%B7%20poiesis-blueviolet)
![Status](https://img.shields.io/badge/status-DESIGN__ONLY-lightgrey)
![Language](https://img.shields.io/badge/language-JavaScript-F7DF1E)

**A web-based, three-dimensional modular synthesizer that reframes sound design as the exploration of the universe's fundamental vibrations, inviting users to inhabit a personal celestial orrery where they discover, shape, and attune to waveform essences spanning quantum particles to heartbeats.**

---

## Table of Contents

1. [Vision](#1-vision)
2. [Solution Overview](#2-solution-overview)
3. [Technical Architecture](#3-technical-architecture)
4. [Installation and Setup](#4-installation-and-setup)
5. [Usage](#5-usage)
6. [Working Examples](#6-working-examples)
7. [Extended System](#7-extended-system)
8. [Testing and Quality](#8-testing-and-quality)
9. [Cross-References](#9-cross-references)
10. [Contributing](#10-contributing)
11. [License and Author](#11-license-and-author)

---

## 1. Vision

Every modular synthesizer ever built shares the same fundamental metaphor: electricity flows through wires from one box to another. The patch cable is the lingua franca of synthesis, and for half a century it has served well. But the patch cable is also a prison. It flattens a profoundly dimensional art form into a two-dimensional routing diagram. It forces the user to think like an electrician when they should be thinking like a composer, a painter, or an astronomer.

Aether Canvas asks a different question: what if we abandoned the cable metaphor entirely and replaced it with the only patching system the universe has ever needed — gravity?

The project begins from the observation that waveforms are not merely mathematical abstractions. They are the substrate of physical reality. The electromagnetic spectrum, the oscillation of a quartz crystal, the firing pattern of a neuron, the orbital period of a moon around its planet — all of these are waveforms, and all of them interact through the same fundamental forces: proximity, mass, attraction, resonance. A moon does not need a patch cable to modulate the tides. It simply orbits, and the modulation emerges from the relationship itself.

This is the core insight of Aether Canvas. Users do not connect modules with cables. They place celestial bodies in three-dimensional space and let orbital mechanics do the routing. An LFO is a moon. An oscillator is a planet. The master output is the sun at the center of everything. Modulation depth is not a knob setting — it is the distance between two orbiting bodies. Modulation rate is not a frequency parameter — it is orbital velocity. The entire interface is a living, breathing orrery that the user inhabits from the inside, flying through their own sound design as it plays.

The result is a synthesizer that is simultaneously more intuitive than any traditional modular system and more capable of producing emergent, organic textures. When every parameter relationship is a spatial relationship, and every spatial relationship is visible as orbital motion, the user develops a physical intuition for synthesis that no amount of reading signal-flow diagrams can provide.

This is synthesis as cosmic exploration. Every session is a voyage. Every patch is a solar system. Every sound is a discovery.

---

## 2. Solution Overview

### The Orrery Model

The user inhabits the center of an infinite three-dimensional space — their personal celestial orrery. At the gravitational center sits the Sun, which represents the master audio output. All sound ultimately flows toward it. Around the Sun, the user places celestial bodies that generate, shape, and transform audio. The background of the entire space is a dynamic nebula that visualizes the current audio output in real time: color maps to frequency content, brightness maps to amplitude, and turbulence maps to harmonic complexity.

### Orbital Patching

Traditional modular synthesizers use patch cables to create signal routes. Aether Canvas eliminates cables entirely. Instead, modulation relationships emerge from orbital mechanics:

- **Proximity** determines modulation depth. A moon (LFO) orbiting close to a planet (oscillator) produces deep modulation. Pull it farther away and the modulation becomes subtle.
- **Orbital speed** determines modulation rate. A fast-orbiting moon is a rapid tremolo; a slow orbit is a glacial sweep.
- **Gravitational capture** determines routing. When a body enters another body's gravitational field, the modulation relationship is automatically established. No menu diving, no cable dragging, no manual assignment.
- **Multi-body interactions** produce emergent complexity. Two moons orbiting the same planet create cross-modulation patterns that would require elaborate cable matrices in a traditional system but arise naturally here.

### Module Ecosystem (Celestial Bodies)

Each module type is represented by a distinct class of celestial object, making the sonic role of every element immediately legible from its visual form:

| Module | Celestial Form | Role |
|--------|---------------|------|
| **Master Audio Out** | The Sun | Central destination — all audio flows here |
| **OSC (Oscillator)** | Planet / Star | Primary audio source — sine, saw, square, triangle, wavetable |
| **LFO (Low Frequency Oscillator)** | Moon | Modulator — orbit speed controls rate, proximity controls depth |
| **Residue** | Nebula / Asteroid Field | Textured noise generator — dust clouds of filtered stochastic signal |
| **Nature** | Pulsar / Atom / Neuron | Models natural processes: heartbeat rhythms, synaptic firing, atomic decay |
| **Swarm** | Flock | Multi-particle flocking algorithms — dozens of micro-oscillators moving as one |
| **Lens** | Floating Portal | Device camera input — real-time optical flow analysis generates CV signals |
| **Compound** | Constellation | Pre-patched collections — entire sub-systems deployed as a single linked group |

The module ecosystem is designed for progressive disclosure. A beginner can place one Planet near the Sun and hear a tone. An advanced user can construct a system of dozens of interlocking bodies producing textures that rival dedicated hardware synthesizers.

---

## 3. Technical Architecture

### Rendering and Audio Pipeline

Aether Canvas is built on two browser-native foundations that require no plugins or installations:

- **WebGL** handles all three-dimensional rendering — the orrery space, celestial bodies, orbital trails, the nebula background, and all particle effects. The rendering pipeline is optimized for 60fps on mid-range hardware, with adaptive quality scaling for mobile devices.
- **Web Audio API** handles all synthesis, effects processing, and audio graph management. The target is sub-10ms audio latency from parameter change to audible result, achieved through careful AudioWorklet design and minimal main-thread audio processing.

The two systems are bridged by a shared state layer that translates spatial relationships (positions, velocities, distances) into audio parameters (frequencies, amplitudes, modulation indices) every frame. This bridge is the heart of the orbital patching system.

### Module System

Each celestial body is a self-contained module instance comprising three layers:

1. **Visual Layer** (WebGL): geometry, shaders, particle effects, orbital trail rendering, gravitational field visualization.
2. **Audio Layer** (Web Audio API): AudioWorklet nodes, parameter automation, internal signal routing.
3. **Physics Layer**: simplified n-body gravitational simulation that drives both the visual animation and the audio parameter mapping.

Modules register themselves with a central Orrery Controller that manages the physics simulation, resolves gravitational captures, and coordinates the visual-audio bridge.

### Camera and Input Pipeline

The Lens module uses **WebRTC / getUserMedia** to access the device camera. The video feed passes through a real-time optical flow analysis pipeline that extracts motion vectors, brightness deltas, and color centroids. These are converted into control-voltage-equivalent signals that can modulate any parameter in the system, enabling the user's physical environment to become part of the sound design.

Microphone input follows the same pipeline, allowing ambient sound to drive modulation through spectral analysis.

### Extended Dialectic Architecture

Beyond the core synthesizer, Aether Canvas implements a philosophical parameter system that governs macro-level behavior:

- **64-entry Dialectic Continuum Matrix**: oscillating dualities (e.g., Order-Chaos, Tension-Release, Dense-Sparse) mapped to floating-point values from -1.0 to +1.0. These continuously interpolate and drive high-level synthesis parameters.
- **32-entry Binary Exclusion Matrix**: strict boolean logic gates (e.g., Pitched/Unpitched, Rhythmic/Arrhythmic) that enforce hard either/or states in the audio graph.
- **15 Conditional Threshold States**: liminal metaphysical conditions that activate only when specific combinations of dialectic and binary values align — emergent behaviors that cannot be directly set, only discovered.
- **Dialectic-Binary 2:1 Interface Bridge**: the translation layer between the continuous dialectic space and the discrete binary space, ensuring coherent macro-behavior across both systems.

### Signal Processing Chain

The full internal signal chain for each audio path:

```
OSC --> Filter --> Drive --> Compressor --> Reverb --> Delay --> Glitch --> Granulator --> Vocoder --> Output (Sun)
```

Each stage is optional and bypassable. Effects modules appear as rings or halos around their parent body, with visual intensity reflecting wet/dry mix.

### Stochastic Mapping System

A procedural dice system (d4 through d1000) provides controlled randomness at every level of the architecture. Users can assign stochastic mappings to any parameter, creating patches that evolve unpredictably within defined bounds. The dice metaphor makes probability distributions tangible — a d4 produces coarse, lumpy randomness; a d1000 produces near-continuous smooth variation.

---

## 4. Installation and Setup

### Prerequisites

- Node.js 18+ (LTS recommended)
- A modern browser with WebGL 2.0 support (Chrome, Firefox, Safari, Edge)
- Optional: webcam and microphone for Lens module functionality

### Quick Start

```bash
git clone https://github.com/organvm-ii-poiesis/universal-waveform-explorer.git
cd universal-waveform-explorer
npm install
npm run dev
```

The development server starts at `http://localhost:5173`. Open it in your browser to enter the orrery.

### Production Build

```bash
npm run build
npm run preview
```

The production build outputs to `dist/` and can be deployed to any static hosting provider (Vercel, Netlify, GitHub Pages, Cloudflare Pages).

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_AUDIO_LATENCY_TARGET` | `10` | Target audio latency in milliseconds |
| `VITE_MAX_BODIES` | `64` | Maximum simultaneous celestial bodies |
| `VITE_PHYSICS_SUBSTEPS` | `4` | Gravitational simulation substeps per frame |
| `VITE_ENABLE_LENS` | `true` | Enable camera input for Lens module |

---

## 5. Usage

### Gesture Controls

Aether Canvas is designed for touch-first interaction, with full mouse and keyboard support:

| Gesture | Touch | Mouse | Keyboard | Action |
|---------|-------|-------|----------|--------|
| Rotate camera | One-finger drag | Left-click drag | Arrow keys | Orbit the viewpoint around the Sun |
| Fly through space | Pinch-to-zoom | Scroll wheel | `W` / `S` | Move toward or away from the center |
| Undo | Two-finger swipe left | — | `Cmd+Z` | Undo last action |
| Redo | Two-finger swipe right | — | `Cmd+Shift+Z` | Redo last undone action |
| Place module | Tap empty space | Right-click | `N` | Open the module palette |
| Select body | Tap body | Left-click body | `Tab` to cycle | Select a celestial body for parameter editing |
| Move body | Drag body | Left-click drag body | — | Reposition in 3D space (affects orbital patching) |

### Making Your First Sound

1. **Open Aether Canvas.** You start at the center of the orrery. The Sun (master output) glows at the origin.
2. **Place an Oscillator.** Tap empty space (or press `N`) and select "Planet (OSC)." A new planet appears in orbit around the Sun. You should immediately hear a tone — the planet's default waveform playing through the Sun.
3. **Shape the tone.** Select the planet and adjust its parameters: waveform shape, pitch, amplitude. Watch the planet's visual appearance change as you modify its sound.
4. **Add modulation.** Place a Moon (LFO) near your planet. It will be gravitationally captured and begin orbiting. You will hear the modulation immediately — a vibrato, a tremolo, or a filter sweep depending on the Moon's target parameter.
5. **Explore.** Drag the Moon closer for deeper modulation. Drag it farther for subtlety. Change its orbital speed. Add more bodies. The system rewards experimentation.

### Lens Module Workflow

The Lens module transforms your physical environment into a modulation source:

1. Place a Lens (Floating Portal) in the orrery.
2. Grant camera permission when prompted.
3. The portal displays a live feed from your device camera, processed through optical flow analysis.
4. Motion in the camera frame generates control signals. Wave your hand to modulate a filter. Walk past the camera to sweep a parameter. Point it at flickering light for rhythmic triggers.
5. The Lens's gravitational field determines which bodies it modulates, just like any other module. Move it close to a Planet to have your camera movements shape that oscillator's output.

---

## 6. Working Examples

### Example 1: Breathing Drone

Place a single Planet (OSC) with a sine waveform near the Sun. Add one Moon (LFO) with a very slow orbit (0.05 Hz equivalent). Set the Moon's modulation target to the Planet's amplitude. The result is a tone that breathes — swelling and fading like a slow respiration. The nebula background will pulse gently in sync, shifting between deep blue (quiet) and warm amber (loud).

### Example 2: Synaptic Percussion

Place a Nature module configured as "Neuron." It will emit sharp, irregular bursts modeled on synaptic firing patterns — not random, but governed by the refractory period and threshold dynamics of biological neurons. Route it through a short, bright Reverb halo. The visual: a pulsing neuron shape that fires brilliant white tendrils into the surrounding space with each burst.

### Example 3: Flocking Texture

Deploy a Swarm module (Flock). Dozens of micro-oscillators appear as a cloud of particles that move according to flocking algorithms — cohesion, separation, alignment. The collective motion produces a shimmering, evolving texture where no single voice dominates but the ensemble creates a rich, organic timbre. Add a Moon with fast orbit to modulate the flock's cohesion parameter, causing the swarm to alternately coalesce (unison tone) and scatter (dense cloud).

### Example 4: Camera-Driven Ambient

Place one Planet with a pad-like wavetable, a Residue module (Asteroid Field) for noise texture, and a Lens module. Point your camera at a window. Clouds passing, trees swaying, and light shifting will generate slow, organic modulation signals that shape both the pad and the noise. The patch essentially listens to the visual rhythm of the natural world and translates it into sound.

---

## 7. Extended System

### Dialectic Continuum Matrix

The 64-entry Dialectic Continuum Matrix provides macro-level control over the entire orrery's behavior through oscillating dualities. Each entry is a named axis with a floating-point value between -1.0 and +1.0:

| Example Axis | -1.0 Pole | +1.0 Pole | Audio Effect |
|-------------|-----------|-----------|-------------|
| Order-Chaos | Strict quantization, locked orbits | Free phase, erratic trajectories | Rhythmic precision vs. organic drift |
| Tension-Release | Dissonant intervals, high filter resonance | Consonant intervals, smooth filtering | Harmonic anxiety vs. resolution |
| Dense-Sparse | Maximum polyphony, close orbits | Minimal voices, distant bodies | Thick texture vs. open space |
| Ancient-Future | Lo-fi degradation, analog artifacts | Pristine clarity, digital precision | Vintage warmth vs. crystalline detail |

These values can be manually set, automated over time, or driven by stochastic mappings. They provide a "mood board" layer above the individual module parameters, allowing users to shape the overall character of a patch without touching individual bodies.

### Binary Exclusion Matrix

The 32-entry Binary Exclusion Matrix enforces hard categorical states. Unlike the dialectic axes, these are strict boolean decisions:

- **Pitched / Unpitched**: all oscillators either produce pitched tones or are replaced with noise-band equivalents.
- **Rhythmic / Arrhythmic**: all time-based modulation either locks to a master clock or runs freely.
- **Finite / Infinite**: patches either have a defined duration and fade to silence, or sustain indefinitely.

The binary matrix prevents contradictory states and ensures that certain fundamental sonic decisions remain coherent across the entire system.

### Dialectic-Binary 2:1 Interface Bridge

The bridge layer translates between the continuous dialectic space and the discrete binary space. When a dialectic axis crosses a defined threshold, it can trigger a binary state change. For example, if the Order-Chaos axis exceeds +0.8, the Rhythmic/Arrhythmic binary might flip to Arrhythmic. This creates a system where gradual drift can produce sudden categorical shifts — an analog of phase transitions in physics.

### Conditional Threshold States

The 15 Conditional Threshold States are emergent conditions that activate only when specific combinations of dialectic values and binary states align simultaneously. They cannot be directly enabled; they must be discovered through exploration. Examples include states where the system begins generating entirely new timbres not present in any individual module, or where orbital mechanics become temporarily inverted (repulsion instead of attraction), or where the nebula background begins driving the audio rather than visualizing it.

These threshold states are the system's hidden rewards — moments of genuine surprise that emerge from the interaction of well-defined rules.

### Procedural Event Sequencer

The Procedural Event Sequencer engine generates time-structured events (note triggers, parameter changes, module spawns) according to probabilistic grammars. It interfaces with the stochastic mapping system (d4 through d1000) to produce sequences that are neither random nor deterministic but occupy the fertile territory between — structured enough to feel intentional, varied enough to remain engaging across extended listening.

### Agent Waveform Models

Agent waveform models are autonomous synthesis personalities that can inhabit any module. When an agent is assigned to a Planet, for instance, the Planet begins making its own decisions about pitch, timbre, and motion within bounds defined by the user. Agents observe the state of the full orrery and respond to it, creating a system where the synthesizer collaborates with the user rather than merely obeying.

---

## 8. Testing and Quality

### Test Strategy

```bash
npm run test              # Unit tests (Vitest)
npm run test:e2e          # End-to-end browser tests (Playwright)
npm run test:audio        # Audio pipeline latency and correctness benchmarks
npm run lint              # ESLint + Prettier check
```

### Quality Gates

- All WebGL rendering must maintain 60fps on a 2020-era mid-range laptop.
- Audio latency from parameter change to audible output must remain below 10ms.
- Gravitational simulation must conserve energy within 0.1% per 1,000 frames (no orbital drift accumulation).
- All modules must gracefully degrade when WebGL context is lost and restored.
- Lens module must function without camera permission (falls back to procedural signal generation).

### Accessibility

- Full keyboard navigation for all module placement and parameter editing.
- Screen reader announcements for module state changes and orbital captures.
- High-contrast mode that replaces nebula background with solid dark field.
- Reduced motion mode that freezes orbital animation while preserving audio behavior.

---

## 9. Cross-References

### ORGAN II Repositories

This project sits within **ORGAN II (Poiesis)** — the art, generative systems, and experiential design organ. Related repositories:

| Repository | Relationship |
|-----------|-------------|
| [`metasystem-master`](https://github.com/organvm-ii-poiesis/metasystem-master) | ORGAN II flagship: metasystem theory and generative architecture |
| [`a-mavs-olevm`](https://github.com/organvm-ii-poiesis/a-mavs-olevm) | Generative art exhibition and experiential design |
| [`creative-coding--visual-algorithms`](https://github.com/organvm-ii-poiesis/creative-coding--visual-algorithms) | Visual algorithm library — shared rendering patterns |
| [`generative-art--parameter-spaces`](https://github.com/organvm-ii-poiesis/generative-art--parameter-spaces) | Parameter space exploration — conceptual sibling |
| [`interactive-art--audience-systems`](https://github.com/organvm-ii-poiesis/interactive-art--audience-systems) | Audience interaction patterns — Lens module lineage |
| [`sound-design--synthesis-engines`](https://github.com/organvm-ii-poiesis/sound-design--synthesis-engines) | Synthesis engine research — direct technical ancestor |

### System Context

Aether Canvas draws from and contributes to the broader eight-organ system:

- **ORGAN I (Theoria)**: The dialectic continuum matrix and binary exclusion matrix are implementations of ontological frameworks developed in ORGAN I's epistemology research, particularly [`recursive-engine--generative-entity`](https://github.com/organvm-i-theoria/recursive-engine--generative-entity).
- **ORGAN III (Ergon)**: Product packaging and distribution strategy for a potential commercial release lives in ORGAN III.
- **ORGAN IV (Taxis)**: Orchestration governance and cross-organ dependency validation.
- **ORGAN V (Logos)**: Public process essays documenting the design philosophy and development journey at [`public-process`](https://github.com/organvm-v-logos/public-process).

---

## 10. Contributing

Aether Canvas is currently in the **DESIGN_ONLY** phase. The specification and architecture are being refined before implementation begins. Contributions at this stage are welcome in the following forms:

1. **Design feedback**: open an issue describing your response to the orrery model, orbital patching concept, or module ecosystem design.
2. **Technical feasibility analysis**: if you have deep experience with WebGL performance, Web Audio API latency optimization, or real-time physics simulation in the browser, your expertise is invaluable.
3. **Sound design perspective**: if you are a practicing sound designer or synthesist, we want to know whether this interaction model resonates with your creative workflow.
4. **Accessibility review**: input on how to make a 3D spatial audio tool genuinely accessible.

When implementation begins, the project will follow standard open-source practices:

- Fork the repository and create a feature branch.
- Write tests for new functionality.
- Ensure all quality gates pass (`npm run test && npm run lint`).
- Submit a pull request with a clear description of the change and its motivation.

Please read `CONTRIBUTING.md` (forthcoming) and `CODE_OF_CONDUCT.md` before participating.

---

## 11. License and Author

**License:** MIT

**Author:** [@4444j99](https://github.com/4444j99)

This repository is part of the **Eight-Organ System** — a creative-institutional architecture coordinating 81 repositories across 8 GitHub organizations:

| Organ | Domain | Organization |
|-------|--------|-------------|
| I | Theory | [`organvm-i-theoria`](https://github.com/organvm-i-theoria) |
| **II** | **Art** | [**`organvm-ii-poiesis`**](https://github.com/organvm-ii-poiesis) |
| III | Commerce | [`organvm-iii-ergon`](https://github.com/organvm-iii-ergon) |
| IV | Orchestration | [`organvm-iv-taxis`](https://github.com/organvm-iv-taxis) |
| V | Public Process | [`organvm-v-logos`](https://github.com/organvm-v-logos) |
| VI | Community | [`organvm-vi-koinonia`](https://github.com/organvm-vi-koinonia) |
| VII | Marketing | [`organvm-vii-kerygma`](https://github.com/organvm-vii-kerygma) |
| Meta | Governance | [`meta-organvm`](https://github.com/meta-organvm) |

---

<sub>Part of the ORGAN II (Poiesis) collection. Sound is the shape of time vibrating through space.</sub>
