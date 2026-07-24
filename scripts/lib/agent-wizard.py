#!/usr/bin/env python3
"""AstroAI hub sidecar — agents + CANFAR + Ray over ``astroai-lab`` CLI.

Listens on 127.0.0.1:ASTROAI_AGENT_WIZARD_PORT (default 4792).
Proxied as /astroai-agents/ by the session path-rewrite proxy.
Failures here must never affect the main UI process.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("ASTROAI_AGENT_WIZARD_PORT", "4792"))
CLI_TIMEOUT = int(os.environ.get("ASTROAI_AGENT_WIZARD_CLI_TIMEOUT", "600"))
HOME = Path.home()


def _run_lab(args: list[str], *, timeout: int | None = None) -> tuple[int, str, str]:
    cmd = ["astroai-lab", *args]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout or CLI_TIMEOUT,
            env=os.environ.copy(),
        )
        return proc.returncode, proc.stdout or "", proc.stderr or ""
    except FileNotFoundError:
        return 127, "", "astroai-lab not found on PATH"
    except subprocess.TimeoutExpired:
        return 124, "", f"timed out after {timeout or CLI_TIMEOUT}s"
    except OSError as exc:
        return 1, "", str(exc)


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
    """Merge status + ray status for the hub CANFAR / Ray panels."""
    tag = os.environ.get("RAY_IMAGE_TAG") or os.environ.get("BUILD_TAG") or "26.07"
    out: dict = {
        "ok": True,
        "session_kind": os.environ.get("ASTROAI_SESSION_KIND") or "",
        "image_tag": tag,
        "canfar": {"auth": None, "sessions": [], "available": False},
        "ray": {},
    }
    rc, stdout, err = _run_lab(["--json", "status"], timeout=90)
    status = _parse_json_stdout(stdout)
    if isinstance(status, dict):
        out["canfar"] = {
            "available": True,
            "auth": status.get("canfar_auth"),
            "sessions": status.get("canfar_sessions") or [],
            "resources": status.get("resources"),
        }
        out["status_cli_exit"] = rc
    else:
        out["canfar"]["error"] = err or stdout or "status failed"
        out["ok"] = False

    rc2, stdout2, err2 = _run_lab(["--json", "ray", "status"], timeout=60)
    ray = _parse_json_stdout(stdout2)
    if isinstance(ray, dict):
        out["ray"] = ray
        out["ray_cli_exit"] = rc2
    else:
        out["ray"] = {
            "hint": "astroai-lab ray status unavailable",
            "launch_command": (
                "canfar create --name raymgr --cpu 2 --memory 8 contributed "
                f"images.canfar.net/astroai/ray-manager:{tag}"
            ),
            "error": err2 or stdout2 or "ray status failed",
        }
        out["ok"] = False
    return out


CHEATSHEET = """\
# Agents (same /arc home)
astroai-lab agent status
astroai-lab agent verify
astroai-lab --yes agent setup
astroai-lab agent install kilo

# CANFAR (interactive login needs webterm)
canfar auth show
canfar ps
canfar login

