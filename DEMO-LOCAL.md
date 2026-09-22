# Local demo — Artifactory, Nexus, and SonarQube

Run the three tools on this machine with Podman, then walk Lightwell through them.
Click paths: [`ARTIFACTORY.md`](ARTIFACTORY.md), [`NEXUS.md`](NEXUS.md),
[`SONARQUBE.md`](SONARQUBE.md).

## The RHEL boot ISO does not install these tools

A `rhel-*-boot.iso` starts Anaconda. It does not contain Artifactory, Nexus, or
SonarQube. To host this demo on RHEL, finish the OS install, attach a subscription,
`sudo dnf install -y podman`, then run the scripts below.

The Podman machine needs about **8 GB** RAM (`podman machine set --memory 8192`, then
restart the machine). A 2 GB VM cannot run these three JVMs.

If an earlier demo left containers named `upgrade-delta-artifactory`,
`upgrade-delta-nexus`, or `upgrade-delta-sonarqube`, stop them first. They use the
same host ports.

## Scripts

| Script | What it starts | URL | Lightwell |
|---|---|---|---|
| [`scripts/setup-artifactory.sh`](scripts/setup-artifactory.sh) | Artifactory OSS | http://127.0.0.1:8082 | Maven remote `lightwell-remote` (UI if the API is Pro-only) |
| [`scripts/setup-nexus.sh`](scripts/setup-nexus.sh) | Nexus OSS | http://127.0.0.1:8083 | Maven2 proxy, layout **Strict** |
| [`scripts/setup-sonarqube.sh`](scripts/setup-sonarqube.sh) | SonarQube Community | http://127.0.0.1:9000 | none — app quality gate only |

Default login after a successful script run: `admin` / `Lightwell-demo1`
(override with `DEMO_PASSWORD`). Demo-only — do not reuse on a shared server.

Public demo feed (no token), which is the default:

```bash
chmod +x scripts/setup-*.sh
./scripts/setup-artifactory.sh
./scripts/setup-nexus.sh
./scripts/setup-sonarqube.sh
```

Production Lightwell (service account):

```bash
export LIGHTWELL_MODE=prod
export LIGHTWELL_USER='XXXXXXX|service-account-name'
export LIGHTWELL_TOKEN='...'
./scripts/setup-artifactory.sh
./scripts/setup-nexus.sh
```

Nexus is published on **8083** so Artifactory can keep host ports **8081** and **8082**.
Current Artifactory OSS images refuse the bundled Derby database unless
`JF_SHARED_DATABASE_ALLOWNONPOSTGRESQL=true` is set. The setup script sets that for the
demo. A production Artifactory should use PostgreSQL. The script also pre-creates
`master.key` so a root-owned Podman volume does not stall first boot.

## Demo beats

1. **Artifactory** — http://127.0.0.1:8082/ui/ . If the script printed UI clicks, create
   `lightwell-remote` there (List Remote Artifacts on, Enable Token Authentication off).
2. **Nexus** — http://127.0.0.1:8083/ , browse `lightwell-remote`, show **Layout policy: Strict**.
3. **What neither did** — the jar is available. Grading whether your app owes a specific
   test set is upgrade-delta, a separate project.
4. **SonarQube** — http://127.0.0.1:9000/ . No Lightwell remote and no upgrade plugin.
   See [`SONARQUBE.md`](SONARQUBE.md).

## Stop

```bash
podman stop lightwell-artifactory lightwell-nexus lightwell-sonarqube
```

Volumes keep data across restarts. Re-running a setup script starts the existing
container and skips recreating a repo that is already there.
