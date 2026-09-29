"""JFrog Xray Custom Issue HTTP client."""

from __future__ import annotations

import os
from typing import Any


def require_requests():
    try:
        import requests
        from requests.adapters import HTTPAdapter
        from urllib3.util.retry import Retry
    except ImportError as exc:  # pragma: no cover
        raise SystemExit(
            "Install dependencies: pip install lightwell-xray-sync "
            "(or pip install -e ./xray)"
        ) from exc
    return requests, HTTPAdapter, Retry


def build_session() -> Any:
    requests, HTTPAdapter, Retry = require_requests()
    session = requests.Session()
    adapter = HTTPAdapter(
        max_retries=Retry(
            total=3,
            connect=3,
            read=3,
            backoff_factor=0.8,
            status_forcelist=(429, 500, 502, 503, 504),
            allowed_methods=frozenset({"GET", "POST", "PUT"}),
        )
    )
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    return session


def xray_auth_headers() -> tuple[str, dict[str, str], tuple[str, str] | None]:
    """Return (base_url, headers, basic_auth_or_None)."""
    base = (os.environ.get("JFROG_URL") or "").rstrip("/")
    token = os.environ.get("JFROG_TOKEN") or ""
    user = os.environ.get("JFROG_USER") or ""
    if not base:
        raise EnvironmentError("JFROG_URL is required")
    if not token:
        raise EnvironmentError("JFROG_TOKEN is required")
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    auth: tuple[str, str] | None = None
    if user:
        auth = (user, token)
    else:
        headers["Authorization"] = f"Bearer {token}"
    return base, headers, auth


def events_url(base: str) -> str:
    if base.rstrip("/").endswith("/xray"):
        return f"{base.rstrip('/')}/api/v1/events"
    return f"{base}/xray/api/v1/events"


def push_event(
    session: Any,
    base: str,
    headers: dict[str, str],
    auth: tuple[str, str] | None,
    payload: dict[str, Any],
    timeout: float,
) -> str:
    """POST create; on conflict PUT update. Returns 'created' | 'updated'."""
    url = events_url(base)
    issue_id = payload["id"]
    resp = session.post(url, headers=headers, auth=auth, json=payload, timeout=timeout)
    if resp.status_code in (200, 201):
        return "created"
    if resp.status_code in (409, 400) and (
        "already" in resp.text.lower()
        or "exist" in resp.text.lower()
        or resp.status_code == 409
    ):
        put_url = f"{url}/{issue_id}"
        body = {k: v for k, v in payload.items() if k != "id"}
        up = session.put(put_url, headers=headers, auth=auth, json=body, timeout=timeout)
        if up.status_code in (200, 201, 204):
            return "updated"
        raise RuntimeError(f"PUT {put_url} → HTTP {up.status_code}: {up.text[:500]}")
    raise RuntimeError(f"POST {url} → HTTP {resp.status_code}: {resp.text[:500]}")
