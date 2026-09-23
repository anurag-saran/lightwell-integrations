#!/usr/bin/env bash
# Copy one Lightwell jar through a local Artifactory remote or Nexus proxy.
# Usage: ./scripts/copy-sample.sh artifactory|nexus
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"

TOOL="${1:-}"
if [[ "$TOOL" != "artifactory" && "$TOOL" != "nexus" ]]; then
  echo "Usage: $0 artifactory|nexus" >&2
  exit 2
fi

SMOKE="${LIGHTWELL_SMOKE_PATH:-com/fasterxml/woodstox/woodstox-core/6.0.3.rhlw-00001/woodstox-core-6.0.3.rhlw-00001.jar}"
STATE="$(integrations_state_dir)"
mkdir -p "$STATE"
OUT="$STATE/$(basename "$SMOKE")"

USER="${LIGHTWELL_COPY_USER:-admin}"
if [[ "$TOOL" == "artifactory" ]]; then
  BASE="http://127.0.0.1:${ARTIFACTORY_UI_PORT:-8082}/artifactory/lightwell-java-remediated"
  PASS="${LIGHTWELL_COPY_PASSWORD:-${DEMO_PASSWORD:-Lightwell-demo1}}"
  LABEL="Artifactory"
else
  BASE="http://127.0.0.1:${NEXUS_HOST_PORT:-8083}/repository/lightwell-java-remediated"
  if [[ -n "${LIGHTWELL_COPY_PASSWORD:-}" ]]; then
    PASS="$LIGHTWELL_COPY_PASSWORD"
  elif [[ -f "$STATE/nexus-admin.password" ]]; then
    PASS="$(cat "$STATE/nexus-admin.password")"
  else
    PASS="${DEMO_PASSWORD:-Lightwell-demo1}"
  fi
  LABEL="Nexus"
fi

URL="${BASE}/${SMOKE}"
echo "Copying through $LABEL: $URL"
HTTP=$(curl -sS -u "${USER}:${PASS}" -o "$OUT" -w "%{http_code}" --max-time 180 "$URL" || true)
SIZE=0
if [[ -f "$OUT" ]]; then
  SIZE=$(wc -c < "$OUT" | tr -d ' ')
fi
if [[ "$HTTP" != "200" || "$SIZE" -lt 1 ]]; then
  echo "Copy failed: HTTP ${HTTP:-none}, bytes $SIZE" >&2
  echo "URL: $URL" >&2
  DIRECT="$STATE/lightwell-direct.body"
  curl -sS -L --max-time 30 -o "$DIRECT" \
    "$(integrations_lightwell_url)${SMOKE}" >/dev/null || true
  if grep -q 'Request has expired' "$DIRECT" "$OUT" 2>/dev/null; then
    echo "Lightwell answered with a redirect to an S3 link that is already expired." >&2
    echo "The repository is configured. Re-run this copy when the feed issues a fresh redirect." >&2
  fi
  rm -f "$OUT" "$DIRECT"
  exit 1
fi

echo "HTTP $HTTP, $SIZE bytes, saved $OUT"
echo "This file is now cached in $LABEL. The next build can resolve it from your server."
