# JupyterLab reads this file for LabApp traits (system /etc/jupyter).
# Tab suffix is the CANFAR session name (pod hostname).
import os
import runpy
import sys

c = get_config()  # noqa: F821
_title = "AstroAI Notebook"
_helper = "/opt/astroai/lib/session_title.py"
if os.path.isfile(_helper):
    try:
        _title = runpy.run_path(_helper)["session_tab_title"]("AstroAI Notebook")
    except Exception as exc:  # noqa: BLE001 — title is cosmetic
        print(f"session tab title helper failed: {exc}", file=sys.stderr)
c.LabApp.app_name = _title
