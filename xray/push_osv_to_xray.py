#!/usr/bin/env python3
"""Compatibility shim — prefer: lightwell-xray-sync sync|push|self-test

Install:  pip install -e ./xray
Or run:   python3 -m lightwell_xray_sync.cli ...
"""

from __future__ import annotations

import sys
from pathlib import Path

# Allow running from a kit checkout without pip install
_SRC = Path(__file__).resolve().parent / "src"
if _SRC.is_dir() and str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from lightwell_xray_sync.cli import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
