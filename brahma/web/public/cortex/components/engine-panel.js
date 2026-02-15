/**
 * Engine Panel — Piano keyboard + param panel for synth engines
 * Sends noteOn/noteOff via /brahma/engine/* OSC
 */
import { createKnob } from "../../golem/ui/knob.js";
import { createSelect } from "../../golem/ui/select.js";

const ENGINE_NAMES = [
    "prima_materia", "azoth", "quintessence", "ouroboros", "chrysopoeia",
    "homunculus", "buchlaeus", "logos", "tetramorph", "nebula"
];

const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const BLACK_KEYS = [1, 3, 6, 8, 10]; // semitone indices that are black keys

export class EnginePanelView {
    constructor(container, state, osc) {
        this.el = container;
        this.state = state;
        this.osc = osc;
        this.selectedEngine = "prima_materia";
        this.instanceName = "engine_voice_1";
        this.octave = 4;
        this.activeNotes = new Set();
        this.knobs = {};
    }

    render() {
        this.el.innerHTML = "";

        // Engine selector
        const selectorBar = document.createElement("div");
        selectorBar.className = "card flex items-center gap-3";

        const engineSelect = createSelect({
            value: this.selectedEngine,
            options: ENGINE_NAMES.map(n => ({
                value: n,
                label: n.replace(/_/g, " ").toUpperCase()
            })),
            label: "Engine",
            onChange: (val) => {
                this.selectedEngine = val;
                // Request params for this engine
                if (!this.state.params[val] || this.state.params[val].length === 0) {
                    this.osc.send("/brahma/modules/params", val);
                }
                this.render();
            }
        });
        selectorBar.appendChild(engineSelect.el);

        // Instance name
        const instLabel = document.createElement("span");
        instLabel.className = "text-xs";
        instLabel.style.color = "var(--text-muted)";
        instLabel.textContent = "Instance:";
        const instInput = document.createElement("input");
        instInput.className = "instance-input";
        instInput.value = this.instanceName;
        instInput.addEventListener("change", (e) => { this.instanceName = e.target.value; });
        selectorBar.append(instLabel, instInput);

        // Octave controls
        const octaveDown = document.createElement("button");
        octaveDown.className = "action-btn";
        octaveDown.textContent = "Oct-";
        octaveDown.addEventListener("click", () => { this.octave = Math.max(1, this.octave - 1); this.render(); });
        const octaveUp = document.createElement("button");
        octaveUp.className = "action-btn";
        octaveUp.textContent = "Oct+";
        octaveUp.addEventListener("click", () => { this.octave = Math.min(7, this.octave + 1); this.render(); });
        const octaveLabel = document.createElement("span");
        octaveLabel.className = "text-xs";
        octaveLabel.textContent = `Oct ${this.octave}`;
        selectorBar.append(octaveDown, octaveLabel, octaveUp);

        // Free all button
        const freeBtn = document.createElement("button");
        freeBtn.className = "action-btn danger";
        freeBtn.textContent = "Free All";
        freeBtn.addEventListener("click", () => {
            this.osc.send("/brahma/engine/freeAll", this.instanceName);
            this.activeNotes.clear();
        });
        selectorBar.appendChild(freeBtn);

        this.el.appendChild(selectorBar);

        // Piano keyboard (2 octaves)
        this.renderPiano();

        // Parameter knobs
        this.renderEngineParams();
    }

