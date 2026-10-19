# Lightwell Bitbucket plugin — customer setup guide

This guide is for **Bitbucket Cloud** (`bitbucket.org`) with Pipelines enabled.
The plugin runs as a Bitbucket Pipeline and opens **pull requests on Bitbucket**.

Plugin project sources: `lightwell-bitbucket-plugin-demo` (sibling of the GitHub
plugin, or a zip of that tree). Companion detail (scripts, catalog, local dry-run):
that repo’s README.

GitHub customers: use [`../github/README.md`](../github/README.md). GitLab customers:
use [`../gitlab/README.md`](../gitlab/README.md). This path does not use GitHub
Actions or a GitHub pull request.

## What you need

| Requirement | Notes |
|---|---|
| Bitbucket Cloud workspace | `bitbucket.org/<workspace>` |
| Pipelines enabled | On the plugin repo and the target app |
| Permission to add secured repository variables | Plugin repo and the app |
| Network egress | `packages.redhat.com` (public demo catalog) and `api.bitbucket.org` |
| Access token for **both** repos | Repository write and pull request write |

A repository access token is bound to one repository. It cannot push `payments-service` and open the pull request from the plugin repo. Use one API token or workspace token that covers both.

Optional: Artifactory or Nexus already wired to Lightwell
([`../artifactory/README.md`](../artifactory/README.md) / [`../nexus/README.md`](../nexus/README.md)) so after you merge
the pull request, Maven resolves `.rhlw` versions through your org virtual
(`acmebank_java_repo` in this kit).

## Architecture

```
┌─────────────────────────────┐     clone / push / pull-request API
│  lightwell-bitbucket-       │ ──────────────────────────►  payments-service
│  plugin-demo  (Pipelines)   │                              on Bitbucket Cloud
│  custom pipeline: remediate │
└─────────────────────────────┘
         │
         │ catalog (public-lightwell-demo)
         ▼
   packages.redhat.com

Target app: pom.xml change on main
  → starts remediate again (badge refresh)
```

## 1. Create an API token with scopes

Create the token while logged into the Atlassian account that can see the
workspace. Bitbucket → profile → **Account settings → Security → Create and
manage API tokens → Create API token with scopes**. Pick the **Bitbucket** app.

App passwords are retired. A token created without scopes is rejected by Git
and by the API.

Scopes are separate checkboxes. **Admin does not include Read or Write.** Check
all of these:

| Area | Scopes |
|---|---|
| Repositories | Read, Write, and Admin |
| Pull requests | Read and Write |

Admin is what creates a repository. Read and Write are what clone and push.
Without Read, a private repository looks like it does not exist.

The token is shown once. Do not commit it and do not paste it into a chat.

