"""Assert agent-wizard maps hub routes to lean astroai-lab verbs (no removed CLI)."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("agent_wizard", ROOT / "agent-wizard.py")
assert SPEC and SPEC.loader
wiz = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wiz)

REMOVED = {"report", "addons", "catalog", "interact", "fix", "clean", "add"}


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


if __name__ == "__main__":
    test_addons_and_catalog_use_list_config()
    test_install_by_tag_loops_plugins_install()
    print("ok")