    renderPiano() {
        const pianoWrap = document.createElement("div");
        pianoWrap.className = "card";

        const title = document.createElement("div");
        title.className = "card-title";
        title.textContent = "KEYBOARD";
        pianoWrap.appendChild(title);

        const piano = document.createElement("div");
        piano.className = "piano";
        piano.style.position = "relative";

        // 2 octaves = 24 semitones
        const numKeys = 25; // 2 octaves + top C
        const whiteKeys = [];
        const blackKeys = [];

        for (let i = 0; i < numKeys; i++) {
            const semitone = i % 12;
            const note = (this.octave * 12) + i; // MIDI note
            const isBlack = BLACK_KEYS.includes(semitone);

            if (isBlack) {
                blackKeys.push({ semitone, note, index: i });
            } else {
                whiteKeys.push({ semitone, note, index: i });
            }
        }

        // Render white keys first
        whiteKeys.forEach(k => {
            const key = document.createElement("div");
            key.className = "piano-key";
            key.dataset.note = k.note;

            key.addEventListener("pointerdown", (e) => {
                e.preventDefault();
                key.setPointerCapture(e.pointerId);
                this.noteOn(k.note, 0.8);
                key.classList.add("active");
            });
            key.addEventListener("pointerup", () => {
                this.noteOff(k.note);
                key.classList.remove("active");
            });
            key.addEventListener("pointerleave", () => {
                if (this.activeNotes.has(k.note)) {
                    this.noteOff(k.note);
                    key.classList.remove("active");
                }
            });

            piano.appendChild(key);
        });

        // Render black keys (positioned absolutely)
        const whiteKeyWidth = 100 / whiteKeys.length;
        blackKeys.forEach(k => {
            const key = document.createElement("div");
            key.className = "piano-key black";
            key.dataset.note = k.note;

            // Position: count white keys before this index
            const whiteBefore = whiteKeys.filter(w => w.index < k.index).length;
            key.style.left = `${(whiteBefore * whiteKeyWidth) - (whiteKeyWidth * 0.3)}%`;
            key.style.width = `${whiteKeyWidth * 0.6}%`;

            key.addEventListener("pointerdown", (e) => {
                e.preventDefault();
                e.stopPropagation();
                key.setPointerCapture(e.pointerId);
                this.noteOn(k.note, 0.8);
                key.classList.add("active");
            });
            key.addEventListener("pointerup", (e) => {
                e.stopPropagation();
                this.noteOff(k.note);
                key.classList.remove("active");
            });

            piano.appendChild(key);
        });

        pianoWrap.appendChild(piano);
        this.el.appendChild(pianoWrap);
    }

    renderEngineParams() {
        const params = this.state.params[this.selectedEngine] || [];
        if (params.length === 0) {
            this.osc.send("/brahma/modules/params", this.selectedEngine);
            const loading = document.createElement("div");
            loading.className = "card text-xs";
            loading.style.color = "var(--text-muted)";
            loading.textContent = "Loading parameters...";
            this.el.appendChild(loading);
            return;
        }

        const panel = document.createElement("div");
        panel.className = "card";
        const title = document.createElement("div");
        title.className = "card-title";
        title.textContent = `${this.selectedEngine.replace(/_/g, " ").toUpperCase()} PARAMETERS`;
        panel.appendChild(title);

        const grid = document.createElement("div");
        grid.className = "param-grid";
        this.knobs = {};

        // Filter out freq/gate/velocity — those come from the keyboard
        const editableParams = params.filter(p =>
            !["freq", "gate", "velocity", "pressure", "slide"].includes(p.name)
        );

        editableParams.forEach(p => {
            const knob = createKnob({
                value: p.default,
                min: p.min,
                max: p.max,
                label: p.name,
                onChange: (val) => {
                    this.osc.send("/brahma/engine/set", this.instanceName, p.name, val);
                }
            });
            this.knobs[p.name] = knob;
            grid.appendChild(knob.el);
        });

        panel.appendChild(grid);
        this.el.appendChild(panel);
    }

    noteOn(note, velocity) {
        this.activeNotes.add(note);
        this.osc.send("/brahma/engine/noteOn",
            this.selectedEngine, this.instanceName, note, velocity);
    }

    noteOff(note) {
        this.activeNotes.delete(note);
        this.osc.send("/brahma/engine/noteOff", this.instanceName, note);
    }
}
