"""CANFAR session widget helpers for marimo notebooks.

Import this module inside a marimo cell::

    from canfar_marimo import file_browser, vospace_controls

    fb = file_browser()
    fb  # last expression → display

    vc = vospace_controls()
    vc.panel  # display inputs + buttons

In a dependent cell, call ``vc.result_md()`` so list/download reacts to clicks.

VOSpace via marimo **Remote Storage** waits on upstream ``vos`` fsspec support.
Until then, use these helpers (or ``vls`` / ``vcp`` in a webterm).
"""

from __future__ import annotations

from types import SimpleNamespace

import marimo as mo


def file_browser(initial_path: str = "/scratch", **kwargs: object) -> object:
    """Return a ``mo.ui.file_browser`` configured for CANFAR session storage.

    Navigation is unrestricted so users can reach ``/scratch``, ``/srcdir``,
    ``/arc/home/*``, and ``/arc/projects/*``. Include the return value as the
    cell's last expression (or in a layout) so it renders.
    """
    return mo.ui.file_browser(
        initial_path=initial_path,
        restrict_navigation=False,
        label="Browse session storage",
        **kwargs,
    )


def file_browser_tips() -> object:
    """Markdown tips for the file browser — use as the cell's last expression."""
    return mo.md(
        """
**Tip:** Navigate to:

- `/scratch` — fast session SSD for data and caches
- `/arc/home/<you>` — persistent home (config, credentials)
- `/arc/projects/<group>` — persistent shared datasets
- `/srcdir` — session code workspace
"""
    )


def vospace_controls() -> SimpleNamespace:
    """Build Vault UI controls as marimo globals-friendly objects.

    Returns a namespace with:

    - ``panel`` — layout to display (inputs + buttons)
    - ``result_md()`` — markdown for the latest list/download action
    - ``available`` — whether ``vos`` imported
    - widget attrs: ``uri``, ``dest``, ``list_btn``, ``fetch_btn``
    """
    vos_mod = None
    err = ""
    try:
        import vos as vos_mod  # noqa: F841
    except ImportError:
        err = (
            "`vos` module not found (expected in the Docker image). "
            "In a **webterm**: `uv pip install --system vos`"
        )

    available = vos_mod is not None
    uri = mo.ui.text(
        label="vos: URI",
        placeholder="vos:cadc.nrc.ca~vospace/your/path",
        full_width=True,
    )
    dest = mo.ui.text(label="Download to", value="/scratch")
    list_btn = mo.ui.button(label="List contents", disabled=not available)
    fetch_btn = mo.ui.button(label="Download file", disabled=not available)

    header = (
        mo.md(f"**Warning:** {err}")
        if err
        else mo.md(
            "Authenticate first: **webterm** → `canfar login`, then list or download."
        )
    )
    panel = mo.vstack([header, uri, dest, mo.hstack([list_btn, fetch_btn])])

    def result_md() -> object:
        if not available or vos_mod is None:
            return mo.md("VOSpace client unavailable.")
        if list_btn.value and uri.value:
            try:
                client = vos_mod.Client()
                entries = client.listdir(uri.value)
                body = "\n".join(entries)
                return mo.md(f"```\nContents of {uri.value}:\n{body}\n```")
            except Exception as exc:  # noqa: BLE001
                return mo.md(f"**Error:** {exc}")
        if fetch_btn.value and uri.value:
            try:
                client = vos_mod.Client()
                fname = uri.value.rstrip("/").rsplit("/", 1)[-1]
                target = dest.value or "/scratch"
                client.copy(uri.value, f"{target}/{fname}")
                return mo.md(f"**Copied** `{uri.value}` → `{target}/{fname}`")
            except Exception as exc:  # noqa: BLE001
                return mo.md(f"**Error:** {exc}")
        return mo.md("_Enter a `vos:` URI and click **List contents** or **Download file**._")

    return SimpleNamespace(
        available=available,
        uri=uri,
        dest=dest,
        list_btn=list_btn,
        fetch_btn=fetch_btn,
        panel=panel,
        result_md=result_md,
    )


class VOSpaceUI:
    """Backward-compatible wrapper around :func:`vospace_controls`.

    Prefer ``vospace_controls()`` in new notebooks. Display ``.panel`` and call
    ``.result_md()`` from a dependent cell so button clicks stay reactive.
    """

    def __init__(self) -> None:
        self._vc = vospace_controls()
        self.available = self._vc.available
        self.msg = "" if self.available else "vos unavailable"
        self.uri = self._vc.uri
        self.dest = self._vc.dest
        self.list_btn = self._vc.list_btn
        self.fetch_btn = self._vc.fetch_btn
        self.panel = self._vc.panel

    def render(self) -> object:
        """Return the control panel (use as the cell's last expression)."""
        return self.panel

    def result_md(self) -> object:
        return self._vc.result_md()


__all__ = [
    "file_browser",
    "file_browser_tips",
    "vospace_controls",
    "VOSpaceUI",
]
