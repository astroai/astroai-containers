"""Prefix rewrite must not run on the AstroAI hub page."""

from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("orx_canfar_proxy", ROOT / "orx-canfar-proxy.py")
assert SPEC and SPEC.loader
proxy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(proxy)


def test_rewrite_prefixes_quoted_astroai_agents() -> None:
    proxy.PREFIX = "/session/contrib/abc"
    html = b"<script>const i = p.indexOf('/astroai-agents');</script>"
    out = proxy.rewrite_body(html, "text/html")
    assert b"/session/contrib/abc/astroai-agents" in out
    assert b"indexOf('/astroai-agents')" not in out


def test_split_marker_survives_rewrite() -> None:
    proxy.PREFIX = "/session/contrib/abc"
    html = b"<html><body><script>const marker = '/astroai-' + 'agents';</script></body></html>"
    out = proxy.rewrite_body(html, "text/html")
    assert b"/astroai-' + 'agents" in out
    assert b"indexOf('/session/contrib/abc/astroai-agents')" not in out


if __name__ == "__main__":
    test_rewrite_prefixes_quoted_astroai_agents()
    test_split_marker_survives_rewrite()
    print("ok")
