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

integrations_require_host_port "$UI_PORT" "$NAME"
integrations_require_host_port "$ROUTER_PORT" "$NAME"
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

# The public repository REST API is Pro-only on this image. The console uses
# /artifactory/ui/admin/repositories, which OSS allows.
UI_REPOS="http://127.0.0.1:${UI_PORT}/artifactory/ui/admin/repositories"
python3 - "$LW_URL" "${LIGHTWELL_MODE:-demo}" <<'PY' >"$STATE/artifactory-ui.json"
import json, os, sys
url, mode = sys.argv[1], sys.argv[2]
basic = {
    "url": url,
    "layout": "maven-2-default",
    "offline": False,
    "includesPattern": "**/*",
    "username": "",
    "password": "",
}
if mode == "prod":
    basic["username"] = os.environ["LIGHTWELL_USER"]
    basic["password"] = os.environ["LIGHTWELL_TOKEN"]
print(json.dumps({
    "type": "remoteRepoConfig",
    "general": {"repoKey": "lightwell-remote"},
    "basic": basic,
    "advanced": {
        # Lightwell redirects to a presigned S3 URL. S3 rejects HEAD.
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

artifactory_apply_remote_fields() {
  python3 - "$LW_URL" "${LIGHTWELL_MODE:-demo}" "$STATE/artifactory-ui-get.json" <<'PY' >"$STATE/artifactory-ui-put.json"
import json, os, sys
url, mode, path = sys.argv[1:]
d = json.load(open(path))
d.setdefault("basic", {})["url"] = url
spec = d.setdefault("typeSpecific", {})
spec["listRemoteFolderItems"] = True
spec["enableTokenAuthentication"] = False
spec["handleReleases"] = True
spec["handleSnapshots"] = False
if mode == "prod":
    d["basic"]["username"] = os.environ["LIGHTWELL_USER"]
    d["basic"]["password"] = os.environ["LIGHTWELL_TOKEN"]
adv = d.setdefault("advanced", {})
adv["bypassHeadRequests"] = True
cache = adv.setdefault("cache", {})
cache["missedRetrievalCachePeriodSecs"] = 600
cache.setdefault("retrievalCachePeriodSecs", 7200)
print(json.dumps(d))
PY
}

GET=$(curl -sS -o "$STATE/artifactory-ui-get.json" -w "%{http_code}" \
  -u "$AUTH" "${UI_REPOS}/remote/lightwell-remote" || true)
HTTP="$GET"
if [[ "$GET" != "200" ]]; then
  HTTP=$(curl -sS -o "$STATE/artifactory-repo.out" -w "%{http_code}" \
    -u "$AUTH" -X POST "$UI_REPOS" \
    -H "Content-Type: application/json" \
    --data-binary @"$STATE/artifactory-ui.json" || true)
  echo "Create remote HTTP $HTTP"
  GET=$(curl -sS -o "$STATE/artifactory-ui-get.json" -w "%{http_code}" \
    -u "$AUTH" "${UI_REPOS}/remote/lightwell-remote" || true)
fi
if [[ "$GET" == "200" ]]; then
  artifactory_apply_remote_fields
  HTTP=$(curl -sS -o "$STATE/artifactory-repo.out" -w "%{http_code}" \
    -u "$AUTH" -X PUT "$UI_REPOS" \
    -H "Content-Type: application/json" \
    --data-binary @"$STATE/artifactory-ui-put.json" || true)
  echo "Update remote HTTP $HTTP"
fi

echo
echo "Artifactory UI:  http://127.0.0.1:${UI_PORT}/ui/"
echo "Login:           admin / ${DEMO_PASSWORD}"
echo "Demo password is local-only. Do not reuse it on a shared Artifactory."

artifactory_clicks() {
  echo "  Administration → Repositories → Create a Repository → Remote → Maven"
  echo "  Repository Key: lightwell-remote"
  echo "  URL:            $LW_URL"
  echo "  Maven Settings: check List Remote Artifacts"
  echo "  Clear Enable Token Authentication"
  echo "  Advanced: check Bypass HEAD Requests (the feed redirects to S3, and S3 rejects HEAD)"
  echo "  Missed Retrieval Cache Period: 600 seconds"
  echo "  If the screen has Metadata Retrieval Cache Period, set that to 600 seconds too"
  echo "Full click path: ARTIFACTORY.md"
}

export LIGHTWELL_COPY_USER="${AUTH%%:*}"
export LIGHTWELL_COPY_PASSWORD="${AUTH#*:}"

if [[ "$HTTP" == "200" || "$HTTP" == "201" ]]; then
  echo "Remote repo:     lightwell-remote"
  "$(dirname "$0")/copy-sample.sh" artifactory
  echo "Browse:          http://127.0.0.1:${UI_PORT}/ui/repos/tree/General/lightwell-remote"
  exit 0
fi

echo
echo "The console API did not save lightwell-remote. Create it in the UI, then this script will copy a sample jar:"
artifactory_clicks
echo
echo "Waiting up to 3 minutes for lightwell-remote to appear..."
READY=0
for ((i = 1; i <= 45; i++)); do
  CODE=$(curl -sS -o /dev/null -w "%{http_code}" -u "$AUTH" \
    "${UI_REPOS}/remote/lightwell-remote" || true)
  if [[ "$CODE" == "200" ]]; then
    READY=1
    break
  fi
  sleep 4
done
if [[ "$READY" == "1" ]]; then
  "$(dirname "$0")/copy-sample.sh" artifactory
  echo "Browse:          http://127.0.0.1:${UI_PORT}/ui/repos/tree/General/lightwell-remote"
  exit 0
fi
echo "lightwell-remote is still missing. Create it with these clicks, then re-run this script:" >&2
artifactory_clicks >&2
echo "Repository API HTTP $HTTP" >&2
if [[ -f "$STATE/artifactory-repo.out" ]]; then
  cat "$STATE/artifactory-repo.out" >&2
fi
exit 1
