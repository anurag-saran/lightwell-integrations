#!/usr/bin/env bash
# Create the public Lightwell Python Validated feed on local Artifactory and
# Nexus, then cache every wheel it publishes.
#
# Repository key: lightwell-python-validated
# Feed: https://packages.redhat.com/lightwell/public-lightwell-demo/python/validated/
#
# Usage: ./scripts/copy-python-validated.sh [artifactory|nexus|both]
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"

TARGET="${1:-both}"
case "$TARGET" in
  artifactory|nexus|both) ;;
  *)
    echo "Usage: $0 [artifactory|nexus|both]" >&2
    exit 2
    ;;
esac

STATE="$(integrations_state_dir)"
mkdir -p "$STATE"
KEY="lightwell-python-validated"
# Index pip uses. Nexus proxies this.
FEED="$(integrations_lightwell_feed_url python validated)"
# Where the wheel bytes live. Artifactory caches this path.
FILES="$(integrations_lightwell_python_files_url)"
USER_NAME="${LIGHTWELL_COPY_USER:-admin}"
DEMO_PASSWORD="${DEMO_PASSWORD:-Lightwell-demo1}"

artifactory_pass() {
  printf '%s' "${LIGHTWELL_COPY_PASSWORD:-$DEMO_PASSWORD}"
}

nexus_pass() {
  if [[ -n "${LIGHTWELL_COPY_PASSWORD:-}" ]]; then
    printf '%s' "$LIGHTWELL_COPY_PASSWORD"
  elif [[ -f "$STATE/nexus-admin.password" ]]; then
    cat "$STATE/nexus-admin.password"
  else
    printf '%s' "$DEMO_PASSWORD"
  fi
}

list_wheels() {
  python3 - "$FEED" <<'PY'
import re, sys
import urllib.request
from urllib.parse import urljoin

feed = sys.argv[1]
if not feed.endswith("/"):
    feed += "/"
simple = feed + "simple/"
req = urllib.request.Request(simple, headers={"User-Agent": "lightwell-integrations"})
html = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")
projects = []
for href in re.findall(r'href="([^"]+)"', html):
    name = href.strip("/")
    if name in ("", "..", "../") or "/" in name:
        continue
    projects.append(name)
for project in sorted(set(projects)):
    page_url = urljoin(simple, project + "/")
    req = urllib.request.Request(page_url, headers={"User-Agent": "lightwell-integrations"})
    page = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")
    for href in re.findall(r'href="([^"]+)"', page):
        if ".whl" not in href and ".tar.gz" not in href:
            continue
        filename = href.split("/")[-1].split("#")[0]
        print(f"{project}\t{filename}")
PY
}

