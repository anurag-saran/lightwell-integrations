# Lightwell GitHub plugin — customer setup guide

This guide is for **GitHub.com** or **GitHub Enterprise Server (GHES)** with Actions
enabled. The plugin runs as GitHub Actions and opens **pull requests on GitHub**.

Plugin project sources: `lightwell-github-plugin-demo` (shipped with this kit or
provided as a zip/bundle). Companion detail (scripts, catalog, local dry-run): that
repo’s README.

GitLab / on-prem customers: use [`GITLAB.md`](GITLAB.md) instead.

## What you need

| Requirement | Notes |
|---|---|
| GitHub.com or GHES with **Actions** enabled | GHES: enable Actions for the org/instance |
| Permission to add repo secrets and run workflows | On the **plugin** repo and each **target app** |
| Network egress | `packages.redhat.com` (public demo catalog) and `api.github.com` (or your GHES API) |
| Fine-grained PAT (or classic `repo`) | Contents + Pull requests on plugin and target apps |

Optional: Artifactory or Nexus already wired to Lightwell
([`ARTIFACTORY.md`](ARTIFACTORY.md) / [`NEXUS.md`](NEXUS.md)) so after you merge
the PR, Maven resolves `.rhlw` versions through your org virtual
(`acmebank_java_repo` in this kit).

## Architecture (GitHub only)

```
┌─────────────────────────────┐     checkout / push / PR API
│  lightwell-github-plugin-   │ ──────────────────────────►  target app on GitHub
│  demo  (Actions)            │                              (e.g. payments-service)
│  workflow: Lightwell        │
│  Remediate                  │
└─────────────────────────────┘
         │
         │ catalog (public-lightwell-demo)
         ▼
   packages.redhat.com

Target app: Lightwell badge sync (on pom.xml change)
  → publishes lightwell-badge.json on branch lightwell/badge
```

There is **no** GitLab CI job or GitLab MR in this path.

## 1. Create a fine-grained Personal Access Token

GitHub → **Settings → Developer settings → Personal access tokens → Fine-grained**.

Grant the token access to the **plugin** repo and every **target app** repo:

| Permission | Access |
|---|---|
| **Contents** | Read and write (push `lightwell/remediations` + `lightwell/badge`) |
| **Pull requests** | Read and write (open/update remediation PRs) |

Classic `repo` scope also works but is broader than needed. Store the token as a
repository secret later — not in git.

## 2. Create the plugin repository on GitHub

Create an empty repository (for example `lightwell-github-plugin-demo`), then push
the plugin sources:

```bash
cd lightwell-github-plugin-demo
git init -b main
git add .
git commit -m "Lightwell GitHub plugin"
git remote add origin https://github.com/<owner>/lightwell-github-plugin-demo.git
git push -u origin main
```

Confirm `.github/workflows/lightwell-remediate.yml` is on the default branch.

## 3. Point at your target app(s)

Use **your** Maven application on GitHub, or clone one of the demo apps from this kit
(for example `payments-service`).

Note the repo path (`owner/name`). Manual runs pick a target in the workflow UI;
scheduled runs can cover several apps — edit the choice list in
`lightwell-remediate.yml` to match your org.

## 4. Configure secrets (plugin repository)

In the **plugin** repo: **Settings → Secrets and variables → Actions**.

| Secret | Value |
|---|---|
| `LIGHTWELL_REPO_TOKEN` | The PAT from step 1 |

Also: **Settings → Actions** — allow Actions / GitHub Actions for this repository.
The workflow uses `gh auth setup-git` (the token is not embedded in the git remote URL).

## 5. Install badge sync on each target app

After a remediation PR merges (or any `pom.xml` change on `main`), the app should
re-scan and republish the shields count — without a second manual plugin run.

```bash
mkdir -p /path/to/app/.github/workflows
cp samples/lightwell-badge-sync.yml /path/to/app/.github/workflows/
# If you forked the plugin, edit repository: to your fork
git -C /path/to/app add .github/workflows/lightwell-badge-sync.yml
git -C /path/to/app commit -m "ci: Lightwell badge sync on pom.xml change"
git -C /path/to/app push
```

Point the README badge at the shields endpoint (JSON on branch `lightwell/badge`):

```markdown
[![Lightwell library updates](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2F<owner>%2F<repo>%2Flightwell%2Fbadge%2Flightwell-badge.json)](https://github.com/<owner>/<repo>/pulls?q=is%3Apr+is%3Aopen+label%3Alightwell)
```

## 6. Run the remediation workflow

1. Plugin repo → **Actions → Lightwell Remediate → Run workflow**
2. Pick a **target_repo** (`owner/name`)
3. Optionally enable **dry_run** to scan without push/PR
4. Run — a PR opens on the **app** from branch `lightwell/remediations` (unless dry-run)
5. On the app: review → **merge** or **close**

After you **merge**, the app’s **Lightwell badge sync** workflow sees the `pom.xml`
change and refreshes the badge toward **0** (no manual plugin re-run needed).

A weekly schedule is already defined in the workflow; adjust the cron or target list
for your org.

### Dry run first

Enable **dry_run** on the workflow dispatch, read the job summary, then run again
with dry_run off to open the PR.

## 7. After merge — resolve jars in your repository manager

Point Maven at your **existing org virtual** (this kit: `acmebank_java_repo`):

1. Lightwell remediated  
2. Lightwell validated  
3. Maven Central (lowest)

See [`ARTIFACTORY.md`](ARTIFACTORY.md) / [`NEXUS.md`](NEXUS.md).

## Demo checklist

1. Actions enabled on plugin and app repos  
2. Plugin has secret `LIGHTWELL_REPO_TOKEN`  
3. Target app path matches the workflow choice / matrix  
4. **Lightwell Remediate** succeeds and opens a PR **on GitHub**  
5. App README shows **Lightwell library updates: N available** (shields endpoint)  
6. App has **Lightwell badge sync** workflow  
7. (Optional) Merge → badge sync updates count; resolve `.rhlw` via Artifactory/Nexus  

## Troubleshooting

| Symptom | Check |
|---|---|
| Workflow not listed / won’t start | Actions disabled for the repo or org |
| `LIGHTWELL_REPO_TOKEN` / auth errors | Secret missing; PAT lacks Contents + Pull requests on the target |
| 404 / cannot checkout target | Wrong `owner/name`; token not granted on that repo |
| No “N available” badge | Run **Lightwell Remediate** once (publishes `lightwell/badge`); confirm README endpoint URL |
| Badge still shows old count after merge | App needs `lightwell-badge-sync.yml`; or **Actions → Lightwell badge sync → Run workflow**. Hard-refresh if shields cached |
| Zero matches | App `pom.xml` versions don’t overlap the catalog |

## Local dry-run (no Actions)

```bash
cd lightwell-github-plugin-demo
python3 -m unittest discover -s tests -v
python3 lightwell-github/scan_poms.py --root /path/to/your-app
cat lightwell-github/out/report.md
```

## Security notes

- Prefer a fine-grained PAT limited to the plugin and target app repos (bot account).
- Public-demo catalog needs no Lightwell token. Production Lightwell credentials
  stay on Artifactory/Nexus remotes, not in GitHub Actions secrets for this demo path.
