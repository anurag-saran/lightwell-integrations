# Lightwell integrations

After setup, `lightwell-java-remediated` on your Artifactory or Nexus server can fetch a
Lightwell jar, and that jar is stored on your server.

These guides walk a first-time operator through that connection. They are not a
substitute for Red Hat’s product documentation. SonarQube does not proxy or copy
Lightwell; it only gates application code quality.

upgrade-delta grades the bump after the jar is resolvable. It is a separate
internal project. This repository does not include it.

## Start here

From this repository, on a machine with Podman:

```bash
./scripts/setup-demo.sh
```

That repeats the public demo: local Artifactory and Nexus, no Lightwell token, and
the small public catalogs. For a production service account:

```bash
./scripts/setup-prod.sh
```

It asks for the Lightwell user (`XXXXXXX|service-account-name`) and token, then
points those same local servers at the production Java feeds. It does not copy the
production catalog. SonarQube stays optional: `./scripts/setup-sonarqube.sh`.
Details are in [`DEMO-LOCAL.md`](DEMO-LOCAL.md).

Point Maven at the local `lightwell-java` repository, not at packages.redhat.com.
Sample builds:

```bash
mvn -f samples/demo/pom.xml dependency:resolve
mvn -f samples/prod/pom.xml dependency:resolve
```

[`samples/demo/pom.xml`](samples/demo/pom.xml) uses a public-demo library.
[`samples/prod/pom.xml`](samples/prod/pom.xml) is the same client URL after
`setup-prod.sh`. Change `lightwell.version` to the production build you adopt.
The token stays on Artifactory or Nexus.

| Guide | When you need it |
|---|---|
| [`ARTIFACTORY.md`](ARTIFACTORY.md) | JFrog Artifactory is your Maven remote |
| [`NEXUS.md`](NEXUS.md) | Sonatype Nexus is your Maven proxy |
| [`SONARQUBE.md`](SONARQUBE.md) | You already gate merges with Sonar |
| [`DEMO-LOCAL.md`](DEMO-LOCAL.md) | Stand the three tools up locally with Podman |

## Words used here

| Word | Meaning |
|---|---|
| **Remote / proxy** | The connection from your server to Lightwell. Artifactory calls it a remote repository. Nexus calls it a Maven2 proxy. |
| **Cache** | The local copy. The first request for a jar downloads it from Lightwell and stores it on your server. The next request for that same file does not leave your server. |
| **`pom.xml`** | Still yours. A new `.rhlw` build does not edit your version. You change the version when you want to adopt it. |

## What this is / is not

**Is:** one remote (or proxy) repository so Maven/Gradle resolve `.rhlw-*` coordinates
the same way they resolve Central — credentials live on the repo manager once, not on
every CI job.

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

The setup does not download the whole Lightwell catalog, and running the setup script
again does not sync anything.

1. Lightwell publishes a new `.rhlw` build.
2. Your server re-reads `maven-metadata.xml` after the metadata cache age. On
   Artifactory set **Missed Retrieval Cache Period** to `600` seconds, and **Metadata
   Retrieval Cache Period** to `600` seconds when that field is on the screen. On Nexus
   set **Maximum metadata age** to 60 minutes.
3. A build that asks for that version copies the jar into the cache.

Release jars that are already cached stay cached. They do not change. You do not
recreate `lightwell-java-remediated` to pick up a new build.

## Demo narrative

1. Show the repo config screen in Artifactory, then Nexus — one remote, additive to existing builds.
2. Resolve one coordinate through each, e.g. `com.jayway.jsonpath:json-path:2.8.0.rhlw-00001`.
3. Say what the repo manager did not do: it did not grade whether adopting that jar is safe to test-scope. That grade is upgrade-delta, a separate project.
4. Sonar quality gate for app health stays in place. It does not replace the upgrade grade. See [`SONARQUBE.md`](SONARQUBE.md).
