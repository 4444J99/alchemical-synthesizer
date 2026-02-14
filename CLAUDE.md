# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

The **Alchemical Synthesizer** (Brahma Meta-Rack) is a modular synthesis organism that absorbs, mutates, and re-expresses sonic identities from other systems. It is a parasitic-symbiotic apparatus—not a fixed instrument—whose identity is contingent on contact.

## Technology Stack

- **SuperCollider** (`brahma/sc/`): DSP engine, trait registries, state machines (~18,000 LOC across 60+ files)
- **Pure Data** (`brahma/pd/`): Performance UI, faceplate abstractions, OSC control surface
- **Node.js + p5.js** (`brahma/web/`): Visual Cortex — real-time browser visualization via OSC-to-WebSocket bridge
- **Python** (`tools/`): Audio specimen validation utilities
- **OSC**: Bidirectional glue between all layers

## Communication Architecture (Critical)

The system uses a **three-port OSC topology** for inter-layer communication:

- **Port 57120**: SuperCollider → Pure Data (send commands, state updates)
- **Port 57121**: Pure Data receive (listens for SC broadcasts)
- **Port 57122**: SuperCollider → Node.js (organism state for web visualization)

All organism state updates follow the format: `/brahma/organism/update [entityId:int] [type:symbol] [coherence:float] [entropy:float]`

Example: `/brahma/organism/update 1001 "Relinquished" 0.65 2.3`

### Web Visualization Flow

1. SuperCollider broadcasts via `NetAddr("127.0.0.1", 57122)` at 10Hz (0.1s intervals)
2. Node.js UDP listener (port 57122) parses OSC and converts to JSON
3. WebSocket server broadcasts JSON to all connected browser clients
4. p5.js sketch renders organism state with:
   - **Radius**: coherence mapped to 50-200px
   - **Jitter**: entropy mapped to 0-10px with Perlin noise
   - **Color**: 16 organism types mapped (Proteus=cyan, Relinquished=red, Golem=orange, Typhon=violet, AgentSmith=green, etc.), default=white
   - **Decay**: 2000ms without update removes organism from display

### Pure Data OSC Bridge

- **Receive**: `netreceive` on port 57121 (UDP, binary) → `oscparse` → `route /sc /golem /brahma /chronos /daemon /patch`
- **Send**: `netsend` to 127.0.0.1:57120
- Enables bidirectional PD ↔ SC communication across all OSC namespaces

## Running the System

### SuperCollider (primary engine)
```bash
# Open brahma/sc/loader.scd in SuperCollider IDE
# Evaluate it (Cmd+Return or Ctrl+Return)
# Expected output: --- BRAHMA SYSTEM ONLINE ---
```

Server configuration: 2048 audio buses, 8192 control buses, expanded memory (8192×32), 4096 buffers, 4096 max nodes.

### Pure Data (UI layer)
```bash
# Open brahma/pd/main.pd in Pd Vanilla (v0.54+)
# This is the master patching surface with OSC bridge to SC
```

### Visual Cortex (web visualization)
```bash
cd brahma/web
npm install
npm start
# Serves on http://localhost:3000
# OSC receive: 57122, OSC send: 57120
```

### Audio validation
```bash
python3 tools/validate_audio.py path/to/specimen.wav
```

### SuperCollider Class Installation
The `.sc` class files (`AdamKadmon.sc`, `BridgeRouter.sc`, `FSAP.sc`, `BrahmaScale.sc`, `BrahmaMPE.sc`, `BrahmaModBus.sc`) must be accessible to the SC class compiler. Either:
- Symlink `brahma/sc/*.sc` into your SC Extensions directory (`Platform.userExtensionDir` in SC)
- Or add the `brahma/sc/` directory to your SC include paths

After installing, recompile the class library (Cmd+Shift+L in SC IDE).

### Dependencies
- **SuperCollider** v3.13+ (core)
- **Pure Data** Vanilla v0.54+ (UI layer, optional)
- **Node.js** v18+ (Visual Cortex, optional)
- **sc3-plugins**: Not strictly required. The `\homunculus` physical modeling engine uses a CombL fallback instead of DWGBowed.

## Architecture

### Boot & Load Order

`loader.scd` orchestrates strict dependency loading via numeric file prefixes:

