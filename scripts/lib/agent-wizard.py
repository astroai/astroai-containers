#!/usr/bin/env python3
"""AstroAI hub sidecar — agents + CANFAR + Ray over ``astroai-lab`` CLI.

Listens on 127.0.0.1:ASTROAI_AGENT_WIZARD_PORT (default 4792).
Proxied as /astroai-agents/ by the session path-rewrite proxy.
Failures here must never affect the main UI process.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import traceback
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("ASTROAI_AGENT_WIZARD_PORT", "4792"))
CLI_TIMEOUT = int(os.environ.get("ASTROAI_AGENT_WIZARD_CLI_TIMEOUT", "600"))
# Hub platform probes must stay snappy — full `astroai-lab status` can hang on
# VOSpace/GMS; prefer short canfar + ray probes in parallel instead.
PLATFORM_CANFAR_TIMEOUT = int(os.environ.get("ASTROAI_HUB_CANFAR_TIMEOUT", "12"))
PLATFORM_RAY_TIMEOUT = int(os.environ.get("ASTROAI_HUB_RAY_TIMEOUT", "30"))
# One-click ensure can create a manager + workers — allow a long wall clock.
COMPUTE_ENSURE_TIMEOUT = int(os.environ.get("ASTROAI_HUB_COMPUTE_ENSURE_TIMEOUT", "1200"))
HOME = Path.home()


def _run_cmd(cmd: list[str], *, timeout: int) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=os.environ.copy(),
        )
        return proc.returncode, proc.stdout or "", proc.stderr or ""
    except FileNotFoundError:
        return 127, "", f"{cmd[0]} not found on PATH"
    except subprocess.TimeoutExpired:
        return 124, "", f"timed out after {timeout}s"
    except OSError as exc:
        return 1, "", str(exc)


def _run_lab(args: list[str], *, timeout: int | None = None) -> tuple[int, str, str]:
    lab = shutil.which("astroai-lab") or "/opt/astroai/venv/cadc/bin/astroai-lab"
    return _run_cmd([lab, *args], timeout=timeout or CLI_TIMEOUT)


def _parse_json_stdout(stdout: str) -> object | None:
    text = stdout.strip()
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            try:
                return json.loads(text[start : end + 1])
            except json.JSONDecodeError:
                return None
        return None


def _log_tail(n: int = 40) -> str:
    path = HOME / ".astroai" / "lab" / "agent-setup.log"
    if not path.is_file():
        return ""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    return "\n".join(lines[-n:])


def _platform_payload() -> dict:
    """CANFAR + Ray panels via short parallel probes (not full lab status)."""
    tag = os.environ.get("RAY_IMAGE_TAG") or os.environ.get("BUILD_TAG") or "26.07"
    out: dict = {
        "ok": True,
        "session_kind": os.environ.get("ASTROAI_SESSION_KIND") or "",
        "image_tag": tag,
        "canfar": {"auth": None, "sessions": [], "available": False},
        "ray": {},
    }

    def _canfar() -> dict:
        if shutil.which("canfar") is None:
            return {
                "available": False,
                "auth": None,
                "sessions": [],
                "error": "canfar CLI not on PATH",
            }
        rc_a, out_a, err_a = _run_cmd(
            ["canfar", "auth", "show"], timeout=PLATFORM_CANFAR_TIMEOUT
        )
        auth = (out_a or err_a or "").strip() or None
        if rc_a == 124:
            auth = f"canfar auth show timed out after {PLATFORM_CANFAR_TIMEOUT}s"
        elif rc_a != 0 and not auth:
            auth = "Not authenticated"
        rc_p, out_p, err_p = _run_cmd(["canfar", "ps"], timeout=PLATFORM_CANFAR_TIMEOUT)
        sessions: list[str] = []
        ps_err = None
        if rc_p == 0:
            sessions = [ln for ln in (out_p or "").splitlines() if ln.strip()]
        elif rc_p == 124:
            ps_err = f"canfar ps timed out after {PLATFORM_CANFAR_TIMEOUT}s"
        else:
            ps_err = (err_p or out_p or "canfar ps failed")[:300]
        payload: dict = {"available": True, "auth": auth, "sessions": sessions}
        if ps_err:
            payload["error"] = ps_err
        return payload

    def _ray() -> tuple[int, dict | None, str]:
        rc2, stdout2, err2 = _run_lab(
            ["--json", "ray", "status"], timeout=PLATFORM_RAY_TIMEOUT
        )
        ray = _parse_json_stdout(stdout2)
        if isinstance(ray, dict):
            return rc2, ray, ""
        return rc2, None, err2 or stdout2 or "ray status failed"

    with ThreadPoolExecutor(max_workers=2) as pool:
        fut_c = pool.submit(_canfar)
        fut_r = pool.submit(_ray)
        out["canfar"] = fut_c.result()
        rc2, ray, ray_err = fut_r.result()

    if ray is not None:
        out["ray"] = ray
        out["ray_cli_exit"] = rc2
    else:
        out["ray"] = {
            "hint": "No batch-compute manager yet — use Start batch compute",
            "launch_command": "astroai-lab ray ensure",
            "error": ray_err,
            "compute_ready": False,
        }
        out["ok"] = False
    if out["canfar"].get("error") and not out["canfar"].get("sessions"):
        out["canfar_soft_fail"] = True
    return out


CHEATSHEET = """\
# Agents (same /arc home)
astroai-lab agent status
astroai-lab agent verify
astroai-lab --yes agent setup
astroai-lab agent install kilo
astroai-lab agent addons --tag lean
astroai-lab agent models free

