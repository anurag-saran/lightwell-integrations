# GitLab on OpenShift — kit deploy (demo cluster)

Deploys **GitLab CE** on OpenShift for a live demo. For the **customer setup
guide** (any GitLab SaaS or self-managed — Runner, PAT, plugin project, target
app, remediate pipeline), see **[`README.md`](README.md)** first.

Plugin sources:
[`lightwell-gitlab-plugin-demo`](https://github.com/anurag-saran/lightwell-gitlab-plugin-demo).

Artifactory / Nexus (optional Maven resolve after merge): [`../openshift/README.md`](../openshift/README.md).

## This kit’s demo URLs and login

| | |
|---|---|
| **GitLab** | https://gitlab.apps.asaran.na-launch.com |
| **Username** | `root` |
| **Password** | `Lightwell-demo1` |
| **Plugin project** | https://gitlab.apps.asaran.na-launch.com/root/lightwell-gitlab-plugin-demo |
| **Sample app** | https://gitlab.apps.asaran.na-launch.com/root/payments-service |
| **Artifactory** | https://artifactory-lightwell-demo.apps.asaran.na-launch.com/ui/ (`admin` / `Lightwell-demo1`) |

Create a Personal Access Token in GitLab (**User settings → Access tokens**:
`api` + `write_repository`) and store it as CI variable `LIGHTWELL_GITLAB_TOKEN`
on the plugin project (masked). Do not commit the token.

### Demo flow (after GitLab + Runner are up)

1. Log in to GitLab as `root` / `Lightwell-demo1`
2. Confirm **Admin → CI/CD → Runners** shows a runner **online**
3. Open **root/lightwell-gitlab-plugin-demo** → **CI/CD → Pipelines → Run pipeline**
4. Run job **`remediate`**
5. Open **root/payments-service** → **Merge requests** → MR from `lightwell/remediations`
6. Confirm **Lightwell library updates: N available** on the project overview (README + project badge)
7. Optional: resolve a `.rhlw` jar via  
   `https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/acmebank_java_repo`

Full customer steps (any environment): [`README.md`](README.md).

## Modes

| Mode | Env | When to use |
|---|---|---|
| **omnibus** (default) | `LIGHTWELL_GITLAB_MODE=omnibus` | Single-node / SNO demos — one `gitlab/gitlab-ce` pod + Route |
| **helm** | `LIGHTWELL_GITLAB_MODE=helm` | Larger clusters — official `gitlab/gitlab` chart ([`openshift/values-demo.yaml`](openshift/values-demo.yaml)) |

## Before you start

- `oc` logged in (cluster-admin helpful for `anyuid` SCC)
- **~4–5 Gi** free RAM for omnibus GitLab (more for Helm)
- By default the setup script **scales Nexus to 0** in `lightwell-demo` so the SNO has room. Set `LIGHTWELL_KEEP_NEXUS=1` to keep Nexus.

## One command (omnibus)

```bash
./gitlab/setup-openshift.sh
```

That applies [`openshift/omnibus.yaml`](openshift/omnibus.yaml), waits for the
Deployment, and prints the Route URL. First boot often takes **10–20 minutes**.

Login: `root` / `Lightwell-demo1` (override with `DEMO_PASSWORD`).

Helm instead:

```bash
LIGHTWELL_GITLAB_MODE=helm ./gitlab/setup-openshift.sh
```

## Runner

Omnibus mode ships a Runner Deployment at **0 replicas** until you register a token:

1. GitLab UI → **Admin** → **CI/CD** → **Runners** → **New instance runner** → copy the
   authentication token  
   (or create via API: `POST /api/v4/user/runners` with `runner_type=instance_type`)
2. Register and scale up:

```bash
./gitlab/register-runner.sh <runner-authentication-token>
```

Confirm the runner shows **online** in the Admin runners page. Job pods use the
Kubernetes executor in namespace `lightwell-gitlab`.

## Seed plugin + sample app (GitLab only — no GitHub)

```bash
# PAT with api + write_repository
# Seeds plugin + local payments-service tree onto GitLab (no GitHub remotes)
./gitlab/seed-projects.sh https://gitlab.apps.asaran.na-launch.com "$TOKEN"
```

Then in the plugin project set CI/CD variable `LIGHTWELL_GITLAB_TOKEN` (masked).
Optional: `TARGET_PROJECT=root/payments-service`.

Customer guide (any GitLab, no GitHub): [`README.md`](README.md).

## Stop / free memory

```bash
oc -n lightwell-gitlab scale deployment/gitlab deployment/gitlab-runner --replicas=0
# Restore Nexus if you scaled it down:
oc -n lightwell-demo scale deployment/nexus --replicas=1
```

Remove the namespace:

```bash
oc delete project lightwell-gitlab
```

With `emptyDir`, omnibus data is gone when the pod is deleted.

## Not in this path

- GitLab Operator / Enterprise features  
- All four payment-service grade variants (start with one app)  
- upgrade-delta / Tekton / SonarQube on the GitLab app  
