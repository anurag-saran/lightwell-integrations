# Local demo — Artifactory, Nexus, and SonarQube

After Nexus or Artifactory is up, `lightwell-java-remediated` on that server can fetch a
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

The scripts start the Podman machine when it is stopped. On a Mac, run them from this
repo, not from another project directory.

| Script | What it does |
|---|---|
| [`scripts/setup-demo.sh`](scripts/setup-demo.sh) | Public demo. No token. Creates the Java and Python repositories and copies the small catalogs. |
| [`scripts/setup-prod.sh`](scripts/setup-prod.sh) | Asks for the Lightwell user and token, then points the same local servers at the production Java feeds. Does not copy the catalog. |
| [`scripts/setup-sonarqube.sh`](scripts/setup-sonarqube.sh) | Optional. SonarQube Community. No Lightwell connection. |

`setup-artifactory.sh` and `setup-nexus.sh` are the lower-level scripts those two
commands call. You do not need to run them yourself.

Default login after a successful script run: `admin` / `Lightwell-demo1`
(override with `DEMO_PASSWORD`). Demo-only — do not reuse on a shared server.

Public demo (no token):

```bash
chmod +x scripts/setup-demo.sh scripts/setup-prod.sh
./scripts/setup-demo.sh
```

That starts Artifactory on http://127.0.0.1:8082/ui/ and Nexus on
http://127.0.0.1:8083/, then creates:

- `lightwell-java-remediated`
- `lightwell-java-validated`
- `lightwell-java` (virtual/group: remediated, then validated)
- `lightwell-python-validated`

It copies the small public catalogs. An expired S3 link is reported and does not
remove the copies that succeeded.

Production Lightwell (service account). The script asks for the user and token.
It does not print the token.

```bash
./scripts/setup-prod.sh
```

That creates the same local servers and repository names, with production Java URLs
and the token stored on each remote:

- `https://packages.redhat.com/lightwell/java/predisclosure/`
- `https://packages.redhat.com/lightwell/java/remediated/`
- `https://packages.redhat.com/lightwell/java/validated/`

`lightwell-java` searches predisclosure, then remediated, then validated. The
production catalog is not copied. The first request for a jar stores that jar.

```bash
./scripts/setup-sonarqube.sh
```

SonarQube starts for the app-quality gate. It does not connect to Lightwell.

## Resolve a jar with Maven

Maven uses `lightwell-java` on your local server. It does not call
packages.redhat.com, and the Lightwell token is not in the `pom.xml`.

| Sample | When | What it resolves |
|---|---|---|
| [`samples/demo/pom.xml`](samples/demo/pom.xml) | After `setup-demo.sh` | `commons-io:commons-io:2.11.0.rhlw-00001` (validated, so the virtual looks past remediated) |
| [`samples/prod/pom.xml`](samples/prod/pom.xml) | After `setup-prod.sh` | `org.yaml:snakeyaml` at `lightwell.version`. Change that property to the production build you adopt. |

Artifactory is the default URL. Nexus is the same command with one property.
Artifactory requires a login. In `settings.xml`, the server id `lightwell-java`
is `admin` / `Lightwell-demo1` (local-only). Nexus on this demo allows anonymous
reads.

```bash
mvn -f samples/demo/pom.xml dependency:resolve
mvn -f samples/demo/pom.xml dependency:resolve \
  -Dlightwell.repo.url=http://127.0.0.1:8083/repository/lightwell-java

mvn -f samples/prod/pom.xml dependency:resolve
mvn -f samples/prod/pom.xml dependency:resolve \
  -Dlightwell.repo.url=http://127.0.0.1:8083/repository/lightwell-java
```

Nexus is published on **8083** so Artifactory can keep host ports **8081** and **8082**.
Current Artifactory OSS images refuse the bundled Derby database unless
`JF_SHARED_DATABASE_ALLOWNONPOSTGRESQL=true` is set. The setup script sets that for the
demo. A production Artifactory should use PostgreSQL. The script also pre-creates
`master.key` so a root-owned Podman volume does not stall first boot.

## Demo beats

1. **Nexus** — browse `lightwell-java` and point at **Layout policy: Strict**.
   The group searches remediated, then validated.
2. **Artifactory** — show `lightwell-java`. Finish the printed clicks only if a
   lower-level script is waiting.
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
