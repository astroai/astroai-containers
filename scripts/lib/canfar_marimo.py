"""CANFAR session widget helpers for marimo notebooks.

Import this module inside a marimo cell to get pre-configured file browser
and VOSpace widgets without copy-pasting boilerplate::

    from canfar_marimo import file_browser, vospace_ui

    fb = file_browser()
    vs = vospace_ui()
"""

from __future__ import annotations

import marimo as mo


def file_browser(initial_path: str = "/scratch", **kwargs: object) -> object:
    """Return a ``mo.ui.file_browser`` configured for CANFAR session storage.

    Navigation is unrestricted so users can reach ``/scratch``, ``/srcdir``,
    ``/arc/home/*``, and ``/arc/projects/*``.
    """
    return mo.ui.file_browser(
        initial_path=initial_path,
        restrict_navigation=False,
        label="Browse session storage",
        **kwargs,
    )


def file_browser_tips() -> object:
    """Render markdown with navigation tips for the file browser widget."""
    return mo.md(
        """
    💡 **Tip:** Navigate to:
    - `/scratch` — fast session SSD for data & caches
    - `/arc/home/<you>` — persistent home (config, credentials)
    - `/arc/projects/<group>` — persistent shared datasets
    - `/srcdir` — session code workspace
    """
    )


class VOSpaceUI:
    """Reusable CANFAR VOSpace browser for marimo notebooks.

    Usage inside a marimo cell::

        vs = canfar_marimo.VOSpaceUI()
        vs.render()
        return (vs,)
    """

    def __init__(self) -> None:
        self.available = False
        self.msg = ""
        self._vos = None
        try:
            import vos  # noqa: F401

            self._vos = vos
            self.available = True
        except ImportError:
            self.msg = (
                "`vos` module not found (expected in the Docker image). "
                "Run in a **webterm**: `uv pip install --system vos`"
            )

        self.uri = mo.ui.text(
            label="vos: URI",
            placeholder="vos:cadc.nrc.ca~vospace/your/path",
            full_width=True,
        )
        self.dest = mo.ui.text(
            label="Download to",
            value="/scratch",
        )
        self.list_btn = mo.ui.button(
            label="List contents",
            disabled=not self.available,
        )
        self.fetch_btn = mo.ui.button(
            label="Download file",
            disabled=not self.available,
        )
        self.result = mo.output()

    def render(self) -> None:
        """Render the full VOSpace UI. Call once per cell evaluation."""
        if self.msg:
            mo.md(
                f"""
            <div style="border-left:4px solid #f5c542;
                        background:rgba(245,197,66,0.08);
                        padding:0.5rem 0.75rem;border-radius:0 8px 8px 0;
                        margin:0.5rem 0;">
            ⚠️ {self.msg}
            </div>
            """
            )

        if not self.available:
            return

        if self.list_btn.value and self.uri.value:
            self._do_list()
        elif self.fetch_btn.value and self.uri.value:
            self._do_fetch()
        else:
            mo.md(
                """
            Authenticate first: open a **webterm** and run `canfar login`.
            Then enter a `vos:` URI above and list or download files.
            """
            )

    def _do_list(self) -> None:
        try:
            c = self._vos.Client()  # type: ignore[union-attr]
            entries = c.listdir(self.uri.value)
            self.result.replace(
                mo.md(
                    f"```\nContents of {self.uri.value}:\n"
                    + "\n".join(entries)
                    + "\n```"
                )
            )
        except Exception as exc:  # noqa: BLE001
            self.result.replace(mo.md(f"❌ {exc}"))

    def _do_fetch(self) -> None:
        try:
            c = self._vos.Client()  # type: ignore[union-attr]
            fname = self.uri.value.rstrip("/").rsplit("/", 1)[-1]
            dest = self.dest.value or "/scratch"
            c.copy(self.uri.value, f"{dest}/{fname}")
            self.result.replace(
                mo.md(f"✅ Copied `{self.uri.value}` → `{dest}/{fname}`")
            )
        except Exception as exc:  # noqa: BLE001
            self.result.replace(mo.md(f"❌ {exc}"))


__all__ = ["file_browser", "file_browser_tips", "VOSpaceUI"]
