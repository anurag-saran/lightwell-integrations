#!/usr/bin/env bash
# Start JFrog Artifactory OSS and create a Maven remote that proxies Lightwell.
# UI: http://127.0.0.1:8082  (admin / the demo password printed at the end)
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
integrations_require_podman

NAME="${ARTIFACTORY_CONTAINER:-lightwell-artifactory}"
IMAGE="${ARTIFACTORY_IMAGE:-releases-docker.jfrog.io/jfrog/artifactory-oss:latest}"
UI_PORT="${ARTIFACTORY_UI_PORT:-8082}"
ROUTER_PORT="${ARTIFACTORY_ROUTER_PORT:-8081}"
DEMO_PASSWORD="${DEMO_PASSWORD:-Lightwell-demo1}"
LW_URL="$(integrations_lightwell_url)"
STATE="$(integrations_state_dir)"
mkdir -p "$STATE"

echo "== Artifactory OSS ($IMAGE) =="
echo "Lightwell remote: $LW_URL  (mode=${LIGHTWELL_MODE:-demo})"

# The image runs as uid 1030. A root-owned Podman volume leaves master.key
# unwritable and Artifactory exits after five minutes.
podman volume create "${NAME}-data" >/dev/null 2>&1 || true
podman run --rm --user 0 --entrypoint bash \
  -v "${NAME}-data:/var/opt/jfrog/artifactory" \
  "$IMAGE" \
  -c 'mkdir -p /var/opt/jfrog/artifactory/etc/security && chown -R 1030:1030 /var/opt/jfrog/artifactory && if [ ! -s /var/opt/jfrog/artifactory/etc/security/master.key ]; then openssl rand -hex 32 > /var/opt/jfrog/artifactory/etc/security/master.key && chown 1030:1030 /var/opt/jfrog/artifactory/etc/security/master.key && chmod 600 /var/opt/jfrog/artifactory/etc/security/master.key; fi'

integrations_ensure_container "$NAME" \
  --restart=unless-stopped \
  -p "${UI_PORT}:8082" \
  -p "${ROUTER_PORT}:8081" \
  -v "${NAME}-data:/var/opt/jfrog/artifactory" \
  -e JF_SHARED_DATABASE_ALLOWNONPOSTGRESQL=true \
  -e EXTRA_JAVA_OPTIONS="-Xms512m -Xmx2g" \
  "$IMAGE"

echo "Waiting for Artifactory UI..."
integrations_wait_http "http://127.0.0.1:${UI_PORT}/artifactory/api/system/ping" 120

AUTH="admin:${DEMO_PASSWORD}"
# First boot uses admin/password until the demo password is set.
if ! curl -fsS -o /dev/null -u "$AUTH" "http://127.0.0.1:${UI_PORT}/artifactory/api/system/ping"; then
  if curl -fsS -o /dev/null -u "admin:password" "http://127.0.0.1:${UI_PORT}/artifactory/api/system/ping"; then
    curl -fsS -u "admin:password" -X POST \
      "http://127.0.0.1:${UI_PORT}/artifactory/api/security/users/authorization/changePassword" \
      -H "Content-Type: application/json" \
      -d "{\"userName\":\"admin\",\"oldPassword\":\"password\",\"newPassword1\":\"${DEMO_PASSWORD}\",\"newPassword2\":\"${DEMO_PASSWORD}\"}" \
      >/dev/null || true
    if ! curl -fsS -o /dev/null -u "$AUTH" "http://127.0.0.1:${UI_PORT}/artifactory/api/system/ping"; then
      AUTH="admin:password"
      echo "Password change did not stick; continuing with the image default admin/password."
    fi
  else
    echo "Could not authenticate as admin. Open the UI and finish the first-boot wizard, then re-run." >&2
    exit 1
  fi
fi

python3 - "$LW_URL" "${LIGHTWELL_MODE:-demo}" <<'PY' >"$STATE/artifactory-repo.json"
import json, os, sys
url, mode = sys.argv[1], sys.argv[2]
body = {
    "key": "lightwell-remote",
    "rclass": "remote",
    "packageType": "maven",
    "url": url,
    "listRemoteFolderItems": True,
    "enableTokenAuthentication": False,
    "handleReleases": True,
    "handleSnapshots": False,
}
if mode == "prod":
    body["username"] = os.environ["LIGHTWELL_USER"]
    body["password"] = os.environ["LIGHTWELL_TOKEN"]
print(json.dumps(body))
PY

HTTP=$(curl -sS -o "$STATE/artifactory-repo.out" -w "%{http_code}" \
  -u "$AUTH" \
  "http://127.0.0.1:${UI_PORT}/artifactory/api/repositories/lightwell-remote" || true)

if [[ "$HTTP" != "200" ]]; then
  HTTP=$(curl -sS -o "$STATE/artifactory-repo.out" -w "%{http_code}" \
    -u "$AUTH" -X PUT \
    "http://127.0.0.1:${UI_PORT}/artifactory/api/repositories/lightwell-remote" \
    -H "Content-Type: application/json" \
    --data-binary @"$STATE/artifactory-repo.json" || true)
fi

echo
echo "Artifactory UI:  http://127.0.0.1:${UI_PORT}/ui/"
echo "Login:           admin / ${DEMO_PASSWORD}"
echo "Demo password is local-only. Do not reuse it on a shared Artifactory."

if [[ "$HTTP" == "200" || "$HTTP" == "201" ]]; then
  echo "Remote repo:     lightwell-remote"
  echo "Browse:          http://127.0.0.1:${UI_PORT}/ui/repos/tree/General/lightwell-remote"
  exit 0
fi

if grep -q 'Artifactory Pro' "$STATE/artifactory-repo.out" 2>/dev/null; then
  echo
  echo "Artifactory OSS is up, but this image blocks creating repositories over REST"
  echo "(Pro-only API). Create the remote in the UI — about one minute:"
  echo "  Administration → Repositories → Create a Repository → Remote → Maven"
  echo "  Repository Key: lightwell-remote"
  echo "  URL:            $LW_URL"
  echo "  Maven Settings: check List Remote Artifacts"
  echo "  Clear Enable Token Authentication"
  echo "Full click path: ARTIFACTORY.md"
  exit 0
fi

echo "Repository API HTTP $HTTP" >&2
cat "$STATE/artifactory-repo.out" >&2
exit 1
