/**
 * CORTEX — Brahma Universal Control Surface
 * Main application: OSC connection, registry state, view routing
 */
import { OSCClient } from "../golem/osc-client.js";
import { applyTheme } from "../golem/themes.js";
import { ModuleBrowserView } from "./components/module-browser.js";
import { EnginePanelView } from "./components/engine-panel.js";
import { PatchMatrixView } from "./components/patch-matrix.js";
import { ChronosPanelView } from "./components/chronos-panel.js";
import { DaemonPanelView } from "./components/daemon-panel.js";
import { SerpensPanelView } from "./components/serpens-panel.js";

// ==========================================
// APPLICATION STATE
// ==========================================
const state = {
    connected: false,
    modules: {},       // name -> { name, category, synthDef, numParams, numInstances, description }
    params: {},        // moduleName -> [{ name, default, min, max, units, desc }]
    selectedModule: null,
    selectedInstance: null,
    // Transport
    playing: false,
    tempo: 120,
    tickCount: 0,
    // Demo patch
    demoActive: false,
    // SERPENS
    serpensTemplates: {},  // name -> { active: bool }
};

// ==========================================
// OSC CLIENT
// ==========================================
const osc = new OSCClient();
const wsUrl = `ws://${window.location.hostname}:${window.location.port}`;
osc.connect(wsUrl);

// Connection status
const origOnOpen = osc.ws?.onopen;
const updateConnection = () => {
    state.connected = osc.connected;
    const dot = document.getElementById("status-indicator");
    if (dot) {
        dot.className = `status-dot ${state.connected ? "connected" : "disconnected"}`;
    }
};
// Poll connection state
setInterval(updateConnection, 1000);

// ==========================================
// INBOUND: SC -> Web (registry broadcasts)
// ==========================================
osc.on("/brahma/registry/module", (args) => {
    const name = args[0]?.value ?? args[0];
    state.modules[name] = {
        name,
        category: args[1]?.value ?? args[1],
        synthDef: args[2]?.value ?? args[2],
        numParams: args[3]?.value ?? args[3],
        numInstances: args[4]?.value ?? args[4],
        description: args[5]?.value ?? args[5] ?? ""
    };
    updateModuleCount();
});

osc.on("/brahma/registry/param", (args) => {
    const moduleName = args[0]?.value ?? args[0];
    const paramName = args[1]?.value ?? args[1];
    if (!state.params[moduleName]) state.params[moduleName] = [];
    const existing = state.params[moduleName].findIndex(p => p.name === paramName);
    const param = {
        name: paramName,
        default: args[2]?.value ?? args[2],
        min: args[3]?.value ?? args[3],
        max: args[4]?.value ?? args[4],
        units: args[5]?.value ?? args[5] ?? "",
        desc: args[6]?.value ?? args[6] ?? ""
    };
    if (existing >= 0) {
        state.params[moduleName][existing] = param;
    } else {
        state.params[moduleName].push(param);
    }
});

osc.on("/brahma/registry/done", (args) => {
    updateModuleCount();
    if (views.modules) views.modules.render();
});

osc.on("/brahma/registry/params/done", (args) => {
    const moduleName = args[0]?.value ?? args[0];
    if (state.selectedModule === moduleName && views.modules) {
        views.modules.renderParams();
    }
});

// Transport state
osc.on("/chronos/transport", (args) => {
    state.playing = !!(args[0]?.value ?? args[0]);
    state.tempo = args[1]?.value ?? args[1];
    updateTransportUI();
});

osc.on("/chronos/tick", (args) => {
    state.tickCount = args[0]?.value ?? args[0];
});

// Demo patch state
osc.on("/brahma/demo/state", (args) => {
    state.demoActive = !!(args[0]?.value ?? args[0]);
    if (views.modules) views.modules.updateDemoState();
});

// SERPENS template state
osc.on("/serpens/template", (args) => {
    const name = args[0]?.value ?? args[0];
    const active = !!(args[1]?.value ?? args[1]);
    state.serpensTemplates[name] = { active };
    if (views.serpens) views.serpens.render();
});

osc.on("/serpens/state", (args) => {
    const name = args[0]?.value ?? args[0];
    const active = !!(args[1]?.value ?? args[1]);
    state.serpensTemplates[name] = { active };
    if (views.serpens) views.serpens.render();
});

function updateModuleCount() {
    const el = document.getElementById("module-count");
    if (el) el.textContent = `${Object.keys(state.modules).length} modules`;
}

// ==========================================
// REQUEST INITIAL DATA
// ==========================================
// On connect, request full registry
const connectCheck = setInterval(() => {
    if (osc.connected) {
        osc.send("/brahma/modules/list");
        osc.send("/serpens/list");
        clearInterval(connectCheck);
    }
}, 500);

// ==========================================
// VIEWS
// ==========================================
const views = {};

function initViews() {
    views.modules = new ModuleBrowserView(
        document.getElementById("view-modules"), state, osc
    );
    views.engines = new EnginePanelView(
        document.getElementById("view-engines"), state, osc
    );
    views.patchbay = new PatchMatrixView(
        document.getElementById("view-patchbay"), state, osc
    );
    views.chronos = new ChronosPanelView(
        document.getElementById("view-chronos"), state, osc
    );
    views.daemons = new DaemonPanelView(
        document.getElementById("view-daemons"), state, osc
    );
    views.serpens = new SerpensPanelView(
        document.getElementById("view-serpens"), state, osc
    );
}

// ==========================================
// VIEW ROUTER
// ==========================================
function switchView(name) {
    document.querySelectorAll(".view").forEach(v => v.classList.remove("active"));
    document.querySelectorAll(".nav-btn").forEach(b => b.classList.remove("active"));

    const view = document.getElementById(`view-${name}`);
    const btn = document.querySelector(`.nav-btn[data-view="${name}"]`);
    if (view) view.classList.add("active");
    if (btn) btn.classList.add("active");

    if (views[name]?.render) views[name].render();
}

// ==========================================
// TRANSPORT
// ==========================================
function updateTransportUI() {
    const playBtn = document.getElementById("btn-play");
    if (playBtn) {
        playBtn.classList.toggle("active", state.playing);
        playBtn.textContent = state.playing ? "PLAYING" : "PLAY";
    }
    const bpmInput = document.getElementById("bpm-input");
    if (bpmInput) bpmInput.value = Math.round(state.tempo);
}

function initTransport() {
    document.getElementById("btn-play")?.addEventListener("click", () => {
        osc.send("/chronos/transport/play");
    });
    document.getElementById("btn-stop")?.addEventListener("click", () => {
        osc.send("/chronos/transport/stop");
    });
    document.getElementById("bpm-input")?.addEventListener("change", (e) => {
        const bpm = parseFloat(e.target.value);
        if (bpm >= 30 && bpm <= 300) {
            state.tempo = bpm;
            osc.send("/chronos/transport/tempo", bpm);
        }
    });
}

// ==========================================
// THEME
// ==========================================
function initTheme() {
    const select = document.getElementById("theme-select");
    select?.addEventListener("change", (e) => {
        applyTheme(e.target.value);
        Object.values(views).forEach(v => v?.render?.());
    });
    applyTheme("midnight");
}

// ==========================================
// NAV
// ==========================================
function initNav() {
    document.querySelectorAll(".nav-btn").forEach(btn => {
        btn.addEventListener("click", () => {
            switchView(btn.dataset.view);
        });
    });
}

// ==========================================
// BOOT
// ==========================================
document.addEventListener("DOMContentLoaded", () => {
    initTheme();
    initNav();
    initTransport();
    initViews();
    switchView("modules");
});
