/**
 * Module Browser — Searchable/filterable list of all registered modules
 * with dynamic param editor panel
 */
import { createKnob } from "../../golem/ui/knob.js";
import { createSelect } from "../../golem/ui/select.js";

const CATEGORIES = ["all", "engine", "fx", "modular", "makenoise", "elektron", "daemon", "organism"];
const CAT_LABELS = {
    all: "All", engine: "Engines", fx: "Effects", modular: "Modular",
    makenoise: "Make Noise", elektron: "Elektron", daemon: "Daemons", organism: "Organisms"
};

export class ModuleBrowserView {
    constructor(container, state, osc) {
        this.el = container;
        this.state = state;
        this.osc = osc;
        this.filter = "all";
        this.search = "";
        this.knobs = {};
    }

    render() {
        this.el.innerHTML = "";

        // Demo patch bar
        const demoBar = document.createElement("div");
        demoBar.className = "demo-bar";
        demoBar.innerHTML = `
            <span class="demo-label">Demo Patch:</span>
            <span id="demo-status" class="demo-status ${this.state.demoActive ? "active" : "inactive"}">
                ${this.state.demoActive ? "PLAYING" : "STOPPED"}
            </span>
            <button id="demo-toggle" class="action-btn">${this.state.demoActive ? "Stop" : "Start"}</button>
        `;
        demoBar.querySelector("#demo-toggle").addEventListener("click", () => {
            this.osc.send(this.state.demoActive ? "/brahma/demo/stop" : "/brahma/demo/start");
        });
        this.el.appendChild(demoBar);

        const layout = document.createElement("div");
        layout.className = "split-layout";

        // Sidebar: search + categories + module list
        const sidebar = document.createElement("div");
        sidebar.className = "sidebar";

        // Search
        const searchBar = document.createElement("div");
        searchBar.className = "search-bar";
        const searchInput = document.createElement("input");
        searchInput.className = "search-input";
        searchInput.placeholder = "Search modules...";
        searchInput.value = this.search;
        searchInput.addEventListener("input", (e) => {
            this.search = e.target.value.toLowerCase();
            this.renderModuleList(sidebar);
        });
        searchBar.appendChild(searchInput);
        sidebar.appendChild(searchBar);

        // Category filters
        const catBar = document.createElement("div");
        catBar.className = "category-bar";
        CATEGORIES.forEach(cat => {
            const btn = document.createElement("button");
            btn.className = `cat-btn ${cat === this.filter ? "active" : ""}`;
            const count = cat === "all"
                ? Object.keys(this.state.modules).length
                : Object.values(this.state.modules).filter(m => m.category === cat).length;
            btn.innerHTML = `${CAT_LABELS[cat]}<span class="cat-count">${count}</span>`;
            btn.addEventListener("click", () => {
                this.filter = cat;
                this.render();
            });
            catBar.appendChild(btn);
        });
        sidebar.appendChild(catBar);

        // Module list
        this.renderModuleList(sidebar);

        // Main panel
        const mainPanel = document.createElement("div");
        mainPanel.className = "main-panel";
        mainPanel.id = "param-panel-container";

        if (this.state.selectedModule) {
            this.renderParamPanel(mainPanel);
        } else {
            mainPanel.innerHTML = `<div class="card"><p class="text-xs" style="color:var(--text-muted)">Select a module to view parameters</p></div>`;
        }

        layout.append(sidebar, mainPanel);
        this.el.appendChild(layout);
    }

