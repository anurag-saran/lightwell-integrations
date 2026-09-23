# Integrate Lightwell with Sonatype Nexus

Running Nexus on this machine? Stop here and follow [`DEMO-LOCAL.md`](DEMO-LOCAL.md).
`./scripts/setup-demo.sh` creates the repositories for you. This page is the click path
for a Nexus server you already administer.

After these steps, Nexus can fetch a Lightwell jar and store it. Maven uses the
**group** repository `lightwell-java`, not packages.redhat.com.

A **proxy** is one connection from Nexus to one Lightwell feed. The **cache** is the
local copy made the first time something requests a file. The **group** repository is
the one URL your builds use; it searches the proxies in order and stops at the first hit.
You still change `pom.xml` yourself when you want a newer build.

Source procedure: [Configure Nexus to use the Lightwell Network repository](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_nexus_to_use_rhln_repository).
This guide adds the **public demo** URL mode. Index: [`README.md`](README.md).
Local Podman start: [`DEMO-LOCAL.md`](DEMO-LOCAL.md).

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

Maven and CI point only at `lightwell-java`.

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

### 2. Create the group repository

1. **Create a new repository** → type **Maven2 (group)**.
2. Name: `lightwell-java`.
3. **Layout Policy**: **Strict**.
4. **Member repositories**: add the proxies in this order — top is searched first:

   | Mode | Order |
   |---|---|
   | Public demo | 1. `lightwell-java-remediated` · 2. `lightwell-java-validated` |
   | Production | 1. `lightwell-java-predisclosure` · 2. `lightwell-java-remediated` · 3. `lightwell-java-validated` |

5. Save.

Maven uses this one URL. Search stops at the first proxy that has the file.

### 3. Local Podman note

`./scripts/setup-demo.sh` and `./scripts/setup-prod.sh` create these proxies and the group
for you (layout Strict, metadata age 60 minutes, negative cache 60 minutes, auto-block off).
You do not need to run `scripts/setup-nexus.sh` yourself when you use those commands.

---

## Verify

Point Maven at the **group** repository, not at a single proxy and not at
packages.redhat.com.

On the local demo (Nexus at `http://127.0.0.1:8083`):

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dlightwell.repo.url=http://127.0.0.1:8083/repository/lightwell-java
```

`BUILD SUCCESS` means `lightwell-java` resolved a validated library
(`commons-io` `2.11.0.rhlw-00001`), so the group had to look past remediated.

On a server you already run, use that server’s Nexus URL for `lightwell-java`.

Optional single-proxy check (remediated only):

```bash
./scripts/copy-sample.sh nexus
```

Success is HTTP 200 and a non-empty `woodstox-core` `6.0.3.rhlw-00001` under
`.local/integrations/`. That does not prove the group or the validated proxy work.

---

## Point Maven at Nexus

Clients use the group repository:

`https://<your-nexus-host>/repository/lightwell-java`

Local demo URL: `http://127.0.0.1:8083/repository/lightwell-java`

Sample builds: [`samples/demo/pom.xml`](samples/demo/pom.xml) and
[`samples/prod/pom.xml`](samples/prod/pom.xml).

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dlightwell.repo.url=http://127.0.0.1:8083/repository/lightwell-java
mvn -f samples/prod/pom.xml -s samples/settings.xml dependency:resolve \
  -Dlightwell.repo.url=http://127.0.0.1:8083/repository/lightwell-java
```

[`samples/settings.xml`](samples/settings.xml) is the local demo login. On a Nexus
server you already run, put that server’s login in the same server id `lightwell-java`.

Put Lightwell credentials on each proxy and keep CI pointed at the group only. See
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
| Validated jar not found through `lightwell-java` | Group members include `lightwell-java-validated`, and remediated is listed before it |
| Production jar not found | Group members include predisclosure, remediated, and validated in that order |
| 401 / 403 from packages.redhat.com | Production username format (`orgId\|name`) and token on **each** proxy |
| Artifact not cached | Hit the group once from Maven; confirm each proxy Remote Storage URL ends with the correct tier |
| CI still hits packages.redhat.com | Client still lists the Lightwell URL instead of the Nexus group |
| Demo auth required by UI | Placeholder credentials + smoke-test before presenting |
| Copy says the S3 link has expired | Lightwell returned a cached redirect. The proxy stays online; re-run `scripts/copy-sample.sh nexus` later |
| Proxy is offline after one failed fetch | Re-run `scripts/setup-nexus.sh` or recreate the proxy with auto-block off |
