# Local demo — Artifactory, Nexus, and SonarQube

After Nexus or Artifactory is up, `lightwell-remote` on that server can fetch a
Lightwell jar, and that jar is stored on your machine. Click paths:
[`ARTIFACTORY.md`](ARTIFACTORY.md), [`NEXUS.md`](NEXUS.md). SonarQube does not copy
Lightwell ([`SONARQUBE.md`](SONARQUBE.md)).

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
| [`scripts/setup-artifactory.sh`](scripts/setup-artifactory.sh) | Artifactory OSS | http://127.0.0.1:8082 | Maven remote `lightwell-remote` |
| [`scripts/setup-nexus.sh`](scripts/setup-nexus.sh) | Nexus OSS | http://127.0.0.1:8083 | Maven2 proxy, layout **Strict** |
| [`scripts/setup-sonarqube.sh`](scripts/setup-sonarqube.sh) | SonarQube Community | http://127.0.0.1:9000 | none — app quality gate only |

Default login after a successful script run: `admin` / `Lightwell-demo1`
(override with `DEMO_PASSWORD`). Demo-only — do not reuse on a shared server.

First-time order (public demo feed, no token):

The scripts start the Podman machine when it is stopped. On a Mac, run them from this
repo, not from another project directory:

```bash
chmod +x scripts/setup-*.sh scripts/copy-sample.sh
./scripts/setup-nexus.sh
```

Nexus creates `lightwell-remote` and copies a sample `spring-core` jar. Success is HTTP
200 and a non-empty file under `.local/integrations/`. If the copy says the S3 link has
expired, the proxy is still configured; re-run `./scripts/copy-sample.sh nexus` when
the feed issues a fresh redirect. Open http://127.0.0.1:8083/ and browse
`lightwell-remote` to see that cached jar.

```bash
./scripts/setup-artifactory.sh
```

The script creates `lightwell-remote` through the console API, sets **Missed Retrieval
Cache Period** to `600` seconds, and turns on **Bypass HEAD Requests** so the S3
redirect can be downloaded ([`ARTIFACTORY.md`](ARTIFACTORY.md)). If that API fails it
prints the clicks and waits. Open http://127.0.0.1:8082/ui/ and find the sample jar
under `lightwell-remote`.

```bash
./scripts/setup-sonarqube.sh
```

SonarQube starts for the app-quality gate. It does not connect to Lightwell.

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

1. **Nexus** — the setup script already copied the sample jar. Browse
   `lightwell-remote` and point at **Layout policy: Strict**.
2. **Artifactory** — the setup script already created `lightwell-remote`. Show the same
   jar in the Artifactory cache. Finish the printed clicks only if the script is waiting.
3. **What neither did** — the jar is available. Grading whether your app owes a specific
   test set is upgrade-delta, a separate internal project. A new `.rhlw` build shows up
   after the metadata cache age; nothing edits `pom.xml` for you.
4. **SonarQube** — http://127.0.0.1:9000/ . No Lightwell remote and no upgrade plugin.
   See [`SONARQUBE.md`](SONARQUBE.md).

## Stop

```bash
podman stop lightwell-artifactory lightwell-nexus lightwell-sonarqube
```

Volumes keep data across restarts. Re-running a setup script starts the existing
container and skips recreating a repo that is already there.