# CANFAR (interactive login needs webterm)
canfar auth show
canfar ps
canfar login

# Batch compute (manager + workers; wires OpenResearch)
astroai-lab ray ensure
astroai-lab ray status
# Put shared batch I/O on /arc — /scratch is per-pod only
"""

SESSION_KIND = (os.environ.get("ASTROAI_SESSION_KIND") or "").strip().lower()
BACK_UI_LABEL = {
    "openresearch": "OpenResearch",
    "openworker": "OpenWorker",
}.get(SESSION_KIND, "main UI")

INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>AstroAI</title>
<link rel="preconnect" href="https://fonts.googleapis.com"/>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin/>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Source+Sans+3:wght@400;600&family=Sora:wght@500;600;700&display=swap" rel="stylesheet"/>
<style>
  :root {
    --bg: #0a1014;
    --bg2: #122018;
    --ink: #e8f0ea;
    --muted: #8aa094;
    --line: #24332a;
    --teal: #2ec4b6;
    --teal-dim: #1a8f84;
    --sky: #9ec9ff;
    --ok: #5dde9a;
    --warn: #e6b84d;
    --err: #ff6b7a;
    --panel: rgba(16, 28, 22, 0.72);
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    min-height: 100vh;
    color: var(--ink);
    font-family: "Source Sans 3", "Segoe UI", sans-serif;
    background:
      radial-gradient(900px 480px at 8% -8%, rgba(46,196,182,.18), transparent 55%),
      radial-gradient(700px 420px at 92% 0%, rgba(158,201,255,.10), transparent 50%),
      linear-gradient(165deg, var(--bg2), var(--bg) 42%, #070c0f);
    padding: clamp(1rem, 3vw, 2.25rem);
  }
  .wrap { max-width: 72rem; margin: 0 auto; }
  .top {
    display: flex; flex-wrap: wrap; align-items: flex-start;
    justify-content: space-between; gap: 1rem 1.5rem;
    margin-bottom: 1.25rem;
    animation: rise .45s ease both;
  }
  .back {
    display: inline-flex; align-items: center; gap: .4rem;
    color: var(--sky); text-decoration: none; font-weight: 600;
    font-size: .95rem; border-bottom: 1px solid transparent;
    transition: border-color .2s ease, color .2s ease;
  }
  .back:hover { border-color: var(--sky); color: #cfe4ff; }
  .brand h1 {
    font-family: Sora, "Source Sans 3", sans-serif;
    font-size: clamp(2rem, 4.5vw, 2.75rem);
    font-weight: 700; letter-spacing: -.03em;
    margin: .15rem 0 .35rem; line-height: 1.05;
  }
  .brand .tag {
    display: inline-block; color: var(--teal);
    font-family: Sora, sans-serif; font-weight: 600;
    font-size: .78rem; letter-spacing: .12em; text-transform: uppercase;
  }
  .lede {
    color: var(--muted); max-width: 36rem; margin: 0;
    font-size: 1.05rem; line-height: 1.45;
  }
  .actions {
    display: flex; flex-wrap: wrap; gap: .55rem;
    margin: 0 0 1rem; animation: rise .5s .05s ease both;
  }
  button, .btn {
    font: 600 .92rem/1 Sora, "Source Sans 3", sans-serif;
    border: 0; border-radius: 8px; padding: .65rem 1rem;
    cursor: pointer; color: #04221f; background: var(--teal);
    transition: transform .15s ease, filter .15s ease, background .15s ease;
  }
  button:hover, .btn:hover { filter: brightness(1.06); transform: translateY(-1px); }
  button.secondary, .btn.secondary {
    background: transparent; color: var(--ink);
    border: 1px solid var(--line);
  }
  button:disabled { opacity: .5; cursor: wait; transform: none; filter: none; }
  #msg {
    min-height: 1.25rem; margin: 0 0 1rem; color: var(--muted);
    font-size: .95rem; animation: rise .5s .08s ease both;
  }
  #msg.ok { color: var(--ok); } #msg.warn { color: var(--warn); } #msg.bad { color: var(--err); }
  .grid {
    display: grid; gap: 1.25rem;
    grid-template-columns: repeat(12, 1fr);
    animation: rise .55s .1s ease both;
  }
  section.panel {
    grid-column: span 6;
    padding: 1.1rem 1.15rem 1.2rem;
    border-top: 1px solid var(--line);
    background: linear-gradient(180deg, rgba(255,255,255,.02), transparent 40%);
  }
  section.panel.wide { grid-column: span 12; }
  @media (max-width: 860px) {
    section.panel, section.panel.wide { grid-column: span 12; }
  }
  h2 {
    font-family: Sora, sans-serif;
    font-size: .72rem; font-weight: 600; margin: 0 0 .85rem;
    color: var(--muted); letter-spacing: .14em; text-transform: uppercase;
  }
  h2 .hint {
    display: block; margin-top: .35rem; letter-spacing: 0; text-transform: none;
    font-family: "Source Sans 3", sans-serif; font-weight: 400; font-size: .88rem;
    color: var(--muted); line-height: 1.35; max-width: 40rem;
  }
  p { margin: .35rem 0; }
  .sub { color: var(--muted); font-size: .9rem; }
  table { width: 100%; border-collapse: collapse; font-size: .92rem; }
  th, td { text-align: left; padding: .4rem .2rem; border-bottom: 1px solid var(--line); vertical-align: top; }
  th { color: var(--muted); font-weight: 600; font-size: .8rem; }
  .ok { color: var(--ok); } .bad { color: var(--err); } .warn { color: var(--warn); }
  pre, code, .mono {
    font-family: "IBM Plex Mono", ui-monospace, monospace;
  }
  pre {
    background: rgba(0,0,0,.28); border: 1px solid var(--line); border-radius: 8px;
    padding: .75rem; overflow: auto; max-height: 220px; font-size: .76rem;
    color: #c8d8cc; white-space: pre-wrap; margin: .5rem 0;
  }
  code.inline {
    background: rgba(0,0,0,.28); border: 1px solid var(--line);
    border-radius: 5px; padding: .12rem .35rem; font-size: .82rem;
  }
  ul.clean { margin: .4rem 0; padding-left: 1.1rem; }
  ul.clean li { margin: .25rem 0; }
  .result {
    margin-top: .75rem; padding: .65rem .75rem; border-radius: 8px;
    border: 1px dashed var(--line); color: var(--muted); font-size: .9rem;
    white-space: pre-wrap;
  }
  .result.has { color: var(--ink); border-style: solid; border-color: rgba(46,196,182,.35); }
  details.more {
    margin-top: 1.25rem; border-top: 1px solid var(--line); padding-top: 1rem;
    animation: rise .6s .12s ease both;
  }
  details.more summary {
    cursor: pointer; font-family: Sora, sans-serif; font-weight: 600;
    color: var(--muted); letter-spacing: .04em;
  }
  a { color: var(--sky); }
  @keyframes rise {
    from { opacity: 0; transform: translateY(8px); }
    to { opacity: 1; transform: none; }
  }
</style>
</head>
<body>
  <div class="wrap">
    <header class="top">
      <div class="brand">
        <a class="back" id="back-link" href="../">← Back to __BACK_LABEL__</a>
        <div class="tag">Agents · CANFAR · Batch compute</div>
        <h1>AstroAI</h1>
        <p class="lede">Status and setup for coding agents on shared <code class="inline">/arc/home</code> — not a chat UI. Your __BACK_LABEL__ session keeps running.</p>
      </div>
    </header>

    <div class="actions">
      <button id="btn-setup">Core setup</button>
      <button id="btn-fix">Auto-Fix</button>
      <button id="btn-clean" class="secondary">Clean</button>
      <button id="btn-verify" class="secondary">Verify</button>
      <button id="btn-update" class="secondary">Update</button>
      <button id="btn-refresh" class="secondary">Refresh</button>
    </div>
    <div id="msg"></div>

    <div class="grid">
      <section class="panel">
        <h2>Agents<span class="hint">CLI install status on this home — binary on PATH and config present.</span></h2>
        <div id="setup-state">Loading…</div>
        <div id="agents" style="margin-top:.75rem">Loading…</div>
        <div id="issues" style="margin-top:.75rem"></div>
        <div class="actions" style="margin-top:.9rem;margin-bottom:0">
          <button id="btn-kilo" class="secondary">Install Kilo CLI</button>
        </div>
        <p class="sub">Kilo is an optional coding agent (<code class="inline">kilo auth</code> after install). Use agents from webterm / the main UI — this page only installs and verifies.</p>
      </section>

      <section class="panel">
        <h2>AI Tools &amp; Container Catalog<span class="hint">Curated directory of AI coding agents, skills, rules, MCPs, and container UIs.</span></h2>
        <div id="catalog">Loading…</div>
      </section>

      <section class="panel">
        <h2>Session resources &amp; Endpoints<span class="hint">This pod only — home quota and active container services.</span></h2>
        <div id="resources">Loading…</div>
        <div id="interact" style="margin-top:.75rem">Loading endpoints…</div>
      </section>

      <section class="panel">
        <h2>Lean addons<span class="hint">Curated skills/rules (not agents). List loads below; Install applies the lean tag.</span></h2>
        <div id="addons">Loading…</div>
        <div class="actions" style="margin-top:.75rem;margin-bottom:0">
          <button id="btn-lean" class="secondary">Install lean addons</button>
        </div>
        <div id="addons-result" class="result">No install run yet.</div>
      </section>

      <section class="panel">
        <h2>Free models<span class="hint">Writes free-tier presets into agent configs (Kilo / OpenRouter). Needs keys for some agents.</span></h2>
        <div id="models">Loading…</div>
        <div class="actions" style="margin-top:.75rem;margin-bottom:0">
          <button id="btn-models" class="secondary">Apply free models</button>
        </div>
        <div id="models-result" class="result">No apply run yet.</div>
      </section>

      <section class="panel">
        <h2>CANFAR sessions<span class="hint">Auth + your open sessions (quota). Batch workers are started below, not listed here as Jobs.</span></h2>
        <div id="canfar">Loading…</div>
      </section>

      <section class="panel">
        <h2>Batch compute<span class="hint">One click starts a manager session + workers and wires OpenResearch. You do not need to configure Ray.</span></h2>
        <div id="ray">Loading…</div>
        <div class="actions" style="margin-top:.75rem;margin-bottom:0">
          <button id="btn-compute">Start batch compute</button>
          <button id="btn-compute-refresh" class="secondary">Refresh</button>
        </div>
        <div id="compute-result" class="result">Not started yet — click Start after agents/keys are set.</div>
      </section>
    </div>

    <details class="more">
      <summary>Shell cheat sheet &amp; setup log</summary>
      <pre id="cheat">__CHEATSHEET__</pre>
      <p class="sub"><code class="inline">canfar login</code> is interactive — run it once in webterm (same home).</p>
      <h2 style="margin-top:1rem">Agent setup log</h2>
      <pre id="log"></pre>
    </details>
  </div>
<script>
const BACK_LABEL = __BACK_LABEL_JSON__;
const base = (document.querySelector('base') && document.querySelector('base').href) ||
  (location.pathname.replace(/\\/?$/, '/') );
function mainUiHref() {
  const p = location.pathname;
  const i = p.indexOf('/astroai-agents');
  if (i >= 0) {
    const root = p.slice(0, i);
    return (root || '') + '/';
  }
  return '../';
}
(function initBack() {
  const a = document.getElementById('back-link');
  a.href = mainUiHref();
  a.textContent = '← Back to ' + BACK_LABEL;
})();
async function api(path, opts) {
  const r = await fetch(base.replace(/\\/?$/, '/') + path.replace(/^\\//,''), opts);
  const text = await r.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { ok: false, error: text }; }
  return { status: r.status, data };
}
function setMsg(t, cls) {
  const el = document.getElementById('msg');
  el.textContent = t || '';
  el.className = cls || '';
}
function setResult(id, text, ok) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = text || '';
  el.className = 'result' + (text ? ' has' : '');
  if (ok === true) el.classList.add('ok');
  if (ok === false) el.classList.add('warn');
}
function yn(v) { return v ? '<span class="ok">yes</span>' : '<span class="bad">no</span>'; }
function fmtPct(v) { return (v===null||v===undefined) ? '—' : (Math.round(v*10)/10) + '%'; }
function esc(s) {
  return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
function renderResources(r) {
  if (!r || !Object.keys(r).length) return '<p class="sub">No resource snapshot yet — try Refresh after setup.</p>';
  const home = r.home || {};
  const scratch = r.scratch || {};
  const gpus = r.gpu || [];
  let html = `<p>CPU ~${fmtPct(r.cpu_pct)} · RAM ${fmtPct(r.mem_pct)}` +
    (r.cgroup_mem_pct!=null ? ` · cgroup ${fmtPct(r.cgroup_mem_pct)}` : '') + `</p>`;
  html += `<p>Home ${fmtPct(home.pct)} <span class="sub">(${home.source||'?'})</span>` +
    ` · Scratch ${fmtPct(scratch.pct)}</p>`;
  if (gpus.length) {
    html += '<p>GPU: ' + gpus.map(g => `${esc(g.name||'gpu')} ${fmtPct(g.util_pct)}`).join(', ') + '</p>';
  }
  for (const n of (r.notes||[])) html += `<p class="sub">${esc(n)}</p>`;
  return html;
}
function renderCanfar(c) {
  if (!c) return '<p class="warn">CANFAR probe unavailable.</p>';
  let html = '<p class="sub">Confirm you are logged in (<code class="inline">canfar login</code> once in webterm). Session quota includes the batch-compute manager.</p>';
  if (c.error && !(c.sessions||[]).length) {
    html += `<p class="warn">${esc(c.error)}</p>`;
  }
  const authLine = ((c.auth||'').split('\\n')[0] || '').trim();
  html += `<p>Auth: <code class="inline">${esc(authLine || '(unknown)')}</code></p>`;
  const sessions = c.sessions || [];
  if (!sessions.length) {
    html += '<p class="sub">No session list yet. If auth looks empty, open <strong>webterm</strong> (same home) and run <code class="inline">canfar login</code> once, then Refresh.</p>';
  } else {
    html += '<pre>' + esc(sessions.slice(0, 40).join('\\n')) + '</pre>';
  }
  return html;
}
function renderRay(r) {
  if (!r) return '<span class="warn">unavailable</span>';
  let html = '';
  if (r.compute_ready || r.ray_address || r.connect_url) {
    html += '<p class="ok">Batch compute is configured for OpenResearch.</p>';
    if (r.ray_address) {
      html += '<p class="sub">Jobs endpoint ready (wired automatically).</p>';
    }
    if (r.connect_url) {
      html += `<p class="sub">Manager: <a href="${esc(r.connect_url)}" target="_blank" rel="noopener">open panel</a></p>`;
    }
  } else if (r.heartbeat_present) {
    html += `<p class="ok">Manager heartbeat: <code class="inline">${esc(r.cluster_id)}</code>` +
      (r.heartbeat_age_seconds!=null ? ` · age ${r.heartbeat_age_seconds}s` : '') +
      (r.phase ? ` · phase ${esc(r.phase)}` : '') + '</p>';
  } else {
    html += '<p class="warn">No batch-compute cluster yet — click <strong>Start batch compute</strong>.</p>';
  }
  if (r.hint) html += `<p class="sub">${esc(r.hint)}</p>`;
  html += `<p class="sub">${esc(r.scratch_note || '/scratch is per-pod — share Jobs data on /arc.')}</p>`;
  html += '<p class="sub">After Start succeeds, go back to OpenResearch and run experiments — default compute is set for you. Focus on agent API keys above.</p>';
  return html;
}
function renderAddons(d) {
  const rows = (d && d.addons) || [];
  if (!rows.length) {
    return '<p class="sub">No lean addons listed (bundle missing or CLI error).'
      + (d && d.error ? ' ' + esc(d.error) : '') + '</p>';
  }
  return '<table><tr><th>Addon</th><th>In</th><th>Summary</th></tr>' +
    rows.map(a => `<tr><td><code class="inline">${esc(a.id)}</code></td>` +
      `<td>${a.installed ? '<span class="ok">yes</span>' : '<span class="bad">no</span>'}</td>` +
      `<td class="sub">${esc(a.summary||'')}</td></tr>`).join('') + '</table>';
}
function renderModels(d) {
  const presets = (d && d.presets) || {};
  const names = Object.keys(presets);
  if (!names.length) {
    return '<p class="sub">No presets listed.'
      + (d && d.error ? ' ' + esc(d.error) : '') + '</p>';
  }
  let html = '<table><tr><th>Preset</th><th>What it sets</th></tr>';
  for (const name of names) {
    const m = presets[name] || {};
    html += `<tr><td><code class="inline">${esc(name)}</code></td>` +
      `<td><strong>${esc(m.label||'')}</strong><br/><span class="sub">${esc(m.description||'')}</span>` +
      (m.openrouter ? `<br/><span class="sub">OpenRouter: ${esc(m.openrouter)}</span>` : '') +
      (m.kilo ? `<br/><span class="sub">Kilo: ${esc(m.kilo)}</span>` : '') +
      `</td></tr>`;
  }
  html += '</table>';
  html += '<p class="sub">Default apply uses preset <code class="inline">coding</code>. Set <code class="inline">OPENROUTER_API_KEY</code> for Goose/OpenCode/Codex free tiers; Kilo can sign in at kilo.ai.</p>';
  return html;
}
function renderCatalog(d) {
  const rows = (d && d.items) || [];
  if (!rows.length) return '<p class="sub">No catalog items loaded.</p>';
  return '<table><tr><th>Item</th><th>Kind</th><th>Status</th><th>Summary</th></tr>' +
    rows.slice(0, 15).map(i => `<tr><td><code class="inline">${esc(i.id)}</code></td>` +
      `<td>${esc(i.kind)}</td>` +
      `<td>${i.installed ? '<span class="ok">installed</span>' : '<span class="sub">available</span>'}</td>` +
      `<td class="sub">${esc(i.summary||'')}</td></tr>`).join('') + '</table>';
}
function renderInteract(d) {
  const eps = (d && d.endpoints) || [];
  if (!eps.length) return '<p class="sub">No endpoints detected.</p>';
  let html = '<ul class="clean">';
  for (const ep of eps) {
    const mark = ep.active ? '<span class="ok">✓ ONLINE</span>' : '<span class="sub">— OFFLINE</span>';
    html += `<li>[${mark}] <strong>${esc(ep.name)}</strong> (${esc(ep.url_hint)})<br/><span class="sub">${esc(ep.description)}</span></li>`;
  }
  html += '</ul>';
  return html;
}
async function refreshLists() {
  const [add, mod, cat, inter] = await Promise.all([
    api('api/addons?tag=lean'),
    api('api/models'),
    api('api/catalog'),
    api('api/interact'),
  ]);
  document.getElementById('addons').innerHTML = renderAddons(add.data || {});
  document.getElementById('models').innerHTML = renderModels(mod.data || {});
  document.getElementById('catalog').innerHTML = renderCatalog(cat.data || {});
  document.getElementById('interact').innerHTML = renderInteract(inter.data || {});
}
async function refresh() {
  setMsg('Loading…');
  document.getElementById('canfar').innerHTML = '<span class="sub">Loading CANFAR…</span>';
  document.getElementById('ray').innerHTML = '<span class="sub">Loading batch compute…</span>';
  const rep = await api('api/report');
  const data = rep.data || {};
  const setup = (data.setup || {});
  document.getElementById('resources').innerHTML = renderResources(data.resources || {});
  document.getElementById('setup-state').innerHTML =
    `<p>OK: ${yn(!!data.ok)} · needs retry: ${yn(!!setup.needs_retry)}</p>` +
    `<p>Stamp: <code class="inline">${esc(setup.stamp || '(never)')}</code></p>` +
    (setup.failed ? `<p class="warn">Failed: ${esc(setup.failed)}</p>` : '');
  const rows = (data.agents || []).map(a =>
    `<tr><td>${esc(a.agent)}</td><td>${yn(a.binary)}</td><td>${yn(a.config)}</td></tr>`).join('');
  document.getElementById('agents').innerHTML = rows
    ? `<table><tr><th>Agent</th><th>Binary</th><th>Config</th></tr>${rows}</table>`
    : '<p class="sub">No agent report yet — run Core setup.</p>';
  const issues = data.issues || [];
  document.getElementById('issues').innerHTML = issues.length
    ? `<ul class="clean">${issues.map(i => `<li class="warn">${esc(i)}</li>`).join('')}</ul>`
    : '<span class="ok">No verify issues</span>';
  document.getElementById('log').textContent = data.log_tail || '(empty)';
  await refreshLists();
  setMsg('Refreshing CANFAR / batch compute…');
  const plat = await api('api/platform');
  document.getElementById('canfar').innerHTML = renderCanfar((plat.data||{}).canfar);
  document.getElementById('ray').innerHTML = renderRay((plat.data||{}).ray);
  setMsg('');
}
async function action(path, label, resultId) {
  document.querySelectorAll('button').forEach(b => b.disabled = true);
  setMsg(label + '…');
  try {
    const { data } = await api(path, { method: 'POST' });
    const summary = data.summary || data.error || data.user_message || '';
    setMsg((data.ok ? 'OK: ' : 'Done with issues: ') + summary, data.ok ? 'ok' : 'warn');
    if (resultId) {
      const detail = Array.isArray(data.actions)
        ? data.actions.map(a => typeof a === 'string' ? a :
            `${a.id||''}: ${a.status||''}${a.detail ? ' — '+a.detail : ''}`).join('\\n')
        : (data.user_message || summary);
      setResult(resultId, detail || summary || '(no detail)', !!data.ok);
    }
  } catch (e) {
    setMsg(String(e), 'bad');
    if (resultId) setResult(resultId, String(e), false);
  }
  document.querySelectorAll('button').forEach(b => b.disabled = false);
  await refresh();
}
document.getElementById('btn-refresh').onclick = () => refresh();
document.getElementById('btn-setup').onclick = () => action('api/setup', 'Core setup');
document.getElementById('btn-fix').onclick = () => action('api/fix', 'Auto-Fix');
document.getElementById('btn-clean').onclick = () => action('api/clean', 'Clean state');
document.getElementById('btn-verify').onclick = () => action('api/verify', 'Verify');
document.getElementById('btn-update').onclick = () => action('api/update', 'Update');
document.getElementById('btn-kilo').onclick = () => action('api/install?tool=kilo', 'Install Kilo');
document.getElementById('btn-lean').onclick = () => action('api/add?tag=lean', 'Install lean addons', 'addons-result');
document.getElementById('btn-models').onclick = () => action('api/models-free', 'Apply free models', 'models-result');
document.getElementById('btn-compute').onclick = () =>
  action('api/compute/ensure', 'Starting batch compute (can take several minutes)', 'compute-result');
document.getElementById('btn-compute-refresh').onclick = () => refresh();
refresh();
setInterval(refresh, 45000);
</script>
</body>
</html>
""".replace("__BACK_LABEL__", BACK_UI_LABEL).replace(
    "__BACK_LABEL_JSON__", json.dumps(BACK_UI_LABEL)
).replace("__CHEATSHEET__", CHEATSHEET.replace("<", "&lt;"))