1. `01_*` — Infrastructure (server config, group hierarchy, global registry, arbitration)
2. `02_*` — Microtonality (BrahmaScale), MIDI/MPE (BrahmaMPE)
3. `03_*` — Proteus (emulation engine)
4. `04_*` — Relinquished + Fusion Core (binding engines)
5. `05_*` — Organisms (Agent Smith, Ditto, Sampler Creatures)
6. `06_*` — Typhon (accumulative stacking)
7. `07_*` — Safety (IMMUNE governor SynthDef)
8. `08_*` — Patch Bay (BrahmaModBus universal CV routing)
9. `09_*` — CHRONOS Master Sequencer (core, clock, tracks, MIDI, automation)
10. `10-13_*` — Validation, metrics, test bench, NRT renderer
11. `14_*` — Visual Cortex bridge
12. `15_*` — Golem Percussion Organism (percussion suite, FX, patterns, sequencer)
13. `16_*` — Synthesis Engines (10 engines: Prima Materia, Azoth, Quintessence, Ouroboros, Chrysopoeia, Homunculus, Buchlaeus, Logos, Tetramorph, Nebula)
14. `17-20_*` — Make Noise module clones (functions, filters, time, oscillators, sequencers, utilities)
15. `21-22_*` — Effects Rack (46 FX: dynamics, EQ, distortion, modulation, spatial, spectral, time)
16. `23-24_*` — Standard Modular modules (oscillators, filters, amplifiers, envelopes, modulation, clock, sequencers, utilities)
17. `25_*` — Elektron machine emulations (Analog machines, Octatrack)
18. `26_*` — Interaction & controllers (MIDI controllers, sensors)
19. `27_*` — Generative systems (Lorenz, Markov, Cellular Automata, chaos attractors + generative sequencers)
20. `28_*` — Audio management (monitoring, recording, presets, sync)

**Critical**: The IMMUNE governor is deployed as the final node in the `\rr` group at the end of `loader.scd`. All loads occur inside `s.doWhenBooted` to prevent boot race conditions.

### 7-Stage Organism Model

Every synthesis module follows this signal path. **New modules must implement all 7 stages**:

1. **IA** (Input Assimilation) → normalization/protection
2. **EG** (Equip Gating) → single-equip constraint state machine
3. **BC** (Binding Core) → signal capture and "wearing"
4. **AE** (Analysis Extraction) → spectral/temporal trait derivation
5. **TE** (Transmutation Engine) → operator-based transformation
6. **PR** (Protection/Reflection) → sacrificial buffering and retaliation
7. **RR** (Release Router) → final routing and bypass

The SC group hierarchy mirrors this: `root → ia → bc → ae → te → pr → rr`.

### Core Infrastructure Classes

#### AdamKadmon.sc — Ontological Registry
- **validateTraitMap(map)**: Checks for required keys `[spectral_profile, temporal_topology, modulation_graph, performance_response]`
- **normalize(map)**: Coerces all trait values to [0.0, 1.0] ranges
- **checkPermission(entityId, mode)**: Access control for read/write/infect operations
- **issueCapabilityToken(action)**: Signs capability tokens for entity actions

Strictness threshold: 0.85. All trait dimensions must exist and be normalized.

#### BridgeRouter.sc — Inter-Domain Backplane
- **emitLinkSet(src, dst, mode, ttl)**: Creates inter-domain links with TTL-based expiry
- **tick()**: Runs at 1kHz; removes expired links by comparing current time against link.expiry
- Link structure: `{src, dst, mode, ttl, expiry}`
- Expiry calculation: `Date.getDate.rawSeconds + (ttl/1000.0)` converts milliseconds to seconds

Implements I2C-style arbitration for contention resolution.

#### FSAP.sc — Fidelity Stacking Absorption Protocol
State machine for cumulative identity integration with four phases:

1. **observe(targetId, registry)** → state=\OBSERVING; retrieves traits from registry
2. **absorb()** → transitions \OBSERVING → \ABSORBING (guards state validity)
3. **integrate(fidelity=1.0)** → validates via AdamKadmon, transitions → \INTEGRATING
4. **accumulate()** → adds to stack, transitions → \IDLE to complete cycle

**Invariant**: Strict state validation prevents out-of-order transitions. Cannot absorb without observing, cannot integrate without absorbing.

### Global State

