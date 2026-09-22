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

integrations_require_host_port "$HOST_PORT" "$NAME"
integrations_ensure_container "$NAME" \
  --restart=unless-stopped \
  -p "${HOST_PORT}:8081" \
  -v "${NAME}-data:/nexus-data" \
  -e INSTALL4J_ADD_VM_PARAMS="-Xms512m -Xmx1g -XX:MaxDirectMemorySize=512m" \
  "$IMAGE"

echo "Waiting for Nexus..."
# 401 means Nexus is up and anonymous access is off.
integrations_wait_http "http://127.0.0.1:${HOST_PORT}/service/rest/v1/status" 150 '200|401'

PASS_FILE="$STATE/nexus-admin.password"
nexus_auth_code() {
  curl -sS -o /dev/null -w '%{http_code}' --max-time 8 \
    -u "admin:$1" "http://127.0.0.1:${HOST_PORT}/service/rest/v1/status" || true
}

ADMIN_PASS=""
if [[ -f "$PASS_FILE" ]]; then
  CANDIDATE="$(cat "$PASS_FILE")"
  CODE="$(nexus_auth_code "$CANDIDATE")"
  if [[ "$CODE" == "200" ]]; then
    ADMIN_PASS="$CANDIDATE"
  elif [[ "$CODE" == "429" ]]; then
    echo "Nexus is rate-limiting admin login. Waiting 30 seconds..."
    sleep 30
    CODE="$(nexus_auth_code "$CANDIDATE")"
    if [[ "$CODE" == "200" ]]; then
      ADMIN_PASS="$CANDIDATE"
    fi
  fi
fi
if [[ -z "$ADMIN_PASS" ]] && [[ "$(nexus_auth_code "$DEMO_PASSWORD")" == "200" ]]; then
  ADMIN_PASS="$DEMO_PASSWORD"
fi
if [[ -z "$ADMIN_PASS" ]]; then
  if ! podman exec "$NAME" test -f /nexus-data/admin.password; then
    echo "Could not log in to Nexus as admin, and the one-time password file is gone." >&2
    echo "Wait for the login lockout to clear, then re-run. Expected password: ${DEMO_PASSWORD}" >&2
    exit 1
  fi
  echo "Reading one-time admin password from the container..."
  ONCE="$(podman exec "$NAME" cat /nexus-data/admin.password)"
  CODE="$(nexus_auth_code "$ONCE")"
  if [[ "$CODE" == "429" ]]; then
    echo "Nexus is rate-limiting admin login. Waiting 30 seconds..."
    sleep 30
    CODE="$(nexus_auth_code "$ONCE")"
  fi
  if [[ "$CODE" != "200" ]]; then
    echo "Nexus admin login returned HTTP ${CODE}." >&2
    exit 1
  fi
  curl -fsS -u "admin:${ONCE}" -X PUT \
    -H "Content-Type: text/plain" \
    --data "$DEMO_PASSWORD" \
    "http://127.0.0.1:${HOST_PORT}/service/rest/v1/security/users/admin/change-password"
  ADMIN_PASS="$DEMO_PASSWORD"
fi
printf '%s' "$ADMIN_PASS" >"$PASS_FILE"
chmod 600 "$PASS_FILE"

python3 - "$LW_URL" "${LIGHTWELL_MODE:-demo}" <<'PY' >"$STATE/nexus-repo.json"
import json, os, sys
url, mode = sys.argv[1], sys.argv[2]
http_client = {
    "blocked": False,
    # A single stale Lightwell redirect must not take the proxy offline.
    "autoBlock": False,
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
    "name": "lightwell-java-remediated",
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

HTTP=$(curl -sS -o "$STATE/nexus-repo.out" -w "%{http_code}" \
  -u "admin:${ADMIN_PASS}" -X POST \
  "http://127.0.0.1:${HOST_PORT}/service/rest/v1/repositories/maven/proxy" \
  -H "Content-Type: application/json" \
  --data-binary @"$STATE/nexus-repo.json" || true)

if [[ "$HTTP" == "400" ]] && grep -q 'already exists\|Duplicate' "$STATE/nexus-repo.out" 2>/dev/null; then
  UPDATE=$(curl -sS -o "$STATE/nexus-repo.out" -w "%{http_code}" \
    -u "admin:${ADMIN_PASS}" -X PUT \
    "http://127.0.0.1:${HOST_PORT}/service/rest/v1/repositories/maven/proxy/lightwell-java-remediated" \
    -H "Content-Type: application/json" \
    --data-binary @"$STATE/nexus-repo.json" || true)
  echo "Proxy lightwell-java-remediated already existed; update HTTP $UPDATE"
  if [[ "$UPDATE" != "200" && "$UPDATE" != "204" ]]; then
    echo "Could not update cache ages. The existing proxy is unchanged; continuing to copy a sample jar."
  fi
  HTTP=200
fi

echo "Repository API HTTP $HTTP"
if [[ "$HTTP" != "200" && "$HTTP" != "201" && "$HTTP" != "204" ]]; then
  echo "Nexus response:" >&2
  cat "$STATE/nexus-repo.out" >&2
  exit 1
fi

export LIGHTWELL_COPY_USER=admin
export LIGHTWELL_COPY_PASSWORD="$ADMIN_PASS"
if [[ "${LIGHTWELL_SKIP_SAMPLE:-}" == "1" ]]; then
  echo "Skipping the sample jar copy."
else
  "$(dirname "$0")/copy-sample.sh" nexus
fi

echo
echo "Nexus UI:   http://127.0.0.1:${HOST_PORT}/"
echo "Login:      admin / ${ADMIN_PASS}"
echo "Proxy repo: lightwell-java-remediated  (Maven layout policy STRICT, metadata age 60 minutes)"
echo "Browse:     http://127.0.0.1:${HOST_PORT}/#browse/browse:lightwell-java-remediated"
echo "Password saved at $PASS_FILE (gitignored)."
