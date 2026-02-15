/**
 * Patch Matrix — Source x Destination grid with click-to-connect
 * Interfaces with the BrahmaModBus patch bay via OSC
 */
export class PatchMatrixView {
    constructor(container, state, osc) {
        this.el = container;
        this.state = state;
        this.osc = osc;
        this.connections = []; // [{ source, dest, amount }]
        this.selectedSource = null;
        this.selectedDest = null;
    }

    render() {
        this.el.innerHTML = "";

        const card = document.createElement("div");
        card.className = "card";

        const title = document.createElement("div");
        title.className = "card-title";
        title.textContent = "PATCH BAY";
        card.appendChild(title);

        const desc = document.createElement("div");
        desc.className = "text-xs mb-2";
        desc.style.color = "var(--text-muted)";
        desc.textContent = "Connect modulation sources to parameter destinations via BrahmaModBus (256-bus CV routing)";
        card.appendChild(desc);

        // Quick-connect bar
        const connectBar = document.createElement("div");
        connectBar.className = "instance-bar";

        const srcInput = document.createElement("input");
        srcInput.className = "instance-input";
        srcInput.placeholder = "Source (e.g. daemon_lorenz)";
        srcInput.addEventListener("change", () => { this.selectedSource = srcInput.value; });

        const dstInput = document.createElement("input");
        dstInput.className = "instance-input";
        dstInput.placeholder = "Destination param bus";
        dstInput.addEventListener("change", () => { this.selectedDest = dstInput.value; });

        const amtInput = document.createElement("input");
        amtInput.className = "instance-input";
        amtInput.placeholder = "Amount (0-1)";
        amtInput.style.width = "80px";
        amtInput.value = "1.0";

        const connectBtn = document.createElement("button");
        connectBtn.className = "action-btn";
        connectBtn.textContent = "Connect";
        connectBtn.addEventListener("click", () => {
            if (srcInput.value && dstInput.value) {
                const amt = parseFloat(amtInput.value) || 1.0;
                this.osc.send("/brahma/patch/connect",
                    srcInput.value, dstInput.value, amt);
                this.connections.push({
                    source: srcInput.value,
                    dest: dstInput.value,
                    amount: amt
                });
                this.renderConnections(card);
            }
        });

        const disconnectBtn = document.createElement("button");
        disconnectBtn.className = "action-btn danger";
        disconnectBtn.textContent = "Disconnect";
        disconnectBtn.addEventListener("click", () => {
            if (srcInput.value && dstInput.value) {
                this.osc.send("/brahma/patch/disconnect",
                    srcInput.value, dstInput.value);
                this.connections = this.connections.filter(c =>
                    c.source !== srcInput.value || c.dest !== dstInput.value);
                this.renderConnections(card);
            }
        });

        connectBar.append(srcInput, dstInput, amtInput, connectBtn, disconnectBtn);
        card.appendChild(connectBar);

        // Active connections
        this.renderConnections(card);

        // Available modules as sources/destinations
        this.renderModuleGrid(card);

        this.el.appendChild(card);
    }

    renderConnections(container) {
        let existing = container.querySelector(".connections-list");
        if (existing) existing.remove();

        const list = document.createElement("div");
        list.className = "connections-list";

        if (this.connections.length === 0) {
            list.innerHTML = `<div class="text-xs mt-2" style="color:var(--text-muted)">No active connections</div>`;
        } else {
            const title = document.createElement("div");
            title.className = "card-title mt-2";
            title.textContent = "ACTIVE CONNECTIONS";
            list.appendChild(title);

            this.connections.forEach(c => {
                const row = document.createElement("div");
                row.className = "daemon-card";
                row.innerHTML = `
                    <div class="daemon-info">
                        <span class="daemon-name">${c.source} → ${c.dest}</span>
                        <span class="daemon-type">Amount: ${c.amount.toFixed(2)}</span>
                    </div>
                `;
                const removeBtn = document.createElement("button");
                removeBtn.className = "action-btn danger";
                removeBtn.textContent = "X";
                removeBtn.style.padding = "2px 8px";
                removeBtn.addEventListener("click", () => {
                    this.osc.send("/brahma/patch/disconnect", c.source, c.dest);
                    this.connections = this.connections.filter(x => x !== c);
                    this.renderConnections(container);
                });
                row.appendChild(removeBtn);
                list.appendChild(row);
            });
        }

        container.appendChild(list);
    }

    renderModuleGrid(container) {
        const grid = document.createElement("div");
        grid.className = "mt-2";

        const title = document.createElement("div");
        title.className = "card-title";
        title.textContent = "REGISTERED MODULES";
        grid.appendChild(title);

        const moduleList = document.createElement("div");
        moduleList.className = "module-list";

        // Show modules grouped by category
        const byCategory = {};
        Object.values(this.state.modules).forEach(m => {
            if (!byCategory[m.category]) byCategory[m.category] = [];
            byCategory[m.category].push(m);
        });

        Object.entries(byCategory).sort().forEach(([cat, modules]) => {
            const catLabel = document.createElement("div");
            catLabel.className = "text-xs font-bold mt-2";
            catLabel.style.color = "var(--text-accent)";
            catLabel.textContent = `${cat.toUpperCase()} (${modules.length})`;
            moduleList.appendChild(catLabel);

            modules.sort((a, b) => a.name.localeCompare(b.name)).forEach(m => {
                const item = document.createElement("div");
                item.className = "module-card";
                item.style.padding = "6px 8px";
                item.innerHTML = `<span class="text-xs">${m.name}</span>`;
                moduleList.appendChild(item);
            });
        });

        grid.appendChild(moduleList);
        container.appendChild(grid);
    }
}
