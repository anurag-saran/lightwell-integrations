#!/usr/bin/env bash
# Deploy Artifactory OSS and Nexus OSS on OpenShift and wire them to the
# anonymous public Lightwell demo (same topology as setup-demo.sh).
#
# Prerequisites: oc logged in, permission to create Namespace/PVC/Deployment/
# Service/Route, and egress to packages.redhat.com plus the container images.
#
# Usage: ./scripts/setup-openshift-demo.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-common.sh
source "$ROOT/scripts/lib-common.sh"
integrations_enable_insecure_curl_if_requested

NS="${LIGHTWELL_OPENSHIFT_NAMESPACE:-lightwell-demo}"
DEMO_PASSWORD="${DEMO_PASSWORD:-Lightwell-demo1}"
STATE="$(integrations_state_dir)"
mkdir -p "$STATE"
chmod 700 "$STATE"

export LIGHTWELL_MODE=demo
unset LIGHTWELL_USER LIGHTWELL_TOKEN LIGHTWELL_URL
# OpenShift router certs are often not in the laptop trust store.
export LIGHTWELL_CURL_INSECURE="${LIGHTWELL_CURL_INSECURE:-1}"
integrations_enable_insecure_curl_if_requested

if ! command -v oc >/dev/null 2>&1; then
  echo "oc is required. Install the OpenShift CLI and log in." >&2
  exit 1
fi
if ! oc whoami >/dev/null 2>&1; then
  echo "oc is not logged in. Run: oc login ..." >&2
  exit 1
fi

echo "== OpenShift public Lightwell demo =="
echo "Namespace: $NS"
echo "No Lightwell token. Feeds are the public demo."

echo "Applying openshift/ ..."
oc apply -k "$ROOT/openshift/"

# Artifactory runs as uid 1030; Nexus as uid 200. Grant anyuid so SCCs allow it.
oc adm policy add-scc-to-user anyuid -z lightwell-artifactory -n "$NS" >/dev/null 2>&1 || {
  echo "Could not grant anyuid to lightwell-artifactory (need cluster-admin)."
  echo "  oc adm policy add-scc-to-user anyuid -z lightwell-artifactory -n $NS"
}
oc adm policy add-scc-to-user anyuid -z lightwell-nexus -n "$NS" >/dev/null 2>&1 || {
  echo "Could not grant anyuid to lightwell-nexus (need cluster-admin)."
  echo "  oc adm policy add-scc-to-user anyuid -z lightwell-nexus -n $NS"
}

echo "Waiting for Artifactory and Nexus Deployments..."
# Artifactory OSS first boot is slow (Derby + many sidecars-in-process).
oc -n "$NS" rollout status deployment/artifactory --timeout=20m
oc -n "$NS" rollout status deployment/nexus --timeout=10m

AF_HOST="$(oc -n "$NS" get route artifactory -o jsonpath='{.spec.host}')"
NX_HOST="$(oc -n "$NS" get route nexus -o jsonpath='{.spec.host}')"
if [[ -z "$AF_HOST" || -z "$NX_HOST" ]]; then
  echo "Routes were not admitted. Check: oc -n $NS get routes" >&2
  exit 1
fi

export LIGHTWELL_ARTIFACTORY_URL="https://${AF_HOST}"
export LIGHTWELL_NEXUS_URL="https://${NX_HOST}"
AF="$(integrations_artifactory_base)"
NX="$(integrations_nexus_base)"

echo "Artifactory Route: $AF"
echo "Nexus Route:       $NX"

echo "Waiting for Artifactory ping..."
integrations_wait_http "${AF}/artifactory/api/system/ping" 90 "200|401"
echo "Waiting for Nexus status..."
integrations_wait_http "${NX}/service/rest/v1/status" 90 "200|401"

