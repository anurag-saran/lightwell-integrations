# Lightwell → JFrog Xray sync — customer setup guide

This guide is for customers who use **JFrog Xray** and want Red Hat **Lightwell**
OSV data (CVEs + `.rhlw` fixed versions) kept current as **Xray Custom Issues**.

The tool is **`lightwell-xray-sync`**: a small Python CLI (and optional container)
you schedule in CI or Kubernetes. It does **not** replace Artifactory remotes —
those still deliver jars ([`ARTIFACTORY.md`](ARTIFACTORY.md)). It does **not** open
SCM merge requests ([`GITLAB.md`](GITLAB.md) / [`GITHUB.md`](GITHUB.md)).

Package sources: [`xray/`](xray/) (shipped with this kit or as a zip/bundle).

> **OSS note:** The kit’s local/OpenShift **Artifactory OSS** often has **no Xray**.
> Use a JFrog Platform trial or production instance with Xray enabled
> (e.g. [jfrog.com/start-free](https://jfrog.com/start-free/)).

## What you need

| Requirement | Notes |
|---|---|
| JFrog Platform + **Xray** | Custom Issues API (`/xray/api/v1/events`) |
| Access token | **Manage Xray Metadata** (prefer an identity token over a password) |
| Network egress | Lightwell OSV index + your `JFROG_URL` |
| Python **3.10+** or Docker | To install or run the tool |
| Scheduler | GitLab CI, GitHub Actions, or a Kubernetes CronJob (examples included) |

Optional but recommended: Artifactory already wired to Lightwell
([`ARTIFACTORY.md`](ARTIFACTORY.md)) so after developers adopt `.rhlw` versions,
Maven resolves them through your org virtual (`acmebank_java_repo` in this kit).

## How it fits (end-to-end)

```
Lightwell OSV feed ──► lightwell-xray-sync ──► Xray Custom Issues ──► policies / gates
Lightwell Maven    ──► Artifactory remotes ──► org virtual        ──► Maven builds
GitLab/GitHub plugin ──► MR/PR with .rhlw bumps ──► developers merge
```

| Layer | Role |
|---|---|
| **This tool** | Keeps Xray’s vulnerability index aware of Lightwell fixes |
| **Artifactory** | Supplies `.rhlw` binaries to builds |
| **SCM plugin** | Proposes version bumps as normal MRs/PRs |
| **Xray / Curation policies** | Fail builds or block downloads by severity (your existing rules) |

## Architecture

```
┌──────────────────────────┐
│  CI schedule / CronJob   │
│  lightwell-xray-sync     │
│  command: sync           │
└────────────┬─────────────┘
             │
     ┌───────┴────────┐
     │ GET OSV index  │ POST/PUT /xray/api/v1/events
     ▼                ▼
 packages.redhat.com   JFrog Xray
 (or your OSV URL)     Custom Issues (provider=Lightwell)
```

Idempotent: create on first see, **update** if the issue id already exists.

## 1. Create a JFrog token

1. Sign in to your Platform (e.g. `https://<your-trial>.jfrog.io`).
2. User menu → **Edit Profile** → **Generate an Identity Token**  
   (or Administration → Identity / Access Tokens).
3. Grant ability to manage **Xray metadata** / Custom Issues.
4. Save the token as a **masked CI secret** — never commit it to git.

## 2. Install the tool

### Option A — pip (from this kit)

```bash
cd lightwell-integrations/xray   # or unzip path that contains xray/
python3 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install .

lightwell-xray-sync self-test    # offline; expect SELF-TEST OK
```

### Option B — container

```bash
cd lightwell-integrations/xray
docker build -t lightwell-xray-sync:1.0 .
docker run --rm lightwell-xray-sync:1.0 self-test
```

### Compatibility shim

If you still call the old script path:

```bash
python3 xray/push_osv_to_xray.py self-test
# forwards to the same CLI (supports legacy flat flags too)
```

## 3. Configure environment

| Variable | Required | Meaning |
|---|---|---|
| `JFROG_URL` | Yes for live sync | Platform base, e.g. `https://acme.jfrog.io` (no `/xray` suffix needed) |
| `JFROG_TOKEN` | Yes for live sync | Identity / access token |
| `JFROG_USER` | No | If set → HTTP Basic (`user` + token); otherwise `Authorization: Bearer` |
| `LIGHTWELL_OSV_URL` | No | OSV index URL; default = public-demo Java remediated feed |

**Public-demo default** (no Lightwell credential):

`https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/`

**Production:** set `LIGHTWELL_OSV_URL` to your entitled Lightwell OSV endpoint.

## 4. First run (dry-run, then live)

```bash
export JFROG_URL=https://acme.jfrog.io
export JFROG_TOKEN=***                 # masked
# export JFROG_USER=admin              # optional Basic
# export LIGHTWELL_OSV_URL=...         # optional override

lightwell-xray-sync sync --dry-run     # fetch + map; no Xray writes
lightwell-xray-sync sync -v            # live upsert
# writes ./xray-sync-summary.json
```

Push from a local cache (e.g. after `./scripts/copy-catalog.sh`):

```bash
lightwell-xray-sync push --input .local/integrations/osv -v
```

Container live sync:

```bash
docker run --rm \
  -e JFROG_URL -e JFROG_TOKEN -e JFROG_USER -e LIGHTWELL_OSV_URL \
  -v "$PWD:/out" -w /out \
  lightwell-xray-sync:1.0 sync -v
```

### Mapping (what lands in Xray)

| OSV field | Xray Custom Issue |
|---|---|
| `id` | `id` (provider `Lightwell`) |
| `summary` / `details` | `summary` / `description` |
| `severity` CVSS v3 | qualitative `severity` + `cves[].cvss_v3` score |
| `aliases` (CVE-*) | `cves` + `sources` |
| `affected` ranges | `components` + `vulnerable_versions` |
| `fixed` ending in `.rhlw-*` / `.redhat-*` | `fixed_versions` |

## 5. Schedule ongoing updates

Copy a ready-made job from [`xray/examples/`](xray/examples/):

| File | Platform |
|---|---|
| [`gitlab-ci.yml`](xray/examples/gitlab-ci.yml) | GitLab — **CI/CD → Schedules** (weekly) |
| [`github-actions.yml`](xray/examples/github-actions.yml) | GitHub Actions cron + `workflow_dispatch` |
| [`cronjob.yaml`](xray/examples/cronjob.yaml) | Kubernetes CronJob + Secret |

Recommended cadence: **weekly** (or daily if your OSV feed changes often).
Re-running `sync` is safe: existing issue ids are **updated**, not duplicated.

## 6. Verify in the JFrog UI

1. Open your Platform → **Xray**.
2. Search a Custom Issue id, for example `x_RHLW-CVE-2023-51074-2.8.0`.
3. Confirm:
   - provider / source looks like Lightwell  
   - CVE alias  
   - component coordinates (e.g. `com.jayway.jsonpath:json-path`)  
   - `fixed_versions` containing a `.rhlw-…` build  

4. Confirm your **severity policies** still apply (no Lightwell-specific policy type required).

## 7. Resolve jars in Artifactory

After developers merge `.rhlw` bumps (manually or via the SCM plugin), Maven must
hit your org virtual with Lightwell remotes **ahead of** Central:

See [`ARTIFACTORY.md`](ARTIFACTORY.md) / [`NEXUS.md`](NEXUS.md).

## Demo checklist

1. Platform login works; **Xray** appears in the left nav  
2. Token with Manage Xray Metadata is set as `JFROG_TOKEN`  
3. `lightwell-xray-sync self-test` passes  
4. `sync --dry-run` lists advisories (public demo ≈ 11 today)  
5. `sync` succeeds; `xray-sync-summary.json` shows `failed=0`  
6. UI shows a Custom Issue with `.rhlw` in `fixed_versions`  
7. (Optional) Artifactory `acmebank_java_repo` resolves a `.rhlw` jar  
8. Schedule job is enabled (GitLab / GitHub / CronJob)  

## CLI reference

```text
lightwell-xray-sync sync [--url URL] [--dry-run] [--print-payloads] [-v]
lightwell-xray-sync push --input PATH [--dry-run] [-v]
lightwell-xray-sync dry-run [--input PATH | --url URL]
lightwell-xray-sync self-test
```

| Flag / artifact | Meaning |
|---|---|
| `--summary PATH` | Write summary JSON (default `xray-sync-summary.json`) |
| `--no-summary` | Skip summary file |
| Exit code | `0` only if `failed=0` |

## Troubleshooting

| Symptom | Check |
|---|---|
| `JFROG_URL is required` | Export env vars or set CI variables |
| HTTP 401/403 | Token scopes; try `JFROG_USER` + token (Basic) |
| HTTP 404 on `/xray/api/v1/events` | Xray not licensed/enabled; wrong base URL |
| No advisories found | `LIGHTWELL_OSV_URL` reachable; HTML index lists `*.json` |
| Badge / issue looks stale | Re-run `sync` (do not rely on an old local `--input` directory) |
| `pip install` permission errors | Use a venv: `python3 -m venv .venv && source .venv/bin/activate` |

## Security notes

- Mask `JFROG_TOKEN` in CI; rotate after shared demos.
- Prefer short-lived identity tokens over account passwords.
- Public-demo OSV needs no Lightwell token. Production Lightwell credentials for
  **Maven** stay on Artifactory remotes — not inside this sync image.

## Related kit docs

| Guide | When |
|---|---|
| [`OSV-XRAY-DESIGN.md`](OSV-XRAY-DESIGN.md) | Technical design and API mapping (OSV → Xray, applied on Artifactory) |
| [`ARTIFACTORY.md`](ARTIFACTORY.md) | Wire Lightwell remotes + org virtual |
| [`GITLAB.md`](GITLAB.md) / [`GITHUB.md`](GITHUB.md) | Remediation MRs/PRs |
| [`xray/README.md`](xray/README.md) | Short package-oriented readme |
| [`README.md`](README.md) | Kit index |
