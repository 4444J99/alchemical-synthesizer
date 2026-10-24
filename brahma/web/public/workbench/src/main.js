// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 4444J99
/**
 * main.js — workbench entry point.
 *
 * Boot sequence: claim the human role from the launch URL's `#t=` fragment (exchanged
 * once for an HttpOnly cookie), open the typed socket, wire transport controls, then
 * start the Strudel scheduler with Brahma as its output.
 *
 * The browser is never trusted by the gateway. Everything here is presentation; the
 * authorization decisions live server-side.
 */

import { createEditor } from "./editor.js";
import { createSocket } from "./socket.js";
import { createStrudel } from "./strudel.js";
import { createUI } from "./ui.js";

const DEFAULT_ENGINE = "prima_materia";

const STARTER_TABS = [
  {
    id: "pattern",
    label: "pattern",
    doc: `// Strudel pattern language → Brahma.
// ctrl/cmd + enter runs the active tab.
note("c3 e3 g3 b3").s("sawtooth")
`
  },
  {
    id: "bass",
    label: "bass",
    doc: `note("c2 ~ c2 eb2").gain(0.7)
`
  },
  {
    id: "texture",
    label: "texture",
    doc: `note("c5 e5 g5").slow(2).gain(0.4)
`
  }
];

const $ = (sel) => document.querySelector(sel);

function readLaunchToken() {
  const params = new URLSearchParams(location.hash.replace(/^#/, ""));
  return params.get("t");
}

function stripTokenFromUrl() {
  if (location.hash) history.replaceState(null, "", location.pathname + location.search);
}

async function claimHumanRole(token) {
  if (!token) return false;
  try {
    const res = await fetch("/api/auth/exchange", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token })
    });
    return res.ok;
  } catch (_) {
    return false;
  }
}

async function fetchModules() {
  try {
    const res = await fetch("/api/modules");
    if (!res.ok) return [];
    const items = await res.json();
    return items.map((m) => m && m.name).filter(Boolean);
  } catch (_) {
    return [];
  }
}

