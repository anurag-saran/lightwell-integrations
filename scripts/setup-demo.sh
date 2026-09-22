#!/usr/bin/env bash
# Public demo on the local Podman Artifactory and Nexus. No Lightwell credentials.
#
# Creates lightwell-java-remediated, lightwell-java-validated, the lightwell-java
# virtual/group (remediated, then validated), and lightwell-python-validated,
# then copies the small public catalogs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-common.sh
source "$ROOT/scripts/lib-common.sh"

export LIGHTWELL_MODE=demo
unset LIGHTWELL_USER LIGHTWELL_TOKEN LIGHTWELL_URL
export LIGHTWELL_SKIP_SAMPLE=1

echo "== Public Lightwell demo =="
echo "No user or token. Feeds are the public demo."

"$ROOT/scripts/setup-artifactory.sh"
"$ROOT/scripts/setup-nexus.sh"

set +e
"$ROOT/scripts/copy-catalog.sh" both all
catalog_status=$?
"$ROOT/scripts/copy-python-validated.sh" both
python_status=$?
set -e

echo
echo "Artifactory UI:  http://127.0.0.1:${ARTIFACTORY_UI_PORT:-8082}/ui/"
echo "Nexus UI:        http://127.0.0.1:${NEXUS_HOST_PORT:-8083}/"
echo "Login:           admin / ${DEMO_PASSWORD:-Lightwell-demo1}"
echo "Java client:     lightwell-java  (remediated, then validated)"
echo "Python:          lightwell-python-validated"
echo "Demo password is local-only. Do not reuse it on a shared server."

if [[ "$catalog_status" -ne 0 || "$python_status" -ne 0 ]]; then
  echo "Some catalog files did not copy. The repositories are still configured."
  echo "An expired S3 link is reported above. The copies that succeeded stay in place."
  exit 1
fi
