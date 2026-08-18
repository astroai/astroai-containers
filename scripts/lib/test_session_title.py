from __future__ import annotations

from unittest.mock import patch

from session_title import session_tab_title, stick_html_title


def test_session_name_from_hostname() -> None:
    with patch("session_title.socket.gethostname", return_value="gputerm"):
        assert session_tab_title("AstroAI Webterm") == "gputerm"


def test_fallback_for_docker_id() -> None:
    with patch("session_title.socket.gethostname", return_value="a1b2c3d4e5f6"):
        assert session_tab_title("AstroAI Notebook") == "AstroAI Notebook"


def test_fallback_localhost() -> None:
    with patch("session_title.socket.gethostname", return_value="localhost"):
        assert session_tab_title("AstroAI") == "AstroAI"


def test_stick_html_title_replaces_and_is_idempotent() -> None:
    with patch("session_title.socket.gethostname", return_value="contributed2"):
        html = "<html><head><title>Old</title></head><body></body></html>"
        once = stick_html_title(html, "AstroAI")
        assert "<title>contributed2</title>" in once
        assert "data-astroai-tab" in once
        twice = stick_html_title(once, "AstroAI")
        assert twice == once


if __name__ == "__main__":
    test_session_name_from_hostname()
    test_fallback_for_docker_id()
    test_fallback_localhost()
    test_stick_html_title_replaces_and_is_idempotent()
    print("ok")
