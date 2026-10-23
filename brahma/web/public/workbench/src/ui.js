// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 4444J99
/**
 * ui.js — DOM surface for the workbench: tab bar, log panel, status strip.
 *
 * No framework. Every message is rendered as text, never as HTML, so engine and
 * error strings cannot inject markup.
 */

export function createUI({ tabBar, log, status, onSelectTab }) {
  const MAX_LINES = 300;

  function line(kind, text) {
    if (!log) return;
    const el = document.createElement("div");
    el.className = `log-line log-${kind}`;
    el.textContent = text;
    log.appendChild(el);
    while (log.childElementCount > MAX_LINES) log.removeChild(log.firstElementChild);
    log.scrollTop = log.scrollHeight;
  }

  function renderTabs(tabs, active) {
    if (!tabBar) return;
    tabBar.replaceChildren();
    for (const tab of tabs) {
      const btn = document.createElement("button");
      btn.className = "tab" + (tab.id === active ? " tab-active" : "");
      btn.textContent = tab.label;
      btn.type = "button";
      btn.addEventListener("click", () => onSelectTab?.(tab.id));
      tabBar.appendChild(btn);
    }
  }

  function renderStatus({ connected, role, engine }) {
    if (!status) return;
    const bits = [
      connected ? "socket: connected" : "socket: offline",
      `role: ${role || "none"}`
    ];
    if (engine) {
      bits.push(engine.ok ? `engine: ${engine.modules} modules, ${engine.voices} voices` : `engine: ${engine.reason}`);
    }
    status.textContent = bits.join("  ·  ");
  }

  return { line, renderTabs, renderStatus };
}
