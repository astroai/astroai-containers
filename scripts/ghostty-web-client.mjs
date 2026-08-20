// Browser client for CANFAR contributed ingress: all URLs must be relative to
// location.pathname (e.g. /session/contrib/<id>/), not domain-root absolute.

import { init, Terminal, FitAddon } from "./dist/ghostty-web.js";

function sessionBase() {
  const p = location.pathname;
  return p.endsWith("/") ? p : `${p}/`;
}

function showError(err) {
  const el = document.getElementById("terminal");
  if (!el) return;
  el.innerHTML = "";
  const box = document.createElement("pre");
  box.style.cssText =
    "margin:1rem;padding:1rem;background:#313244;color:#f38ba8;" +
    "border:1px solid #585b70;border-radius:8px;white-space:pre-wrap;font:14px/1.4 Menlo,monospace";
  box.textContent = `ghostty-web failed to start:\n${err?.stack || err?.message || err}`;
  el.appendChild(box);
}

try {
  await init();
  const term = new Terminal({
    cols: 80,
    rows: 24,
    fontFamily: "Menlo, monospace",
    fontSize: 15,
    theme: {
      background: "#1e1e2e",
      foreground: "#cdd6f4",
      cursor: "#f5e0dc",
      selectionBackground: "#585b70",
    },
  });
  const fitAddon = new FitAddon();
  term.loadAddon(fitAddon);
  await term.open(document.getElementById("terminal"));
  fitAddon.fit();
  fitAddon.observeResize();

  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  const wsUrl =
    `${proto}//${location.host}${sessionBase()}ws?cols=${term.cols}&rows=${term.rows}`;
  let ws;
  function connect() {
    ws = new WebSocket(wsUrl);
    ws.onmessage = (ev) => term.write(ev.data);
    ws.onclose = () => setTimeout(connect, 2000);
    ws.onerror = () => {
      term.write("\r\n\x1b[31mWebSocket error — retrying…\x1b[0m\r\n");
    };
  }
  connect();

  term.onData((data) => {
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(data);
  });
  term.onResize(({ cols, rows }) => {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: "resize", cols, rows }));
    }
  });
  window.addEventListener("resize", () => fitAddon.fit());
} catch (err) {
  showError(err);
}
