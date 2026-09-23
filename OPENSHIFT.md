# OpenShift public demo — Artifactory and Nexus

Deploys Artifactory OSS and Nexus OSS into a new namespace and connects them to the
anonymous public Lightwell demo (same repositories as
[`scripts/setup-demo.sh`](scripts/setup-demo.sh)).

This path uses **Deployments + PVCs + Routes**. It does **not** install JFrog or
Sonatype Operators.

Local Podman demo: [`DEMO-LOCAL.md`](DEMO-LOCAL.md).

## Before you start

- `oc` logged into a cluster where you can create a Namespace, PVC, Deployment,
  Service, and Route.
- About **8 Gi** memory free in the project (two JVMs).
- Egress to `packages.redhat.com`, `releases-docker.jfrog.io`, and
  `docker.io` (or mirrored images — see below).
- Cluster-admin once (or an admin) to grant `anyuid` to the Artifactory service
  account so the initContainer can chown the PVC.

## One command

From this repository:

```bash
./scripts/setup-openshift-demo.sh
```

That applies [`openshift/`](openshift/), waits for the Deployments, sets
`admin` / `Lightwell-demo1`, creates:

- `lightwell-java-remediated`
- `lightwell-java-validated`
- `lightwell-java` (virtual/group: remediated, then validated)
- `lightwell-python-validated`

and copies the small public catalogs. An expired S3 link is reported and does not
remove the copies that succeeded.

Default namespace: `lightwell-demo` (override with `LIGHTWELL_OPENSHIFT_NAMESPACE`).

## After it finishes

The script prints the Route URLs. Open them and log in as `admin` /
`Lightwell-demo1`. That password is for this demo only.

Maven (replace the host with your Artifactory Route):

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dlightwell.repo.url=https://artifactory-lightwell-demo.apps.example.com/artifactory/lightwell-java
```

[`samples/settings.xml`](samples/settings.xml) is the Artifactory login, not a
Lightwell token. Router TLS: the script sets `LIGHTWELL_CURL_INSECURE=1` by
default so laptop curl accepts the cluster router cert. Set
`LIGHTWELL_CURL_INSECURE=0` if your trust store already has that CA.

## What was applied

```bash
oc apply -k openshift/
oc -n lightwell-demo get pods,pvc,route
```

| Name | Role |
|---|---|
| Deployment `artifactory` | JFrog Artifactory OSS, uid 1030, Derby allowed for demo only |
| Deployment `nexus` | Sonatype Nexus OSS |
| Route `artifactory` | HTTPS edge to port 8082 |
| Route `nexus` | HTTPS edge to port 8081 |

## SCC for Artifactory

The Artifactory initContainer runs as root once to chown the volume and seed
`master.key` (same need as the local Podman script). The setup script tries:

```bash
oc adm policy add-scc-to-user anyuid -z lightwell-artifactory -n lightwell-demo
```

If that fails and the pod CrashLoops on permissions, ask a cluster admin to run
the same command.

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

That removes the namespace resources. PVCs are deleted with the manifests; data
is gone unless your StorageClass retains volumes.

## Not in this path

- OLM Operators for Artifactory or Nexus
- Production Lightwell user/token (use the local [`scripts/setup-prod.sh`](scripts/setup-prod.sh) pattern later, or set credentials on the remotes by hand per [`ARTIFACTORY.md`](ARTIFACTORY.md))
- SonarQube
