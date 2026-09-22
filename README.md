# Lightwell integrations

Proxy the Lightwell Network through the artifact repository managers you already run,
and see how SonarQube sits next to a dependency-upgrade grade. These are customer
wiring docs, not a substitute for Red Hat’s product documentation.

upgrade-delta grades the bump after the jar is resolvable. It is a separate
internal project. This repository does not include it.

| Guide | When you need it |
|---|---|
| [`ARTIFACTORY.md`](ARTIFACTORY.md) | JFrog Artifactory is your Maven remote |
| [`NEXUS.md`](NEXUS.md) | Sonatype Nexus is your Maven proxy |
| [`SONARQUBE.md`](SONARQUBE.md) | You already gate merges with Sonar |
| [`DEMO-LOCAL.md`](DEMO-LOCAL.md) | Stand the three tools up locally with Podman |

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

## Demo narrative

1. Show the repo config screen in Artifactory, then Nexus — one remote, additive to existing builds.
2. Resolve one coordinate through each, e.g. `com.jayway.jsonpath:json-path:2.8.0.rhlw-00001`.
3. Say what the repo manager did not do: it did not grade whether adopting that jar is safe to test-scope. That grade is upgrade-delta, a separate project.
4. Sonar quality gate for app health stays in place. It does not replace the upgrade grade. See [`SONARQUBE.md`](SONARQUBE.md).
