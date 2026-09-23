# Integrate Lightwell with JFrog Artifactory

Running Artifactory on this machine? Stop here and follow [`DEMO-LOCAL.md`](DEMO-LOCAL.md).
`./scripts/setup-demo.sh` creates the repositories for you. This page is the click path
for an Artifactory server you already administer.

After these steps, Artifactory can fetch a Lightwell jar and store it. Maven uses the
**virtual** repository `lightwell-java`, not packages.redhat.com.

A **remote** is one connection from Artifactory to one Lightwell feed. The **cache** is
the local copy made the first time something requests a file. The **virtual** repository
is the one URL your builds use; it searches the remotes in order and stops at the first hit.
You still change `pom.xml` yourself when you want a newer build.

Source procedure: [Configure Artifactory to use the Lightwell Network Java repository](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_artifactory_to_use_rhln_repository).
This guide adds the **public demo** URL mode. Index: [`README.md`](README.md).
Local Podman start: [`DEMO-LOCAL.md`](DEMO-LOCAL.md).

---

## Before you begin

- Administrator access to your JFrog Artifactory (JFrog Platform) instance.
- For **production**: an active Lightwell Network membership and a
  [service account](https://docs.redhat.com/en/documentation/lightwell_network/current/get_started-create_a_red_hat_lightwell_network_service_account)
  (`XXXXXXX|service-account-name` + token).
- **Your Artifactory naming policy allows the `.rhlw-0000X` version suffix** (e.g.
  `5.3.17.rhlw-00001`). Strict version-format rules can reject Lightwell coordinates —
  check this before a demo, not during it.

---

## What you will create

| Repository key | Type | Public demo | Production |
|---|---|---|---|
| `lightwell-java-predisclosure` | Remote (Maven) | Skip — that feed 404s | Create |
| `lightwell-java-remediated` | Remote (Maven) | Create | Create |
| `lightwell-java-validated` | Remote (Maven) | Create | Create |
| `lightwell-java` | Virtual (Maven) | Members: remediated, then validated | Members: predisclosure, then remediated, then validated |

Maven and CI point only at `lightwell-java`.

---

## Procedure

### 1. Open Repositories

In the **JFrog Platform** console, open **Administration → Repositories**.

### 2. Create each remote

For **every row** in the table below that applies to your mode, do this:

1. **Create a Repository** → **Remote**.
2. Package type: **Maven**.
3. On the **Basic** tab, set:

   | Field | Value |
   |---|---|
   | Repository Key | the key from the table |
   | URL | the URL from the table |
   | User Name | production: `XXXXXXX\|service-account-name` · public demo: leave blank, or a placeholder if the UI requires a value |
   | Password / Access Token | production: service-account token · public demo: leave blank, or the same placeholder |

4. Under **Maven Settings**, check **List Remote Artifacts**.
5. Confirm **Enable Token Authentication** is **cleared**.
6. On **Advanced** (or the cache section), set:

   | Field | Value | Why |
   |---|---|---|
   | **Metadata Retrieval Cache Period** | `600` seconds, when the field is shown | How soon a newly published `.rhlw` version can show up in `maven-metadata.xml` |
   | **Missed Retrieval Cache Period** | `600` seconds | A version that was missing is retried within 10 minutes |
   | **Bypass HEAD Requests** | checked | The feed redirects to S3, and S3 rejects HEAD |
   | Retrieval cache for release jars | leave the default (hours) | A release file does not change once it is copied |

7. Save. Leave every other field at its default. Artifactory OSS 7.161 does not show
   Metadata Retrieval Cache Period; still set Missed Retrieval Cache Period and Bypass HEAD Requests.

Repeat until every remote you need exists.

#### Public demo remotes

| Repository Key | URL |
|---|---|
| `lightwell-java-remediated` | `https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/` |
| `lightwell-java-validated` | `https://packages.redhat.com/lightwell/public-lightwell-demo/java/validated/` |

Do **not** create `lightwell-java-predisclosure` for the public demo.

#### Production remotes

| Repository Key | URL |
|---|---|
| `lightwell-java-predisclosure` | `https://packages.redhat.com/lightwell/java/predisclosure/` |
| `lightwell-java-remediated` | `https://packages.redhat.com/lightwell/java/remediated/` |
| `lightwell-java-validated` | `https://packages.redhat.com/lightwell/java/validated/` |

Use the same service-account user and token on each remote.

### 3. Create the virtual repository

1. **Create a Repository** → **Virtual**.
2. Package type: **Maven**.
3. Repository Key: `lightwell-java`.
4. Under **Repositories** (or Selected Repositories), add the remotes in this order — top is searched first:

   | Mode | Order |
   |---|---|
   | Public demo | 1. `lightwell-java-remediated` · 2. `lightwell-java-validated` |
   | Production | 1. `lightwell-java-predisclosure` · 2. `lightwell-java-remediated` · 3. `lightwell-java-validated` |

5. Save.

Maven uses this one URL. Search stops at the first remote that has the file. That is why
a library present in both remediated and validated comes from remediated when remediated
is listed first.

### 4. Local Podman note

Artifactory OSS blocks creating remotes over the public repository REST API (Pro-only).
`./scripts/setup-demo.sh` and `./scripts/setup-prod.sh` create the remotes and the virtual
through the console API, including Bypass HEAD Requests and Missed Retrieval Cache Period
`600`. If a lower-level script waits and prints clicks, finish those remotes in the UI,
then re-run the script.

---

## Verify

Point Maven at the **virtual** repository, not at a single remote and not at
packages.redhat.com.

On the local demo (Artifactory at `http://127.0.0.1:8082`):

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve
```

`BUILD SUCCESS` means `lightwell-java` resolved a validated library
(`commons-io` `2.11.0.rhlw-00001`), so the virtual had to look past remediated.
[`samples/settings.xml`](samples/settings.xml) is the Artifactory login
(`admin` / `Lightwell-demo1`), not a Lightwell token.

On a server you already run, use that server’s Artifactory URL for `lightwell-java` and
that server’s login as Maven server id `lightwell-java`.

Optional single-remote check (remediated only):

```bash
./scripts/copy-sample.sh artifactory
```

Success is HTTP 200 and a non-empty `woodstox-core` `6.0.3.rhlw-00001` under
`.local/integrations/`. That does not prove the virtual or the validated remote work.

If a public-demo remote fails with empty credentials, try a non-empty placeholder in
User Name / Password. The demo path does not validate credentials for anonymous fetches,
but some Artifactory UIs reject blank auth fields.

---

## How it stays in sync

Lightwell publishes a new build. After the metadata cache period (10 minutes with the
settings above), a build that asks for that version copies it into Artifactory. Nothing
rewrites your `pom.xml`. You do not recreate the remotes or `lightwell-java` to sync, and
re-running the setup script does not download the catalog.

---

## Point Maven at Artifactory

Clients use the virtual repository:

`https://<your-artifactory-host>/artifactory/lightwell-java`

Local demo URL: `http://127.0.0.1:8082/artifactory/lightwell-java`

Sample builds: [`samples/demo/pom.xml`](samples/demo/pom.xml) and
[`samples/prod/pom.xml`](samples/prod/pom.xml).

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve
mvn -f samples/prod/pom.xml -s samples/settings.xml dependency:resolve
```

Put the Lightwell token on each remote, not in the pom or in CI. Follow JFrog’s
[Connect your Maven Client to Artifactory](https://jfrog.com/help/r/jfrog-artifactory-documentation/maven-repository)
and Red Hat’s
[Configure your Java build tool](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_java_build_tool).

---

## After the jar resolves

Artifactory makes the jar *available*. It does not tell you whether adopting it is safe
for *your* application, or which tests the bump owes. That grade is upgrade-delta, a
separate project.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Version rejected / not found | Artifactory naming policy vs `.rhlw-0000X`; confirm the GAV exists on the tier that should hold it |
| Validated jar not found through `lightwell-java` | Virtual members include `lightwell-java-validated`, and remediated is listed before it |
| Production jar not found | Virtual members include predisclosure, remediated, and validated in that order |
| 401 / 403 from packages.redhat.com | Production service-account format and token on **each** remote; Enable Token Authentication must stay cleared |
| Empty catalog in UI | **List Remote Artifacts** checked; fetch once so the remote caches |
| CI still hits packages.redhat.com | Client `settings.xml` / `pom` still lists the Lightwell URL instead of `lightwell-java` |
| Demo auth fields won’t save blank | Use any placeholder string for public-demo; smoke-test a jar fetch before presenting |
| Jar fetch is Forbidden after a redirect | **Bypass HEAD Requests** must be checked. S3 presigned URLs reject HEAD |
| Copy says the S3 link has expired | Lightwell returned a cached redirect. The remote is already saved; re-run `scripts/copy-sample.sh` later |
| Script waits and prints clicks | The console API did not save a remote. Finish it in the UI, then re-run the script |