async function main() {
  const ui = createUI({
    tabBar: $("#tabs"),
    log: $("#log"),
    status: $("#status"),
    onSelectTab: (id) => {
      editor.setActive(id);
      ui.renderTabs(STARTER_TABS.map((t) => ({ id: t.id, label: t.label })), id);
      refreshStatus();
    }
  });

  const state = {
    connected: false,
    role: null,
    engine: null,
    running: null
  };

  const editor = createEditor({
    mount: $("#editor"),
    tabs: STARTER_TABS,
    onChange: () => {
      // Editing invalidates the running buffer's identity; the server holds the
      // authority, but the UI should stop claiming a pattern is current.
      if (state.running) setRunning(null);
    }
  });

  const strudel = createStrudel({
    send: (frame) => socket.send(frame),
    onError: (err) => {
      ui.line("error", `evaluate: ${err.message}`);
      state.running = null;
      setRunning(null);
    },
    onState: ({ started }) => {
      if (!started) state.running = null;
    }
  });

  const socket = createSocket({
    onOpen: () => {
      state.connected = true;
      ui.line("info", "socket connected");
      socket.send({ type: "status" });
      refreshStatus();
    },
    onClose: () => {
      state.connected = false;
      ui.line("warn", "socket closed — retrying");
      refreshStatus();
    },
    onFrame: (frame) => {
      if (frame.type === "auth") {
        state.role = frame.role;
      } else if (frame.type === "ack") {
        ui.line("info", `${frame.action}${frame.id ? " " + frame.id : ""} ok`);
        if (frame.action === "run") setRunning(frame.id);
        if (frame.action === "stop" || frame.action === "stop_all") setRunning(null);
      } else if (frame.type === "status") {
        state.role = frame.role || state.role;
        state.engine = frame.engine;
      } else if (frame.type === "error") {
        ui.line("error", `${frame.code}: ${frame.message}`);
      } else if (frame.address === "/brahma/live/error") {
        ui.line("error", `engine: ${frame.args?.[0]} ${frame.args?.[1] ?? ""}`);
      } else if (frame.address === "/brahma/live/panic/done") {
        ui.line("info", `panic: ${frame.args?.[0]} voices, ${frame.args?.[1]} instances freed`);
      }
      refreshStatus();
    }
  });

  function setRunning(id) {
    state.running = id;
    const badge = $("#running");
    if (badge) badge.textContent = id ? `running: ${id}` : "stopped";
    if (badge) badge.className = id ? "badge badge-live" : "badge";
  }

  function refreshStatus() {
    ui.renderStatus({ connected: state.connected, role: state.role, engine: state.engine });
  }

  function requireHuman(action) {
    if (state.role === "human") return true;
    ui.line("error", `${action} needs the human role. Open the URL the gateway printed at launch.`);
    return false;
  }

  function run() {
    if (!requireHuman("run")) return;
    const id = editor.active;
    const code = editor.getText(id);
    if (!code.trim()) {
      ui.line("warn", "nothing to run");
      return;
    }
    const engine = $("#engine")?.value || DEFAULT_ENGINE;
    socket.send({ type: "run", id, engine, source: code });
    ui.line("info", `run ${id} → ${engine}`);
    strudel.evaluate(code, { id, engine });
  }

  function stopOne() {
    if (!requireHuman("stop")) return;
    if (state.running) socket.send({ type: "stop", id: state.running });
    strudel.stop();
    setRunning(null);
  }

  function panic() {
    if (!requireHuman("panic")) return;
    socket.send({ type: "stop_all" });
    strudel.stop();
    setRunning(null);
    ui.line("warn", "panic sent");
  }

  $("#run")?.addEventListener("click", run);
  $("#stop")?.addEventListener("click", stopOne);
  $("#panic")?.addEventListener("click", panic);
  $("#status-btn")?.addEventListener("click", () => socket.send({ type: "status" }));

  window.addEventListener("keydown", (ev) => {
    if ((ev.metaKey || ev.ctrlKey) && ev.key === "Enter") {
      ev.preventDefault();
      run();
    }
    if (ev.key === "Escape") {
      ev.preventDefault();
      panic();
    }
  });

  ui.renderTabs(STARTER_TABS.map((t) => ({ id: t.id, label: t.label })), editor.active);

  // Claim the role before opening the socket, so the first frame is already trusted.
  const token = readLaunchToken(); // allow-secret
  if (token) {
    const ok = await claimHumanRole(token);
    stripTokenFromUrl();
    ui.line(ok ? "info" : "error", ok ? "human role claimed" : "launch token rejected");
    state.role = ok ? "human" : null;
  } else {
    ui.line("warn", "no launch token in the URL — run/stop/panic will be refused");
  }

  const modules = await fetchModules();
  strudel.setKnownEngines(modules);

  const select = $("#engine");
  if (select) {
    select.replaceChildren();
    const names = modules.length ? modules : [{ name: DEFAULT_ENGINE }];
    for (const m of names) {
      const name = typeof m === "string" ? m : m.name;
      const opt = document.createElement("option");
      opt.value = name;
      opt.textContent = name;
      select.appendChild(opt);
    }
    if (!names.some((n) => (typeof n === "string" ? n : n.name) === DEFAULT_ENGINE)) {
      const opt = document.createElement("option");
      opt.value = DEFAULT_ENGINE;
      opt.textContent = DEFAULT_ENGINE;
      select.appendChild(opt);
    }
    select.value = DEFAULT_ENGINE;
  }

  ui.line("info", `engine modules visible: ${modules.length}`);
  socket.connect();
  refreshStatus();
}

main().catch((err) => {
  const log = document.querySelector("#log");
  if (log) {
    const el = document.createElement("div");
    el.className = "log-line log-error";
    el.textContent = `boot failed: ${err.message}`;
    log.appendChild(el);
  }
});
