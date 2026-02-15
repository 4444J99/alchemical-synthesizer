/**
 * Daemon Panel — DAEMON module creation, control, and clock registration
 * Interfaces with DAEMON OSC responders and DAEMON-CHRONOS Clock Bridge
 */
import { createKnob } from "../../golem/ui/knob.js";
import { createSelect } from "../../golem/ui/select.js";

const DAEMON_TYPES = [
    { value: "machina", label: "Turing Machine", desc: "16-bit shift register with probability feedback" },
    { value: "moirai", label: "MOIRAI (Markov)", desc: "N-state Markov chain with temperature control" },
    { value: "genesis", label: "GENESIS (CA)", desc: "Wolfram cellular automaton (rules 0-255)" },
    { value: "arbor", label: "ARBOR (L-System)", desc: "Lindenmayer system fractal sequencer" },
    { value: "euclidean", label: "Euclidean Rhythm", desc: "Euclidean rhythm with accent patterns" },
    { value: "probmatrix", label: "Prob Matrix", desc: "Probability grid sequencer" },
    { value: "lorenz", label: "Lorenz Attractor", desc: "3-axis continuous chaotic CV" },
    { value: "henon", label: "Henon Map", desc: "2-axis discrete chaotic CV" },
    { value: "rossler", label: "Rossler Attractor", desc: "3-axis quasi-periodic chaos" }
];

export class DaemonPanelView {
    constructor(container, state, osc) {
        this.el = container;
        this.state = state;
        this.osc = osc;
        this.instances = []; // { name, type, clockRegistered, division }
        this.selectedType = "machina";
    }

    render() {
        this.el.innerHTML = "";

        // Create daemon bar
        const createCard = document.createElement("div");
        createCard.className = "card";
        const createTitle = document.createElement("div");
        createTitle.className = "card-title";
        createTitle.textContent = "CREATE DAEMON";
        createCard.appendChild(createTitle);

        const createRow = document.createElement("div");
        createRow.className = "instance-bar";

        const typeSelect = createSelect({
            value: this.selectedType,
            options: DAEMON_TYPES.map(t => ({ value: t.value, label: t.label })),
            label: "Type",
            onChange: (val) => { this.selectedType = val; this.renderTypeDesc(createCard); }
        });

        const nameInput = document.createElement("input");
        nameInput.className = "instance-input";
        nameInput.placeholder = "Instance name";
        nameInput.value = `daemon_${Date.now() % 10000}`;

        const createBtn = document.createElement("button");
        createBtn.className = "action-btn";
        createBtn.textContent = "Create";
        createBtn.addEventListener("click", () => {
            const name = nameInput.value.trim();
            if (!name) return;
            this.createDaemon(this.selectedType, name);
            nameInput.value = `daemon_${Date.now() % 10000}`;
        });

        createRow.append(typeSelect.el, nameInput, createBtn);
        createCard.appendChild(createRow);

        // Type description
        this.renderTypeDesc(createCard);

        this.el.appendChild(createCard);

        // Active instances
        const instCard = document.createElement("div");
        instCard.className = "card";
        const instTitle = document.createElement("div");
        instTitle.className = "card-title";
        instTitle.textContent = `ACTIVE DAEMONS (${this.instances.length})`;
        instCard.appendChild(instTitle);

        if (this.instances.length === 0) {
            const empty = document.createElement("div");
            empty.className = "text-xs";
            empty.style.color = "var(--text-muted)";
            empty.textContent = "No active daemon instances. Create one above.";
            instCard.appendChild(empty);
        } else {
            const list = document.createElement("div");
            list.className = "daemon-list";

            this.instances.forEach(inst => {
                const card = document.createElement("div");
                card.className = "daemon-card";

                const info = document.createElement("div");
                info.className = "daemon-info";
                info.innerHTML = `
                    <span class="daemon-name">${inst.name}</span>
                    <span class="daemon-type">${inst.type}${inst.clockRegistered ? " | Clock: div=" + inst.division : ""}</span>
                `;

                const controls = document.createElement("div");
                controls.className = "daemon-controls";

                // Clock register button
                if (!inst.clockRegistered) {
                    const clockBtn = document.createElement("button");
                    clockBtn.className = "action-btn";
                    clockBtn.textContent = "Clock";
                    clockBtn.addEventListener("click", () => {
                        this.osc.send("/daemon/clock/register", inst.name, inst.type, 1);
                        inst.clockRegistered = true;
                        inst.division = 1;
                        this.render();
                    });
                    controls.appendChild(clockBtn);
                } else {
                    // Division control
                    const divSelect = createSelect({
                        value: String(inst.division),
                        options: [
                            { value: "1", label: "16th" },
                            { value: "2", label: "8th" },
                            { value: "4", label: "1/4" },
                            { value: "8", label: "1/2" },
                            { value: "16", label: "1 bar" }
                        ],
                        onChange: (val) => {
                            inst.division = parseInt(val);
                            this.osc.send("/daemon/clock/division", inst.name, inst.division);
                        }
                    });
                    controls.appendChild(divSelect.el);

                    const unclockBtn = document.createElement("button");
                    unclockBtn.className = "action-btn";
                    unclockBtn.textContent = "Unclock";
                    unclockBtn.addEventListener("click", () => {
                        this.osc.send("/daemon/clock/unregister", inst.name);
                        inst.clockRegistered = false;
                        this.render();
                    });
                    controls.appendChild(unclockBtn);
                }

                // Free button
                const freeBtn = document.createElement("button");
                freeBtn.className = "action-btn danger";
                freeBtn.textContent = "Free";
                freeBtn.addEventListener("click", () => {
                    this.freeDaemon(inst);
                });
                controls.appendChild(freeBtn);

                card.append(info, controls);
                list.appendChild(card);
            });

            instCard.appendChild(list);
        }

        this.el.appendChild(instCard);
    }

