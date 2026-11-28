[![ORGAN-II: Poiesis](https://img.shields.io/badge/ORGAN--II-Poiesis-6a1b9a?style=flat-square)](https://github.com/organvm-ii-poiesis)
[![Status: Stub](https://img.shields.io/badge/status-stub-yellow?style=flat-square)](#roadmap)
[![API Docs Required](https://img.shields.io/badge/needs-API%20docs-orange?style=flat-square)](#planned-architecture)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

# audio-synthesis-bridge

[![CI](https://github.com/organvm-ii-poiesis/audio-synthesis-bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/organvm-ii-poiesis/audio-synthesis-bridge/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/coverage-pending-lightgrey)](https://github.com/organvm-ii-poiesis/audio-synthesis-bridge)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/organvm-ii-poiesis/audio-synthesis-bridge/blob/main/LICENSE)
[![Organ II](https://img.shields.io/badge/Organ-II%20Poiesis-EC4899)](https://github.com/organvm-ii-poiesis)
[![Status](https://img.shields.io/badge/status-active-brightgreen)](https://github.com/organvm-ii-poiesis/audio-synthesis-bridge)
[![Markdown](https://img.shields.io/badge/lang-Markdown-informational)](https://github.com/organvm-ii-poiesis/audio-synthesis-bridge)


**A protocol bridge between generative compositional systems and real-time audio synthesis engines, translating recursive structural descriptions into sound.**

> *Part of [ORGAN-II: Poiesis](https://github.com/organvm-ii-poiesis) — the art and generative creation organ of the [ORGANVM](https://github.com/meta-organvm) system.*

---

## Table of Contents

- [Artistic Purpose](#artistic-purpose)
- [Conceptual Approach](#conceptual-approach)
- [Theory Implemented](#theory-implemented)
- [Planned Architecture](#planned-architecture)
- [Protocol Design](#protocol-design)
- [Target Synthesis Backends](#target-synthesis-backends)
- [Related Work](#related-work)
- [Integration Points](#integration-points)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)
- [Author](#author)

---

## Artistic Purpose

Sound is the most temporal of all artistic media. Unlike a painting that persists on a canvas or a sculpture that occupies space indefinitely, a sonic event exists only in the moment of its unfolding. This temporal quality makes sound uniquely suited to express the recursive, self-referencing structures that define the ORGANVM theoretical framework — structures that are themselves processes rather than static objects.

The **audio-synthesis-bridge** exists to solve a fundamental translation problem: how do you move from an abstract generative description — a recursive grammar, a self-similar structure, an emergent compositional logic — into actual vibrating air? The generative systems in ORGAN-II (and the theoretical engines in ORGAN-I) produce structural descriptions of artistic works. These descriptions are rich in relational information — hierarchies, recursions, transformations, self-references — but they are not sound. They are blueprints for sound.

This bridge is the last mile between compositional thought and sonic reality. It receives structured descriptions from the ORGANVM generative pipeline and translates them into control messages, parameter streams, and scheduling instructions that synthesis engines can execute in real time. Without this bridge, the generative systems remain silent — producing beautiful structures that no one can hear.

The artistic goal is not merely functional audio output. It is the preservation of structural meaning through translation. When a recursive engine generates a self-similar phrase that references its own beginning, the listener should be able to *hear* that self-reference — as a timbral echo, a rhythmic callback, a harmonic return. The bridge must be semantically transparent: the listener's experience of the generated sound should reflect the structural intentions of the generative system that produced it.

This positions audio-synthesis-bridge as an interpretive layer — closer to a performer reading a score than a printer outputting text. The bridge makes artistic decisions about how abstract structure becomes audible form.

---

## Conceptual Approach

### The Translation Problem

Generative systems in the ORGANVM ecosystem produce output in a structural description language — trees of recursive relationships, annotated with metadata about intention, emphasis, self-reference, and transformation history. Audio synthesis engines, by contrast, expect concrete parameters: frequency values, amplitude envelopes, filter coefficients, scheduling timestamps.

The conceptual challenge is mapping between these two representations without losing the information that makes generative output interesting. A naive approach — flattening the recursive structure into a linear sequence of note events — discards precisely the relational richness that distinguishes generative art from random number generation.

### Semantic Preservation

The bridge operates on a principle of **semantic preservation**: every structurally meaningful relationship in the input description should have an audible correlate in the output sound. This does not mean a one-to-one mapping (which would be sonification, not music). It means that the bridge maintains a **correspondence table** between structural features and sonic parameters, and this table is itself configurable — it is part of the artistic voice of any given piece.

For example, a recursive self-reference might map to:

- **Timbral quotation**: the referenced passage returns with the same spectral characteristics
- **Temporal echo**: the referenced passage returns at a proportional time offset
- **Harmonic memory**: the referenced passage's harmonic content influences the current moment's chord voicing
- **Dynamic emphasis**: the moment of self-reference is marked by a change in loudness or density

Which mapping is chosen depends on the aesthetic context. The bridge provides all of these as configurable strategies, and new strategies can be registered as plugins.

### Real-Time Constraint

The bridge is designed for real-time operation. Generative systems may produce structural descriptions faster than real time (pre-computing an entire piece) or in real time (generating the next structural unit as the previous one sounds). The bridge must handle both modes, buffering when the generator is ahead and requesting more material when the generator falls behind.

This real-time constraint shapes the architecture fundamentally. The bridge cannot perform global optimization over the entire piece — it must make locally optimal decisions about how to render each structural unit, informed by a sliding window of context. This constraint is itself artistically interesting: it introduces a kind of bounded rationality into the rendering process, analogous to how a human performer makes interpretive decisions in the moment rather than computing the globally optimal interpretation.

---

## Theory Implemented

The audio-synthesis-bridge draws on theoretical foundations from ORGAN-I, particularly:

- **[recursive-engine](https://github.com/organvm-i-theoria/recursive-engine--generative-entity)** — The core recursive generation framework. The bridge receives output from recursive-engine's structural description format and must understand its recursion depth annotations, self-reference pointers, and transformation histories. The bridge is, in a sense, the "runtime" for recursive-engine's "compiled" output in the audio domain.

- **[organon-noumenon--ontogenetic-morphe](https://github.com/organvm-i-theoria/organon-noumenon--ontogenetic-morphe)** — The ontological framework that defines what constitutes a "thing" in the ORGANVM system. The bridge must understand ORGANVM's ontological categories to correctly interpret structural descriptions: when a generative system says "this phrase *is* a transformation of that phrase," the bridge needs the ontological framework to understand what kind of identity relationship "is" denotes and how to render it sonically.

- **[metasystem-master](https://github.com/organvm-ii-poiesis/metasystem-master)** — The ORGAN-II flagship repository that coordinates all generative subsystems. The audio-synthesis-bridge registers with metasystem-master as an output backend, receiving routed structural descriptions and returning status information about rendering progress and buffer state.

The theoretical commitment is that **sound is not a flat output format** but a rich medium capable of expressing the same recursive and self-referential structures that the generative engine produces. The bridge is the proof of this commitment.

---

## Planned Architecture

> **Status: API DOCS REQUIRED** — The architecture below is the intended design. Implementation requires formal API documentation for the structural description format and synthesis backend protocols.

### Component Overview

```
┌─────────────────────────────────────────────────────┐
│                 metasystem-master                     │
│            (ORGAN-II coordinator)                     │
└──────────────────────┬──────────────────────────────┘
                       │ structural descriptions
                       ▼
┌─────────────────────────────────────────────────────┐
│              audio-synthesis-bridge                   │
│                                                       │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ Parser   │→ │ Semantic     │→ │ Backend       │  │
│  │ Layer    │  │ Mapper       │  │ Dispatcher    │  │
│  └──────────┘  └──────────────┘  └───────┬───────┘  │
│                                          │           │
│  ┌──────────┐  ┌──────────────┐          │           │
│  │ Buffer   │  │ Correspondence│          │           │
│  │ Manager  │  │ Table        │          │           │
│  └──────────┘  └──────────────┘          │           │
└──────────────────────────────────────────┼───────────┘
                       │                   │
          ┌────────────┼───────────────────┼────────┐
          ▼            ▼                   ▼        ▼
    ┌──────────┐ ┌──────────┐      ┌──────────┐ ┌──────┐
    │ Web Audio│ │ Tone.js  │      │ Super-   │ │ OSC  │
    │ API      │ │          │      │ Collider │ │ Out  │
    └──────────┘ └──────────┘      └──────────┘ └──────┘
```

### Core Components

1. **Parser Layer** — Deserializes structural descriptions from the ORGANVM interchange format (JSON-based recursive tree with annotation metadata). Validates schema compliance and extracts the recursion graph.

2. **Semantic Mapper** — The heart of the bridge. Walks the parsed structural tree and, consulting the Correspondence Table, assigns sonic parameters to each structural node. This is where recursive self-references are detected and mapped to their audible correlates.

3. **Correspondence Table** — A configurable mapping from structural features (recursion depth, self-reference type, transformation kind) to sonic parameters (frequency range, timbral preset, temporal offset, dynamic curve). Ships with sensible defaults; fully overridable per piece.

4. **Buffer Manager** — Handles the temporal coordination between generator and renderer. Maintains a lookahead buffer of pre-mapped sonic events and a lookbehind buffer of recently rendered events (for context-sensitive decisions).

5. **Backend Dispatcher** — Routes mapped sonic events to the appropriate synthesis backend. Supports multiple simultaneous backends (e.g., Web Audio for browser preview, SuperCollider for high-fidelity rendering).

### Planned Technology Stack

- **Runtime**: TypeScript / Node.js (matching ORGAN-II ecosystem conventions)
- **Browser target**: Web Audio API + AudioWorklet for low-latency in-browser rendering
- **Desktop target**: OSC protocol output to SuperCollider, Max/MSP, or Pure Data
- **Interchange format**: JSON structural descriptions over WebSocket or stdin/stdout pipe

---

## Protocol Design

### Input Protocol

The bridge accepts structural descriptions in the ORGANVM Structural Description Format (SDF), a JSON schema that encodes:

- **Nodes**: Individual sonic events or event groups, each with a unique ID
- **Edges**: Relationships between nodes (parent-child, self-reference, transformation-of)
- **Annotations**: Metadata per node (intended emphasis, recursion depth, generation pass number)
- **Temporal hints**: Relative timing suggestions (not absolute timestamps — the bridge resolves these)

### Output Protocol

The bridge emits backend-specific control messages:

- **Web Audio**: Direct API calls to AudioContext, creating and connecting AudioNodes
- **OSC**: Open Sound Control messages over UDP, compatible with SuperCollider, Max/MSP, Pure Data, and most live-coding environments
- **MIDI**: Standard MIDI messages for integration with hardware synthesizers and DAWs
- **Custom**: Plugin interface for additional backends

### Feedback Channel

The bridge reports rendering state back to metasystem-master:

- Buffer fullness (how far ahead the generator is)
- Rendering latency (time from structural description receipt to audio output)
- Dropped events (if the renderer cannot keep up with the generator)
- Correspondence table hits (which mappings are being used most frequently — useful for aesthetic analysis)

---

## Target Synthesis Backends

### Web Audio API (Browser)

The Web Audio API provides a graph-based audio processing model native to all modern browsers. The bridge creates `AudioNode` graphs that mirror the structural description's recursive relationships — a recursive phrase literally becomes a recursive signal routing path. This is the primary target for web-based demonstrations and public-facing generative installations.

### Tone.js

[Tone.js](https://tonejs.github.io/) provides a higher-level abstraction over Web Audio, with built-in synthesizers, effects, and scheduling primitives. The bridge can optionally target Tone.js when the structural description maps well to traditional musical concepts (notes, chords, phrases) rather than pure signal processing.

### SuperCollider

[SuperCollider](https://supercollider.github.io/) is the premier open-source environment for algorithmic composition and real-time audio synthesis. The bridge communicates with SuperCollider via OSC, sending SynthDef instantiation messages, parameter updates, and scheduling commands. SuperCollider is the target for high-fidelity rendering and live performance contexts.

### OSC Generic

For maximum flexibility, the bridge can output raw OSC messages to any OSC-compatible receiver. This enables integration with Max/MSP, Pure Data, Ableton Live (via Max for Live), TouchDesigner, and bespoke synthesis environments.

---

## Related Work

The audio-synthesis-bridge operates in a space defined by several existing tools and paradigms. Understanding how it differs from and builds upon these predecessors clarifies its unique contribution.

### Web Audio API (Native)

The Web Audio API is a low-level browser primitive, not an artistic tool. It provides AudioNodes and a routing graph but no concept of musical structure, recursion, or semantic mapping. The bridge uses Web Audio as an output target, not a replacement. Where Web Audio asks "what frequency should this oscillator play?", the bridge asks "what does this recursive self-reference sound like?"

### Tone.js

Tone.js adds musical abstractions (Transport, Synth, Sequence) on top of Web Audio. It is excellent for conventional music programming but does not address the translation problem from recursive structural descriptions. Tone.js assumes the composer has already decided what notes to play and when. The bridge makes those decisions based on structural input.

### SuperCollider

SuperCollider is both a synthesis engine and a programming language for algorithmic composition. Its `Patterns` library is conceptually similar to the bridge's semantic mapper — both translate abstract descriptions into concrete sonic events. However, SuperCollider's pattern system is designed for patterns written *in* SuperCollider, not for receiving external structural descriptions over a protocol. The bridge complements SuperCollider rather than replacing it.

### FAUST

[FAUST](https://faust.grame.fr/) is a functional programming language for real-time audio DSP. It compiles to efficient C++ code and can target multiple platforms. FAUST is focused on signal processing algorithms, not on the interpretive translation of structural descriptions. The bridge could potentially use FAUST-compiled DSP modules as synthesis primitives within its backend.

### Sonic Pi

[Sonic Pi](https://sonic-pi.net/) is a live-coding environment for music creation. Its approach — writing code that becomes sound in real time — shares the bridge's commitment to real-time operation. However, Sonic Pi is a self-contained composition environment, while the bridge is a translation layer that sits between a generative system and a synthesis engine.

### ORCA

[ORCA](https://100r.co/site/orca.html) is an esoteric live-coding environment that uses a two-dimensional grid of single-character operators. Like the bridge, ORCA translates spatial/structural arrangements into temporal sonic events. ORCA's constraint is its grid; the bridge's constraint is the recursive structural description format.

---

## Integration Points

### Within ORGAN-II

- **[metasystem-master](https://github.com/organvm-ii-poiesis/metasystem-master)** — Registers as an output backend; receives routed structural descriptions
- **[example-generative-visual](https://github.com/organvm-ii-poiesis/example-generative-visual)** — Potential synchronized audiovisual output (both receiving the same structural description, rendering in their respective media)
- **[example-choreographic-interface](https://github.com/organvm-ii-poiesis/example-choreographic-interface)** — Movement-to-sound mapping when the choreographic interface generates structural descriptions that the bridge renders as audio

### With ORGAN-I (Theory)

- **[recursive-engine](https://github.com/organvm-i-theoria/recursive-engine--generative-entity)** — Primary source of structural descriptions
- **[organon-noumenon--ontogenetic-morphe](https://github.com/organvm-i-theoria/organon-noumenon--ontogenetic-morphe)** — Ontological framework for interpreting structural relationships

### With ORGAN-III (Commerce)

- No direct dependency (ORGAN-III does not depend on ORGAN-II). However, audio output from the bridge may be used in product demonstrations or marketing materials routed through ORGAN-VII.

---

## Roadmap

### Phase 1: API Documentation (Current)

- [ ] Formalize the Structural Description Format (SDF) schema
- [ ] Define the Correspondence Table configuration format
- [ ] Document the backend plugin interface
- [ ] Establish the feedback channel protocol

### Phase 2: Proof of Concept

- [ ] Implement Parser Layer for SDF v1
- [ ] Build minimal Semantic Mapper with default correspondence table
- [ ] Web Audio backend: render simple recursive structures as sound
- [ ] Integration test with recursive-engine sample output

### Phase 3: Full Implementation

- [ ] SuperCollider backend via OSC
- [ ] Tone.js backend for musical contexts
- [ ] Buffer Manager for real-time generator coordination
- [ ] Correspondence Table plugin system
- [ ] Integration with metasystem-master routing

### Phase 4: Performance and Polish

- [ ] AudioWorklet migration for low-latency browser rendering
- [ ] MIDI output backend
- [ ] Visualization of correspondence table activity
- [ ] Documentation and tutorial examples

---

## Contributing

This repository is part of the [ORGANVM](https://github.com/meta-organvm) creative-institutional system. Contributions are welcome, particularly in the following areas:

- **Synthesis backend implementations** — If you work with a synthesis environment not listed above, a backend plugin would be valuable.
- **Correspondence table presets** — Artistic mappings from structural features to sonic parameters. Each preset is a creative statement about how recursion sounds.
- **Protocol design feedback** — The SDF schema and backend protocols are in design phase. Input from practitioners working with generative audio systems is especially welcome.

Please open an issue to discuss substantial changes before submitting a pull request. All contributions must be compatible with the MIT license.

---

## License

[MIT](LICENSE)

---

## Author

**[@4444j99](https://github.com/4444j99)**

Part of the [ORGANVM](https://github.com/meta-organvm) project — an eight-organ creative-institutional system spanning theory, art, commerce, orchestration, public process, community, and communication.

---

*This repository is a component of [ORGAN-II: Poiesis](https://github.com/organvm-ii-poiesis). For the ORGAN-II flagship, see [metasystem-master](https://github.com/organvm-ii-poiesis/metasystem-master). For the system-wide overview, see [meta-organvm](https://github.com/meta-organvm).*