    renderModuleList(sidebar) {
        // Remove existing list
        const existing = sidebar.querySelector(".module-list");
        if (existing) existing.remove();

        const list = document.createElement("div");
        list.className = "module-list";
        list.style.display = "flex";
        list.style.flexDirection = "column";
        list.style.gap = "4px";

        const modules = Object.values(this.state.modules)
            .filter(m => this.filter === "all" || m.category === this.filter)
            .filter(m => !this.search ||
                m.name.toLowerCase().includes(this.search) ||
                m.description.toLowerCase().includes(this.search) ||
                m.category.toLowerCase().includes(this.search))
            .sort((a, b) => a.name.localeCompare(b.name));

        modules.forEach(mod => {
            const card = document.createElement("div");
            card.className = `module-card ${this.state.selectedModule === mod.name ? "selected" : ""}`;
            card.innerHTML = `
                <div class="module-name">${mod.name}</div>
                <div class="module-meta">${mod.category} | ${mod.synthDef} | ${mod.numParams} params</div>
                ${mod.description ? `<div class="module-desc">${mod.description}</div>` : ""}
            `;
            card.addEventListener("click", () => {
                this.state.selectedModule = mod.name;
                // Request params if not cached
                if (!this.state.params[mod.name] || this.state.params[mod.name].length === 0) {
                    this.osc.send("/brahma/modules/params", mod.name);
                }
                this.render();
            });
            list.appendChild(card);
        });

        sidebar.appendChild(list);
    }

    renderParamPanel(container) {
        const mod = this.state.modules[this.state.selectedModule];
        if (!mod) return;

        const panel = document.createElement("div");
        panel.className = "param-panel";

        // Header
        const header = document.createElement("div");
        header.className = "flex items-center justify-between mb-2";
        header.innerHTML = `
            <div>
                <div class="font-bold">${mod.name}</div>
                <div class="text-xs" style="color:var(--text-muted)">${mod.description}</div>
            </div>
        `;
        panel.appendChild(header);

        // Instance controls
        const instBar = document.createElement("div");
        instBar.className = "instance-bar";
        const instInput = document.createElement("input");
        instInput.className = "instance-input";
        instInput.placeholder = "Instance name";
        instInput.value = this.state.selectedInstance || `${mod.name}_1`;

        const createBtn = document.createElement("button");
        createBtn.className = "action-btn";
        createBtn.textContent = "Create";
        createBtn.addEventListener("click", () => {
            const name = instInput.value.trim();
            if (name) {
                this.state.selectedInstance = name;
                this.osc.send("/brahma/module/create", mod.name, name, 0);
            }
        });

        const freeBtn = document.createElement("button");
        freeBtn.className = "action-btn danger";
        freeBtn.textContent = "Free";
        freeBtn.addEventListener("click", () => {
            const name = instInput.value.trim();
            if (name) {
                this.osc.send("/brahma/module/free", mod.name, name);
            }
        });

        instBar.append(instInput, createBtn, freeBtn);
        panel.appendChild(instBar);

        // Param knobs
        this.renderParams(panel);

        container.appendChild(panel);
    }

    renderParams(container) {
        const params = this.state.params[this.state.selectedModule] || [];
        if (params.length === 0) {
            const loading = document.createElement("div");
            loading.className = "text-xs";
            loading.style.color = "var(--text-muted)";
            loading.textContent = "Loading parameters...";
            container.appendChild(loading);
            // Request params
            this.osc.send("/brahma/modules/params", this.state.selectedModule);
            return;
        }

        const grid = document.createElement("div");
        grid.className = "param-grid";
        this.knobs = {};

        params.forEach(p => {
            const knob = createKnob({
                value: p.default,
                min: p.min,
                max: p.max,
                label: p.name,
                onChange: (val) => {
                    const instName = this.state.selectedInstance || `${this.state.selectedModule}_1`;
                    this.osc.send("/brahma/module/set",
                        this.state.selectedModule, instName, p.name, val);
                }
            });
            this.knobs[p.name] = knob;
            grid.appendChild(knob.el);
        });

        container.appendChild(grid);
    }

    updateDemoState() {
        const status = this.el.querySelector("#demo-status");
        const btn = this.el.querySelector("#demo-toggle");
        if (status) {
            status.className = `demo-status ${this.state.demoActive ? "active" : "inactive"}`;
            status.textContent = this.state.demoActive ? "PLAYING" : "STOPPED";
        }
        if (btn) btn.textContent = this.state.demoActive ? "Stop" : "Start";
    }
}