# Ray (large Jobs — separate ray-manager session)
astroai-lab ray guide
astroai-lab ray status
# Put shared batch I/O on /arc — /scratch is per-pod only
"""

INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>AstroAI</title>
<style>
  :root {
    --bg: #0f1419;
    --panel: #1a2332;
    --text: #e7ecf3;
    --muted: #8b9bb4;
    --accent: #3d8bfd;
    --ok: #3dd68c;
    --warn: #f5a524;
    --err: #f31260;
    --border: #2a3548;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; font-family: "IBM Plex Sans", "Segoe UI", sans-serif;
    background: radial-gradient(1200px 600px at 10% -10%, #1b2a44, var(--bg));
    color: var(--text); min-height: 100vh; padding: 1.5rem;
  }
  h1 { font-size: 1.6rem; font-weight: 600; margin: 0 0 .25rem; letter-spacing: -.02em; }
  .sub { color: var(--muted); margin-bottom: 1.25rem; max-width: 48rem; }
  .row { display: flex; flex-wrap: wrap; gap: .6rem; margin-bottom: 1rem; }
  button {
    background: var(--accent); color: #fff; border: 0; border-radius: 6px;
    padding: .55rem .9rem; font: inherit; cursor: pointer;
  }
  button.secondary { background: var(--panel); border: 1px solid var(--border); }
  button:disabled { opacity: .5; cursor: wait; }
  .grid { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); }
  section {
    background: color-mix(in srgb, var(--panel) 88%, transparent);
    border: 1px solid var(--border); border-radius: 10px; padding: 1rem;
  }
  h2 { font-size: .95rem; margin: 0 0 .75rem; color: var(--muted); text-transform: uppercase; letter-spacing: .06em; }
  table { width: 100%; border-collapse: collapse; font-size: .9rem; }
  td, th { text-align: left; padding: .35rem .25rem; border-bottom: 1px solid var(--border); vertical-align: top; }
  .ok { color: var(--ok); } .bad { color: var(--err); } .warn { color: var(--warn); }
  pre, code {
    background: #0b1018; border: 1px solid var(--border); border-radius: 8px;
    padding: .75rem; overflow: auto; max-height: 220px; font-size: .78rem;
    color: #c5d0e0; white-space: pre-wrap;
  }
  code.inline { padding: .15rem .35rem; max-height: none; }
  #msg { min-height: 1.2rem; margin-bottom: .75rem; color: var(--muted); }
  a { color: var(--accent); }
  .copy { margin-top: .5rem; }
</style>
</head>
<body>
  <h1>AstroAI</h1>
  <p class="sub">Home base for agents, CANFAR sessions, and Ray batch work.
  Shared state lives on <code class="inline">/arc/home</code>. The main UI keeps running if this hub fails.</p>
  <div id="msg"></div>
  <div class="row">
    <button id="btn-refresh" class="secondary">Refresh</button>
    <button id="btn-setup">Core setup</button>
    <button id="btn-verify" class="secondary">Verify</button>
    <button id="btn-update" class="secondary">Update</button>
    <button id="btn-kilo" class="secondary">Install kilo</button>
    <button id="btn-lean" class="secondary">Lean addons</button>
    <button id="btn-models" class="secondary">Free models</button>
  </div>
  <div class="grid">
    <section>
      <h2>Session resources</h2>
      <div id="resources">Loading…</div>
    </section>
    <section>
      <h2>Agents</h2>
      <div id="setup-state">Loading…</div>
      <div id="agents" style="margin-top:.75rem">Loading…</div>
      <div id="issues" style="margin-top:.75rem"></div>
    </section>
    <section>
      <h2>CANFAR</h2>
      <div id="canfar">Loading…</div>
    </section>
    <section>
      <h2>Ray (large Jobs)</h2>
      <div id="ray">Loading…</div>
    </section>
    <section>
      <h2>Shell cheat sheet</h2>
      <pre id="cheat">""" + CHEATSHEET.replace("<", "&lt;") + """</pre>
      <p class="sub" style="margin:0">Interactive <code class="inline">canfar login</code> needs webterm (same home).</p>
    </section>
  </div>
  <section style="margin-top:1rem">
    <h2>Agent setup log</h2>
    <pre id="log"></pre>
  </section>
<script>
const base = (document.querySelector('base') && document.querySelector('base').href) ||
  (location.pathname.replace(/\\/?$/, '/') );
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
function yn(v) { return v ? '<span class="ok">yes</span>' : '<span class="bad">no</span>'; }
function fmtPct(v) { return (v===null||v===undefined) ? '—' : (Math.round(v*10)/10) + '%'; }
function esc(s) {
  return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
function renderResources(r) {
  if (!r) return '<span class="warn">unavailable</span>';
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
  if (!c) return '<span class="warn">unavailable</span>';
  if (c.error) return `<p class="warn">${esc(c.error)}</p>`;
  let html = `<p>Auth: <code class="inline">${esc((c.auth||'').split('\\n')[0] || '(unknown)')}</code></p>`;
  const sessions = c.sessions || [];
  if (!sessions.length) {
    html += '<p class="sub">No sessions from <code class="inline">canfar ps</code> (or CLI missing).</p>';
  } else {
    html += '<pre>' + esc(sessions.slice(0, 40).join('\\n')) + '</pre>';
  }
  html += '<p class="sub">Login once in webterm: <code class="inline">canfar login</code> — credentials persist on /arc/home.</p>';
  return html;
}
function renderRay(r) {
  if (!r) return '<span class="warn">unavailable</span>';
  const tag = r.ray_image_tag || '26.07';
  let html = '';
  if (r.heartbeat_present) {
    html += `<p class="ok">Manager heartbeat: <code class="inline">${esc(r.cluster_id)}</code>` +
      (r.heartbeat_age_seconds!=null ? ` · age ${r.heartbeat_age_seconds}s` : '') +
      (r.phase ? ` · phase ${esc(r.phase)}` : '') + '</p>';
  } else {
    html += '<p class="warn">No Ray manager heartbeat on this home yet.</p>';
  }
  if (r.hint) html += `<p class="sub">${esc(r.hint)}</p>`;
  const launch = r.launch_command ||
    `canfar create --name raymgr --cpu 2 --memory 8 contributed images.canfar.net/astroai/ray-manager:${tag}`;
  html += `<p>Launch manager (Portal or CLI):</p><pre id="ray-launch">${esc(launch)}</pre>`;
  html += '<button class="secondary copy" id="btn-copy-ray">Copy launch command</button>';
  html += `<p class="sub">${esc(r.scratch_note || '/scratch is per-pod — share Jobs data on /arc.')}</p>`;
  html += '<p class="sub">Open the manager Connect URL for the control panel and Jobs dashboard.</p>';
  const clusters = (r.clusters || []).filter(c => c.heartbeat_present);
  if (clusters.length > 1) {
    html += '<p>Heartbeats:</p><ul>' + clusters.map(c =>
      `<li><code class="inline">${esc(c.cluster_id)}</code> age ${c.heartbeat_age_seconds??'—'}s` +
      (c.phase ? ` · ${esc(c.phase)}` : '') + '</li>').join('') + '</ul>';
  }
  return html;
}
async function refresh() {
  setMsg('Loading…');
  const [rep, plat] = await Promise.all([api('api/report'), api('api/platform')]);
  const data = rep.data || {};
  const setup = (data.setup || {});
  document.getElementById('resources').innerHTML = renderResources(data.resources || (plat.data.canfar||{}).resources);
  document.getElementById('setup-state').innerHTML =
    `<p>OK: ${yn(!!data.ok)} · needs retry: ${yn(!!setup.needs_retry)}</p>` +
    `<p>Stamp: <code class="inline">${esc(setup.stamp || '(never)')}</code></p>` +
    (setup.failed ? `<p class="warn">Failed: ${esc(setup.failed)}</p>` : '');
  const rows = (data.agents || []).map(a =>
    `<tr><td>${esc(a.agent)}</td><td>${yn(a.binary)}</td><td>${yn(a.config)}</td></tr>`).join('');
  document.getElementById('agents').innerHTML =
    `<table><tr><th>Agent</th><th>Binary</th><th>Config</th></tr>${rows}</table>`;
  const issues = data.issues || [];
  document.getElementById('issues').innerHTML = issues.length
    ? `<ul>${issues.map(i => `<li class="warn">${esc(i)}</li>`).join('')}</ul>`
    : '<span class="ok">No verify issues</span>';
  document.getElementById('log').textContent = data.log_tail || '(empty)';
  document.getElementById('canfar').innerHTML = renderCanfar((plat.data||{}).canfar);
  document.getElementById('ray').innerHTML = renderRay((plat.data||{}).ray);
  const copyBtn = document.getElementById('btn-copy-ray');
  if (copyBtn) {
    copyBtn.onclick = async () => {
      const t = document.getElementById('ray-launch')?.textContent || '';
      try { await navigator.clipboard.writeText(t); setMsg('Copied launch command', 'ok'); }
      catch { setMsg('Copy failed — select the command manually', 'warn'); }
    };
  }
  setMsg('');
}
async function action(path, label) {
  document.querySelectorAll('button').forEach(b => b.disabled = true);
  setMsg(label + '…');
  try {
    const { data } = await api(path, { method: 'POST' });
    setMsg((data.ok ? 'OK: ' : 'Done with issues: ') + (data.summary || data.error || ''), data.ok ? 'ok' : 'warn');
  } catch (e) {
    setMsg(String(e), 'bad');
  }
  document.querySelectorAll('button').forEach(b => b.disabled = false);
  await refresh();
}
document.getElementById('btn-refresh').onclick = () => refresh();
document.getElementById('btn-setup').onclick = () => action('api/setup', 'Core setup');
document.getElementById('btn-verify').onclick = () => action('api/verify', 'Verify');
document.getElementById('btn-update').onclick = () => action('api/update', 'Update');
document.getElementById('btn-kilo').onclick = () => action('api/install?tool=kilo', 'Install kilo');
document.getElementById('btn-lean').onclick = () => action('api/add?tag=lean', 'Lean addons');
document.getElementById('btn-models').onclick = () => action('api/models-free', 'Free models');
refresh();
setInterval(refresh, 30000);
</script>
</body>
</html>
"""


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
                data["summary"] = "models applied" if rc == 0 else (err or out or "failed")[:300]
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