FALLBACK_HTML = """<!DOCTYPE html>
<html><head><meta charset="utf-8"/><title>AstroAI</title></head>
<body style="font-family:sans-serif;padding:2rem;background:#111;color:#eee">
<h1>AstroAI hub unavailable</h1>
<p>Use webterm (same /arc home) and run:</p>
<pre style="background:#222;padding:1rem">""" + CHEATSHEET + """</pre>
</body></html>
"""


class WizardHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("agent-wizard: %s\n" % (fmt % args))

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _json(self, code: int, payload: dict) -> None:
        raw = json.dumps(payload).encode("utf-8")
        self._send(code, raw, "application/json; charset=utf-8")

    def _path(self) -> tuple[str, dict[str, list[str]]]:
        parsed = urlparse(self.path)
        path = parsed.path
        for prefix in ("/astroai-agents",):
            if path.startswith(prefix):
                path = path[len(prefix) :] or "/"
        return path, parse_qs(parsed.query)

    def do_GET(self) -> None:  # noqa: N802
        path, _qs = self._path()
        if path in ("/", "/index.html"):
            self._send(200, INDEX_HTML.encode("utf-8"), "text/html; charset=utf-8")
            return
        if path == "/api/report":
            rc, out, err = _run_lab(["agent", "report"], timeout=120)
            data = _parse_json_stdout(out)
            if isinstance(data, dict):
                data.setdefault("log_tail", _log_tail())
                data["cli_exit"] = rc
                if err and not data.get("ok"):
                    data.setdefault("cli_stderr", err[-2000:])
                self._json(200 if rc in (0, 1) else 500, data)
                return
            self._json(
                500,
                {
                    "ok": False,
                    "error": err or out or "report failed",
                    "log_tail": _log_tail(),
                    "cli_exit": rc,
                },
            )
            return
        if path == "/api/platform":
            try:
                self._json(200, _platform_payload())
            except Exception as exc:  # noqa: BLE001
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path == "/api/addons":
            tag = (_qs.get("tag") or ["lean"])[0]
            args = ["--json", "agent", "addons"]
            if tag:
                args.extend(["--tag", tag])
            rc, out, err = _run_lab(args, timeout=60)
            data = _parse_json_stdout(out)
            if isinstance(data, list):
                self._json(200, {"ok": rc == 0, "addons": data, "tag": tag, "cli_exit": rc})
                return
            if isinstance(data, dict) and "addons" in data:
                data.setdefault("ok", rc == 0)
                data.setdefault("tag", tag)
                data["cli_exit"] = rc
                self._json(200, data)
                return
            self._json(
                200 if rc == 0 else 500,
                {
                    "ok": False,
                    "addons": [],
                    "tag": tag,
                    "error": err or out or "addons list failed",
                    "cli_exit": rc,
                },
            )
            return
        if path == "/api/models":
            rc, out, err = _run_lab(["--json", "agent", "models", "list"], timeout=30)
            data = _parse_json_stdout(out)
            if isinstance(data, dict):
                self._json(
                    200,
                    {"ok": rc == 0, "presets": data, "cli_exit": rc, "error": err or None},
                )
                return
            self._json(
                200 if rc == 0 else 500,
                {
                    "ok": False,
                    "presets": {},
                    "error": err or out or "models list failed",
                    "cli_exit": rc,
                },
            )
            return
        if path in ("/api/catalog", "/api/awesome"):
            rc, out, err = _run_lab(["--json", "agent", "catalog"], timeout=30)
            data = _parse_json_stdout(out)
            if isinstance(data, list):
                self._json(200, {"ok": rc == 0, "items": data, "cli_exit": rc})
                return
            self._json(200 if rc == 0 else 500, {"ok": False, "items": [], "error": err or out})
            return
        if path == "/api/interact":
            rc, out, err = _run_lab(["--json", "agent", "interact"], timeout=30)
            data = _parse_json_stdout(out)
            if isinstance(data, dict):
                self._json(200, data)
                return
            self._json(200 if rc == 0 else 500, {"ok": False, "endpoints": [], "error": err or out})
            return
        if path == "/healthz":
            self._json(200, {"ok": True})
            return
        self._send(404, b"not found\n", "text/plain; charset=utf-8")

    def do_POST(self) -> None:  # noqa: N802
        path, qs = self._path()
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length:
            self.rfile.read(length)

        try:
            if path == "/api/setup":
                rc, out, err = _run_lab(["--yes", "--json", "agent", "setup"])
                data = _parse_json_stdout(out) or {}
                if not isinstance(data, dict):
                    data = {}
                data["ok"] = rc == 0
                data["partial"] = rc == 2
                data["cli_exit"] = rc
                data["summary"] = (
                    "setup ok"
                    if rc == 0
                    else ("partial setup" if rc == 2 else (err or out or "setup failed")[:300])
                )
                data["log_tail"] = _log_tail()
                self._json(200, data)
                return

            if path == "/api/fix":
                rc, out, err = _run_lab(["--json", "agent", "fix"], timeout=180)
                data = _parse_json_stdout(out) or {}
                if isinstance(data, list):
                    data = {"ok": rc == 0, "actions": data}
                data["ok"] = rc == 0
                data["summary"] = "fix ok" if rc == 0 else (err or out or "fix failed")[:300]
                data["log_tail"] = _log_tail()
                self._json(200, data)
                return

            if path == "/api/clean":
                rc, out, err = _run_lab(["--json", "agent", "clean"], timeout=60)
                data = _parse_json_stdout(out) or {}
                if isinstance(data, list):
                    data = {"ok": rc == 0, "actions": data}
                data["ok"] = rc == 0
                data["summary"] = "clean ok" if rc == 0 else (err or out or "clean failed")[:300]
                data["log_tail"] = _log_tail()
                self._json(200, data)
                return

            if path == "/api/verify":
                rc, out, err = _run_lab(["--json", "agent", "verify"], timeout=180)
                data = _parse_json_stdout(out) or {}
                if not isinstance(data, dict):
                    data = {}
                data["ok"] = rc == 0
                data["cli_exit"] = rc
                data["summary"] = "verify ok" if rc == 0 else (err or out or "verify failed")[:300]
                data["log_tail"] = _log_tail()
                self._json(200, data)
                return

            if path == "/api/update":
                rc, out, err = _run_lab(["--yes", "--json", "agent", "update"], timeout=600)
                data = _parse_json_stdout(out) or {}
                if not isinstance(data, dict):
                    data = {}
                data["ok"] = rc == 0
                data["cli_exit"] = rc
                data["summary"] = "update ok" if rc == 0 else (err or out or "update failed")[:300]
                data["log_tail"] = _log_tail()
                self._json(200, data)
                return

            if path == "/api/install":
                tool = (qs.get("tool") or ["kilo"])[0]
                rc, out, err = _run_lab(["--json", "agent", "install", tool])
                data = _parse_json_stdout(out) or {}
                if not isinstance(data, dict):
                    data = {}
                data["ok"] = rc == 0
                data["cli_exit"] = rc
                data["summary"] = f"install {tool}" if rc == 0 else (err or out or "failed")[:300]
                data["log_tail"] = _log_tail()
                self._json(200, data)
                return

            if path == "/api/add":
                tag = (qs.get("tag") or [None])[0]
                name = (qs.get("name") or [None])[0]
                args = ["--yes", "--json", "agent", "add"]
                if tag:
                    args.extend(["--tag", tag])
                elif name:
                    args.append(name)
                else:
                    args.extend(["--tag", "lean"])
                rc, out, err = _run_lab(args)
                data = _parse_json_stdout(out) or {}
                if not isinstance(data, dict):
                    data = {}
                data["ok"] = rc == 0
                data["partial"] = rc == 2
                data["cli_exit"] = rc
                actions = data.get("actions") or []
                if actions:
                    n_ok = sum(
                        1
                        for a in actions
                        if isinstance(a, dict) and a.get("status") not in ("failed", "skipped")
                    )
                    n_skip = sum(
                        1 for a in actions if isinstance(a, dict) and a.get("status") == "skipped"
                    )
                    n_fail = sum(
                        1 for a in actions if isinstance(a, dict) and a.get("status") == "failed"
                    )
                    data["summary"] = (
                        f"lean addons: {n_ok} installed, {n_skip} skipped, {n_fail} failed"
                    )
                else:
                    data["summary"] = "addons ok" if rc == 0 else (err or out or "failed")[:300]
                data["log_tail"] = _log_tail()
                self._json(200, data)
                return

            if path == "/api/models-free":
                rc, out, err = _run_lab(["--yes", "--json", "agent", "models", "free"])
                data = _parse_json_stdout(out) or {}
                if not isinstance(data, dict):
                    data = {}
                data["ok"] = rc == 0
                data["cli_exit"] = rc
                actions = data.get("actions") or []
                if actions:
                    data["summary"] = "; ".join(str(a) for a in actions[:6])
                else:
                    data["summary"] = (
                        "models applied" if rc == 0 else (err or out or "failed")[:300]
                    )
                self._json(200, data)
                return

            if path == "/api/compute/ensure":
                # Long-running: create manager + workers + wire orx.
                rc, out, err = _run_lab(
                    ["--json", "ray", "ensure"],
                    timeout=COMPUTE_ENSURE_TIMEOUT,
                )
                data = _parse_json_stdout(out)
                if not isinstance(data, dict):
                    data = {
                        "ok": False,
                        "error": (err or out or "ray ensure failed")[:800],
                        "cli_exit": rc,
                    }
                else:
                    data["cli_exit"] = rc
                    if "ok" not in data:
                        data["ok"] = rc == 0
                if not data.get("summary"):
                    data["summary"] = data.get("user_message") or (
                        "batch compute ready" if data.get("ok") else (err or "failed")[:300]
                    )
                self._json(200, data)
                return

            self._send(404, b"not found\n", "text/plain; charset=utf-8")
        except Exception as exc:  # noqa: BLE001 — never crash the server loop
            self._json(
                500,
                {
                    "ok": False,
                    "error": str(exc),
                    "trace": traceback.format_exc()[-1500:],
                    "log_tail": _log_tail(),
                },
            )


def main() -> int:
    try:
        server = ThreadingHTTPServer(("127.0.0.1", PORT), WizardHandler)
    except OSError as exc:
        sys.stderr.write(f"agent-wizard: bind failed: {exc}\n")
        return 1
    sys.stderr.write(f"agent-wizard: listening 127.0.0.1:{PORT}\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
