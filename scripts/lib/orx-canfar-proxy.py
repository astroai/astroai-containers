"""Reverse-proxy orx (or similar) for CANFAR contributed sessions.

orx serves a Vite SPA with absolute paths (``/assets/...``, ``/api/...``).
The browser URL is ``/session/contrib/<id>/`` while ingress strips that prefix
before the container. Absolute root paths therefore escape the session and the
UI stays blank (dark empty ``#root``).

This proxy:
  * listens on ``0.0.0.0:PUBLIC_PORT`` (default 5000)
  * forwards to ``127.0.0.1:ORX_PORT`` (default 4791)
  * routes ``/astroai-agents/*`` to the AstroAI agent wizard sidecar
  * rewrites HTML/JS/CSS so absolute ``/api``, ``/assets``, ``/favicon``,
    ``/astroai-agents`` URLs include ``/session/contrib/<skaha_sessionid>``
  * injects a small "Agents" link chip into HTML (proxy-only; no upstream fork)
"""

from __future__ import annotations

import contextlib
import os
import select
import socket
import sys
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

_LIB = Path(__file__).resolve().parent
if str(_LIB) not in sys.path:
    sys.path.insert(0, str(_LIB))
from session_title import stick_html_title  # noqa: E402

PUBLIC_PORT = int(os.environ.get("ASTROAI_OPENRESEARCH_PORT", "5000"))
ORX_HOST = os.environ.get("ORX_HOST", "127.0.0.1")
ORX_PORT = int(os.environ.get("ORX_PORT", "4791"))
WIZARD_HOST = os.environ.get("ASTROAI_AGENT_WIZARD_HOST", "127.0.0.1")
WIZARD_PORT = int(os.environ.get("ASTROAI_AGENT_WIZARD_PORT", "4792"))
SESSION_ID = (os.environ.get("skaha_sessionid") or "").strip()  # noqa: SIM112 — platform env var is lowercase
PREFIX = f"/session/contrib/{SESSION_ID}" if SESSION_ID else ""
WIZARD_MOUNT = "/astroai-agents"

REWRITE_TYPES = (
    "text/html",
    "text/css",
    "text/javascript",
    "application/javascript",
    "application/x-javascript",
    "application/json",
)

# Absolute paths the SPA embeds that must stay under the contrib prefix.
ABS_PREFIXES = ("/api/", "/assets/", "/favicon", "/astroai-agents")

# Agents + session resources (RAM/CPU/GPU/scratch/home)
AGENTS_CHIP = (
    '<a id="astroai-agents-chip" href="{href}" '
    'style="position:fixed;right:16px;top:16px;z-index:2147483646;'
    "padding:10px 14px;border-radius:8px;background:#3d8bfd;color:#fff;"
    "font:600 14px/1.2 system-ui,sans-serif;text-decoration:none;"
    'border:1px solid #5aa0ff;box-shadow:0 4px 16px rgba(0,0,0,.4)">'
    "AstroAI</a>"
)


def rewrite_body(data: bytes, content_type: str) -> bytes:
    ctype = content_type.split(";", 1)[0].strip().lower()
    if ctype not in REWRITE_TYPES and not ctype.endswith("+json"):
        return data
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data
    if PREFIX:
        for abs_prefix in ABS_PREFIXES:
            # Avoid double-prefixing if somehow already rewritten.
            text = text.replace(f'"{PREFIX}{abs_prefix}', f'"__KEEP__{abs_prefix}')
            text = text.replace(f"'{PREFIX}{abs_prefix}", f"'__KEEP__{abs_prefix}")
            text = text.replace(f"`{PREFIX}{abs_prefix}", f"`__KEEP__{abs_prefix}")

            text = text.replace(f'"{abs_prefix}', f'"{PREFIX}{abs_prefix}')
            text = text.replace(f"'{abs_prefix}", f"'{PREFIX}{abs_prefix}")
            text = text.replace(f"`{abs_prefix}", f"`{PREFIX}{abs_prefix}")

            text = text.replace(f'"__KEEP__{abs_prefix}', f'"{PREFIX}{abs_prefix}')
            text = text.replace(f"'__KEEP__{abs_prefix}", f"'{PREFIX}{abs_prefix}")
            text = text.replace(f"`__KEEP__{abs_prefix}", f"`{PREFIX}{abs_prefix}")

    if ctype == "text/html":
        text = stick_html_title(text)
        if "astroai-agents-chip" not in text:
            href = f"{PREFIX}{WIZARD_MOUNT}/" if PREFIX else f"{WIZARD_MOUNT}/"
            chip = AGENTS_CHIP.format(href=href)
            lower = text.lower()
            idx = lower.rfind("</body>")
            text = text[:idx] + chip + text[idx:] if idx >= 0 else text + chip
    return text.encode("utf-8")


