"""Browser tab title = CANFAR session name (pod hostname)."""

from __future__ import annotations

import re
import socket

_SKIP = frozenset({"localhost", "astroai", "unknown"})
_HEX_ID = re.compile(r"^[0-9a-f]{12,}$")


def session_tab_title(fallback: str = "AstroAI") -> str:
    """Skaha sets spec.hostname to the session name (lowercase)."""
    try:
        name = socket.gethostname().split(".")[0].strip()
    except OSError:
        return fallback
    lowered = name.lower()
    if not name or lowered in _SKIP or _HEX_ID.fullmatch(lowered):
        return fallback
    return name


def stick_html_title(html: str, fallback: str = "AstroAI") -> str:
    """Set <title> and keep a SPA from overwriting it."""
    if "data-astroai-tab" in html:
        return html
    title = session_tab_title(fallback)
    html = re.sub(
        r"<title>[^<]*</title>",
        f"<title>{title}</title>",
        html,
        count=1,
        flags=re.IGNORECASE,
    )
    script = (
        '<script data-astroai-tab="1">(function(){var t='
        + repr(title)
        + ";function s(){if(document.title!==t)document.title=t}s();"
        "addEventListener('load',s);"
        "var el=document.querySelector('title');"
        "if(el)new MutationObserver(s).observe(el,"
        "{childList:true,characterData:true,subtree:true});"
        "})();</script>"
    )
    lower = html.lower()
    idx = lower.find("<head>")
    if idx >= 0:
        insert = idx + len("<head>")
        return html[:insert] + script + html[insert:]
    return script + html
