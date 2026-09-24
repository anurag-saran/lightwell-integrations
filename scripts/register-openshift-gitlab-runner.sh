#!/usr/bin/env bash
# Patch the omnibus Runner ConfigMap with a registration token and scale up.
#
# Usage: ./scripts/register-openshift-gitlab-runner.sh <runner-authentication-token>
set -euo pipefail

NS="${LIGHTWELL_GITLAB_NAMESPACE:-lightwell-gitlab}"
TOKEN="${1:-}"

if [[ -z "$TOKEN" ]]; then
  echo "Usage: $0 <runner-authentication-token>" >&2
  echo "Create an instance or group runner in GitLab UI and paste the token." >&2
  exit 1
fi
if ! command -v oc >/dev/null 2>&1; then
  echo "oc is required." >&2
  exit 1
fi
if ! oc whoami >/dev/null 2>&1; then
  echo "oc is not logged in." >&2
  exit 1
fi

oc -n "$NS" get configmap lightwell-gitlab-runner-config -o jsonpath='{.data.config\.toml}' \
  > /tmp/lightwell-runner-config.toml
python3 - "$TOKEN" <<'PY'
import pathlib, re, sys
token = sys.argv[1]
path = pathlib.Path("/tmp/lightwell-runner-config.toml")
text = path.read_text()
if "REPLACE_WITH_RUNNER_TOKEN" in text:
    text = text.replace("REPLACE_WITH_RUNNER_TOKEN", token)
else:
    text, n = re.subn(
        r'(?m)^(\s*token\s*=\s*")[^"]*(")',
        rf"\g<1>{token}\2",
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit("Could not find token = \"...\" in runner config.toml")
path.write_text(text)
PY

oc -n "$NS" create configmap lightwell-gitlab-runner-config \
  --from-file=config.toml=/tmp/lightwell-runner-config.toml \
  --dry-run=client -o yaml | oc apply -f - >/dev/null
rm -f /tmp/lightwell-runner-config.toml

oc -n "$NS" scale deployment/gitlab-runner --replicas=1 >/dev/null
oc -n "$NS" rollout restart deployment/gitlab-runner >/dev/null
oc -n "$NS" rollout status deployment/gitlab-runner --timeout=5m

echo "Runner Deployment is up in $NS."
echo "Confirm in GitLab UI → Admin → CI/CD → Runners (should show online)."
