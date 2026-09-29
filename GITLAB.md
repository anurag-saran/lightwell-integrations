# Lightwell GitLab plugin — customer setup guide

This guide is for **on-prem / self-managed GitLab** (or GitLab.com). It does **not**
require GitHub. The plugin runs as GitLab CI and opens **merge requests on GitLab**.

OpenShift kit (our demo cluster): [`GITLAB-OPENSHIFT.md`](GITLAB-OPENSHIFT.md).

Plugin project sources (copy onto your GitLab; no runtime call to GitHub):
`lightwell-gitlab-plugin-demo` (shipped with this kit or provided as a zip/bundle).

## What you need

| Requirement | Notes |
|---|---|
| GitLab 15+ with CI | Self-managed (typical for on-prem) or SaaS |
| A **Runner** that can pull `python:3.12-bookworm` and reach your GitLab API | Your runner — not GitHub Actions |
| Network egress | `packages.redhat.com` (public demo catalog) and your GitLab host |
| Maintainer on the **plugin** project and **target app** project | CI variables + MRs |

Optional: Artifactory or Nexus already wired to Lightwell
([`ARTIFACTORY.md`](ARTIFACTORY.md) / [`NEXUS.md`](NEXUS.md)) so after you merge
the MR, Maven resolves `.rhlw` versions through your org virtual
(`acmebank_java_repo` in this kit).

## Architecture (GitLab only)

```
┌─────────────────────────────┐     clone / push / MR API
│  lightwell-gitlab-plugin-   │ ──────────────────────────►  target app on GitLab
│  demo  (CI project)         │                              (e.g. payments-service)
│  job: remediate             │
└─────────────────────────────┘
         │
         │ catalog (public-lightwell-demo)
         ▼
   packages.redhat.com
```

There is **no** GitHub remote, GitHub Actions workflow, or GitHub PR in this path.

## 1. Create a Personal Access Token

In GitLab: **User settings → Access tokens** (or a Project/Group access token).

| Scope | Required |
|---|---|
| `api` | Yes |
| `write_repository` | Yes (push branches + create MRs on the target app) |

Store the token as a CI/CD variable later — not in git.

## 2. Create the plugin project on GitLab

Create an empty project (for example `lightwell-gitlab-plugin-demo`), then push the
plugin sources from your laptop or from this kit:

```bash
cd lightwell-gitlab-plugin-demo
git init -b main
git add .
git commit -m "Lightwell GitLab plugin"
git remote add origin https://gitlab.example.com/<group>/lightwell-gitlab-plugin-demo.git
git push -u origin main
```

Confirm `.gitlab-ci.yml` is on the default branch. Do **not** use “Import from
GitHub” if you want a GitLab-only estate — push the files into GitLab instead.

## 3. Create the target app on GitLab

Use **your** application on GitLab, or seed the demo app from a **local** Maven tree
(no GitHub clone):

```bash
# From lightwell-gitlab-plugin-demo:
./scripts/seed-gitlab-app.sh https://gitlab.example.com <group> "$LIGHTWELL_GITLAB_TOKEN" \
  /path/to/local/payments-service
```

That script:

- Creates `\<group\>/payments-service` on GitLab if needed  
- Copies the local tree **without** `.git` (no GitHub remotes/history)  
- Installs a GitLab-only README (no GitHub badge or PR links)  
- Installs `.gitlab-ci.yml` so **`pom.xml` changes on the default branch** trigger the
  Lightwell plugin (badge refresh). Sets `LIGHTWELL_GITLAB_TOKEN` on the app project.

Note the project path (example: `acme/payments-service`). That becomes
`TARGET_PROJECT`.

## 4. Configure CI/CD variables (plugin project)

In the **plugin** project: **Settings → CI/CD → Variables**.

| Variable | Value | Flags |
|---|---|---|
| `LIGHTWELL_GITLAB_TOKEN` | The PAT from step 1 | **Masked** |
| `TARGET_PROJECT` | `<group>/<app>` (default `root/payments-service`) | Optional |
| `DRY_RUN` | `true` for a first scan-only run | Optional |

`CI_SERVER_URL` is set by GitLab CI automatically.

Use the **same** masked `LIGHTWELL_GITLAB_TOKEN` on the **target app** (seed does this)
so its `lightwell-refresh` job can start a plugin pipeline after `pom.xml` merges.

## 5. Ensure a Runner is online

Register a GitLab Runner (shell, Docker, or Kubernetes) that can run
`image: python:3.12-bookworm` (plugin) and `curlimages/curl` (app trigger). Shared
runners on GitLab.com also work.

## 6. Run the remediation pipeline

1. Plugin project → **CI/CD → Pipelines → Run pipeline**
2. Job **`remediate`**
3. Target app → **Merge requests** — MR from branch `lightwell/remediations`
4. Badge: the target app README and project header show **Lightwell library updates: N available** (static shields badge; click opens GitLab MRs). Refreshed by each **`remediate`** run. Also published as JSON on branch `lightwell/badge`.

After you **merge** that MR, the app’s CI sees the `pom.xml` change and triggers the
plugin again so the badge drops toward **0** (no manual refresh needed).

Schedule weekly under **CI/CD → Schedules** if desired.

### Dry run first

Set `DRY_RUN=true`, run the pipeline, read the job log. Then set `DRY_RUN=false`
to open the MR.

## 7. After merge — resolve jars in your repository manager

Point Maven at your **existing org virtual** (this kit: `acmebank_java_repo`):

1. Lightwell remediated  
2. Lightwell validated  
3. Maven Central (lowest)

See [`ARTIFACTORY.md`](ARTIFACTORY.md) / [`NEXUS.md`](NEXUS.md).

## Demo checklist

1. GitLab UI login works  
2. Runner **online**  
3. Plugin has `LIGHTWELL_GITLAB_TOKEN`  
4. Target app is a **GitLab** project (path matches `TARGET_PROJECT`)  
5. **`remediate`** succeeds and opens an MR **on GitLab**  
6. Target app shows **Lightwell library updates: N available** (README + project badge)  
7. (Optional) Merge → app CI re-triggers plugin → badge updates; resolve `.rhlw` via Artifactory/Nexus  

## Troubleshooting

| Symptom | Check |
|---|---|
| Job stuck pending | No runner / shared runners disabled |
| `LIGHTWELL_GITLAB_TOKEN is required` | Variable missing or protected-only on unprotected branch |
| 401/403 cloning target | Token scopes / wrong `TARGET_PROJECT` |
| Browser opens GitHub | Old README badge still pointing at GitHub — re-seed with `seed-gitlab-app.sh` or replace README |
| No “N available” badge | Run **`remediate`** once; it updates the README shields line and the GitLab project badge |
| Badge still shows old count after merge | App needs `.gitlab-ci.yml` + `LIGHTWELL_GITLAB_TOKEN`; or re-run plugin **`remediate`**. Check app job **`lightwell-refresh`**. |
| Zero matches | App `pom.xml` versions don’t overlap the catalog |

## Local dry-run (no CI)

```bash
cd lightwell-gitlab-plugin-demo
python3 -m unittest discover -s tests -v
python3 lightwell-github/scan_poms.py --root /path/to/your-app
cat lightwell-github/out/report.md
```

## Security notes

- Prefer a Project access token or bot user limited to the target app.
- Public-demo catalog needs no Lightwell token. Production Lightwell credentials
  stay on Artifactory/Nexus remotes, not in GitLab CI.
