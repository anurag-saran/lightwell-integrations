# Integrate Lightwell with Sonatype Nexus

Running Nexus on this machine? Stop here and follow [`DEMO-LOCAL.md`](../DEMO-LOCAL.md).
`./scripts/setup-demo.sh` creates the repositories for you. This page is the click path
for a Nexus server you already administer.

After these steps, Nexus can fetch a Lightwell jar and store it. Maven uses the
**existing org group** repository `acmebank_java_repo` (which includes the Lightwell
group `lightwell-java`), not packages.redhat.com.

A **proxy** is one connection from Nexus to one Lightwell feed. The **cache** is the
local copy made the first time something requests a file. The **group** repository is
the one URL your builds use; it searches the proxies in order and stops at the first hit.
You still change `pom.xml` yourself when you want a newer build.

Source procedure: [Configure Nexus to use the Lightwell Network repository](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_nexus_to_use_rhln_repository).
This guide adds the **public demo** URL mode. Index: [`README.md`](../README.md).
Local Podman start: [`DEMO-LOCAL.md`](../DEMO-LOCAL.md).

---

## Before you begin

- Administrator access to Sonatype Nexus Repository Manager.
- For **production**: an active Lightwell Network membership and a
  [service account](https://docs.redhat.com/en/documentation/lightwell_network/current/get_started-create_a_red_hat_lightwell_network_service_account)
  (`XXXXXXX|service-account-name` + token).

---

## What you will create

| Repository name | Type | Public demo | Production |
|---|---|---|---|
| `lightwell-java-predisclosure` | Maven2 (proxy) | Skip — that feed 404s | Create |
| `lightwell-java-remediated` | Maven2 (proxy) | Create | Create |
| `lightwell-java-validated` | Maven2 (proxy) | Create | Create |
| `lightwell-java` | Maven2 (group) | Members: remediated, then validated | Members: predisclosure, then remediated, then validated |
| `maven-central` | Maven2 (proxy) | Create (or reuse your existing Central proxy) | Same |
| `acmebank_java_repo` | Maven2 (group) | Members: `lightwell-java`, then **`maven-central` (last)** | Same |

Maven and CI keep pointing at `acmebank_java_repo`. Admins add `lightwell-java`
**ahead of** `maven-central` so `.rhlw` builds win when present and ordinary
Central deps still resolve. Developers mainly change dependency versions to `.rhlw`.

---

## Procedure

### 1. Create each proxy

For **every row** in the tables below that applies to your mode:

1. **Create a new repository** → type **Maven2 (proxy)**.
2. Name: the repository name from the table.
3. **Remote storage**: the URL from the table.
4. **Layout Policy**: **Strict** (required for `.rhlw` suffixes).
5. Also set:

   | Field | Value | Why |
   |---|---|---|
   | **Maximum metadata age** | `60` minutes | How soon a newly published `.rhlw` version can show up |
   | **Negative cache TTL** | `60` minutes | A version that was missing is retried within an hour |
   | Maximum component age for release jars | leave it long (hours or more) | A release file does not change once it is copied |
   | Auto-block | off | One stale Lightwell redirect must not take the proxy offline |

6. **Authentication**:

   | Mode | Username | Password |
   |---|---|---|
   | Production | `XXXXXXX\|service-account-name` | service-account token |
   | Public demo | leave empty if Nexus allows it; otherwise a placeholder | leave empty, or the same placeholder |

7. Save.

Repeat until every proxy you need exists.

#### Public demo proxies

| Name | Remote storage |
|---|---|
| `lightwell-java-remediated` | `https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/` |
| `lightwell-java-validated` | `https://packages.redhat.com/lightwell/public-lightwell-demo/java/validated/` |

Do **not** create `lightwell-java-predisclosure` for the public demo.

#### Production proxies

| Name | Remote storage |
|---|---|
| `lightwell-java-predisclosure` | `https://packages.redhat.com/lightwell/java/predisclosure/` |
| `lightwell-java-remediated` | `https://packages.redhat.com/lightwell/java/remediated/` |
| `lightwell-java-validated` | `https://packages.redhat.com/lightwell/java/validated/` |

Use the same service-account user and token on each proxy.

### 2. Create the Lightwell group repository

1. **Create a new repository** → type **Maven2 (group)**.
2. Name: `lightwell-java`.
3. **Layout Policy**: **Strict**.
4. **Member repositories**: add the proxies in this order — top is searched first:

   | Mode | Order |
   |---|---|
   | Public demo | 1. `lightwell-java-remediated` · 2. `lightwell-java-validated` |
   | Production | 1. `lightwell-java-predisclosure` · 2. `lightwell-java-remediated` · 3. `lightwell-java-validated` |

5. Save.

### 3. Add Lightwell to the existing org group

If your teams already use a group such as `acmebank_java_repo`:

1. Ensure a **Maven Central** proxy exists (this kit uses name `maven-central` →
   `https://repo1.maven.org/maven2/`).
2. Open the org group (or create it) as **Maven2 (group)** with **Layout Policy: Strict**.
3. Member list, top searched first:
   1. `lightwell-java`
   2. `maven-central` (**last** — so non-`.rhlw` deps and plugins still succeed)
4. Save.

Maven keeps using `acmebank_java_repo`. Effective resolve order is remediated →
validated → Maven Central. Search stops at the first member that has the file.

### 4. Local Podman note

`./scripts/setup-demo.sh` and `./scripts/setup-prod.sh` create these proxies, the
Lightwell group, and `acmebank_java_repo` for you (layout Strict, metadata age 60
minutes, negative cache 60 minutes, auto-block off). You do not need to run
`./nexus/setup.sh` yourself when you use those commands.

---

## Verify

Point Maven at the **org group** repository (`acmebank_java_repo`), not at a single
proxy and not at packages.redhat.com.

On the local demo (Nexus at `http://127.0.0.1:8083`):

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dacmebank.repo.url=http://127.0.0.1:8083/repository/acmebank_java_repo
```

`BUILD SUCCESS` means `acmebank_java_repo` → `lightwell-java` resolved a validated
library (`commons-io` `2.11.0.rhlw-00001`), so the Lightwell group had to look past
remediated.

On a server you already run, use that server’s Nexus URL for `acmebank_java_repo`.

Optional single-proxy check (remediated only):

```bash
./scripts/copy-sample.sh nexus
```

Success is HTTP 200 and a non-empty `woodstox-core` `6.0.3.rhlw-00001` under
`.local/integrations/`. That does not prove the group or the validated proxy work.

---

## Point Maven at Nexus

Clients use the existing org group repository:

`https://<your-nexus-host>/repository/acmebank_java_repo`

Local demo URL: `http://127.0.0.1:8083/repository/acmebank_java_repo`

Sample builds: [`samples/demo/pom.xml`](../samples/demo/pom.xml) and
[`samples/prod/pom.xml`](../samples/prod/pom.xml).

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dacmebank.repo.url=http://127.0.0.1:8083/repository/acmebank_java_repo
mvn -f samples/prod/pom.xml -s samples/settings.xml dependency:resolve \
  -Dacmebank.repo.url=http://127.0.0.1:8083/repository/acmebank_java_repo
```

(`samples/prod/pom.xml` defaults to the OpenShift Artifactory Route; pass the Nexus
URL above for local Nexus.)

[`samples/settings.xml`](../samples/settings.xml) is the local demo login. On a Nexus
server you already run, put that server’s login in the same server id
`acmebank_java_repo`.

Put Lightwell credentials on each proxy and keep CI pointed at the org group. See
Red Hat’s
[Configure your Java build tool](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_java_build_tool).

---

## How it stays in sync

Lightwell publishes a new build. After the metadata age (60 minutes with the settings
above), a build that asks for that version copies it into Nexus. Nothing rewrites your
`pom.xml`. You do not recreate the proxies or `lightwell-java` to sync, and re-running
the setup script does not download the catalog.

## After the jar resolves

Nexus makes the jar *available*. It does not grade impact on *your* bytecode or select
the owed tests. That grade is upgrade-delta, a separate project.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Odd / missing `.rhlw-` versions | **Layout Policy** must be **Strict** on every proxy and on the group |
| Validated jar not found through `acmebank_java_repo` | Org group includes `lightwell-java`; that group includes `lightwell-java-validated`, with remediated listed before it |
| Non-`.rhlw` / Central jar not found | `maven-central` is a member of `acmebank_java_repo` and listed **after** `lightwell-java` |
| CI still hits packages.redhat.com | Client still lists the Lightwell URL instead of `acmebank_java_repo` |
| Demo auth required by UI | Placeholder credentials + smoke-test before presenting |
| Copy says the S3 link has expired | Lightwell returned a cached redirect. The proxy stays online; re-run `./scripts/copy-sample.sh nexus` later |
| Proxy is offline after one failed fetch | Re-run `./nexus/setup.sh` or recreate the proxy with auto-block off |
