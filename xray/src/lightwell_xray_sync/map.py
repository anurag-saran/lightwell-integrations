"""Map OSV documents to JFrog Xray Custom Issue payloads."""

from __future__ import annotations

import re
from collections import defaultdict
from typing import Any

from lightwell_xray_sync.cvss import severity_from_osv

_ECOSYSTEM_TO_PACKAGE_TYPE = {
    "maven": "maven",
    "pypi": "pypi",
    "npm": "npm",
    "go": "go",
    "golang": "go",
    "nuget": "nuget",
    "rubygems": "gems",
    "crates.io": "cargo",
    "cargo": "cargo",
    "debian": "debian",
    "alpine": "alpine",
    "docker": "docker",
    "generic": "generic",
}

_RHLW_FIXED_RE = re.compile(r"\.(?:rhlw|redhat)-\d+$", re.IGNORECASE)


def is_lightwell_fixed(version: str) -> bool:
    return bool(version and _RHLW_FIXED_RE.search(version))


def map_ecosystem(ecosystem: str) -> str:
    key = (ecosystem or "generic").strip().lower()
    return _ECOSYSTEM_TO_PACKAGE_TYPE.get(key, "generic")


def sanitize_issue_id(osv_id: str, package_type: str | None = None) -> str:
    """Xray forbids ids prefixed with 'Xray'; keep ids stable and URL-safe."""
    base = (osv_id or "unknown").strip()
    if base.lower().startswith("xray"):
        base = "LW-" + base
    base = re.sub(r"[^\w.\-:+]", "_", base)
    if package_type:
        return f"{base}-{package_type}"
    return base


def bracket_version(ver: str) -> str:
    ver = ver.strip()
    if ver.startswith("["):
        return ver
    return f"[{ver}]"


def range_to_vulnerable(introduced: str | None, fixed: str | None) -> str | None:
    """OSV introduced/fixed → Xray Maven-style range string."""
    intro = (introduced or "0").strip() or "0"
    if fixed:
        return f"[{intro},{fixed.strip()})"
    if intro and intro != "0":
        return f"[{intro},)"
    return None


def _uniq(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for x in items:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def component_from_affected(aff: dict[str, Any]) -> dict[str, Any] | None:
    pkg = aff.get("package") or {}
    name = (pkg.get("name") or "").strip()
    if not name:
        return None

    vulnerable: list[str] = []
    fixed_versions: list[str] = []

    for ver in aff.get("versions") or []:
        if isinstance(ver, str) and ver.strip():
            vulnerable.append(bracket_version(ver))

    for rng in aff.get("ranges") or []:
        if not isinstance(rng, dict):
            continue
        introduced: str | None = None
        fixed: str | None = None
        for ev in rng.get("events") or []:
            if not isinstance(ev, dict):
                continue
            if "introduced" in ev and ev["introduced"] is not None:
                introduced = str(ev["introduced"])
            if "fixed" in ev and ev["fixed"]:
                fixed = str(ev["fixed"])
                if is_lightwell_fixed(fixed):
                    fixed_versions.append(bracket_version(fixed))
        vr = range_to_vulnerable(introduced, fixed)
        if vr:
            vulnerable.append(vr)

    vulnerable = _uniq(vulnerable)
    fixed_versions = _uniq(fixed_versions)
    if not vulnerable and not fixed_versions:
        return None

    comp: dict[str, Any] = {"id": name, "vulnerable_versions": vulnerable or ["[0,]"]}
    if fixed_versions:
        comp["fixed_versions"] = fixed_versions
    return comp


def osv_to_xray_events(doc: dict[str, Any]) -> list[dict[str, Any]]:
    """Convert one OSV document into one or more Xray Custom Issue payloads."""
    if not isinstance(doc, dict) or not doc.get("id"):
        raise ValueError("OSV document missing required 'id'")

    osv_id = str(doc["id"])
    score, severity, vector = severity_from_osv(doc)
    summary = (doc.get("summary") or "").strip()
    details = (doc.get("details") or "").strip()
    if not summary:
        summary = details.split("\n", 1)[0][:200] if details else osv_id

    aliases = [
        a
        for a in (doc.get("aliases") or [])
        if isinstance(a, str) and a.upper().startswith("CVE-")
    ]
    cves: list[dict[str, str]] = []
    for cve in aliases:
        entry: dict[str, str] = {"cve": cve}
        if score is not None:
            entry["cvss_v3"] = f"{score:g}"
        cves.append(entry)
    if not cves and score is not None:
        cves.append(
            {
                "cve": osv_id if osv_id.upper().startswith("CVE-") else f"LW-{osv_id}",
                "cvss_v3": f"{score:g}",
            }
        )

    sources = [{"source_id": a} for a in aliases] or [{"source_id": osv_id}]

    by_type: dict[str, list[dict[str, Any]]] = defaultdict(list)
    all_fixed: list[str] = []
    for aff in doc.get("affected") or []:
        if not isinstance(aff, dict):
            continue
        pkg = aff.get("package") or {}
        ptype = map_ecosystem(str(pkg.get("ecosystem") or "generic"))
        comp = component_from_affected(aff)
        if not comp:
            continue
        by_type[ptype].append(comp)
        for fv in comp.get("fixed_versions") or []:
            all_fixed.append(fv)

    if not by_type:
        raise ValueError(f"{osv_id}: no mappable affected components")

    desc_parts = [details] if details else []
    if vector:
        desc_parts.append(f"CVSS v3 vector: {vector}")
    if all_fixed:
        desc_parts.append(
            "Lightwell fixed builds: " + ", ".join(sorted(set(all_fixed)))
        )
    description = "\n\n".join(p for p in desc_parts if p) or summary

    multi = len(by_type) > 1
    events: list[dict[str, Any]] = []
    for ptype, components in sorted(by_type.items()):
        issue_id = sanitize_issue_id(osv_id, ptype if multi else None)
        payload: dict[str, Any] = {
            "id": issue_id,
            "type": "Security",
            "provider": "Lightwell",
            "package_type": ptype,
            "severity": severity,
            "summary": summary[:512],
            "description": description,
            "components": components,
            "sources": sources,
            "properties": {
                "lightwell_osv_id": osv_id,
                "lightwell_cvss_vector": vector or "",
            },
        }
        if cves:
            payload["cves"] = cves
        events.append(payload)
    return events


FIXTURE = {
    "schema_version": "1.6.8",
    "id": "x_RHLW-CVE-2023-51074-2.8.0",
    "severity": [
        {
            "type": "CVSS_V3",
            "score": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H",
        }
    ],
    "details": "json-path stack overflow.",
    "aliases": ["CVE-2023-51074"],
    "affected": [
        {
            "package": {
                "ecosystem": "Maven",
                "name": "com.jayway.jsonpath:json-path",
            },
            "ranges": [
                {
                    "type": "ECOSYSTEM",
                    "events": [
                        {"introduced": "0"},
                        {"fixed": "2.8.0.rhlw-00001"},
                    ],
                }
            ],
        }
    ],
}
