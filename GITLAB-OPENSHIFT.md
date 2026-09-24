# GitLab on OpenShift — Lightwell plugin demo

Deploys **GitLab CE** on OpenShift and pairs it with
[`lightwell-gitlab-plugin-demo`](https://github.com/anurag-saran/lightwell-gitlab-plugin-demo)
(CI that opens Lightwell remediation MRs on a GitLab copy of `payments-service`).

Artifactory public-demo Routes (optional Maven resolve after merge):
[`OPENSHIFT.md`](OPENSHIFT.md).

## Modes

| Mode | Env | When to use |
|---|---|---|
| **omnibus** (default) | `LIGHTWELL_GITLAB_MODE=omnibus` | Single-node / SNO demos — one `gitlab/gitlab-ce` pod + Route |
| **helm** | `LIGHTWELL_GITLAB_MODE=helm` | Larger clusters — official `gitlab/gitlab` chart ([`openshift/gitlab/values-demo.yaml`](openshift/gitlab/values-demo.yaml)) |

## Before you start

- `oc` logged in (cluster-admin helpful for `anyuid` SCC)
- **~4–5 Gi** free RAM for omnibus GitLab (more for Helm)
- By default the setup script **scales Nexus to 0** in `lightwell-demo` so the SNO has room. Set `LIGHTWELL_KEEP_NEXUS=1` to keep Nexus.

## One command (omnibus)

```bash
./scripts/setup-openshift-gitlab.sh
```

That applies [`openshift/gitlab/omnibus.yaml`](openshift/gitlab/omnibus.yaml), waits for the
Deployment, and prints the Route URL. First boot often takes **10–20 minutes**.

Login: `root` / `Lightwell-demo1` (override with `DEMO_PASSWORD`).

Helm instead:

```bash
LIGHTWELL_GITLAB_MODE=helm ./scripts/setup-openshift-gitlab.sh
```

## Runner

Omnibus mode ships a Runner Deployment at **0 replicas** until you register a token:

1. GitLab UI → **Admin** → **CI/CD** → **Runners** → create an **instance** runner → copy token  
2. Register and scale up:

```bash
./scripts/register-openshift-gitlab-runner.sh <runner-authentication-token>
```

Confirm the runner shows **online** in the Admin runners page. Job pods use the
Kubernetes executor in namespace `lightwell-gitlab`.

## Plugin + sample app

1. Create GitLab project **lightwell-gitlab-plugin-demo** (push this repo or import).
2. Import **payments-service**:

```bash
# From lightwell-gitlab-plugin-demo clone:
./scripts/import-payments-service.sh https://<gitlab-route-host> root "$GITLAB_TOKEN"
```

Or GitLab UI → **New project** → **Import** → Repository by URL  
`https://github.com/anurag-saran/payments-service.git`

3. In the plugin project → **Settings → CI/CD → Variables**:
   - `LIGHTWELL_GITLAB_TOKEN` — PAT with `api` + `write_repository` on the app (masked)
   - Optional: `TARGET_PROJECT=root/payments-service`, `DRY_RUN=true`

4. **CI/CD → Run pipeline** → run job **remediate** (or set a weekly schedule).

5. Open the MR on `payments-service` (`lightwell/remediations`). Badge branch:
   `lightwell/badge`.

## Demo checklist

1. Open GitLab Route → log in as `root`  
2. Runner online  
3. Plugin pipeline **remediate** succeeds  
4. MR appears with CVE/CVSS table  
5. Optional: resolve a bumped `.rhlw` jar through Artifactory  
   `https://artifactory-lightwell-demo.apps.<domain>/artifactory/lightwell-java`

## URLs (this kit’s cluster pattern)

| Service | URL pattern |
|---|---|
| GitLab | `https://gitlab.apps.asaran.na-launch.com` (or Route host from `oc -n lightwell-gitlab get route`) |
| Artifactory | `https://artifactory-lightwell-demo.apps.asaran.na-launch.com/ui/` |

```bash
oc -n lightwell-gitlab get pods,route
oc -n lightwell-gitlab logs deploy/gitlab --tail=80
```

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
