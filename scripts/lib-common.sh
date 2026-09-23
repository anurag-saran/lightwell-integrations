# Shared helpers for the Artifactory / Nexus / SonarQube setup scripts.
# Sourced, not executed.

integrations_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

integrations_state_dir() {
  local root
  root="$(integrations_root)"
  echo "${LIGHTWELL_INTEGRATIONS_STATE:-$root/.local/integrations}"
}

integrations_require_podman() {
  if ! command -v podman >/dev/null 2>&1; then
    echo "podman is required. On a Mac, install Podman. On RHEL: sudo dnf install -y podman" >&2
    exit 1
  fi
  if podman info >/dev/null 2>&1; then
    return 0
  fi
  if ! podman machine list >/dev/null 2>&1; then
    echo "Podman is installed but cannot reach a machine. On a Mac run: podman machine start" >&2
    exit 1
  fi
  echo "Starting the Podman machine..."
  podman machine start
  local i
  for ((i = 1; i <= 30; i++)); do
    if podman info >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "Podman machine did not become reachable. On a Mac run: podman machine start" >&2
  exit 1
}

# Fail when some other container already publishes this host port.
integrations_require_host_port() {
  local port="$1" owner="$2" line name
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    name="${line%% *}"
    [[ "$name" == "$owner" ]] && continue
    if [[ "$line" == *":${port}->"* ]]; then
      echo "Host port ${port} is used by container ${name}. Stop it, then re-run:" >&2
      echo "  podman stop ${name}" >&2
      exit 1
    fi
  done < <(podman ps --format '{{.Names}} {{.Ports}}')
}

# LIGHTWELL_MODE=demo (default, anonymous public feed) or prod (service account).
# integrations_lightwell_feed_url ECOSYSTEM TIER
# ecosystem: java | python
# tier: predisclosure | remediated | validated
# The public demo has no predisclosure feed.
integrations_lightwell_feed_url() {
  local eco="${1:-java}" tier="${2:-remediated}" mode="${LIGHTWELL_MODE:-demo}"
  case "$eco" in
    java|python) ;;
    *)
      echo "ecosystem must be java or python (got ${eco})" >&2
      return 2
      ;;
  esac
  case "$tier" in
    predisclosure|remediated|validated) ;;
    *)
      echo "tier must be predisclosure, remediated, or validated (got ${tier})" >&2
      return 2
      ;;
  esac
  case "$mode" in
    demo)
      if [[ "$tier" == "predisclosure" ]]; then
        echo "The public demo has no ${eco} predisclosure feed." >&2
        return 2
      fi
      echo "https://packages.redhat.com/lightwell/public-lightwell-demo/${eco}/${tier}/"
      ;;
    prod)
      : "${LIGHTWELL_USER:?Set LIGHTWELL_USER to XXXXXXX|service-account-name}"
      : "${LIGHTWELL_TOKEN:?Set LIGHTWELL_TOKEN to the service-account token}"
      echo "https://packages.redhat.com/lightwell/${eco}/${tier}/"
      ;;
    *)
      echo "LIGHTWELL_MODE must be demo or prod (got ${mode})" >&2
      return 2
      ;;
  esac
}

# Java remediated URL. LIGHTWELL_URL overrides this in prod only.
integrations_lightwell_url() {
  if [[ "${LIGHTWELL_MODE:-demo}" == "prod" && -n "${LIGHTWELL_URL:-}" ]]; then
    : "${LIGHTWELL_USER:?Set LIGHTWELL_USER to XXXXXXX|service-account-name}"
    : "${LIGHTWELL_TOKEN:?Set LIGHTWELL_TOKEN to the service-account token}"
    echo "$LIGHTWELL_URL"
    return 0
  fi
  integrations_lightwell_feed_url java remediated
}

# Wheel bytes for the Python validated feed. The public demo serves those
# files from the Pulp content path, not from the simple-index URL.
integrations_lightwell_python_files_url() {
  if [[ "${LIGHTWELL_MODE:-demo}" == "demo" ]]; then
    echo "https://packages.redhat.com/api/pulp-content/public-lightwell-demo/python/validated"
    return 0
  fi
  integrations_lightwell_feed_url python validated
}

# OSV advisories published next to the public demo remediated feed.
integrations_lightwell_osv_url() {
  if [[ "${LIGHTWELL_MODE:-demo}" != "demo" ]]; then
    echo "OSV copy is for the public demo feed." >&2
    return 2
  fi
  echo "https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/"
}

# Base URLs for the local repo managers. Override for OpenShift Routes:
#   LIGHTWELL_ARTIFACTORY_URL=https://artifactory-lightwell-demo.apps.example.com
#   LIGHTWELL_NEXUS_URL=https://nexus-lightwell-demo.apps.example.com
integrations_artifactory_base() {
  local base="${LIGHTWELL_ARTIFACTORY_URL:-http://127.0.0.1:${ARTIFACTORY_UI_PORT:-8082}}"
  echo "${base%/}"
}

integrations_nexus_base() {
  local base="${LIGHTWELL_NEXUS_URL:-http://127.0.0.1:${NEXUS_HOST_PORT:-8083}}"
  echo "${base%/}"
}

# True when callers point at a remote Artifactory/Nexus (OpenShift Routes).
integrations_using_remote_managers() {
  [[ -n "${LIGHTWELL_ARTIFACTORY_URL:-}" || -n "${LIGHTWELL_NEXUS_URL:-}" ]]
}

# curl wrapper. Set LIGHTWELL_CURL_INSECURE=1 for OpenShift router certs.
integrations_curl() {
  if [[ "${LIGHTWELL_CURL_INSECURE:-}" == "1" ]]; then
    command curl -k "$@"
  else
    command curl "$@"
  fi
}

# Call from scripts after sourcing this file so local curl uses -k when needed.
integrations_enable_insecure_curl_if_requested() {
  if [[ "${LIGHTWELL_CURL_INSECURE:-}" == "1" ]]; then
    curl() { command curl -k "$@"; }
  fi
}

# Third argument is a '|' list of acceptable HTTP codes. Default is 200.
# Nexus answers 401 on /status when anonymous access is off; that still means it is up.
integrations_wait_http() {
  local url="$1" tries="${2:-90}" accept="${3:-200}" i code=""
  for ((i = 1; i <= tries; i++)); do
    code=$(integrations_curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)
    if [[ "$code" =~ ^(${accept})$ ]]; then
      return 0
    fi
    sleep 4
  done
  echo "Timed out waiting for $url (last HTTP ${code:-none})" >&2
  return 1
}

integrations_ensure_container() {
  local name="$1"
  shift
  if podman container exists "$name"; then
    podman start "$name" >/dev/null
    return 0
  fi
  podman run -d --name "$name" "$@"
}

# Nexus Repository Community Edition blocks proxy/upload until the CE EULA is accepted.
# USER_PASS is "user:password". BASE is the Nexus root URL (no trailing slash).
integrations_nexus_accept_eula() {
  local base="$1" user_pass="$2" body code
  body="$(integrations_curl -fsS -u "$user_pass" "${base}/service/rest/v1/system/eula" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); d["accepted"]=True; print(json.dumps(d))')"
  code="$(integrations_curl -sS -o /dev/null -w '%{http_code}' -u "$user_pass" -X POST \
    -H "Content-Type: application/json" \
    --data-binary "$body" \
    "${base}/service/rest/v1/system/eula" || true)"
  if [[ "$code" != "204" && "$code" != "200" ]]; then
    echo "Nexus CE EULA accept returned HTTP ${code}." >&2
    return 1
  fi
}
