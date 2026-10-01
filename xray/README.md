# lightwell-xray-sync

Customer-facing CLI that **fetches Lightwell OSV** advisories and **upserts JFrog
Xray Custom Issues** (CVEs + `.rhlw` fixed versions). Schedule it so Xray stays
current without manual uploads.

**Full setup guide:** [`GUIDE.md`](GUIDE.md)

## Quick start

```bash
cd xray
python3 -m venv .venv && source .venv/bin/activate
pip install .

export JFROG_URL=https://acme.jfrog.io
export JFROG_TOKEN=***          # Manage Xray Metadata

lightwell-xray-sync self-test
lightwell-xray-sync sync --dry-run
lightwell-xray-sync sync -v     # writes xray-sync-summary.json
```

### Container

```bash
docker build -t lightwell-xray-sync:1.0 .
docker run --rm -e JFROG_URL -e JFROG_TOKEN lightwell-xray-sync:1.0 sync
```

### Schedule examples

| File | Use |
|---|---|
| [`examples/gitlab-ci.yml`](examples/gitlab-ci.yml) | GitLab scheduled pipeline |
| [`examples/github-actions.yml`](examples/github-actions.yml) | GitHub Actions |
| [`examples/cronjob.yaml`](examples/cronjob.yaml) | Kubernetes CronJob |

## Commands

```text
lightwell-xray-sync sync       # fetch LIGHTWELL_OSV_URL (or public-demo) → Xray
lightwell-xray-sync push -i DIR
lightwell-xray-sync dry-run
lightwell-xray-sync self-test
```

Env: `JFROG_URL`, `JFROG_TOKEN`, optional `JFROG_USER`, `LIGHTWELL_OSV_URL`.

Artifactory remotes for jar resolve are **not** part of this package — see
[`../artifactory/README.md`](../artifactory/README.md).
