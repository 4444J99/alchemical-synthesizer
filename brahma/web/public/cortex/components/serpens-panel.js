/**
 * Serpens Panel — Template browser with one-click materialization
 * Interfaces with SERPENS self-patching templates via OSC
 */
export class SerpensPanelView {
    constructor(container, state, osc) {
        this.el = container;
        this.state = state;
        this.osc = osc;
    }

    render() {
        this.el.innerHTML = "";

        const card = document.createElement("div");
        card.className = "card";
        const title = document.createElement("div");
        title.className = "card-title";
        title.textContent = "SERPENS — SELF-PATCHING TEMPLATES";
        card.appendChild(title);

        const desc = document.createElement("div");
        desc.className = "text-xs mb-2";
        desc.style.color = "var(--text-muted)";
        desc.textContent = "Pre-wired generative topologies. Click to materialize — creates real DAEMON instances, allocates buses, and starts the generative process.";
        card.appendChild(desc);

        // Refresh button
        const refreshBtn = document.createElement("button");
        refreshBtn.className = "action-btn mb-2";
        refreshBtn.textContent = "Refresh Templates";
        refreshBtn.addEventListener("click", () => {
            this.osc.send("/serpens/list");
        });

        const stopAllBtn = document.createElement("button");
        stopAllBtn.className = "action-btn danger mb-2";
        stopAllBtn.style.marginLeft = "8px";
        stopAllBtn.textContent = "Stop All";
        stopAllBtn.addEventListener("click", () => {
            this.osc.send("/serpens/stopAll");
            Object.keys(this.state.serpensTemplates).forEach(k => {
                this.state.serpensTemplates[k].active = false;
            });
            this.render();
        });

        card.append(refreshBtn, stopAllBtn);

        // Template cards
        const TEMPLATES = [
            {
                name: "generativeLoop",
                title: "Generative Loop",
                desc: "Turing Machine → pentatonic quantization → Prima Materia synthesis. Creates a continuously evolving melodic pattern with probability-controlled mutation."
            },
            {
                name: "chaosModulation",
                title: "Chaos Modulation",
                desc: "Lorenz attractor → 3 CV buses for parameter modulation. Creates slowly evolving chaotic modulation sources for filter cutoff, FM index, etc."
            },
            {
                name: "markovMelody",
                title: "Markov Melody",
                desc: "MOIRAI Markov chain → pentatonic melody → Prima Materia. Learns transition probabilities from pentatonic scale for stochastic melody generation."
            },
            {
                name: "euclideanDrums",
                title: "Euclidean Drums",
                desc: "3 Euclidean rhythm generators: E(4,16) kick + E(7,16) hi-hat + E(3,16) snare. Polyrhythmic drum patterns from mathematical distributions."
            },
            {
                name: "cellularTexture",
                title: "Cellular Texture",
                desc: "Rule 30 cellular automaton → harmonic oscillator bank. Maps cell states to harmonic overtones for evolving textural drones."
            }
        ];

        TEMPLATES.forEach(tmpl => {
            const isActive = this.state.serpensTemplates[tmpl.name]?.active || false;

            const tmplCard = document.createElement("div");
            tmplCard.className = `template-card ${isActive ? "active" : ""}`;

            const header = document.createElement("div");
            header.className = "flex items-center justify-between";

            const nameEl = document.createElement("div");
            nameEl.className = "template-name";
            nameEl.textContent = tmpl.title;

            const statusEl = document.createElement("span");
            statusEl.className = `template-status ${isActive ? "active" : "inactive"}`;
            statusEl.textContent = isActive ? "ACTIVE" : "INACTIVE";

            header.append(nameEl, statusEl);
            tmplCard.appendChild(header);

            const descEl = document.createElement("div");
            descEl.className = "template-desc";
            descEl.textContent = tmpl.desc;
            tmplCard.appendChild(descEl);

            const btnRow = document.createElement("div");
            btnRow.className = "flex gap-2";

            if (isActive) {
                const stopBtn = document.createElement("button");
                stopBtn.className = "action-btn danger";
                stopBtn.textContent = "Stop";
                stopBtn.addEventListener("click", () => {
                    this.osc.send("/serpens/stop", tmpl.name);
                    if (this.state.serpensTemplates[tmpl.name]) {
                        this.state.serpensTemplates[tmpl.name].active = false;
                    }
                    this.render();
                });
                btnRow.appendChild(stopBtn);
            } else {
                const startBtn = document.createElement("button");
                startBtn.className = "action-btn";
                startBtn.textContent = "Materialize";
                startBtn.addEventListener("click", () => {
                    this.osc.send("/serpens/apply", tmpl.name, 0);
                    this.state.serpensTemplates[tmpl.name] = { active: true };
                    this.render();
                });
                btnRow.appendChild(startBtn);
            }

            tmplCard.appendChild(btnRow);
            card.appendChild(tmplCard);
        });

        this.el.appendChild(card);
    }
}
