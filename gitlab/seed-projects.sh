#!/usr/bin/env bash
# Seed plugin + target app onto GitLab from local trees only (no GitHub import).
#
# Usage:
#   ./gitlab/seed-projects.sh https://gitlab.apps.example.com "$TOKEN"
set -euo pipefail

GITLAB_URL="${1:?GitLab base URL required (https://gitlab....)}"
TOKEN="${2:?GitLab personal access token with api + write_repository}"
PLUGIN_SRC="${LIGHTWELL_GITLAB_PLUGIN_SRC:-$HOME/projects/lightwell-gitlab-plugin-demo}"
APP_SRC="${LIGHTWELL_APP_SRC:-$HOME/projects/payments-service}"
NS="${GITLAB_NAMESPACE:-root}"

GITLAB_URL="${GITLAB_URL%/}"

echo "== Seed Lightwell GitLab demo projects (GitLab-only; no GitHub) =="
echo "GitLab: $GITLAB_URL"
echo

if [[ ! -f "$PLUGIN_SRC/scripts/seed-gitlab-app.sh" ]]; then
  echo "Plugin sources not found at $PLUGIN_SRC"
  echo "Set LIGHTWELL_GITLAB_PLUGIN_SRC to lightwell-gitlab-plugin-demo."
  exit 1
fi

echo "1) Seed payments-service from local tree (strips .git / GitHub README)"
( cd "$PLUGIN_SRC" && ./scripts/seed-gitlab-app.sh "$GITLAB_URL" "$NS" "$TOKEN" "$APP_SRC" )

echo
echo "2) Push lightwell-gitlab-plugin-demo to GitLab"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
rsync -a --exclude .git --exclude __pycache__ --exclude .local "$PLUGIN_SRC/" "$WORKDIR/plugin/"
cd "$WORKDIR/plugin"
git init -b main
git add .
git -c user.name=lightwell-bot -c user.email=lightwell-bot@example.com commit -m "Lightwell GitLab plugin demo"
API="$GITLAB_URL/api/v4"
HOSTPATH="${GITLAB_URL#https://}"
HOSTPATH="${HOSTPATH#http://}"
NS_ID="$(curl -fsS --header "PRIVATE-TOKEN: $TOKEN" "$API/namespaces?search=${NS}" \
  | python3 -c "import json,sys; ns=json.load(sys.stdin); print(next(x['id'] for x in ns if x.get('path')=='${NS}' or x.get('full_path')=='${NS}'))")"
curl -fsS --header "PRIVATE-TOKEN: $TOKEN" --header "Content-Type: application/json" \
  --data "{\"name\":\"lightwell-gitlab-plugin-demo\",\"path\":\"lightwell-gitlab-plugin-demo\",\"namespace_id\":${NS_ID},\"visibility\":\"private\",\"initialize_with_readme\":false}" \
  "$API/projects" >/dev/null 2>&1 || true
# Unprotect main if needed for force push
curl -fsS -X DELETE --header "PRIVATE-TOKEN: $TOKEN" \
  "$API/projects/$(python3 -c "import urllib.parse; print(urllib.parse.quote('${NS}/lightwell-gitlab-plugin-demo', safe=''))")/protected_branches/main" \
  >/dev/null 2>&1 || true
git remote add origin "https://oauth2:${TOKEN}@${HOSTPATH}/${NS}/lightwell-gitlab-plugin-demo.git"
git push -u origin main --force

echo
echo "3) In GitLab UI on ${NS}/lightwell-gitlab-plugin-demo:"
echo "   Settings → CI/CD → Variables → LIGHTWELL_GITLAB_TOKEN = <same token> (masked)"
echo "   Optional: TARGET_PROJECT=${NS}/payments-service"
echo "   CI/CD → Run pipeline → run job remediate"
echo
echo "Done. Projects are GitLab-native (no GitHub remotes or README links)."
