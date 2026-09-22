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
    echo "podman is required. On RHEL: sudo dnf install -y podman" >&2
    exit 1
  fi
}

# LIGHTWELL_MODE=demo (default, anonymous public feed) or prod (service account).
integrations_lightwell_url() {
  case "${LIGHTWELL_MODE:-demo}" in
    demo)
      echo "https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/"
      ;;
    prod)
      : "${LIGHTWELL_USER:?Set LIGHTWELL_USER to XXXXXXX|service-account-name}"
      : "${LIGHTWELL_TOKEN:?Set LIGHTWELL_TOKEN to the service-account token}"
      echo "${LIGHTWELL_URL:-https://packages.redhat.com/lightwell/java/remediated/}"
      ;;
    *)
      echo "LIGHTWELL_MODE must be demo or prod (got ${LIGHTWELL_MODE})" >&2
      exit 2
      ;;
  esac
}

integrations_wait_http() {
  local url="$1" tries="${2:-90}" i
  for ((i = 1; i <= tries; i++)); do
    if curl -sf -o /dev/null --max-time 5 "$url"; then
      return 0
    fi
    sleep 4
  done
  echo "Timed out waiting for $url" >&2
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
