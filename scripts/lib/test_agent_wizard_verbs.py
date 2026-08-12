"""Assert lean hub maps to lean astroai-lab verbs + honest compute ensure."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("agent_wizard", ROOT / "agent-wizard.py")
assert SPEC and SPEC.loader
wiz = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wiz)

REMOVED = {"report", "addons", "catalog", "interact", "repair", "clean", "add"}


def _assert_lean(calls: list[list[str]]) -> None:
    for c in calls:
        if "agent" not in c:
            continue
        i = c.index("agent")
        verb = c[i + 1] if i + 1 < len(c) else ""
        assert verb not in REMOVED, c


def test_addons_and_catalog_use_list_config() -> None:
    calls: list[list[str]] = []

    def fake(args: list[str], *, timeout: int | None = None) -> tuple[int, str, str]:
        calls.append(args)
        if "config" in args:
            return (
                0,
                '[{"id":"ponytail","kind":"skill","tags":["lean"],'
                '"any_installed":false,"summary":"x"}]',
                "",
            )
        if args[-1] == "list":
            return (
                0,
                '{"ok":true,"agents":[{"id":"kilo","agent":"kilo",'
                '"binary":true,"summary":"cli"}]}',
                "",
            )
        return 0, "{}", ""

    with patch.object(wiz, "_run_lab", side_effect=fake):
        rc, rows, _ = wiz._plugins_from_list_config("lean")
        assert rc == 0
        assert rows and rows[0]["installed"] is False
        rc2, items, _ = wiz._catalog_items()
        assert rc2 == 0
        kinds = {i["kind"] for i in items}
        assert "agent" in kinds and "skill" in kinds
    _assert_lean(calls)


def test_install_by_tag_loops_plugins_install() -> None:
    calls: list[list[str]] = []

    def fake(args: list[str], *, timeout: int | None = None) -> tuple[int, str, str]:
        calls.append(args)
        if "list" in args and "config" in args:
            return (
                0,
                '[{"id":"ponytail","kind":"skill","tags":["lean"],"any_installed":false},'
                '{"id":"other","kind":"skill","tags":["science"],"any_installed":false}]',
                "",
            )
        if "plugins" in args and "install" in args:
            pid = args[-1]
            return (
                0,
                f'{{"ok":true,"plugin":"{pid}",'
                f'"actions":[{{"id":"{pid}","status":"ok"}}]}}',
                "",
            )
        return 1, "", "unexpected"

    with patch.object(wiz, "_run_lab", side_effect=fake):
        rc, data = wiz._install_plugins_by_tag("lean")
    assert rc == 0
    assert data["ok"]
    assert any(c[-2:] == ["install", "ponytail"] for c in calls)
    assert not any("other" == c[-1] for c in calls if "install" in c)
    _assert_lean(calls)


def test_compute_ensure_idempotent_and_wires() -> None:
    wire = MagicMock()
    wire.find_manager_sessions.return_value = [
        {"status": "Running", "image": "astroai/ray-manager", "connectURL": "https://mgr/"}
    ]
    wire._session_status.side_effect = lambda m: m["status"]
    wire._session_connect_url.side_effect = lambda m: m.get("connectURL", "")
    wire.jobs_url_from_connect.return_value = "https://mgr/dashboard"
    wire.wire_orx.return_value = {"address": "https://mgr/dashboard"}

    def fake_cmd(cmd: list[str], *, timeout: int) -> tuple[int, str, str]:
        if cmd[:2] == ["astroai-workload", "cluster"]:
            return (
                0,
                json.dumps(
                    {
                        "jobs_address": "https://mgr/dashboard",
                        "joined_workers": 2,
                        "cluster_phase": "running",
                        "manager_url": "https://mgr/",
                    }
                ),
                "",
            )
        return 0, "", ""

    with (
        patch.object(wiz, "_load_wire", return_value=wire),
        patch.object(wiz, "WIRE_OPENRESEARCH", True),
        patch.object(wiz, "shutil") as sh,
        patch.object(wiz, "_run_cmd", side_effect=fake_cmd),
    ):
        sh.which.return_value = "/usr/bin/astroai-workload"
        data = wiz._compute_ensure()

    assert data["ok"] is True
    assert data["jobs_address"] == "https://mgr/dashboard"
    assert "wire-orx" in data["steps"]
    wire.wire_orx.assert_called_once()
    # No canfar create when manager already Running
    assert "create" not in data["steps"]


def test_index_html_is_lean() -> None:
    html = wiz.INDEX_HTML
    assert "Start batch compute" in html
    assert "Setup agents" in html
    assert "Install Kilo" not in html
    assert "kilo" not in html.lower()
    assert "Advanced" not in html
    assert "cheat sheet" not in html.lower()
    assert "Install lean addons" not in html
    assert "api/catalog" not in html


if __name__ == "__main__":
    test_addons_and_catalog_use_list_config()
    test_install_by_tag_loops_plugins_install()
    test_compute_ensure_idempotent_and_wires()
    test_index_html_is_lean()
    print("ok")
