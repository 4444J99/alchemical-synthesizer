// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 4444J99
/**
 * socket.js — typed WebSocket client for the workbench.
 *
 * Frames are JSON objects. The gateway answers with `auth`, `ack`, `status` and
 * `error`; engine broadcasts arrive as `{address, args}`. Nothing here trusts the
 * server beyond rendering what it says.
 */

export function createSocket({ onFrame, onOpen, onClose }) {
  let ws = null;
  let closedByUs = false;
  let retryTimer = null;
  let attempts = 0;
  const outbox = [];

  function url() {
    const scheme = location.protocol === "https:" ? "wss:" : "ws:";
    return `${scheme}//${location.host}`;
  }

  function flush() {
    while (outbox.length && ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(outbox.shift()));
    }
  }

  function connect() {
    closedByUs = false;
    ws = new WebSocket(url());

    ws.addEventListener("open", () => {
      attempts = 0;
      onOpen?.();
      flush();
    });

    ws.addEventListener("message", (ev) => {
      let frame;
      try {
        frame = JSON.parse(ev.data);
      } catch (_) {
        return; // a non-JSON frame is not ours to render
      }
      onFrame?.(frame);
    });

    ws.addEventListener("close", () => {
      onClose?.();
      if (closedByUs) return;
      attempts += 1;
      const delay = Math.min(5000, 250 * 2 ** Math.min(attempts, 5));
      retryTimer = setTimeout(connect, delay);
    });

    ws.addEventListener("error", () => {
      // `close` follows and owns the retry.
    });
  }

  return {
    connect,
    send(frame) {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(frame));
      } else {
        outbox.push(frame);
      }
    },
    get connected() {
      return !!ws && ws.readyState === WebSocket.OPEN;
    },
    close() {
      closedByUs = true;
      if (retryTimer) clearTimeout(retryTimer);
      try { ws?.close(); } catch (_) { /* already gone */ }
    }
  };
}
