# **Aether Canvas: The Universal Waveform Explorer**

## **Master Design & UI/UX Specification**

### **1\. Metadata**

* **Author**: User & Gemini  
* **Date**: 2025-07-04  
* **Version**: 1.3 (Master)  
* **Keywords**: modular synthesizer, 3D, mobile-first, design specification, UI/UX, waveform discovery, nature’s vibrations, micro-to-macro, environmental input, WebGL, Web Audio API, creative exploration, biofeedback, accessibility

### **2\. Front Matter**

#### **Summary**

Aether Canvas is a web-based, 3D modular synthesizer that reframes sound design as an exploration of the universe's fundamental vibrations. It invites users into a personal celestial orrery where they can discover, shape, and "attune to" the waveform essence of everything from quantum particles to their own heartbeat. By combining traditional synthesis with modules that model natural phenomena and analyze the user's live environment via the device camera, Aether Canvas serves as a profound instrument for creative and philosophical discovery.

#### **Objectives**

* To create an immersive, 3D, mobile-first environment where sound synthesis is experienced as the orbital mechanics of celestial bodies.  
* To define a unique module ecosystem that includes traditional synthesizers (OSCs, LFOs), textural generators (Residue), and novel components that model natural processes (Nature, Swarm) and analyze the real world (Lens).  
* To establish an intuitive, gesture-based interaction model for navigation, patching, and modulation that is free of traditional cables and menus.  
* To provide constant, meaningful audio-visual feedback where the entire environment reacts to the sound being created, solving the "silent patch problem" inherent in modular systems.  
* To frame the user experience as a "Waveform Journey," from a guided onboarding to limitless creative exploration, encouraging a deeper connection between the user, their environment, and the act of creation.

### **3\. Core Philosophy & User Experience**

#### **The 3D Orrery**

The user does not look at a flat canvas; they inhabit the center of an infinite 3D space. This is their personal orrery. The background is a dynamic nebula that visualizes the final audio output—its color determined by frequency, its brightness by amplitude.

#### **Gesture-Based Navigation**

* **One-Finger Drag:** Rotates the camera around the user's central viewpoint.  
* **Pinch-to-Zoom:** Flies the camera forward and backward through the 3D space.  
* **Two-Finger Swipe (Left/Right):** Performs a multi-level Undo/Redo of the last action, with a simple text confirmation. This is the core safety net that encourages fearless experimentation.

#### **Orbital Patching: The Core Interaction**

Patch cables are eliminated. Modulation is achieved through gravity and orbits. To modulate a primary sound source (a "Planet"), the user drags a modulating module (a "Moon") into its gravitational pull. The Moon snaps into a stable orbit, and the connection is made. The Moon's orbital speed controls the modulation rate, and its proximity to the Planet controls the modulation depth.

### **4\. The Module Ecosystem: Celestial Bodies**

Modules are living, 3D objects instantiated from the **Source Field** (a portal that opens with a swipe from the screen's edge).

| Module Type | Celestial Metaphor | Function & Parameters | 3D Visualization |
| :---- | :---- | :---- | :---- |
| **Master Audio Out** | **The Sun** | The permanent, central destination for all audible signals. Cannot be moved or deleted. | A large, brightly glowing star at the center of the orrery. |
| **OSC Module** | **Planet / Star** | The primary audio source. **Parameters:** Frequency (Pitch), Amplitude (Volume). | A 3D planet or star whose color reflects its pitch and whose light pulses in time with its waveform. |
| **LFO Module** | **Moon** | The primary modulator. **Parameters:** Rate, Depth (controlled by orbit). | A smaller celestial body (crystalline, rocky, etc.) that orbits a Planet to modulate it. Leaves a glowing orbital trail. |
| **Residue Module** | **Nebula / Asteroid Field** | An "ancient ambient machine" for generating textured noise. **Parameters:** Color (Timbre), Age (Crackle/Decay), Stereo Drift. | A shimmering, interactive cloud of dust and particles that can be shaped and colored. |
| **Nature Module** | **Pulsar / Atom / Neuron** | Models specific natural or physical processes to generate complex CV. **Presets:** "Heartbeat," "Synapse," "Atom." | A unique 3D model for each preset (e.g., a crackling neuron, a jittering atomic structure). |
| **Swarm Module** | **Flock / Swarm** | A multi-particle system based on flocking algorithms. Generates multiple, related CV outputs. **Preset:** "Geese Flocking." | A cluster of small, glowing particles that move together in emergent patterns. |
| **Lens Module** | **Floating Portal / Ring** | The bridge to the real world. Uses the device camera to analyze motion and generate CV signals. | An ethereal 3D ring that, when active, shows a live camera feed within its aperture, overlaid with motion analysis vectors. |
| **Compound Module** | **System / Constellation** | Pre-patched collections of modules. **Preset:** "Jet Engine" (OSC+Residue+LFO). | A gravitationally bound group of celestial bodies that can be instantiated as a single unit. |

### **5\. Key User Journeys & Interaction Flows**

#### **A. The Onboarding ("First Attunement")**

The user is guided through a mandatory pinch-to-zoom journey from a single point of light (Quantum) to a cell (Biological) to a planet (Planetary), finally arriving in the 3D orrery. This teaches the core navigation gesture and establishes the micro-to-macro theme.

#### **B. Making a Sound (Solving the "Silent Patch Problem")**

1. **Instantiate:** The user drags a "Planet" (OSC) from the Source Field into the space. It is silent.  
2. **Activate:** The user taps the Planet, then taps the central "Sun" (Master Out).  
3. **Feedback:** A visible **beam of light** connects the Planet to the Sun. The Planet now emits sound and its light pulses more brightly. The background nebula begins to react. This "light beam" provides unambiguous, instant feedback on what is audible.

#### **C. The "Lens" Module Workflow**

1. **Instantiate:** Drag the "Lens" module into the orrery.  
2. **Activate:** Tap the Lens. The device camera feed opens in a corner overlay, and the 3D Lens portal becomes a live window.  
3. **Attune:** Point the camera at a moving object (e.g., a flickering candle). Tap and drag on the camera overlay to define a region of interest.  
4. **Analyze:** The Lens locks on, performing real-time optical flow analysis on the selected region. Motion vectors are visualized on the 3D portal.  
5. **Generate:** The Lens's output jacks (X-Axis, Y-Axis, Velocity, Chaos) begin to pulse with CV signals derived from the real-world motion.  
6. **Patch:** The user can now connect these outputs to any compatible parameter (e.g., patch the candle's "Velocity" to a Planet's brightness/amplitude).

### **6\. Technical & Accessibility Specifications**

* **Technology Stack:** WebGL (for 3D rendering), Web Audio API (for synthesis), WebRTC/getUserMedia (for Camera/Mic input).  
* **Performance:** Targets \<10ms audio latency. Employs module culling and efficient signal routing for mobile performance. A soft limit of \~20 modules is recommended.  
* **Accessibility:** High-contrast mode for visualizers, screen reader support for module names and parameters, haptic feedback for patching confirmation, and voice control for core actions ("Connect Planet to Sun"). The onboarding and module descriptions will be narrated.  
* **Export:** Patches can be saved as JSON files for sharing. Audio can be recorded internally.