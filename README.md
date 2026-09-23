# Lightwell integrations

This repository connects a Java build to Lightwell. Your Artifactory or Nexus server
fetches the jar and stores it. Maven asks that server for the jar. Maven does not
call Lightwell itself, and the Lightwell token is not stored in `pom.xml`.

These pages are a first-time walkthrough. They are not a substitute for Red Hat’s
product documentation. SonarQube does not fetch Lightwell jars. upgrade-delta, which
grades a dependency bump, is a separate project and is not in this repository.

## Start here

You need Podman and Maven. On a Mac, the first time only:

```bash
podman machine init --memory 8192
```

From this repository, pick one command.

**Trying it out** (no Lightwell account):

```bash
./scripts/setup-demo.sh
```

**Your company’s Lightwell account** (the script asks for the user and token, and does not print the token):

```bash
./scripts/setup-prod.sh
```

Then open the UI and log in with `admin` / `Lightwell-demo1`. That password is only for this local demo. Do not reuse it on a shared server.

| | Address |
|---|---|
| Artifactory | http://127.0.0.1:8082/ui/ |
| Nexus | http://127.0.0.1:8083/ |

Confirm Maven can fetch a Lightwell jar. The `-s` file is the Artifactory login, not the Lightwell token.

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve
```

`BUILD SUCCESS` means Artifactory stored `commons-io` `2.11.0.rhlw-00001`. The same check through Nexus:

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dlightwell.repo.url=http://127.0.0.1:8083/repository/lightwell-java
```

Step-by-step, including what each repository name means: [`DEMO-LOCAL.md`](DEMO-LOCAL.md).

**OpenShift** (after `./scripts/setup-openshift-demo.sh`):

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dlightwell.repo.url=https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/lightwell-java
```

Developers change more than `pom.xml`: they also need Maven `settings.xml` credentials
for Artifactory/Nexus (id `lightwell-java`), and on OpenShift a JVM that trusts the
router cert. Sample pom, settings, and smoke tests: [`OPENSHIFT.md`](OPENSHIFT.md).

| Guide | When you need it |
|---|---|
| [`DEMO-LOCAL.md`](DEMO-LOCAL.md) | You are running Artifactory and Nexus on this machine |
| [`OPENSHIFT.md`](OPENSHIFT.md) | You are running Artifactory and Nexus on OpenShift (public demo); includes developer laptop changes and smoke tests |
| [`ARTIFACTORY.md`](ARTIFACTORY.md) | You already have an Artifactory server and want the click path |
| [`NEXUS.md`](NEXUS.md) | You already have a Nexus server and want the click path |
| [`SONARQUBE.md`](SONARQUBE.md) | You already use Sonar. Skip this if you do not. |
| [`OSV-DEMO-GAPS.md`](OSV-DEMO-GAPS.md) | Eng: public-demo OSV vs Maven mismatches (clickable URLs) |

## Words used here

| Word | Meaning |
|---|---|
| **`.rhlw-00001`** | The end of a Lightwell version, for example `2.11.0.rhlw-00001`. You type that version into `pom.xml` when you want that build. |
| **Remediated / Validated / Predisclosure** | Three Lightwell feeds. Remediated and Validated are on the public demo. Predisclosure exists only in production. |
| **Remote / proxy** | One connection from your server to one feed. Artifactory calls it a remote repository. Nexus calls it a Maven2 proxy. |
| **Virtual / group** | One URL your build uses. It searches the feeds in order. The name in this kit is `lightwell-java`. |
| **Cache** | The local copy. The first request downloads the jar from Lightwell. The next request for that same file stays on your server. |

## What this is / is not

**Is:** one URL (`lightwell-java`) so Maven resolves a `.rhlw` version the same way
it resolves Maven Central. The Lightwell user and token live on Artifactory or Nexus,
once, not in each build.

**Is not:** a grade of the upgrade. Artifactory/Nexus make a remediated build
*available*. SonarQube still owns app-code quality. Neither tells you which of your
tests a dependency bump owes.

## Official sources

- [Configure Artifactory (Java)](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_artifactory_to_use_rhln_repository)
- [Configure Nexus](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_nexus_to_use_rhln_repository)
- [Choose the right repository tier](https://docs.redhat.com/en/documentation/lightwell_network/current/get_started-choose_the_right_repository)
- [Configure your Java build tool](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_java_build_tool)

## URL modes

| Mode | Base URL | Auth |
|---|---|---|
| **Production** | `https://packages.redhat.com/lightwell/java/remediated/` (also `validated/`, `predisclosure/`) | Service account `XXXXXXX\|service-account-name` + token |
| **Public demo** | `https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/` | None — leave blank, or a placeholder if the UI rejects empty fields. **Smoke-test before a live demo.** |

Most production environments layer tiers in a virtual/group repository, ordered
**Predisclosure → Remediated → Validated**. Lightwell supplies the tiers; you own the
combined view.

## How it stays in sync

`setup-demo.sh` copies the small public catalog once. `setup-prod.sh` does not copy
the production catalog. Running either script again does not download builds that
Lightwell publishes later.

1. Lightwell publishes a new `.rhlw` build.
2. Your server re-reads `maven-metadata.xml` after the metadata cache age. On
   Artifactory set **Missed Retrieval Cache Period** to `600` seconds, and **Metadata
   Retrieval Cache Period** to `600` seconds when that field is on the screen. On Nexus
   set **Maximum metadata age** to 60 minutes.
3. A build that asks for that version copies the jar into the cache.

A jar that is already cached stays as it is. You change the version in `pom.xml` when
you want a newer build. You do not recreate `lightwell-java` to pick it up.

## What success looks like

1. Artifactory and Nexus each show a repository named `lightwell-java`.
2. `mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve` prints `BUILD SUCCESS`.
3. The servers stored the jar. They did not decide whether your application should adopt it. That grade is upgrade-delta, a separate project.
4. SonarQube, if you start it, still only checks your application code. See [`SONARQUBE.md`](SONARQUBE.md).