ensure_artifactory() {
  local pass ui get http
  pass="$(artifactory_pass)"
  ui="http://127.0.0.1:${ARTIFACTORY_UI_PORT:-8082}/artifactory/ui/admin/repositories"
  get=$(curl -sS -o "$STATE/pypi-get.json" -w '%{http_code}' --max-time 30 \
    -u "${USER_NAME}:${pass}" "${ui}/remote/${KEY}" || true)
  if [[ "$get" != "200" ]]; then
    python3 - "$KEY" "$FILES" "$FEED" <<'PY' >"$STATE/pypi-create.json"
import json, sys
key, url, registry = sys.argv[1], sys.argv[2].rstrip("/"), sys.argv[3].rstrip("/")
print(json.dumps({
    "type": "remoteRepoConfig",
    "general": {"repoKey": key},
    "basic": {
        "url": url,
        "layout": "simple-default",
        "offline": False,
        "includesPattern": "**/*",
        "username": "",
        "password": "",
    },
    "advanced": {
        "bypassHeadRequests": True,
        "cache": {
            "missedRetrievalCachePeriodSecs": 600,
            "retrievalCachePeriodSecs": 7200,
            "assumedOfflineLimitSecs": 300,
            "keepUnusedArtifactsHours": 0,
            "metadataRetrievalTimeoutSecs": 60,
        },
    },
    "typeSpecific": {
        "repoType": "Pypi",
        "listRemoteFolderItems": True,
        "enableTokenAuthentication": False,
        "registryUrl": registry,
    },
}))
PY
    http=$(curl -sS -o "$STATE/pypi-create.out" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" -X POST "$ui" \
      -H "Content-Type: application/json" \
      --data-binary @"$STATE/pypi-create.json" || true)
    echo "Create Artifactory ${KEY} HTTP ${http}"
    if [[ "$http" != "200" && "$http" != "201" ]]; then
      cat "$STATE/pypi-create.out" >&2
    fi
    get=$(curl -sS -o "$STATE/pypi-get.json" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" "${ui}/remote/${KEY}" || true)
  else
    echo "Artifactory remote ${KEY} already exists"
  fi
  [[ "$get" == "200" ]] || return 1
  python3 - "$KEY" "$FILES" "$FEED" "$STATE/pypi-get.json" <<'PY' >"$STATE/pypi-put.json"
import json, sys
key, url, registry, path = sys.argv[1], sys.argv[2].rstrip("/"), sys.argv[3].rstrip("/"), sys.argv[4]
d = json.load(open(path))
d.setdefault("general", {})["repoKey"] = key
basic = d.setdefault("basic", {})
basic["url"] = url
spec = d.setdefault("typeSpecific", {})
spec["repoType"] = "Pypi"
spec["listRemoteFolderItems"] = True
spec["enableTokenAuthentication"] = False
spec["registryUrl"] = registry
adv = d.setdefault("advanced", {})
adv["bypassHeadRequests"] = True
cache = adv.setdefault("cache", {})
cache["missedRetrievalCachePeriodSecs"] = 600
cache.setdefault("retrievalCachePeriodSecs", 7200)
print(json.dumps(d))
PY
  http=$(curl -sS -o "$STATE/pypi-put.out" -w '%{http_code}' --max-time 30 \
    -u "${USER_NAME}:${pass}" -X PUT "$ui" \
    -H "Content-Type: application/json" \
    --data-binary @"$STATE/pypi-put.json" || true)
  echo "Update Artifactory ${KEY} HTTP ${http}"
}

ensure_nexus() {
  local pass api code
  pass="$(nexus_pass)"
  api="http://127.0.0.1:${NEXUS_HOST_PORT:-8083}/service/rest/v1/repositories/pypi/proxy"
  python3 - "$KEY" "$FEED" <<'PY' >"$STATE/pypi-nexus.json"
import json, sys
key, url = sys.argv[1], sys.argv[2]
if not url.endswith("/"):
    url += "/"
print(json.dumps({
    "name": key,
    "online": True,
    "storage": {"blobStoreName": "default", "strictContentTypeValidation": True},
    "proxy": {"remoteUrl": url, "contentMaxAge": 1440, "metadataMaxAge": 60},
    "negativeCache": {"enabled": True, "timeToLive": 60},
    "httpClient": {
        "blocked": False,
        "autoBlock": False,
        "connection": {
            "retries": 0,
            "userAgentSuffix": "lightwell-integrations",
            "timeout": 60,
            "enableCircularRedirects": False,
            "enableCookies": False,
        },
    },
    "pypi": {"removeQuarantined": False},
}))
PY
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    -u "${USER_NAME}:${pass}" "${api}/${KEY}" || true)
  if [[ "$code" == "200" ]]; then
    code=$(curl -sS -o "$STATE/pypi-nexus.out" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" -X PUT "${api}/${KEY}" \
      -H "Content-Type: application/json" \
      --data-binary @"$STATE/pypi-nexus.json" || true)
    echo "Update Nexus ${KEY} HTTP ${code}"
  else
    code=$(curl -sS -o "$STATE/pypi-nexus.out" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" -X POST "$api" \
      -H "Content-Type: application/json" \
      --data-binary @"$STATE/pypi-nexus.json" || true)
    echo "Create Nexus ${KEY} HTTP ${code}"
    if [[ "$code" != "201" && "$code" != "200" ]]; then
      cat "$STATE/pypi-nexus.out" >&2
      return 1
    fi
  fi
}

copy_wheel() {
  local tool="$1" project="$2" filename="$3" pass base http size out wheel_url
  out="$STATE/pypi-body"
  if [[ "$tool" == "artifactory" ]]; then
    pass="$(artifactory_pass)"
    wheel_url="http://127.0.0.1:${ARTIFACTORY_UI_PORT:-8082}/artifactory/${KEY}/${filename}"
  else
    pass="$(nexus_pass)"
    base="http://127.0.0.1:${NEXUS_HOST_PORT:-8083}/repository/${KEY}"
    curl -sS -u "${USER_NAME}:${pass}" --max-time 60 \
      "${base}/simple/${project}/" -o "$STATE/pypi-simple.html" || true
    wheel_url=$(python3 - "$base" "$project" "$filename" "$STATE/pypi-simple.html" <<'PY'
import sys
from urllib.parse import urljoin
import re
base, project, filename, path = sys.argv[1:]
page = open(path, encoding="utf-8", errors="replace").read()
simple = base.rstrip("/") + "/simple/" + project + "/"
for href in re.findall(r'href="([^"]+)"', page):
    if filename in href.split("#", 1)[0]:
        print(urljoin(simple, href.split("#", 1)[0]))
        break
PY
)
    if [[ -z "$wheel_url" ]]; then
      wheel_url="${base}/packages/${project}/${filename}"
    fi
  fi
  http=$(curl -sS -L -u "${USER_NAME}:${pass}" -o "$out" -w '%{http_code}' --max-time 180 \
    "$wheel_url" || true)
  size=0
  if [[ -f "$out" ]]; then
    size=$(wc -c < "$out" | tr -d ' ')
  fi
  if [[ "$http" == "200" && "$size" -gt 1000 ]] && ! grep -q 'Request has expired' "$out"; then
    rm -f "$out"
    echo "  ok   $tool  $project  $filename  ($size bytes)"
    return 0
  fi
  if grep -q 'Request has expired' "$out" 2>/dev/null; then
    echo "  expired  $tool  $project  $filename"
  else
    echo "  fail HTTP ${http:-none} ($size bytes)  $tool  $project  $filename"
  fi
  rm -f "$out"
  return 1
}

echo "Python Validated: $FEED"
list_wheels >"$STATE/python-validated-wheels.txt"
echo "Wheels: $(grep -c . "$STATE/python-validated-wheels.txt" || true)"
cut -f1 "$STATE/python-validated-wheels.txt" | sed 's/^/  /'

integrations_require_podman
if [[ "$TARGET" == "artifactory" || "$TARGET" == "both" ]]; then
  podman start lightwell-artifactory >/dev/null 2>&1 || true
  integrations_wait_http "http://127.0.0.1:${ARTIFACTORY_UI_PORT:-8082}/artifactory/api/system/ping" 30 "200|401"
  ensure_artifactory
fi
if [[ "$TARGET" == "nexus" || "$TARGET" == "both" ]]; then
  if podman container exists lightwell-nexus-run; then
    podman start lightwell-nexus-run >/dev/null 2>&1 || true
  else
    podman start "${NEXUS_CONTAINER:-lightwell-nexus}" >/dev/null 2>&1 || true
  fi
  integrations_wait_http "http://127.0.0.1:${NEXUS_HOST_PORT:-8083}/service/rest/v1/status" 30 "200|401"
  ensure_nexus
fi

FAILED=0
while IFS=$'\t' read -r project filename; do
  [[ -n "$project" && -n "$filename" ]] || continue
  if [[ "$TARGET" == "artifactory" || "$TARGET" == "both" ]]; then
    copy_wheel artifactory "$project" "$filename" || FAILED=$((FAILED + 1))
  fi
  if [[ "$TARGET" == "nexus" || "$TARGET" == "both" ]]; then
    copy_wheel nexus "$project" "$filename" || FAILED=$((FAILED + 1))
  fi
done <"$STATE/python-validated-wheels.txt"

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "Python Validated copy finished."
  echo "Artifactory: http://127.0.0.1:${ARTIFACTORY_UI_PORT:-8082}/ui/  repository ${KEY}"
  echo "Nexus:       http://127.0.0.1:${NEXUS_HOST_PORT:-8083}/#browse/browse:${KEY}"
else
  echo "Python Validated copy finished with $FAILED failure(s)."
  exit 1
fi
