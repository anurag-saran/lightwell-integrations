"""Core sync/push orchestration and summary artifact."""

from __future__ import annotations

import json
import logging
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from lightwell_xray_sync.client import (
    build_session,
    events_url,
    push_event,
    xray_auth_headers,
)
from lightwell_xray_sync.load import collect_docs_from_path, collect_docs_from_url
from lightwell_xray_sync.map import FIXTURE, osv_to_xray_events

LOG = logging.getLogger("lightwell.xray")


@dataclass
class SyncSummary:
    created: int = 0
    updated: int = 0
    dry_run: int = 0
    failed: int = 0
    advisories: int = 0
    issues: list[dict[str, str]] = field(default_factory=list)

    @property
    def succeeded(self) -> int:
        return self.created + self.updated + self.dry_run


def run_self_test() -> int:
    events = osv_to_xray_events(FIXTURE)
    assert len(events) == 1, events
    ev = events[0]
    assert ev["provider"] == "Lightwell"
    assert ev["package_type"] == "maven"
    assert ev["severity"] == "High", ev["severity"]
    comps = ev["components"]
    assert comps and comps[0]["id"] == "com.jayway.jsonpath:json-path"
    fixed = comps[0].get("fixed_versions") or []
    assert any(".rhlw-" in f for f in fixed), fixed
    assert any("CVE-2023-51074" == c.get("cve") for c in ev.get("cves") or [])
    LOG.info(
        "SELF-TEST OK: id=%s fixed_versions=%s severity=%s",
        ev["id"],
        fixed,
        ev["severity"],
    )
    print(json.dumps(ev, indent=2))
    return 0


def process_docs(
    docs: list[tuple[str, dict[str, Any]]],
    *,
    dry_run: bool,
    timeout: float,
    print_payloads: bool = False,
) -> SyncSummary:
    summary = SyncSummary(advisories=len(docs))
    if not docs:
        return summary

    LOG.info("Loaded %d OSV document(s)", len(docs))

    session: Any = None
    base = headers = auth = None
    if not dry_run:
        base, headers, auth = xray_auth_headers()
        session = build_session()
        LOG.info("Xray endpoint: %s", events_url(base))

    for source, doc in docs:
        osv_id = doc.get("id", source)
        try:
            events = osv_to_xray_events(doc)
        except ValueError as exc:
            LOG.error("FAIL map %s: %s", osv_id, exc)
            summary.failed += 1
            summary.issues.append({"id": str(osv_id), "status": "map_failed", "error": str(exc)})
            continue

        for payload in events:
            issue_id = payload["id"]
            if dry_run:
                LOG.info("DRY-RUN %s ← %s", issue_id, source)
                if print_payloads:
                    print(json.dumps(payload, indent=2))
                summary.dry_run += 1
                summary.issues.append({"id": issue_id, "status": "dry_run", "source": source})
                continue
            try:
                action = push_event(session, base, headers, auth, payload, timeout)
                LOG.info("SUCCESS %s (%s)", issue_id, action)
                if action == "created":
                    summary.created += 1
                else:
                    summary.updated += 1
                summary.issues.append({"id": issue_id, "status": action, "source": source})
            except Exception as exc:
                LOG.error("FAIL push %s: %s", issue_id, exc)
                summary.failed += 1
                summary.issues.append(
                    {"id": issue_id, "status": "push_failed", "error": str(exc)}
                )
            time.sleep(0.05)

    LOG.info(
        "Done: created=%d updated=%d dry_run=%d failed=%d",
        summary.created,
        summary.updated,
        summary.dry_run,
        summary.failed,
    )
    return summary


def load_docs(
    *,
    input_path: str | None,
    url: str | None,
    timeout: float,
) -> list[tuple[str, dict[str, Any]]]:
    session: Any = None
    if input_path:
        return collect_docs_from_path(Path(input_path))
    if not url:
        raise ValueError("Provide --input or --url / LIGHTWELL_OSV_URL")
    session = build_session()
    return collect_docs_from_url(url, session, timeout)


def write_summary(summary: SyncSummary, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(summary), indent=2) + "\n", encoding="utf-8")
    LOG.info("Wrote summary %s", path)
