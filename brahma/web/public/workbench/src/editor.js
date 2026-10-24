// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 4444J99
/**
 * editor.js — multi-tab CodeMirror 6 buffers.
 *
 * Each tab keeps its own EditorState, so undo history and cursor position survive a
 * tab switch. `onChange` reports the active tab's text so the caller can hash it for
 * the approval boundary.
 */

import { EditorState } from "@codemirror/state";
import { EditorView, basicSetup } from "codemirror";
import { javascript } from "@codemirror/lang-javascript";

const theme = EditorView.theme({
  "&": { height: "100%", fontSize: "13px" },
  ".cm-scroller": { fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace' }
});

export function createEditor({ mount, tabs, onChange }) {
  const states = new Map();
  const order = (tabs || [{ id: "pattern", label: "pattern", doc: "" }]).map((t) => t.id);
  let active = order[0];

  function extensions() {
    return [
      basicSetup,
      javascript(),
      EditorView.lineWrapping,
      theme,
      EditorView.updateListener.of((update) => {
        if (!update.docChanged) return;
        onChange?.(active, update.state.doc.toString());
      })
    ];
  }

  for (const tab of tabs || []) {
    states.set(tab.id, EditorState.create({ doc: tab.doc || "", extensions: extensions() }));
  }

  const view = new EditorView({ state: states.get(active), parent: mount });

  function setActive(id) {
    if (!states.has(id) || id === active) return;
    // Persist the live state of the tab we are leaving.
    states.set(active, view.state);
    active = id;
    view.setState(states.get(id));
    view.focus();
  }

  return {
    view,
    get active() {
      return active;
    },
    get order() {
      return [...order];
    },
    getText(id = active) {
      return states.get(id) ? states.get(id).doc.toString() : "";
    },
    setText(id, text) {
      const state = states.get(id);
      if (!state) return;
      states.set(id, EditorState.create({ doc: text, extensions: extensions() }));
      if (id === active) view.setState(states.get(id));
    },
    setActive,
    focus() {
      view.focus();
    }
  };
}
