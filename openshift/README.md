# OpenShift public demo — Artifactory and Nexus

Deploys Artifactory OSS and Nexus OSS into a new namespace and connects them to the
anonymous public Lightwell demo (same repositories as
[`scripts/setup-demo.sh`](../scripts/setup-demo.sh)).

This path uses **Deployments + Routes** (and `emptyDir` for demo data). It does
**not** install JFrog or Sonatype Operators.

Local Podman demo: [`DEMO-LOCAL.md`](../DEMO-LOCAL.md).

## Demo URLs and login

On this kit’s OpenShift cluster (after `./scripts/setup-openshift-demo.sh`):

| Service | Web URL |
|---|---|
| Artifactory UI | https://artifactory-lightwell-demo.apps.asaran.na-launch.com/ui/ |
| Nexus UI | https://nexus-lightwell-demo.apps.asaran.na-launch.com/ |

| | |
|---|---|
| **Username** | `admin` |
| **Password** | `Lightwell-demo1` |

Maven repository URLs (same login via [`samples/settings.xml`](../samples/settings.xml)):

| Service | Maven URL (existing org virtual) |
|---|---|
| Artifactory | https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/acmebank_java_repo |
| Nexus | https://nexus-lightwell-demo.apps.asaran.na-launch.com/repository/acmebank_java_repo |

**Resolve order** through `acmebank_java_repo` (first match wins):

1. `lightwell-java-remediated`
2. `lightwell-java-validated`
3. `maven-central` (lowest — normal Central deps and plugins still succeed)

Dedicated Lightwell virtual/group (members 1–2 above; also a member of `acmebank_java_repo`):

| Service | Lightwell-only URL |
|---|---|
| Artifactory | https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/lightwell-java |
| Nexus | https://nexus-lightwell-demo.apps.asaran.na-launch.com/repository/lightwell-java |

That password is for this OpenShift demo only. Do not reuse it on a shared server.
If you deploy on another cluster, replace the host with your Route from
`oc -n lightwell-demo get route`.

## Before you start

- `oc` logged into a cluster where you can create a Namespace, Deployment,
  Service, and Route.
- About **8 Gi** memory free in the project (two JVMs).
- Egress to `packages.redhat.com`, `releases-docker.jfrog.io`, and
  `docker.io` (or mirrored images — see below).
- Cluster-admin once (or an admin) to grant `anyuid` to the Artifactory and
  Nexus service accounts (fixed non-root UIDs 1030 and 200).

## One command

From this repository:

```bash
./scripts/setup-openshift-demo.sh
```

That applies [`kustomization.yaml`](kustomization.yaml), waits for the Deployments, sets
`admin` / `Lightwell-demo1`, accepts the Nexus Community Edition EULA, creates:

- `lightwell-java-remediated` / `lightwell-java-validated` (remotes/proxies)
- `lightwell-java` (virtual/group: remediated, then validated)
- `maven-central` (remote/proxy of Maven Central — **lowest** member of the org virtual)
- `acmebank_java_repo` (org virtual/group: `lightwell-java`, then `maven-central`)
- `lightwell-python-validated`

and copies the small public catalogs. An expired S3 link is reported and does not
remove the copies that succeeded.

Default namespace: `lightwell-demo` (override with `LIGHTWELL_OPENSHIFT_NAMESPACE`).

Artifactory OSS first boot is slow (often 10–15 minutes). The script waits up to
20 minutes for that Deployment.

## After it finishes