# --- Artifactory admin password ---
AUTH="admin:${DEMO_PASSWORD}"
if ! integrations_curl -fsS -o /dev/null -u "$AUTH" "${AF}/artifactory/api/system/ping"; then
  if integrations_curl -fsS -o /dev/null -u "admin:password" "${AF}/artifactory/api/system/ping"; then
    integrations_curl -fsS -u "admin:password" -X POST \
      "${AF}/artifactory/api/security/users/authorization/changePassword" \
      -H "Content-Type: application/json" \
      -d "{\"userName\":\"admin\",\"oldPassword\":\"password\",\"newPassword1\":\"${DEMO_PASSWORD}\",\"newPassword2\":\"${DEMO_PASSWORD}\"}" \
      >/dev/null || true
  fi
fi
if ! integrations_curl -fsS -o /dev/null -u "$AUTH" "${AF}/artifactory/api/system/ping"; then
  echo "Could not authenticate to Artifactory as admin / ${DEMO_PASSWORD}." >&2
  echo "Open ${AF}/ui/ and finish first-boot, then re-run this script." >&2
  exit 1
fi

# --- Nexus admin password ---
PASS_FILE="$STATE/nexus-admin.password"
nexus_auth_code() {
  integrations_curl -sS -o /dev/null -w '%{http_code}' --max-time 8 \
    -u "admin:$1" "${NX}/service/rest/v1/status" || true
}

ADMIN_PASS=""
if [[ -f "$PASS_FILE" ]]; then
  CANDIDATE="$(cat "$PASS_FILE")"
  if [[ "$(nexus_auth_code "$CANDIDATE")" == "200" ]]; then
    ADMIN_PASS="$CANDIDATE"
  fi
fi
if [[ -z "$ADMIN_PASS" ]] && [[ "$(nexus_auth_code "$DEMO_PASSWORD")" == "200" ]]; then
  ADMIN_PASS="$DEMO_PASSWORD"
fi
if [[ -z "$ADMIN_PASS" ]]; then
  echo "Reading Nexus one-time admin password from the pod..."
  ONCE="$(oc -n "$NS" exec deploy/nexus -- cat /nexus-data/admin.password 2>/dev/null || true)"
  if [[ -z "$ONCE" ]]; then
    echo "Could not read /nexus-data/admin.password. Wait for Nexus to finish first boot, then re-run." >&2
    exit 1
  fi
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
  integrations_curl -fsS -u "admin:${ONCE}" -X PUT \
    -H "Content-Type: text/plain" \
    --data "$DEMO_PASSWORD" \
    "${NX}/service/rest/v1/security/users/admin/change-password"
  ADMIN_PASS="$DEMO_PASSWORD"
fi
printf '%s' "$ADMIN_PASS" >"$PASS_FILE"
chmod 600 "$PASS_FILE"

echo "Accepting Nexus Community Edition EULA..."
integrations_nexus_accept_eula "$NX" "admin:${ADMIN_PASS}"

export LIGHTWELL_COPY_USER=admin
export LIGHTWELL_COPY_PASSWORD="$ADMIN_PASS"

echo
echo "Creating Lightwell repositories and copying the small public catalogs..."
set +e
"$ROOT/scripts/copy-catalog.sh" both all
catalog_status=$?
"$ROOT/scripts/copy-python-validated.sh" both
python_status=$?
set -e

echo
echo "Artifactory UI:  ${AF}/ui/"
echo "Nexus UI:        ${NX}/"
echo "Login:           admin / ${DEMO_PASSWORD}"
echo "Java client:     ${AF}/artifactory/lightwell-java"
echo "Maven sample:"
echo "  mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \\"
echo "    -Dlightwell.repo.url=${AF}/artifactory/lightwell-java"
echo
echo "Demo password is for this OpenShift demo only. Do not reuse it on a shared server."
echo "If a pod is stuck on SCC, grant anyuid:"
echo "  oc adm policy add-scc-to-user anyuid -z lightwell-artifactory -n ${NS}"
echo "  oc adm policy add-scc-to-user anyuid -z lightwell-nexus -n ${NS}"

if [[ "$catalog_status" -ne 0 || "$python_status" -ne 0 ]]; then
  echo "Some catalog files did not copy. The repositories are still configured."
  echo "An expired S3 link is reported above. The copies that succeeded stay in place."
  exit 1
fi
