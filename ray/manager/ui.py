"""HTML helpers for the Ray manager contributed UI."""

from __future__ import annotations

import html
from urllib.parse import quote


def flash_html(flash: str | None, message: str | None) -> str:
    if not flash or not message:
        return ""
    safe = html.escape(message)
    kind = {
        "ok": "flash-ok",
        "error": "flash-error",
        "warn": "flash-warn",
    }.get(flash, "flash-info")
    return f'<p class="flash {kind}" role="alert">{safe}</p>'


def redirect_with_flash(path: str, flash: str, message: str) -> str:
    return f"{path}?flash={quote(flash)}&msg={quote(message)}"


def phase_class(phase: str) -> str:
    mapping = {
        "Running": "phase-ok",
        "Creating": "phase-busy",
        "Degraded": "phase-warn",
        "Failed": "phase-bad",
        "Stopped": "phase-muted",
        "Idle": "phase-muted",
        "Stopping": "phase-busy",
    }
    return mapping.get(phase, "phase-muted")


PAGE_STYLE = """
:root {
  --bg: #0f1419;
  --bg-elevated: #1a222c;
  --bg-card: #1e2733;
  --border: #2d3a4a;
  --text: #e7eef7;
  --muted: #9aabbd;
  --accent: #3d9cf0;
  --accent-hover: #5aaff5;
  --ok: #3dd68c;
  --warn: #f5c542;
  --bad: #f07178;
  --info: #7aa2f7;
  --radius: 10px;
  --font: "IBM Plex Sans", "Segoe UI", system-ui, sans-serif;
  --mono: "IBM Plex Mono", "SF Mono", ui-monospace, monospace;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: var(--font);
  background:
    radial-gradient(1200px 600px at 10% -10%, rgba(61,156,240,0.18), transparent 55%),
    radial-gradient(900px 500px at 100% 0%, rgba(61,214,140,0.08), transparent 50%),
    var(--bg);
  color: var(--text);
  line-height: 1.45;
  min-height: 100vh;
}
a { color: var(--accent); text-decoration: none; }
a:hover { color: var(--accent-hover); text-decoration: underline; }
.wrap { max-width: 1100px; margin: 0 auto; padding: 1.25rem 1.25rem 3rem; }
.topbar {
  display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
  gap: 1rem; margin-bottom: 1.25rem;
}
.brand h1 { margin: 0; font-size: 1.45rem; font-weight: 650; letter-spacing: -0.02em; }
.brand p { margin: 0.2rem 0 0; color: var(--muted); font-size: 0.92rem; }
.cta-row { display: flex; flex-wrap: wrap; gap: 0.6rem; align-items: center; }
.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 0.4rem;
  border: 1px solid var(--border); background: var(--bg-card); color: var(--text);
  border-radius: 8px; padding: 0.5rem 0.9rem; font: inherit; font-weight: 560;
  cursor: pointer; text-decoration: none;
}
.btn:hover { border-color: var(--accent); color: var(--text); text-decoration: none; }
.btn-primary {
  background: linear-gradient(180deg, #4aa6f5, #2f86d6);
  border-color: #2a78c4; color: #fff;
}
.btn-primary:hover { filter: brightness(1.06); color: #fff; }
.btn-danger { border-color: #8a3a40; color: #ffb4b8; }
.btn-ghost { background: transparent; }
.cards {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 0.75rem; margin: 1rem 0 1.25rem;
}
.card {
  background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--radius);
  padding: 0.85rem 1rem;
}
.card .label { color: var(--muted); font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.04em; }
.card .value { margin-top: 0.35rem; font-size: 1.15rem; font-weight: 650; }
.card .sub { margin-top: 0.2rem; color: var(--muted); font-size: 0.82rem; font-family: var(--mono); }
.panel {
  background: var(--bg-elevated); border: 1px solid var(--border); border-radius: var(--radius);
  padding: 1rem 1.1rem; margin-bottom: 1rem;
}
.panel h2 { margin: 0 0 0.75rem; font-size: 1.05rem; }
.grid {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 0.65rem; margin: 0.5rem 0 1rem;
}
label { display: flex; flex-direction: column; gap: 0.3rem; font-size: 0.85rem; color: var(--muted); }
input, select {
  background: var(--bg); border: 1px solid var(--border); border-radius: 7px;
  color: var(--text); padding: 0.45rem 0.55rem; font: inherit;
}
table { border-collapse: collapse; width: 100%; margin: 0.35rem 0 0.25rem; font-size: 0.9rem; }
th, td { border-bottom: 1px solid var(--border); padding: 0.55rem 0.45rem; text-align: left; vertical-align: top; }
th { color: var(--muted); font-weight: 560; font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.03em; }
code, .mono { font-family: var(--mono); font-size: 0.86em; }
.actions { display: flex; flex-wrap: wrap; gap: 0.5rem; }
form.inline { display: inline; margin: 0; }
.flash { padding: 0.7rem 0.9rem; border-radius: 8px; margin: 0 0 1rem; border: 1px solid transparent; }
.flash-ok { background: rgba(61,214,140,0.12); border-color: rgba(61,214,140,0.35); color: var(--ok); }
.flash-error { background: rgba(240,113,120,0.12); border-color: rgba(240,113,120,0.35); color: var(--bad); }
.flash-warn { background: rgba(245,197,66,0.12); border-color: rgba(245,197,66,0.35); color: var(--warn); }
.flash-info { background: rgba(122,162,247,0.12); border-color: rgba(122,162,247,0.35); color: var(--info); }
.phase-ok { color: var(--ok); }
.phase-busy { color: var(--accent); }
.phase-warn { color: var(--warn); }
.phase-bad { color: var(--bad); }
.phase-muted { color: var(--muted); }
.pill {
  display: inline-block; padding: 0.12rem 0.5rem; border-radius: 999px;
  border: 1px solid var(--border); font-size: 0.78rem; font-weight: 600;
}
.muted { color: var(--muted); }
.footer { margin-top: 1.5rem; color: var(--muted); font-size: 0.85rem; }
.progress {
  height: 8px; background: var(--bg); border-radius: 999px; overflow: hidden; margin-top: 0.55rem;
}
.progress > span {
  display: block; height: 100%; background: linear-gradient(90deg, #2f86d6, #3dd68c);
  width: 0%; transition: width 0.4s ease;
}
.op-banner {
  display: none; margin-bottom: 1rem; padding: 0.7rem 0.9rem; border-radius: 8px;
  border: 1px solid rgba(61,156,240,0.35); background: rgba(61,156,240,0.1);
}
.op-banner.active { display: block; }
"""
