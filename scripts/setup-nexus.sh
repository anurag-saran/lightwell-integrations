#!/usr/bin/env bash
# Start Sonatype Nexus Repository OSS and create a Maven2 proxy of Lightwell.
# UI: http://127.0.0.1:8083  (host 8083 -> container 8081, so Artifactory can keep 8081/8082)
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
integrations_require_podman

NAME="${NEXUS_CONTAINER:-lightwell-nexus}"
IMAGE="${NEXUS_IMAGE:-docker.io/sonatype/nexus3:latest}"
HOST_PORT="${NEXUS_HOST_PORT:-8083}"
DEMO_PASSWORD="${DEMO_PASSWORD:-Lightwell-demo1}"
LW_URL="$(integrations_lightwell_url)"
STATE="$(integrations_state_dir)"
mkdir -p "$STATE"
chmod 700 "$STATE"

echo "== Nexus OSS ($IMAGE) =="
echo "Lightwell proxy: $LW_URL  (mode=${LIGHTWELL_MODE:-demo})"

integrations_ensure_container "$NAME" \
  --restart=unless-stopped \
  -p "${HOST_PORT}:8081" \
  -v "${NAME}-data:/nexus-data" \
  -e INSTALL4J_ADD_VM_PARAMS="-Xms512m -Xmx1g -XX:MaxDirectMemorySize=512m" \
  "$IMAGE"

echo "Waiting for Nexus..."
integrations_wait_http "http://127.0.0.1:${HOST_PORT}/service/rest/v1/status" 150

PASS_FILE="$STATE/nexus-admin.password"
if [[ -f "$PASS_FILE" ]]; then
  ADMIN_PASS="$(cat "$PASS_FILE")"
elif curl -fsS -o /dev/null -u "admin:${DEMO_PASSWORD}" "http://127.0.0.1:${HOST_PORT}/service/rest/v1/status"; then
  ADMIN_PASS="$DEMO_PASSWORD"
  printf '%s' "$ADMIN_PASS" >"$PASS_FILE"
  chmod 600 "$PASS_FILE"
else
  echo "Reading one-time admin password from the container..."
  ADMIN_PASS="$(podman exec "$NAME" cat /nexus-data/admin.password)"
  printf '%s' "$ADMIN_PASS" >"$PASS_FILE"
  chmod 600 "$PASS_FILE"
  curl -fsS -u "admin:${ADMIN_PASS}" -X PUT \
    -H "Content-Type: text/plain" \
    --data "$DEMO_PASSWORD" \
    "http://127.0.0.1:${HOST_PORT}/service/rest/v1/security/users/admin/change-password"
  ADMIN_PASS="$DEMO_PASSWORD"
  printf '%s' "$ADMIN_PASS" >"$PASS_FILE"
fi

python3 - "$LW_URL" "${LIGHTWELL_MODE:-demo}" <<'PY' >"$STATE/nexus-repo.json"
import json, os, sys
url, mode = sys.argv[1], sys.argv[2]
http_client = {
    "blocked": False,
    "autoBlock": True,
    "connection": {
        "retries": 0,
        "userAgentSuffix": "lightwell-integrations",
        "timeout": 60,
        "enableCircularRedirects": False,
        "enableCookies": False,
    },
}
if mode == "prod":
    http_client["authentication"] = {
        "type": "username",
        "username": os.environ["LIGHTWELL_USER"],
        "password": os.environ["LIGHTWELL_TOKEN"],
    }
print(json.dumps({
    "name": "lightwell-remote",
    "online": True,
    "storage": {"blobStoreName": "default", "strictContentTypeValidation": True},
    "proxy": {"remoteUrl": url, "contentMaxAge": 1440, "metadataMaxAge": 1440},
    "negativeCache": {"enabled": True, "timeToLive": 1440},
    "httpClient": http_client,
    "maven": {
        "versionPolicy": "RELEASE",
        "layoutPolicy": "STRICT",
        "contentDisposition": "INLINE",
    },
}))
PY

HTTP=$(curl -sS -o "$STATE/nexus-repo.out" -w "%{http_code}" \
  -u "admin:${ADMIN_PASS}" -X POST \
  "http://127.0.0.1:${HOST_PORT}/service/rest/v1/repositories/maven/proxy" \
  -H "Content-Type: application/json" \
  --data-binary @"$STATE/nexus-repo.json" || true)

if [[ "$HTTP" == "400" ]] && grep -q 'already exists\|Duplicate' "$STATE/nexus-repo.out" 2>/dev/null; then
  HTTP=200
  echo "Proxy lightwell-remote already exists."
fi

echo "Repository API HTTP $HTTP"
if [[ "$HTTP" != "200" && "$HTTP" != "201" && "$HTTP" != "204" ]]; then
  echo "Nexus response:" >&2
  cat "$STATE/nexus-repo.out" >&2
  exit 1
fi

echo
echo "Nexus UI:   http://127.0.0.1:${HOST_PORT}/"
echo "Login:      admin / ${ADMIN_PASS}"
echo "Proxy repo: lightwell-remote  (Maven layout policy STRICT)"
echo "Browse:     http://127.0.0.1:${HOST_PORT}/#browse/browse:lightwell-remote"
echo "Password saved at $PASS_FILE (gitignored)."
