#!/usr/bin/env bash
# Copy every library on the public Lightwell demo feed through a local
# Artifactory remote and/or Nexus proxy, and save the OSV advisories.
#
# The demo Maven index is five libraries (jar, pom, and maven-metadata).
# OSV advisories are a separate feed. The Maven remote cannot cache them,
# so this script writes those JSON files under .local/integrations/osv/.
#
# The public demo console has two Maven repositories:
#   remediated -> lightwell-java-remediated
#   validated  -> lightwell-java-validated
#   virtual    -> lightwell-java  (remediated, then validated)
#
# Usage: ./scripts/copy-catalog.sh [artifactory|nexus|both] [predisclosure|remediated|validated|all]
# Feed URLs come from lib-common.sh and LIGHTWELL_MODE.
# LIGHTWELL_REPOS_ONLY=1 creates the repositories and does not copy files.
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
integrations_enable_insecure_curl_if_requested

TARGET="${1:-both}"
TIER="${2:-all}"
case "$TARGET" in
  artifactory|nexus|both) ;;
  *)
    echo "Usage: $0 [artifactory|nexus|both] [remediated|validated|all]" >&2
    exit 2
    ;;
esac
case "$TIER" in
  predisclosure|remediated|validated|all) ;;
  *)
    echo "Usage: $0 [artifactory|nexus|both] [predisclosure|remediated|validated|all]" >&2
    exit 2
    ;;
esac

STATE="$(integrations_state_dir)"
mkdir -p "$STATE"
LW_URL="$(integrations_lightwell_url)"
REPO_KEY="${LIGHTWELL_REPO_KEY:-lightwell-java-remediated}"
if [[ -n "${LIGHTWELL_OSV_URL:-}" ]]; then
  OSV_URL="$LIGHTWELL_OSV_URL"
elif [[ "${LIGHTWELL_MODE:-demo}" == "demo" ]]; then
  OSV_URL="$(integrations_lightwell_osv_url)"
else
  OSV_URL=""
fi
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

