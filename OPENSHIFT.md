# OpenShift public demo — Artifactory and Nexus

Deploys Artifactory OSS and Nexus OSS into a new namespace and connects them to the
anonymous public Lightwell demo (same repositories as
[`scripts/setup-demo.sh`](scripts/setup-demo.sh)).

This path uses **Deployments + Routes** (and `emptyDir` for demo data). It does
**not** install JFrog or Sonatype Operators.

Local Podman demo: [`DEMO-LOCAL.md`](DEMO-LOCAL.md).

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

That applies [`openshift/`](openshift/), waits for the Deployments, sets
`admin` / `Lightwell-demo1`, accepts the Nexus Community Edition EULA, creates:

- `lightwell-java-remediated`
- `lightwell-java-validated`
- `lightwell-java` (virtual/group: remediated, then validated)
- `lightwell-python-validated`

and copies the small public catalogs. An expired S3 link is reported and does not
remove the copies that succeeded.

Default namespace: `lightwell-demo` (override with `LIGHTWELL_OPENSHIFT_NAMESPACE`).

Artifactory OSS first boot is slow (often 10–15 minutes). The script waits up to
20 minutes for that Deployment.

## After it finishes

The script prints the Route URLs. On this kit’s cluster they are:

| | URL |
|---|---|
| Artifactory UI | https://artifactory-lightwell-demo.apps.asaran.na-launch.com/ui/ |
| Nexus UI | https://nexus-lightwell-demo.apps.asaran.na-launch.com/ |
| Artifactory Maven | https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/lightwell-java |
| Nexus Maven | https://nexus-lightwell-demo.apps.asaran.na-launch.com/repository/lightwell-java |

Login: `admin` / `Lightwell-demo1`. That password is for this demo only. Do not
reuse it on a shared server.

Replace the host with your own Routes if you deployed into a different cluster.

---

## What developers change on their boxes

Maven never talks to Lightwell directly. It talks to **your** Artifactory or
Nexus URL (`lightwell-java`). The Lightwell token (production) stays on the
server remotes/proxies, not on the laptop.

Developers need **two** client-side pieces, not only `pom.xml`:

| Piece | Where | What it does |
|---|---|---|
| **Repository URL + `.rhlw` version** | Project `pom.xml` (or a parent BOM) | Points Maven at `lightwell-java` and asks for a Lightwell build |
| **Server login** | `~/.m2/settings.xml` or `-s samples/settings.xml` | Username/password for Artifactory or Nexus. **Not** the Lightwell token. The `<server><id>` must match the `<repository><id>` in the pom (`lightwell-java`) |

Optional on OpenShift only:

| Piece | When | What to do |
|---|---|---|
| **Router TLS trust** | JVM does not trust the OpenShift router cert | Import the cluster/router CA into the JDK trust store, or use a corporate MDM image that already trusts it. Script-side curl uses `LIGHTWELL_CURL_INSECURE=1` by default; Maven does not honor that flag |
| **Nexus credentials** | Anonymous browse is off (default here) | Same `settings.xml` server entry works for both Artifactory and Nexus when the repository id stays `lightwell-java` |

Do **not** put the Lightwell service-account token in `pom.xml`, `settings.xml`, or CI secrets meant for Maven. Put it once on each Artifactory remote / Nexus proxy (production path).

### Sample `pom.xml`

Full file: [`samples/demo/pom.xml`](samples/demo/pom.xml). The important parts:

```xml
<properties>
  <lightwell.repo.url>
    https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/lightwell-java
  </lightwell.repo.url>
</properties>

<repositories>
  <repository>
    <id>lightwell-java</id>
    <name>Lightwell Java</name>
    <url>${lightwell.repo.url}</url>
    <releases><enabled>true</enabled></releases>
    <snapshots><enabled>false</enabled></snapshots>
  </repository>
</repositories>

<dependencies>
  <!-- Example: validated-only jar; virtual/group must look past remediated. -->
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
-Dlightwell.repo.url=https://<host>/artifactory/lightwell-java
```

### Sample Maven `settings.xml` (beyond the pom)

Full file: [`samples/settings.xml`](samples/settings.xml). Copy the `<server>`
block into `~/.m2/settings.xml` (or keep using `-s`):

```xml
<settings>
  <servers>
    <server>
      <id>lightwell-java</id>
      <username>admin</username>
      <password>Lightwell-demo1</password>
    </server>
  </servers>
</settings>
```

On a shared Artifactory/Nexus, replace `admin` / `Lightwell-demo1` with that
server’s developer or CI account. Keep `<id>lightwell-java</id>` aligned with
the repository id in the pom.

---

## Smoke test

From this repository, after setup finishes.

**Artifactory** (this cluster):

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dlightwell.repo.url=https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/lightwell-java
```

**Nexus** (same cluster):

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dlightwell.repo.url=https://nexus-lightwell-demo.apps.asaran.na-launch.com/repository/lightwell-java
```

`BUILD SUCCESS` means Maven resolved `commons-io` `2.11.0.rhlw-00001` through
`lightwell-java` (validated feed). That jar is not on remediated, so the
virtual/group had to search past the first member.

A second sample ([`samples/prod/pom.xml`](samples/prod/pom.xml)) resolves
`snakeyaml` `1.33.0.rhlw-00001` the same way — useful after you change
`lightwell.version` for a production adopt.

Quick HTTP checks (Artifactory needs the demo login; Nexus CE needs EULA accepted
by the setup script):

```bash
curl -sk -u 'admin:Lightwell-demo1' -o /dev/null -w "%{http_code}\n" \
  "https://artifactory-lightwell-demo.apps.asaran.na-launch.com/artifactory/lightwell-java/commons-io/commons-io/2.11.0.rhlw-00001/commons-io-2.11.0.rhlw-00001.jar"

curl -sk -u 'admin:Lightwell-demo1' -o /dev/null -w "%{http_code}\n" \
  "https://nexus-lightwell-demo.apps.asaran.na-launch.com/repository/lightwell-java/commons-io/commons-io/2.11.0.rhlw-00001/commons-io-2.11.0.rhlw-00001.jar"
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
edit the `image:` fields in [`openshift/artifactory.yaml`](openshift/artifactory.yaml)
and [`openshift/nexus.yaml`](openshift/nexus.yaml):

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
- Production Lightwell user/token (use the local [`scripts/setup-prod.sh`](scripts/setup-prod.sh) pattern later, or set credentials on the remotes by hand per [`ARTIFACTORY.md`](ARTIFACTORY.md))
- SonarQube