- `~BRAHMA_REGISTRY` — Entity IDs, trait maps, lineage graph (managed by Adam Kadmon)
- `~BRIDGE` — I2C-style bus state with domain dictionary and active link tracking
- `~SC_GRP` — Group hierarchy for signal ordering (root, ia, bc, ae, te, pr, rr)
- `~SC_BUS` — Dynamic bus allocation dictionary
- `~VISUAL_CORTEX` — OSC broadcast interface and demo stream control
- `~METRIC_COLLECTOR` — Language-side metrics Event (coherence, fidelity, stress, entropy)
- `~BRAHMA_TUNING` — Global tuning state, scale library, BrahmaScale instance
- `~BRAHMA_MIDI` — MIDI/MPE state, voice allocation, learn routes, clock
- `~PATCH_BAY` — BrahmaModBus instance for universal CV routing (256-bus pool)
- `~CHRONOS` — Master sequencer state (transport, tracks, scenes, undo/redo, song mode)
- `~NRT_RENDERER` — Non-real-time rendering interface
- `~GOLEM` / `~GOLEM_SEQ` — Golem percussion organism and sequencer state

### Validation & Metrics Infrastructure

#### Measurement System (~METRIC_COLLECTOR)
Language-side Event (not a class — SC's class compiler only processes `.sc` files). Four-dimensional quantification:
- **Coherence**: Spectral stability (placeholder — requires FluidBufSpectralShape for real implementation)
- **Fidelity**: Cross-correlation between input and output (placeholder)
- **Stress**: System CPU load via `Server.local.avgCPU` (real)
- **Entropy**: Shannon entropy of spectral distribution (placeholder)

Methods: `measureCoherence`, `measureFidelity`, `measureStress`, `measureEntropy`, `logMetric`, `exportReport`.

#### A/B Test Bench
- **runComparison(synth1, synth2)**: Sequentially runs two SynthDefs on same input with metrics
- **spawnMutant(baseSynthDef)**: Creates temporary mutated version for testing variations

#### Non-Real-Time Rendering
- **renderSpecimen(inputPath, outputPath)**: Processes audio offline through Relinquished → Transmuted pipeline
- Uses Score system with time-stamped OSC-style commands for batch processing
- Enables specimen generation without real-time constraints

### Pure Data Architecture

#### Three-Layer Abstraction Hierarchy

1. **main.pd** (master control surface)
   - Instantiates all major abstractions
   - Distributes clock to all modules
   - 800×600 canvas

2. **Specialized Abstractions**
   - **osc_bridge.pd**: Bidirectional OSC (SC↔PD)
   - **master_clock.pd**: BPM-based sync with formula `60000 / BPM = metro_interval`
     - Dual outputs: `global_clock` and `cell_cycle_tick` buses
   - **macro_panel.pd**: Performance control (12 continuous + 8 triggers)
   - **faceplate_14.pd, faceplate_18.pd, faceplate_24.pd**: Module faceplates (HP standardization)

3. **Low-Level Pd Objects**
   - `netreceive` (UDP), `netsend`, `oscparse`, `route`, `number~`, `bang`, etc.

#### Master Clock Synchronization
Formula: `60000 / BPM = metro_interval_ms`
- Receives BPM via `r BPM` (default 120 on loadbang)
- Sends bangs to `global_clock` (all modules) and `cell_cycle_tick` (cell-level timing)
- No clock drift due to formula-based calculation

#### Macro Panel Control Scheme
- **12 Continuous Controllers** (k1-k12): Number boxes, range 0-127, arranged 4×3
- **8 Discrete Triggers** (b1-b8): Bang objects with 250ms debounce
- Uses local namespace `$0` for data isolation (safe multi-instantiation)

### Web Visualization (p5.js)

#### Real-Time Rendering Pipeline

```javascript
// OSC message handler
if (msg.address === "/brahma/organism/update") {
    let id = msg.args[0].value;
    organisms[id] = {
        type: msg.args[1].value,
        coherence: msg.args[2].value,
        entropy: msg.args[3].value,
        lastUpdate: millis()
    };
}

// Visual mapping
let r = map(org.coherence, 0, 1, 50, 200);        // radius
let jitter = map(org.entropy, 0, 10, 0, 10);      // jitter amount

// Render with Perlin noise offset
for (let i = 0; i < TWO_PI; i += 0.1) {
    let offset = map(noise(i + millis()*0.001), 0, 1, -jitter, jitter);
    let x = (r + offset) * cos(i);
    let y = (r + offset) * sin(i);
    vertex(x, y);
}
```

#### Decay Logic
- Organisms removed from display if no update for 2000ms
- Trails effect: semi-transparent background (alpha 20) each frame
- Color differentiation enables visual identification of organism types

## Coding Conventions

### SuperCollider
- **Arguments**: `snake_case` (e.g., `out_bus`, `in_bus`)
- **Classes**: `CamelCase` (e.g., `AdamKadmon`, `BridgeRouter`)
- **Methods**: `camelCase` (e.g., `validateTraitMap`)
- **All SynthDefs must include**: `outBus` and `inBus` arguments for modular routing
- **Group routing**: Always explicitly set group assignment in SynthDef

### Pure Data
- Follow 14HP/18HP/24HP faceplate standardization using provided abstractions
- Use local namespace `$0` for multi-instantiation safety
- All abstractions should have clear inlet/outlet documentation

### Python
- Follow PEP 8
- Use type hints for function signatures
- Validate audio specimens before analysis

## Invariants (Never Violate)

- **Single-Equip**: A module core may only bind one donor identity at a time
- **Lossless Stacking**: In FSAP-compliant modules, no prior absorption may be degraded during accumulation
- **Safety First**: The `IMMUNE` governor (07_safety.scd) must be the final node before any output to prevent recursive collapse
- **State Ordering**: FSAP transitions must follow strict ordering (observe → absorb → integrate → accumulate)
- **Trait Validation**: All trait maps must pass AdamKadmon.validateTraitMap before integration

## Git Workflow

- **Branch prefixes**: `feat/`, `fix/`, `docs/`
- **Commit messages**: Imperative mood, <72 chars title
- **WIP limit**: 2 active implementation items
- **Triage flow**: Triage → Backlog → Design → In Progress → Validation → Done

## Common Development Tasks

### Verify System Startup
```bash
# Terminal 1: SuperCollider
# Open brahma/sc/loader.scd, evaluate
# Watch for: --- BRAHMA SYSTEM ONLINE ---

# Terminal 2: Node.js Visual Cortex
cd brahma/web && npm start
# Watch for: --- VISUAL CORTEX ONLINE: http://localhost:3000 ---

# Terminal 3: Pure Data (optional for performance)
# Open brahma/pd/main.pd
# Verify OSC bridge connection
```

### Add a New Synthesis Module
1. Create file with prefix `0X_module_name.scd` (insert in sequence 01-15)
2. Implement all 7 stages: IA → EG → BC → AE → TE → PR → RR
3. Define SynthDef with `outBus` and `inBus` arguments
4. Register entity in `~BRAHMA_REGISTRY` with trait map via AdamKadmon
5. Test with validation/metrics infrastructure (brahma/sc/10_*, 11_*, 12_*)
6. Add entry to loader.scd load sequence

### Validate Trait Map Integrity
```supercollider
// In SC
~trait_map = (spectral_profile: [...], temporal_topology: [...], modulation_graph: [...], performance_response: [...]);
AdamKadmon.validateTraitMap(~trait_map);  // Returns true if valid
~normalized = AdamKadmon.normalize(~trait_map);  // Ensures [0.0, 1.0] ranges
```

### Monitor Visualization
Navigate to `http://localhost:3000` while SuperCollider and Node.js are running. Organisms appear as circles with:
- 16 color-coded organism types (cyan=Proteus, red=Relinquished, orange=Golem, violet=Typhon, green=AgentSmith, etc.)
- Radius proportional to coherence
- Jitter proportional to entropy
- Auto-reconnecting WebSocket (3s retry)

### Run Offline Specimen Processing
```supercollider
~NRT_RENDERER.renderSpecimen(
    "/path/to/input.wav",
    "/path/to/output.wav"
);
```

## Performance Tuning

- **SuperCollider bus allocation**: `~SC_BUS` tracks dynamic allocation; audit if exceeding 512 control buses
- **WebSocket latency**: 10Hz organism updates; increase frequency if visualization feels sluggish
- **Pure Data CPU**: Reduce metro frequency if `dsp load` approaches 80%
- **Node.js buffering**: Monitor WebSocket client count; may need per-domain load balancing at scale

## References

- **SuperCollider OSC**: `NetAddr` class sends via UDP; use `metadata: true` in UDPPort for type info
- **Pure Data OSC**: `oscparse` converts binary to Pd messages; `route` filters by address
- **p5.js WebSocket**: `new WebSocket('ws://host')` for persistent bidirectional connection
- **Trait Map Schema**: Four required keys; any additional keys accepted but not validated
- **FSAP State Machine**: Strict ordering enforced; invalid transitions return warnings and reset state to \IDLE