list_maven_paths() {
  python3 - "$LW_URL" <<'PY'
import re, sys
import urllib.request
from urllib.parse import urljoin

base = sys.argv[1]
if not base.endswith("/"):
    base += "/"
seen = set()
queue = [base]
paths = []
keep_suffixes = (
    ".jar", ".pom",
    "maven-metadata.xml",
    "maven-metadata.xml.md5",
    "maven-metadata.xml.sha1",
    "maven-metadata.xml.sha256",
)
while queue:
    url = queue.pop(0)
    if url in seen:
        continue
    seen.add(url)
    req = urllib.request.Request(url, headers={"User-Agent": "lightwell-integrations"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        html = resp.read().decode("utf-8", "replace")
    for href in re.findall(r'href="([^"]+)"', html):
        if href in ("../", "..") or href.startswith(("?", "/")):
            continue
        full = urljoin(url, href)
        if not full.startswith(base):
            continue
        if full.endswith("/"):
            queue.append(full)
        else:
            rel = full[len(base):]
            if rel.startswith(".meta/"):
                continue
            if rel.endswith(keep_suffixes):
                paths.append(rel)
for rel in sorted(set(paths)):
    print(rel)
PY
}

list_osv_names() {
  python3 - "$OSV_URL" <<'PY'
import re, sys
import urllib.request

base = sys.argv[1]
if not base.endswith("/"):
    base += "/"
req = urllib.request.Request(base, headers={"User-Agent": "lightwell-integrations"})
with urllib.request.urlopen(req, timeout=30) as resp:
    html = resp.read().decode("utf-8", "replace")
names = []
for href in re.findall(r'href="([^"]+)"', html):
    name = href[2:] if href.startswith("./") else href
    if name in ("../", "..") or name.endswith("/") or "/" in name:
        continue
    if name.endswith(".json") or name == "PULP_MANIFEST":
        names.append(name)
for name in sorted(set(names)):
    print(name)
PY
}

copy_through() {
  local tool="$1" rel="$2" base pass out http size direct
  if [[ "$tool" == "artifactory" ]]; then
    base="$(integrations_artifactory_base)/artifactory/${REPO_KEY}"
    pass="$(artifactory_pass)"
  else
    base="$(integrations_nexus_base)/repository/${REPO_KEY}"
    pass="$(nexus_pass)"
  fi
  out="$STATE/catalog-body"
  http=$(curl -sS -u "${USER_NAME}:${pass}" -o "$out" -w '%{http_code}' --max-time 180 \
    "${base}/${rel}" || true)
  size=0
  if [[ -f "$out" ]]; then
    size=$(wc -c < "$out" | tr -d ' ')
  fi
  if [[ "$http" == "200" && "$size" -gt 0 ]]; then
    rm -f "$out"
    echo "  ok   $tool  $rel  ($size bytes)"
    return 0
  fi
  if [[ -z "$http" || "$http" == "000" ]]; then
    rm -f "$out"
    echo "  unreachable  $tool  $rel"
    return 1
  fi
  direct="$STATE/lightwell-direct.body"
  curl -sS -L --max-time 30 -o "$direct" "${LW_URL}${rel}" >/dev/null || true
  if grep -q 'Request has expired' "$direct" "$out" 2>/dev/null; then
    echo "  expired  $tool  $rel"
  else
    echo "  fail HTTP ${http} ($size bytes)  $tool  $rel"
  fi
  rm -f "$out" "$direct"
  return 1
}

wait_for_server() {
  local tool="$1" url accept
  if [[ "$tool" == "artifactory" ]]; then
    url="$(integrations_artifactory_base)/artifactory/api/system/ping"
    accept="200|401"
  else
    url="$(integrations_nexus_base)/service/rest/v1/status"
    accept="200|401"
  fi
  echo "Waiting for $tool..."
  integrations_wait_http "$url" 30 "$accept"
}

ensure_artifactory_remote() {
  local key="$1" url="$2" pass ui get http
  pass="$(artifactory_pass)"
  ui="$(integrations_artifactory_base)/artifactory/ui/admin/repositories"
  get=$(curl -sS -o "$STATE/artifactory-tier-get.json" -w '%{http_code}' --max-time 30 \
    -u "${USER_NAME}:${pass}" "${ui}/remote/${key}" || true)
  if [[ "$get" != "200" ]]; then
    python3 - "$key" "$url" <<'PY' >"$STATE/artifactory-tier-create.json"
import json, os, sys
key, url = sys.argv[1], sys.argv[2]
user = password = ""
if os.environ.get("LIGHTWELL_MODE") == "prod":
    user = os.environ["LIGHTWELL_USER"]
    password = os.environ["LIGHTWELL_TOKEN"]
print(json.dumps({
    "type": "remoteRepoConfig",
    "general": {"repoKey": key},
    "basic": {
        "url": url,
        "layout": "maven-2-default",
        "offline": False,
        "includesPattern": "**/*",
        "username": user,
        "password": password,
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
        "repoType": "Maven",
        "handleReleases": True,
        "handleSnapshots": False,
        "listRemoteFolderItems": True,
        "enableTokenAuthentication": False,
        "suppressPomConsistencyChecks": False,
        "eagerlyFetchJars": False,
        "eagerlyFetchSources": False,
        "forceMavenAuthentication": False,
    },
}))
PY
    http=$(curl -sS -o "$STATE/artifactory-tier-create.out" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" -X POST "$ui" \
      -H "Content-Type: application/json" \
      --data-binary @"$STATE/artifactory-tier-create.json" || true)
    echo "Create Artifactory ${key} HTTP ${http}"
    get=$(curl -sS -o "$STATE/artifactory-tier-get.json" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" "${ui}/remote/${key}" || true)
  else
    echo "Artifactory remote ${key} already exists"
  fi
  if [[ "$get" != "200" ]]; then
    echo "Could not read Artifactory remote ${key} (HTTP ${get})." >&2
    return 1
  fi
  python3 - "$key" "$url" "$STATE/artifactory-tier-get.json" <<'PY' >"$STATE/artifactory-tier-put.json"
import json, os, sys
key, url, path = sys.argv[1:]
d = json.load(open(path))
d.setdefault("general", {})["repoKey"] = key
basic = d.setdefault("basic", {})
basic["url"] = url
if os.environ.get("LIGHTWELL_MODE") == "prod":
    basic["username"] = os.environ["LIGHTWELL_USER"]
    basic["password"] = os.environ["LIGHTWELL_TOKEN"]
else:
    basic["username"] = ""
    basic["password"] = ""
spec = d.setdefault("typeSpecific", {})
spec["listRemoteFolderItems"] = True
spec["enableTokenAuthentication"] = False
spec["handleReleases"] = True
spec["handleSnapshots"] = False
adv = d.setdefault("advanced", {})
adv["bypassHeadRequests"] = True
cache = adv.setdefault("cache", {})
cache["missedRetrievalCachePeriodSecs"] = 600
cache.setdefault("retrievalCachePeriodSecs", 7200)
print(json.dumps(d))
PY
  http=$(curl -sS -o "$STATE/artifactory-tier-put.out" -w '%{http_code}' --max-time 30 \
    -u "${USER_NAME}:${pass}" -X PUT "$ui" \
    -H "Content-Type: application/json" \
    --data-binary @"$STATE/artifactory-tier-put.json" || true)
  echo "Update Artifactory ${key} HTTP ${http}"
}

ensure_nexus_proxy() {
  local key="$1" url="$2" pass api code
  pass="$(nexus_pass)"
  api="$(integrations_nexus_base)/service/rest/v1/repositories/maven/proxy"
  python3 - "$key" "$url" <<'PY' >"$STATE/nexus-tier.json"
import json, os, sys
key, url = sys.argv[1], sys.argv[2]
http_client = {
    "blocked": False,
    "autoBlock": False,
    "connection": {
        "retries": 0,
        "userAgentSuffix": "lightwell-integrations",
        "timeout": 60,
        "enableCircularRedirects": False,
        "enableCookies": False,
    },
}
if os.environ.get("LIGHTWELL_MODE") == "prod":
    http_client["authentication"] = {
        "type": "username",
        "username": os.environ["LIGHTWELL_USER"],
        "password": os.environ["LIGHTWELL_TOKEN"],
    }
print(json.dumps({
    "name": key,
    "online": True,
    "storage": {"blobStoreName": "default", "strictContentTypeValidation": True},
    "proxy": {"remoteUrl": url, "contentMaxAge": 1440, "metadataMaxAge": 60},
    "negativeCache": {"enabled": True, "timeToLive": 60},
    "httpClient": http_client,
    "maven": {
        "versionPolicy": "RELEASE",
        "layoutPolicy": "STRICT",
        "contentDisposition": "INLINE",
    },
}))
PY
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    -u "${USER_NAME}:${pass}" "${api}/${key}" || true)
  if [[ "$code" == "200" ]]; then
    code=$(curl -sS -o "$STATE/nexus-tier.out" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" -X PUT "${api}/${key}" \
      -H "Content-Type: application/json" \
      --data-binary @"$STATE/nexus-tier.json" || true)
    echo "Update Nexus ${key} HTTP ${code}"
  else
    code=$(curl -sS -o "$STATE/nexus-tier.out" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" -X POST "$api" \
      -H "Content-Type: application/json" \
      --data-binary @"$STATE/nexus-tier.json" || true)
    echo "Create Nexus ${key} HTTP ${code}"
  fi
}

copy_tier() {
  local tier="$1"
  case "$tier" in
    predisclosure|remediated|validated) ;;
    *)
      echo "Unknown tier: $tier" >&2
      return 1
      ;;
  esac
  LW_URL="$(integrations_lightwell_feed_url java "$tier")"
  REPO_KEY="lightwell-java-${tier}"
  echo
  echo "Lightwell ${tier}: $LW_URL"
  echo "Repository key: $REPO_KEY"
  if [[ "$TARGET" == "artifactory" || "$TARGET" == "both" ]]; then
    echo
    wait_for_server artifactory
    ensure_artifactory_remote "$REPO_KEY" "$LW_URL" || FAILED=$((FAILED + 1))
  fi
  if [[ "$TARGET" == "nexus" || "$TARGET" == "both" ]]; then
    echo
    wait_for_server nexus
    ensure_nexus_proxy "$REPO_KEY" "$LW_URL" || FAILED=$((FAILED + 1))
  fi
  if [[ "${LIGHTWELL_REPOS_ONLY:-}" == "1" ]]; then
    echo "Repository ${REPO_KEY} is configured. Not copying the catalog."
    return 0
  fi
  PATHS_FILE="$STATE/catalog-paths-${tier}.txt"
  list_maven_paths >"$PATHS_FILE"
  COUNT=$(grep -c . "$PATHS_FILE" || true)
  echo "Files on the demo index: $COUNT"
  JARS=$(grep -c '\.jar$' "$PATHS_FILE" || true)
  echo "Libraries (jars): $JARS"
  grep '\.jar$' "$PATHS_FILE" | sed 's/^/  /'
  if [[ "$TARGET" == "artifactory" || "$TARGET" == "both" ]]; then
    echo "== Artifactory ${REPO_KEY} =="
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      copy_through artifactory "$rel" || FAILED=$((FAILED + 1))
    done <"$PATHS_FILE"
  fi
  if [[ "$TARGET" == "nexus" || "$TARGET" == "both" ]]; then
    echo "== Nexus ${REPO_KEY} =="
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      copy_through nexus "$rel" || FAILED=$((FAILED + 1))
    done <"$PATHS_FILE"
  fi
}

if ! integrations_using_remote_managers; then
  integrations_require_podman
  if [[ "$TARGET" == "artifactory" || "$TARGET" == "both" ]]; then
    podman start lightwell-artifactory >/dev/null 2>&1 || true
  fi
  if [[ "$TARGET" == "nexus" || "$TARGET" == "both" ]]; then
    if podman container exists lightwell-nexus-run; then
      podman start lightwell-nexus-run >/dev/null 2>&1 || true
    else
      podman start "${NEXUS_CONTAINER:-lightwell-nexus}" >/dev/null 2>&1 || true
    fi
  fi
fi

ensure_artifactory_virtual() {
  local pass ui get http
  pass="$(artifactory_pass)"
  ui="$(integrations_artifactory_base)/artifactory/ui/admin/repositories"
  python3 - <<'PY' >"$STATE/artifactory-virtual.json"
import json, os
members = [m for m in os.environ["LIGHTWELL_JAVA_MEMBERS"].split(",") if m]
print(json.dumps({
    "type": "virtualRepoConfig",
    "general": {"repoKey": "lightwell-java"},
    "basic": {
        "layout": "maven-2-default",
        "includesPattern": "**/*",
        "selectedRepositories": [
            {"repoName": name, "type": "remote"} for name in members
        ],
    },
    "advanced": {
        "propertySets": [],
        "blackedOut": False,
        "allowContentBrowsing": False,
        "signedUrlTtl": 90,
    },
    "typeSpecific": {
        "repoType": "Maven",
        "forceMavenAuthentication": False,
    },
}))
PY
  get=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    -u "${USER_NAME}:${pass}" "${ui}/virtual/lightwell-java" || true)
  if [[ "$get" == "200" ]]; then
    http=$(curl -sS -o "$STATE/artifactory-virtual.out" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" -X PUT "$ui" \
      -H "Content-Type: application/json" \
      --data-binary @"$STATE/artifactory-virtual.json" || true)
    echo "Update Artifactory virtual lightwell-java HTTP ${http}"
  else
    http=$(curl -sS -o "$STATE/artifactory-virtual.out" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" -X POST "$ui" \
      -H "Content-Type: application/json" \
      --data-binary @"$STATE/artifactory-virtual.json" || true)
    echo "Create Artifactory virtual lightwell-java HTTP ${http}"
  fi
  if [[ "$http" != "200" && "$http" != "201" ]]; then
    cat "$STATE/artifactory-virtual.out" >&2 || true
    return 1
  fi
}

ensure_nexus_group() {
  local pass api code
  pass="$(nexus_pass)"
  api="$(integrations_nexus_base)/service/rest/v1/repositories/maven/group"
  python3 - <<'PY' >"$STATE/nexus-group.json"
import json, os
members = [m for m in os.environ["LIGHTWELL_JAVA_MEMBERS"].split(",") if m]
print(json.dumps({
    "name": "lightwell-java",
    "online": True,
    "storage": {"blobStoreName": "default", "strictContentTypeValidation": True},
    "group": {"memberNames": members},
    "maven": {"versionPolicy": "RELEASE", "layoutPolicy": "STRICT", "contentDisposition": "INLINE"},
}))
PY
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    -u "${USER_NAME}:${pass}" "${api}/lightwell-java" || true)
  if [[ "$code" == "200" ]]; then
    code=$(curl -sS -o "$STATE/nexus-group.out" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" -X PUT "${api}/lightwell-java" \
      -H "Content-Type: application/json" \
      --data-binary @"$STATE/nexus-group.json" || true)
    echo "Update Nexus group lightwell-java HTTP ${code}"
  else
    code=$(curl -sS -o "$STATE/nexus-group.out" -w '%{http_code}' --max-time 30 \
      -u "${USER_NAME}:${pass}" -X POST "$api" \
      -H "Content-Type: application/json" \
      --data-binary @"$STATE/nexus-group.json" || true)
    echo "Create Nexus group lightwell-java HTTP ${code}"
  fi
  if [[ "$code" != "200" && "$code" != "201" && "$code" != "204" ]]; then
    cat "$STATE/nexus-group.out" >&2 || true
    return 1
  fi
}

if [[ "${LIGHTWELL_MODE:-demo}" == "prod" ]]; then
  export LIGHTWELL_JAVA_MEMBERS="lightwell-java-predisclosure,lightwell-java-remediated,lightwell-java-validated"
else
  export LIGHTWELL_JAVA_MEMBERS="lightwell-java-remediated,lightwell-java-validated"
fi

FAILED=0
if [[ "$TIER" == "all" ]]; then
  if [[ "${LIGHTWELL_MODE:-demo}" == "prod" ]]; then
    copy_tier predisclosure
  fi
  copy_tier remediated
  copy_tier validated
  if [[ "$TARGET" == "artifactory" || "$TARGET" == "both" ]]; then
    ensure_artifactory_virtual || FAILED=$((FAILED + 1))
  fi
  if [[ "$TARGET" == "nexus" || "$TARGET" == "both" ]]; then
    ensure_nexus_group || FAILED=$((FAILED + 1))
  fi
else
  copy_tier "$TIER"
fi

if [[ "${LIGHTWELL_REPOS_ONLY:-}" != "1" && ( "$TIER" == "remediated" || "$TIER" == "all" ) && -n "${OSV_URL}" ]]; then
  echo
  echo "== OSV advisories =="
  echo "Source: $OSV_URL"
  OSV_DIR="$STATE/osv"
mkdir -p "$OSV_DIR"
OSV_OK=0
OSV_BAD=0
if ! list_osv_names >"$STATE/osv-names.txt"; then
  echo "Could not list the OSV index."
  FAILED=$((FAILED + 1))
else
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    http=$(curl -sS -L -o "$OSV_DIR/$name" -w '%{http_code}' --max-time 60 \
      "${OSV_URL}${name}" || true)
    if [[ "$http" == "200" ]] && [[ -s "$OSV_DIR/$name" ]] \
      && ! grep -q 'Request has expired' "$OSV_DIR/$name"; then
      echo "  ok   $name"
      OSV_OK=$((OSV_OK + 1))
    else
      echo "  expired or failed ($http)  $name"
      rm -f "$OSV_DIR/$name"
      OSV_BAD=$((OSV_BAD + 1))
      FAILED=$((FAILED + 1))
    fi
  done <"$STATE/osv-names.txt"
  echo "OSV saved: $OSV_OK, not saved: $OSV_BAD, directory: $OSV_DIR"
fi
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "Catalog copy finished."
else
  echo "Catalog copy finished with $FAILED failure(s)."
  echo "An expired S3 link is the Lightwell redirect, not the local repository. Re-run this script when that file is fresh."
  exit 1
fi
