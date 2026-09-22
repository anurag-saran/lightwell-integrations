#!/usr/bin/env bash
# Point the local Podman Artifactory and Nexus at production Lightwell Java feeds.
# Asks for the service-account user and token. Does not copy the catalog.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-common.sh
source "$ROOT/scripts/lib-common.sh"

if [[ -z "${LIGHTWELL_USER:-}" || -z "${LIGHTWELL_TOKEN:-}" ]]; then
  if [[ ! -t 0 ]]; then
    echo "Set LIGHTWELL_USER and LIGHTWELL_TOKEN, or run this script in a terminal." >&2
    exit 1
  fi
fi

if [[ -z "${LIGHTWELL_USER:-}" ]]; then
  read -r -p "Lightwell user (XXXXXXX|service-account-name): " LIGHTWELL_USER
fi
if [[ -z "${LIGHTWELL_TOKEN:-}" ]]; then
  read -r -s -p "Lightwell token: " LIGHTWELL_TOKEN
  echo
fi

if [[ -z "${LIGHTWELL_USER}" || -z "${LIGHTWELL_TOKEN}" ]]; then
  echo "User and token are required." >&2
  exit 1
fi

export LIGHTWELL_MODE=prod
export LIGHTWELL_USER
export LIGHTWELL_TOKEN
export LIGHTWELL_SKIP_SAMPLE=1
export LIGHTWELL_REPOS_ONLY=1

echo "== Production Lightwell =="
echo "User: ${LIGHTWELL_USER}"
echo "Token is set and will not be printed."

"$ROOT/scripts/setup-artifactory.sh"
"$ROOT/scripts/setup-nexus.sh"
"$ROOT/scripts/copy-catalog.sh" both all

feed="$(integrations_lightwell_feed_url java remediated)"
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 \
  -u "${LIGHTWELL_USER}:${LIGHTWELL_TOKEN}" "$feed" || true)

echo
echo "Production remediated feed check: HTTP ${code}"
if [[ "$code" != "200" && "$code" != "302" ]]; then
  echo "The token check did not succeed. The repositories are still in place."
fi

echo
echo "Artifactory UI:  http://127.0.0.1:${ARTIFACTORY_UI_PORT:-8082}/ui/"
echo "Nexus UI:        http://127.0.0.1:${NEXUS_HOST_PORT:-8083}/"
echo "Login:           admin / ${DEMO_PASSWORD:-Lightwell-demo1}"
echo "Java client:     lightwell-java  (predisclosure, then remediated, then validated)"
echo "The production catalog was not copied. The first request for a jar stores that jar."