def rewrite_location(value: str) -> str:
    if not PREFIX or not value.startswith("/"):
        return value
    if value.startswith(PREFIX + "/") or value == PREFIX:
        return value
    for abs_prefix in ABS_PREFIXES:
        if value == abs_prefix.rstrip("/") or value.startswith(abs_prefix):
            return PREFIX + value
    if value.startswith(("/api", "/assets", WIZARD_MOUNT)):
        return PREFIX + value
    return value


HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-length",
    "host",
}


def _forward(
    handler: BaseHTTPRequestHandler, host: str, port: int, path: str, *, rewrite: bool = True
) -> None:
    accept = handler.headers.get("Accept", "")
    streaming = "text/event-stream" in accept or path.startswith("/api/events")

    headers = {
        k: v
        for k, v in handler.headers.items()
        if k.lower() not in HOP_BY_HOP
    }
    length = int(handler.headers.get("Content-Length", "0") or "0")
    body = handler.rfile.read(length) if length > 0 else None

    conn = HTTPConnection(host, port, timeout=600)
    try:
        conn.request(handler.command, path, body=body, headers=headers)
        upstream = conn.getresponse()
    except OSError as exc:
        if host == WIZARD_HOST and port == WIZARD_PORT:
            fallback = (
                b"<!DOCTYPE html><html><body style='font-family:sans-serif;padding:2rem'>"
                b"<h1>Agents unavailable</h1>"
                b"<p>Use webterm and run <code>astroai agent list --ui</code>.</p>"
                b"</body></html>"
            )
            handler.send_response(503)
            handler.send_header("Content-Type", "text/html; charset=utf-8")
            handler.send_header("Content-Length", str(len(fallback)))
            handler.end_headers()
            with contextlib.suppress(BrokenPipeError, ConnectionResetError):
                handler.wfile.write(fallback)
            return
        handler.send_error(502, f"upstream unreachable: {exc}")
        return

    content_type = upstream.getheader("Content-Type") or ""
    raw = b"" if streaming else upstream.read()
    if not streaming and rewrite:
        raw = rewrite_body(raw, content_type)

    handler.send_response(upstream.status, upstream.reason)
    for key, value in upstream.getheaders():
        lk = key.lower()
        if lk in HOP_BY_HOP:
            continue
        if lk == "location":
            value = rewrite_location(value)
        if lk == "content-length" and not streaming:
            continue
        handler.send_header(key, value)
    if not streaming:
        handler.send_header("Content-Length", str(len(raw)))
    handler.send_header("Connection", "close")
    handler.end_headers()

    if streaming:
        try:
            while True:
                chunk = upstream.read(8192)
                if not chunk:
                    break
                handler.wfile.write(chunk)
                handler.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
    else:
        with contextlib.suppress(BrokenPipeError, ConnectionResetError):
            handler.wfile.write(raw)
    conn.close()


class OrxProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("orx-proxy: %s\n" % (fmt % args))

    def _proxy(self) -> None:
        path = self.path
        # Route AstroAI wizard under /astroai-agents (strip mount for sidecar).
        # Do not rewrite wizard HTML: prefixing quoted `/astroai-agents` in the
        # back-link script makes "Back" navigate to `/` and leave the session.
        if path == WIZARD_MOUNT or path.startswith(WIZARD_MOUNT + "/"):
            rest = path[len(WIZARD_MOUNT) :] or "/"
            _forward(self, WIZARD_HOST, WIZARD_PORT, rest, rewrite=False)
            return
        _forward(self, ORX_HOST, ORX_PORT, path)

    def do_GET(self) -> None:
        self._proxy()

    def do_POST(self) -> None:
        self._proxy()

    def do_PUT(self) -> None:  # noqa: N802
        self._proxy()

    def do_PATCH(self) -> None:  # noqa: N802
        self._proxy()

    def do_DELETE(self) -> None:  # noqa: N802
        self._proxy()

    def do_HEAD(self) -> None:  # noqa: N802
        self._proxy()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._proxy()


def main() -> int:
    server = ThreadingHTTPServer(("0.0.0.0", PUBLIC_PORT), OrxProxyHandler)
    sys.stderr.write(
        f"orx-proxy: listening 0.0.0.0:{PUBLIC_PORT} → {ORX_HOST}:{ORX_PORT} "
        f"wizard={WIZARD_HOST}:{WIZARD_PORT}{WIZARD_MOUNT} "
        f"prefix={PREFIX or '(none)'}\n"
    )
    with contextlib.suppress(KeyboardInterrupt):
        server.serve_forever()
    return 0


if __name__ == "__main__":
    _ = (select, socket, urlsplit)
    raise SystemExit(main())
