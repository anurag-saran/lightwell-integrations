"""CVSS v3 helpers (self-contained; mirrors lightwell osv_cves scoring)."""

from __future__ import annotations

import math
from typing import Any

_AV = {"N": 0.85, "A": 0.62, "L": 0.55, "P": 0.2}
_AC = {"L": 0.77, "H": 0.44}
_PR_U = {"N": 0.85, "L": 0.62, "H": 0.27}
_PR_C = {"N": 0.85, "L": 0.68, "H": 0.5}
_UI = {"N": 0.85, "R": 0.62}
_CIA = {"N": 0.0, "L": 0.22, "H": 0.56}


def round_up_1(value: float) -> float:
    return math.ceil(value * 10) / 10


def cvss_v3_base_score(vector: str) -> float | None:
    """Parse a CVSS:3.x vector string into a base score, or None if incomplete."""
    if not vector or not vector.upper().startswith("CVSS:3"):
        return None
    metrics: dict[str, str] = {}
    for part in vector.split("/"):
        if ":" not in part:
            continue
        k, v = part.split(":", 1)
        k = k.strip().upper()
        if k.startswith("CVSS"):
            continue
        metrics[k] = v.strip().upper()
    try:
        scope = metrics["S"]
        av = _AV[metrics["AV"]]
        ac = _AC[metrics["AC"]]
        ui = _UI[metrics["UI"]]
        pr = (_PR_C if scope == "C" else _PR_U)[metrics["PR"]]
        c = _CIA[metrics["C"]]
        i = _CIA[metrics["I"]]
        a = _CIA[metrics["A"]]
    except KeyError:
        return None

    iss = 1.0 - (1.0 - c) * (1.0 - i) * (1.0 - a)
    if scope == "U":
        impact = 6.42 * iss
    else:
        impact = 7.52 * (iss - 0.029) - 3.25 * ((iss - 0.02) ** 15)
    exploitability = 8.22 * av * ac * pr * ui
    if impact <= 0:
        return 0.0
    if scope == "U":
        base = min(impact + exploitability, 10.0)
    else:
        base = min(1.08 * (impact + exploitability), 10.0)
    return round_up_1(base)


def qualitative_severity(score: float | None) -> str:
    """Xray qualitative severity string (Low/Medium/High/Critical)."""
    if score is None:
        return "Medium"
    if score == 0.0:
        return "Low"
    if score < 4.0:
        return "Low"
    if score < 7.0:
        return "Medium"
    if score < 9.0:
        return "High"
    return "Critical"


def severity_from_osv(doc: dict[str, Any]) -> tuple[float | None, str, str | None]:
    best_score: float | None = None
    best_vector: str | None = None
    for sev in doc.get("severity") or []:
        if not isinstance(sev, dict):
            continue
        raw = sev.get("score")
        if not isinstance(raw, str):
            continue
        if raw.upper().startswith("CVSS:3"):
            score = cvss_v3_base_score(raw)
            vector = raw
        else:
            try:
                score = float(raw)
                vector = None
            except ValueError:
                continue
        if score is None:
            continue
        if best_score is None or score > best_score:
            best_score = score
            best_vector = vector
    return best_score, qualitative_severity(best_score), best_vector