Git over HTTPS uses the static username `x-bitbucket-api-token-auth` and the
token as the password ([Using API tokens](https://support.atlassian.com/bitbucket-cloud/docs/using-api-tokens/)):

```text
https://x-bitbucket-api-token-auth@bitbucket.org/<workspace>/<repo>.git
```

The pull-request API is different. It uses Basic auth with your **Atlassian
account email** as the username and the same token as the password. The
pipeline variable for that email is `LIGHTWELL_BITBUCKET_USER`.

## 2. Create the plugin repository

Create an empty repository `lightwell-bitbucket-plugin-demo`, enable Pipelines,
then push this tree:

```bash
cd lightwell-bitbucket-plugin-demo
git init -b main
git add .
git commit -m "Lightwell Bitbucket plugin"
git remote add origin https://bitbucket.org/<workspace>/lightwell-bitbucket-plugin-demo.git
git push -u origin main
```

Confirm `bitbucket-pipelines.yml` is on `main`. The default pipeline runs the unit tests.

In the plugin repo: **Repository settings → Pipelines → Repository variables**.

| Variable | Value | Secured |
|---|---|---|
| `LIGHTWELL_BITBUCKET_TOKEN` | The token from step 1 | Yes |
| `LIGHTWELL_BITBUCKET_USER` | Atlassian account email | No |
| `LIGHTWELL_BITBUCKET_GIT_USER` | `x-bitbucket-api-token-auth` | No |

`LIGHTWELL_BITBUCKET_GIT_USER` is optional. The script already defaults to
`x-bitbucket-api-token-auth`. Set it to `x-token-auth` only when the credential
is a repository or workspace access token, not an API token.

## 3. Seed payments-service

From the plugin tree, copy a local Maven app. The script omits `.git`, `.github`,
and the upgrade-delta Tekton bundle, then installs a Bitbucket README and
`bitbucket-pipelines.yml`.

```bash
./scripts/seed-bitbucket-app.sh <workspace> /path/to/payments-service
```

That writes `payments-service-seed/` and does not push. To create the Bitbucket
repository and push `main`:

```bash
LIGHTWELL_BITBUCKET_TOKEN=... \
LIGHTWELL_BITBUCKET_USER=you@example.com \
  ./scripts/seed-bitbucket-app.sh <workspace> /path/to/payments-service --push
```

`--push` also tries to enable Pipelines and store the secured token on the app
(and on the plugin repo, if that repo already exists). If the API refuses, set
the same secured variable in the UI. The script does not print the token.

The app pipeline, on a `pom.xml` change to `main`, starts the plugin’s custom
pipeline `remediate`. It assumes the plugin repository is
`<workspace>/lightwell-bitbucket-plugin-demo`. Override that with the secured or
plain variable `LIGHTWELL_PLUGIN_REPO` if the slug differs.

## 4. Run remediate

1. Plugin repo → **Pipelines → Run pipeline**
2. Choose the custom pipeline **remediate**
3. Set `TARGET_REPO` to `<workspace>/payments-service`
4. Set `DRY_RUN` to `true` and run. Read the log. No branch is pushed.
5. Run again with `DRY_RUN` `false`

A pull request opens on the app from branch `lightwell/remediations`. The badge
JSON is published on branch `lightwell/badge`.

The README badge is a Shields.io image. Shields fetches this URL with no
Bitbucket login:

```text
https://bitbucket.org/<workspace>/payments-service/raw/lightwell/badge/lightwell-badge.json
```

That works only when `payments-service` is **public**. On a private repository
Bitbucket returns 404 to Shields, and the README shows **custom badge / resource
not found**. The pipeline still writes the JSON on `lightwell/badge`. Make the
app public before you expect a coworker to see the count. Shields also keeps a
failed image for a few minutes; reload after the first successful publish.

After you **merge**, the app pipeline sees the `pom.xml` change and starts
`remediate` again so the count moves toward **0**.

To run weekly, add a schedule in the Bitbucket UI (**Pipelines → Schedules**)
pointed at the custom pipeline `remediate`, with `TARGET_REPO` set. The schedule
is not declared in `bitbucket-pipelines.yml`.

## 5. After merge — resolve jars in your repository manager

Point Maven at your existing org virtual (this kit: `acmebank_java_repo`):

1. Lightwell remediated
2. Lightwell validated
3. Maven Central (lowest)

See [`../artifactory/README.md`](../artifactory/README.md) / [`../nexus/README.md`](../nexus/README.md).

## Demo checklist

1. Pipelines enabled on the plugin and the app
2. Both repos have secured `LIGHTWELL_BITBUCKET_TOKEN`
3. `TARGET_REPO` is `<workspace>/payments-service`
4. `remediate` with `DRY_RUN=true` prints matches
5. `remediate` with `DRY_RUN=false` opens a pull request on Bitbucket
6. `lightwell/badge` on the app contains `lightwell-badge.json`
7. A later `pom.xml` push on `main` starts `remediate` again

## Troubleshooting

| Symptom | Check |
|---|---|
| Pipeline not listed | Pipelines disabled for the repo |
| `LIGHTWELL_BITBUCKET_TOKEN is required` | Secured variable missing on the repo that is running |
| Clone or API 401/403 | Token is missing Read or Write. Admin alone cannot push. `LIGHTWELL_BITBUCKET_USER` must be the Atlassian email |
| `API token must be used with an atlassian registered email` | Git username is `x-bitbucket-api-token-auth`. The REST call still needs `LIGHTWELL_BITBUCKET_USER` set to the email |
| Badge says **custom badge / resource not found** | App repo is private, `lightwell/badge` was never pushed, or Shields cached the first 404. Make the app public and reload |
| `TARGET_REPO must be workspace/repo_slug` | Custom pipeline variable still says `workspace/payments-service` |
| No pull request | `DRY_RUN` is `true`, or the pom is already on the catalog versions |
| Badge URL 404 in the browser | Branch `lightwell/badge` was not pushed, or the repo is private and shields cannot read it |
| Badge still shows the old count after merge | App needs `bitbucket-pipelines.yml` and the token. Re-run custom pipeline `refresh` on the app |
| Zero matches | App `pom.xml` versions do not overlap `lightwell-github/catalog.json` |

## Local dry-run (no Pipelines)

```bash
cd lightwell-bitbucket-plugin-demo
python3 -m unittest discover -s tests -v
python3 lightwell-github/scan_poms.py --root /path/to/payments-service
cat lightwell-github/out/report.md
```

## Security notes

- Prefer a bot user or workspace token limited to the plugin and the target app.
- The public-demo catalog needs no Lightwell token. Production Lightwell credentials stay on Artifactory or Nexus, not in Pipelines variables.
