#!/usr/bin/env bash
# Start SonarQube Community.
# Sonar does not proxy Lightwell — it gates application code quality.
# UI: http://127.0.0.1:9000
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
integrations_require_podman

NAME="${SONAR_CONTAINER:-lightwell-sonarqube}"
IMAGE="${SONAR_IMAGE:-docker.io/sonarqube:community}"
HOST_PORT="${SONAR_HOST_PORT:-9000}"
DEMO_PASSWORD="${DEMO_PASSWORD:-Lightwell-demo1}"
STATE="$(integrations_state_dir)"
mkdir -p "$STATE"

echo "== SonarQube Community ($IMAGE) =="
echo "This container does not proxy Lightwell. Pair it with Artifactory or Nexus."

integrations_ensure_container "$NAME" \
  --restart=unless-stopped \
  -p "${HOST_PORT}:9000" \
  -v "${NAME}-data:/opt/sonarqube/data" \
  -v "${NAME}-logs:/opt/sonarqube/logs" \
  -v "${NAME}-ext:/opt/sonarqube/extensions" \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  -e SONAR_WEB_JAVAOPTS="-Xmx512m" \
  -e SONAR_CE_JAVAOPTS="-Xmx512m" \
  "$IMAGE"

echo "Waiting for SonarQube..."
BASE="http://127.0.0.1:${HOST_PORT}"
for ((i = 1; i <= 90; i++)); do
  STATUS=$(curl -fsS "$BASE/api/system/status" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)
  if [[ "$STATUS" == "UP" ]]; then
    break
  fi
  sleep 4
done
if [[ "${STATUS:-}" != "UP" ]]; then
  echo "SonarQube did not reach UP. Check: podman logs $NAME" >&2
  exit 1
fi

if curl -fsS -o /dev/null -u "admin:${DEMO_PASSWORD}" "$BASE/api/system/status"; then
  :
elif curl -fsS -o /dev/null -u "admin:admin" "$BASE/api/authentication/validate?password=admin"; then
  curl -fsS -u "admin:admin" -X POST \
    "$BASE/api/users/change_password?login=admin&previousPassword=admin&password=${DEMO_PASSWORD}" \
    >/dev/null
fi

echo
echo "SonarQube UI: http://127.0.0.1:${HOST_PORT}/"
echo "Login:        admin / ${DEMO_PASSWORD}"
echo
echo "Sonar quality gate = app health. A dependency-upgrade grade (upgrade-delta)"
echo "is a separate project and a separate gate. Both must pass."
echo "See SONARQUBE.md"