    renderTypeDesc(container) {
        let existing = container.querySelector(".type-desc");
        if (existing) existing.remove();

        const typeInfo = DAEMON_TYPES.find(t => t.value === this.selectedType);
        if (typeInfo) {
            const desc = document.createElement("div");
            desc.className = "type-desc text-xs mt-2";
            desc.style.color = "var(--text-muted)";
            desc.textContent = typeInfo.desc;
            container.appendChild(desc);
        }
    }

    createDaemon(type, name) {
        switch (type) {
            case "machina":
                this.osc.send("/daemon/machina/create", name, 16, 0.5);
                break;
            case "moirai":
                this.osc.send("/moirai/create", name, 8);
                break;
            case "genesis":
                this.osc.send("/genesis/create", name, 32, 30);
                break;
            case "arbor":
                this.osc.send("/arbor/create", name, "F", 3);
                break;
            case "euclidean":
                this.osc.send("/daemon/euclidean/create", name, 16, 5, 2, 0);
                break;
            case "probmatrix":
                this.osc.send("/daemon/probmatrix/create", name, 8, 16);
                break;
            case "lorenz":
                this.osc.send("/daemon/lorenz/create", name, 10, 28, 2.667);
                break;
            case "henon":
                this.osc.send("/daemon/henon/create", name, 1.4, 0.3);
                break;
            case "rossler":
                this.osc.send("/daemon/rossler/create", name, 0.2, 0.2, 5.7);
                break;
        }

        this.instances.push({
            name,
            type,
            clockRegistered: false,
            division: 1
        });
        this.render();
    }

    freeDaemon(inst) {
        // Unregister from clock if needed
        if (inst.clockRegistered) {
            this.osc.send("/daemon/clock/unregister", inst.name);
        }
        // Free the instance
        this.osc.send("/daemon/free", inst.name);
        this.instances = this.instances.filter(i => i !== inst);
        this.render();
    }
}
