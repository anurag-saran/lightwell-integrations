#!/usr/bin/env bash
# Deploy GitLab CE on OpenShift for the Lightwell GitLab plugin demo.
#
# Modes:
#   LIGHTWELL_GITLAB_MODE=omnibus  (default) — single gitlab-ce pod + Route + Runner skeleton
#   LIGHTWELL_GITLAB_MODE=helm     — official gitlab/gitlab Helm chart (needs more RAM)
#
# By default scales Nexus in lightwell-demo to 0 so a SNO has room for GitLab.
# Set LIGHTWELL_KEEP_NEXUS=1 to skip that.
#
# Usage: ./scripts/setup-openshift-gitlab.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-common.sh
source "$ROOT/scripts/lib-common.sh"

NS="${LIGHTWELL_GITLAB_NAMESPACE:-lightwell-gitlab}"
DEMO_NS="${LIGHTWELL_OPENSHIFT_NAMESPACE:-lightwell-demo}"
MODE="${LIGHTWELL_GITLAB_MODE:-omnibus}"
DEMO_PASSWORD="${DEMO_PASSWORD:-Lightwell-demo1}"
DOMAIN="${LIGHTWELL_OPENSHIFT_APPS_DOMAIN:-}"
KEEP_NEXUS="${LIGHTWELL_KEEP_NEXUS:-0}"
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

echo "== OpenShift GitLab (Lightwell plugin demo) =="
echo "Namespace: $NS"
echo "Mode:      $MODE"

if [[ "$KEEP_NEXUS" != "1" ]]; then
  if oc -n "$DEMO_NS" get deploy nexus >/dev/null 2>&1; then
    echo "Scaling Nexus in $DEMO_NS to 0 (SNO memory). Set LIGHTWELL_KEEP_NEXUS=1 to skip."
    oc -n "$DEMO_NS" scale deployment/nexus --replicas=0 >/dev/null || true
  fi
fi

# Infer apps domain from an existing Route when not set.
if [[ -z "$DOMAIN" ]]; then
  SAMPLE_HOST="$(oc -n "$DEMO_NS" get route artifactory -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  if [[ -n "$SAMPLE_HOST" && "$SAMPLE_HOST" == *.apps.* ]]; then
    DOMAIN="${SAMPLE_HOST#*.}"
  fi
fi
DOMAIN="${DOMAIN:-apps.asaran.na-launch.com}"
GITLAB_HOST="gitlab.${DOMAIN}"
EXTERNAL_URL="https://${GITLAB_HOST}"
echo "GitLab URL: $EXTERNAL_URL"

oc create namespace "$NS" --dry-run=client -o yaml | oc apply -f - >/dev/null
oc adm policy add-scc-to-user anyuid -z lightwell-gitlab -n "$NS" >/dev/null 2>&1 || {
  echo "Could not grant anyuid to lightwell-gitlab (need cluster-admin)."
  echo "  oc adm policy add-scc-to-user anyuid -z lightwell-gitlab -n $NS"
}
oc adm policy add-scc-to-user anyuid -z lightwell-gitlab-runner -n "$NS" >/dev/null 2>&1 || true

if [[ "$MODE" == "helm" ]]; then
  if ! command -v helm >/dev/null 2>&1; then
    echo "helm is required for LIGHTWELL_GITLAB_MODE=helm" >&2
    exit 1
  fi
  helm repo add gitlab https://charts.gitlab.io/ >/dev/null 2>&1 || true
  helm repo update gitlab >/dev/null
  oc -n "$NS" create secret generic lightwell-gitlab-initial-root \
    --from-literal=password="$DEMO_PASSWORD" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  helm upgrade --install lightwell-gitlab gitlab/gitlab \
    -n "$NS" \
    -f "$ROOT/openshift/gitlab/values-demo.yaml" \
    --set global.hosts.domain="$DOMAIN" \
    --set global.hosts.gitlab.name="$GITLAB_HOST" \
    --timeout 45m \
    --wait=false
  echo "Helm release applied. Watch: oc -n $NS get pods"
  echo "When webservice is Ready, open $EXTERNAL_URL (root / $DEMO_PASSWORD)."
  echo "Runner ships with the chart (gitlab-runner). Confirm: oc -n $NS get pods -l app=gitlab-gitlab-runner"
else
  # Patch password + EXTERNAL_URL into omnibus manifests, then apply.
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cp "$ROOT/openshift/gitlab/omnibus.yaml" "$TMP/omnibus.yaml"
  # shellcheck disable=SC2016
  python3 - "$TMP/omnibus.yaml" "$DEMO_PASSWORD" "$EXTERNAL_URL" "$GITLAB_HOST" <<'PY'
import pathlib, sys
path, password, external_url, host = sys.argv[1:5]
text = pathlib.Path(path).read_text()
text = text.replace("password: Lightwell-demo1", f"password: {password}", 1)
text = text.replace(
    'value: "https://gitlab-lightwell-gitlab.apps.asaran.na-launch.com"',
    f'value: "{external_url}"',
    1,
)
# Prefer Route host gitlab.<domain>; also set Route host explicitly if empty.
if "name: gitlab\n  namespace: lightwell-gitlab" in text and "spec:\n  to:" in text:
    text = text.replace(
        "spec:\n  to:\n    kind: Service\n    name: gitlab\n  port:\n    targetPort: http\n  tls:",
        f"spec:\n  host: {host}\n  to:\n    kind: Service\n    name: gitlab\n  port:\n    targetPort: http\n  tls:",
        1,
    )
pathlib.Path(path).write_text(text)
PY
  oc apply -f "$TMP/omnibus.yaml"
  echo "Waiting for GitLab Deployment (first boot often 10–20 minutes)..."
  oc -n "$NS" rollout status deployment/gitlab --timeout=30m || {
    echo "Rollout still progressing. Check: oc -n $NS get pods,route"
    echo "Logs: oc -n $NS logs deploy/gitlab --tail=100"
  }
fi

HOST="$(oc -n "$NS" get route gitlab -o jsonpath='{.spec.host}' 2>/dev/null || true)"
if [[ -z "$HOST" ]]; then
  # Helm chart creates routes named differently
  HOST="$(oc -n "$NS" get route -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)"
fi
if [[ -n "$HOST" ]]; then
  EXTERNAL_URL="https://${HOST}"
fi

echo
echo "GitLab UI:  $EXTERNAL_URL"
echo "Login:      root / ${DEMO_PASSWORD}"
echo
echo "Next — register a Runner (omnibus mode starts with replicas=0 until token is set):"
echo "  1. GitLab UI → Admin → CI/CD → Runners → New instance runner → copy token"
echo "  2. ./scripts/register-openshift-gitlab-runner.sh <runner-token>"
echo "  3. Import payments-service + lightwell-gitlab-plugin-demo (see GITLAB-OPENSHIFT.md)"
echo
echo "Demo password is for this OpenShift demo only."