The script prints the same Route URLs. Open the UIs from
[Demo URLs and login](#demo-urls-and-login) above (`admin` / `Lightwell-demo1`).

---

## What developers change on their boxes

Maven never talks to Lightwell directly. It talks to **your** Artifactory or
Nexus URL. In this kit that URL is the existing org virtual/group
`acmebank_java_repo`. Resolve order: remediated → validated → **maven-central**
(lowest). The Lightwell token (production) stays on the server remotes/proxies,
not on the laptop.

Because teams already point Maven at `acmebank_java_repo`, adopting Lightwell
is mostly a **server-side** member change. On the laptop, the usual client
change is the **`.rhlw` dependency version** (and credentials you already had
for Artifactory/Nexus):

| Piece | Where | What it does |
|---|---|---|
| **`.rhlw` version** | Project `pom.xml` (or a parent BOM) | Asks for a Lightwell build through the same org repo URL |
| **Repository URL** | Usually unchanged | Still `acmebank_java_repo` — admins added Lightwell as a member |
| **Server login** | `~/.m2/settings.xml` or `-s samples/settings.xml` | Username/password for Artifactory or Nexus. **Not** the Lightwell token. The `<server><id>` must match the `<repository><id>` in the pom (`acmebank_java_repo`) |

Optional on OpenShift only:

| Piece | When | What to do |
|---|---|---|
| **Router TLS trust** | JVM does not trust the OpenShift router cert | Import the cluster/router CA into the JDK trust store, or use a corporate MDM image that already trusts it. Script-side curl uses `LIGHTWELL_CURL_INSECURE=1` by default; Maven does not honor that flag |
| **Nexus credentials** | Anonymous browse is off (default here) | Same `settings.xml` server entry works for both Artifactory and Nexus when the repository id stays `acmebank_java_repo` |

Do **not** put the Lightwell service-account token in `pom.xml`, `settings.xml`, or CI secrets meant for Maven. Put it once on each Artifactory remote / Nexus proxy (production path).

### Sample `pom.xml`

Full file: [`samples/demo/pom.xml`](../samples/demo/pom.xml). The important parts:

```xml
<properties>
  <acmebank.repo.url>
    https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/acmebank_java_repo
  </acmebank.repo.url>
</properties>

<repositories>
  <repository>
    <id>acmebank_java_repo</id>
    <name>Acme Bank Java (existing org virtual)</name>
    <url>${acmebank.repo.url}</url>
    <releases><enabled>true</enabled></releases>
    <snapshots><enabled>false</enabled></snapshots>
  </repository>
</repositories>

<!-- Same URL for plugins so builds fall through to maven-central. -->
<pluginRepositories>
  <pluginRepository>
    <id>acmebank_java_repo</id>
    <url>${acmebank.repo.url}</url>
    <releases><enabled>true</enabled></releases>
    <snapshots><enabled>false</enabled></snapshots>
  </pluginRepository>
</pluginRepositories>

<dependencies>
  <!-- Client change: .rhlw version. Repo id/URL stay the org standard. -->
  <dependency>
    <groupId>commons-io</groupId>
    <artifactId>commons-io</artifactId>
    <version>2.11.0.rhlw-00001</version>
  </dependency>
</dependencies>
```

In a real app you usually keep the default URL as your team’s Artifactory/Nexus
and override only when needed:

```bash
-Dacmebank.repo.url=https://<host>/artifactory/acmebank_java_repo
```

### Sample Maven `settings.xml` (beyond the pom)

Full file: [`samples/settings.xml`](../samples/settings.xml). Copy the `<server>`
block into `~/.m2/settings.xml` (or keep using `-s`):

```xml
<settings>
  <servers>
    <server>
      <id>acmebank_java_repo</id>
      <username>admin</username>
      <password>Lightwell-demo1</password>
    </server>
  </servers>
</settings>
```

On a shared Artifactory/Nexus, replace `admin` / `Lightwell-demo1` with that
server’s developer or CI account. Keep `<id>acmebank_java_repo</id>` aligned with
the repository id in the pom.

---

## Smoke test

From this repository, after setup finishes.

**Artifactory** (this cluster):

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dacmebank.repo.url=https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/acmebank_java_repo
```

**Nexus** (same cluster):

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dacmebank.repo.url=https://nexus-lightwell-demo.apps.asaran.na-launch.com/repository/acmebank_java_repo
```

`BUILD SUCCESS` means Maven resolved `commons-io` `2.11.0.rhlw-00001` through
`acmebank_java_repo` → `lightwell-java` (validated feed). That jar is not on
remediated, so the Lightwell virtual/group had to search past the first member.

A second sample ([`samples/prod/pom.xml`](../samples/prod/pom.xml)) resolves
`snakeyaml` `1.33.0.rhlw-00001` the same way — useful after you change
`lightwell.version` for a production adopt.

Quick HTTP checks (Artifactory needs the demo login; Nexus CE needs EULA accepted
by the setup script):

```bash
curl -sk -u 'admin:Lightwell-demo1' -o /dev/null -w "%{http_code}\n" \
  "https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/acmebank_java_repo/commons-io/commons-io/2.11.0.rhlw-00001/commons-io-2.11.0.rhlw-00001.jar"

curl -sk -u 'admin:Lightwell-demo1' -o /dev/null -w "%{http_code}\n" \
  "https://nexus-lightwell-demo.apps.asaran.na-launch.com/repository/acmebank_java_repo/commons-io/commons-io/2.11.0.rhlw-00001/commons-io-2.11.0.rhlw-00001.jar"
```

Expect `200` and a non-empty download.

Router TLS: the setup script sets `LIGHTWELL_CURL_INSECURE=1` so laptop curl
accepts the cluster router cert. Set `LIGHTWELL_CURL_INSECURE=0` if your trust
store already has that CA. Maven still needs a JVM that trusts the cert (see
above).

---

## What was applied

```bash
oc apply -k openshift/
oc -n lightwell-demo get pods,route
```

| Name | Role |
|---|---|
| Deployment `artifactory` | JFrog Artifactory OSS, uid 1030, Derby allowed for demo only |
| Deployment `nexus` | Sonatype Nexus OSS / Community Edition |
| Route `artifactory` | HTTPS edge to port 8082 |
| Route `nexus` | HTTPS edge to port 8081 |

Data uses `emptyDir` (lost on pod restart). Durable PVCs need a working
StorageClass; on this kit’s test cluster `nfs-csi` stopped provisioning new
volumes, so the demo does not wait on PVCs.

## SCC for Artifactory and Nexus

Both containers run as fixed non-root UIDs (Artifactory 1030, Nexus 200). The
setup script grants `anyuid` to both service accounts:

```bash
oc adm policy add-scc-to-user anyuid -z lightwell-artifactory -n lightwell-demo
oc adm policy add-scc-to-user anyuid -z lightwell-nexus -n lightwell-demo
```

If that fails and a pod is stuck Pending on SCC, ask a cluster admin to run the
same commands.

## Image mirrors

If the cluster cannot pull from the public registries, mirror the images and
edit the `image:` fields in [`artifactory.yaml`](artifactory.yaml)
and [`nexus.yaml`](nexus.yaml):

- `releases-docker.jfrog.io/jfrog/artifactory-oss:latest`
- `docker.io/sonatype/nexus3:latest`

## Stop / remove

```bash
oc delete -k openshift/
```

That removes the namespace resources. With `emptyDir`, demo data is gone when
pods are deleted.

## Not in this path

- OLM Operators for Artifactory or Nexus
- Production Lightwell user/token (use the local [`scripts/setup-prod.sh`](../scripts/setup-prod.sh) pattern later, or set credentials on the remotes by hand per [`../artifactory/README.md`](../artifactory/README.md))
- SonarQube

GitLab CE + Lightwell plugin demo on the same cluster: [`../gitlab/openshift.md`](../gitlab/openshift.md).
