/**
 * Chronos Panel — Transport controls, tempo, tick display
 * Interfaces with CHRONOS master sequencer via OSC
 */
import { createKnob } from "../../golem/ui/knob.js";

export class ChronosPanelView {
    constructor(container, state, osc) {
        this.el = container;
        this.state = state;
        this.osc = osc;
    }

    render() {
        this.el.innerHTML = "";

        // Transport panel
        const transport = document.createElement("div");
        transport.className = "transport-panel";

        const playBtn = document.createElement("button");
        playBtn.className = `transport-btn ${this.state.playing ? "active" : ""}`;
        playBtn.textContent = this.state.playing ? "PLAYING" : "PLAY";
        playBtn.addEventListener("click", () => {
            this.osc.send("/chronos/transport/play");
        });

        const stopBtn = document.createElement("button");
        stopBtn.className = "transport-btn";
        stopBtn.textContent = "STOP";
        stopBtn.addEventListener("click", () => {
            this.osc.send("/chronos/transport/stop");
        });

        const tempoDisplay = document.createElement("div");
        tempoDisplay.className = "tempo-display";
        tempoDisplay.textContent = Math.round(this.state.tempo);

        const tempoKnob = createKnob({
            value: this.state.tempo,
            min: 30,
            max: 300,
            label: "BPM",
            onChange: (val) => {
                this.state.tempo = val;
                tempoDisplay.textContent = Math.round(val);
                this.osc.send("/chronos/transport/tempo", val);
            }
        });

        const tickDisplay = document.createElement("span");
        tickDisplay.className = "text-xs";
        tickDisplay.style.color = "var(--text-muted)";
        tickDisplay.textContent = `Tick: ${this.state.tickCount}`;

        // Update tick display periodically
        this.osc.on("/chronos/tick", (args) => {
            const tick = args[0]?.value ?? args[0];
            tickDisplay.textContent = `Tick: ${tick}`;
        });

        transport.append(playBtn, stopBtn, tempoDisplay, tempoKnob.el, tickDisplay);
        this.el.appendChild(transport);

        // Scenes
        const scenesCard = document.createElement("div");
        scenesCard.className = "card";
        const scenesTitle = document.createElement("div");
        scenesTitle.className = "card-title";
        scenesTitle.textContent = "SCENES";
        scenesCard.appendChild(scenesTitle);

        const sceneRow = document.createElement("div");
        sceneRow.className = "scene-row";
        for (let i = 0; i < 8; i++) {
            const saveBtn = document.createElement("button");
            saveBtn.className = "scene-btn";
            saveBtn.textContent = `${i + 1}`;
            saveBtn.addEventListener("click", () => {
                this.osc.send("/chronos/scene/load", i);
            });
            saveBtn.addEventListener("dblclick", () => {
                this.osc.send("/chronos/scene/save", i);
                saveBtn.classList.add("active");
            });
            sceneRow.appendChild(saveBtn);
        }
        scenesCard.appendChild(sceneRow);

        const sceneHelp = document.createElement("div");
        sceneHelp.className = "text-xs mt-2";
        sceneHelp.style.color = "var(--text-muted)";
        sceneHelp.textContent = "Click to load, double-click to save";
        scenesCard.appendChild(sceneHelp);

        this.el.appendChild(scenesCard);

        // Fill controls
        const fillCard = document.createElement("div");
        fillCard.className = "card";
        const fillTitle = document.createElement("div");
        fillTitle.className = "card-title";
        fillTitle.textContent = "FILL & CONTROLS";
        fillCard.appendChild(fillTitle);

        const fillRow = document.createElement("div");
        fillRow.className = "flex gap-2";

        const fillOn = document.createElement("button");
        fillOn.className = "action-btn";
        fillOn.textContent = "Fill ON";
        fillOn.addEventListener("pointerdown", () => {
            this.osc.send("/chronos/fill/on");
            fillOn.classList.add("active");
        });
        fillOn.addEventListener("pointerup", () => {
            this.osc.send("/chronos/fill/off");
            fillOn.classList.remove("active");
        });

        const undoBtn = document.createElement("button");
        undoBtn.className = "action-btn";
        undoBtn.textContent = "Undo";
        undoBtn.addEventListener("click", () => this.osc.send("/chronos/undo"));

        const redoBtn = document.createElement("button");
        redoBtn.className = "action-btn";
        redoBtn.textContent = "Redo";
        redoBtn.addEventListener("click", () => this.osc.send("/chronos/redo"));

        fillRow.append(fillOn, undoBtn, redoBtn);
        fillCard.appendChild(fillRow);

        this.el.appendChild(fillCard);

        // Scene morphing
        const morphCard = document.createElement("div");
        morphCard.className = "card";
        const morphTitle = document.createElement("div");
        morphTitle.className = "card-title";
        morphTitle.textContent = "SCENE MORPH";
        morphCard.appendChild(morphTitle);

        const morphKnob = createKnob({
            value: 0,
            min: 0,
            max: 1,
            label: "Morph",
            onChange: (val) => {
                this.osc.send("/chronos/scene/morph", val);
            }
        });
        morphCard.appendChild(morphKnob.el);

        this.el.appendChild(morphCard);
    }
}
