"""Load OSV documents from files or HTTP indexes."""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urljoin

LOG = logging.getLogger("lightwell.xray")


def load_json_file(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {path}: {exc}") from exc


def iter_osv_docs_from_obj(obj: Any, source: str) -> Iterable[dict[str, Any]]:
    if isinstance(obj, dict):
        if obj.get("affected") is not None or obj.get("id"):
            yield obj
            return
        for key in ("advisories", "vulns", "results"):
            if isinstance(obj.get(key), list):
                for item in obj[key]:
                    if isinstance(item, dict):
                        yield item
                return
    if isinstance(obj, list):
        for item in obj:
            if isinstance(item, dict):
                yield item
        return
    raise ValueError(f"{source}: unrecognized OSV JSON structure")


def collect_docs_from_path(path: Path) -> list[tuple[str, dict[str, Any]]]:
    out: list[tuple[str, dict[str, Any]]] = []
    if path.is_file():
        obj = load_json_file(path)
        for doc in iter_osv_docs_from_obj(obj, str(path)):
            out.append((str(path), doc))
        return out
    if path.is_dir():
        for fp in sorted(path.rglob("*.json")):
            try:
                obj = load_json_file(fp)
                for doc in iter_osv_docs_from_obj(obj, str(fp)):
                    out.append((str(fp), doc))
            except ValueError as exc:
                LOG.error("SKIP %s: %s", fp, exc)
        return out
    raise FileNotFoundError(path)


def collect_docs_from_url(
    url: str, session: Any, timeout: float
) -> list[tuple[str, dict[str, Any]]]:
    LOG.info("Fetching %s", url)
    resp = session.get(url, timeout=timeout)
    resp.raise_for_status()
    ctype = (resp.headers.get("content-type") or "").lower()
    text = resp.text
    if (
        "html" in ctype
        or text.lstrip().lower().startswith("<!doctype")
        or "<html" in text[:200].lower()
    ):
        hrefs = re.findall(r'href=["\']([^"\']+\.json)["\']', text, flags=re.I)
        docs: list[tuple[str, dict[str, Any]]] = []
        for href in sorted(set(hrefs)):
            child = urljoin(url if url.endswith("/") else url + "/", href)
            docs.extend(collect_docs_from_url(child, session, timeout))
        return docs
    try:
        obj = resp.json()
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON from {url}: {exc}") from exc
    return [(url, d) for d in iter_osv_docs_from_obj(obj, url)]
