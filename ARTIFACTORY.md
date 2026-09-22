# Integrate Lightwell with JFrog Artifactory

After these steps, `lightwell-java-remediated` on your Artifactory server can fetch a Lightwell
jar, and that jar is stored on your server.

A **remote** is the connection to Lightwell. The **cache** is the local copy made the
first time something requests a file. You still change `pom.xml` yourself when you want
a newer build.

Source procedure: [Configure Artifactory to use the Lightwell Network Java repository](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_artifactory_to_use_rhln_repository).
This guide adds the **public demo** URL mode. Index: [`README.md`](README.md).
Local Podman start: [`DEMO-LOCAL.md`](DEMO-LOCAL.md) and `scripts/setup-artifactory.sh`.

---

## Before you begin

- Administrator access to your JFrog Artifactory (JFrog Platform) instance.
- For **production**: an active Lightwell Network membership and a
  [service account](https://docs.redhat.com/en/documentation/lightwell_network/current/get_started-create_a_red_hat_lightwell_network_service_account)
  (`XXXXXXX|service-account-name` + token).
- Chosen [repository tier](https://docs.redhat.com/en/documentation/lightwell_network/current/get_started-choose_the_right_repository)
  (Validated / Remediated / Predisclosure).
- **Your Artifactory naming policy allows the `.rhlw-0000X` version suffix** (e.g.
  `5.3.17.rhlw-00001`). Strict version-format rules can reject Lightwell coordinates —
  check this before a demo, not during it.

---

## Procedure

1. In the **JFrog Platform** console, open **Administration → Repositories**.
2. **Create a Repository** → **Remote**.
3. Package type: **Maven**.
4. On the **Basic** tab, set:

   | Field | Production | Public demo |
   |---|---|---|
   | Repository Key | `lightwell-java-remediated` | `lightwell-java-remediated` (or `lightwell-java-remediated-demo`) |
   | URL | `https://packages.redhat.com/lightwell/java/remediated/` | `https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/` |
   | User Name | `XXXXXXX\|service-account-name` | leave blank, or a placeholder if the UI requires a value |
   | Password / Access Token | service-account token | leave blank, or the same placeholder |

   Swap `remediated` for `validated` or `predisclosure` when that is the tier you need.
   For multiple tiers, create one remote per tier and combine them in a virtual repository
   (typical order: Predisclosure → Remediated → Validated).

5. Under **Maven Settings**, check **List Remote Artifacts** so the catalog is browsable
   in the Artifactory UI.
6. Confirm **Enable Token Authentication** is **cleared**.
7. On the same remote, set the cache timers that control new builds (Advanced, or the
   cache section on the remote — the labels are):

   | Field | Value | Why |
   |---|---|---|
   | **Metadata Retrieval Cache Period** | `600` seconds, when the field is shown | How soon a newly published `.rhlw` version can show up in `maven-metadata.xml` |
   | **Missed Retrieval Cache Period** | `600` seconds | A version that was missing is retried within 10 minutes |
   | **Bypass HEAD Requests** | checked | The feed redirects to S3, and S3 rejects HEAD |
   | Retrieval cache for release jars | leave the default (hours) | A release file does not change once it is copied |

   Leave every other field at its default. Artifactory OSS 7.161 does not show
   Metadata Retrieval Cache Period; the setup script still sets the missed-retrieval
   timer and Bypass HEAD Requests.

Artifactory OSS blocks creating this remote over the public repository REST API (that
API is Pro-only). `scripts/setup-artifactory.sh` saves it through the same console API
the UI uses, including **Bypass HEAD Requests** (the feed redirects to S3, and S3
rejects HEAD) and **Missed Retrieval Cache Period** `600`. This OSS build has no
Metadata Retrieval Cache Period field; set that to `600` as well when the screen shows
it. If the console API fails, the script prints the clicks and waits for you to save
`lightwell-java-remediated`, then copies a sample jar.

---

## Verify

With Artifactory running and `lightwell-java-remediated` saved:

```bash
./scripts/copy-sample.sh artifactory
```

Success is HTTP 200 and a non-empty file under `.local/integrations/` (the script prints
the path). That file is the local copy. The same jar is now in the Artifactory cache.
Open `lightwell-java-remediated` in the UI and you should see `spring-core` after this fetch.

If the public-demo remote fails with empty credentials, try a non-empty placeholder in
User Name / Password. The demo path does not validate credentials for anonymous fetches,
but some Artifactory UIs reject blank auth fields.

---

## How it stays in sync

Lightwell publishes a new build. After the metadata cache period (10 minutes with the
settings above), a build that asks for that version copies it into Artifactory. Nothing
rewrites your `pom.xml`. You do not recreate `lightwell-java-remediated` to sync, and re-running
the setup script does not download the catalog.

---

## Point Maven at Artifactory

Clients use the virtual repository, not packages.redhat.com:

`http://127.0.0.1:8082/artifactory/lightwell-java`

`scripts/setup-demo.sh` builds that virtual from remediated, then validated, and
copies the small public catalog. `scripts/setup-prod.sh` builds it from
predisclosure, then remediated, then validated, and stores the service-account
token on each remote. Sample builds: [`samples/demo/pom.xml`](samples/demo/pom.xml)
and [`samples/prod/pom.xml`](samples/prod/pom.xml).

```bash
mvn -f samples/demo/pom.xml dependency:resolve
mvn -f samples/prod/pom.xml dependency:resolve
```

In `settings.xml`, server id `lightwell-java` is the Artifactory login
(`admin` / `Lightwell-demo1` on this local demo). Put the Lightwell token on the
remote, not in the pom or in CI. Follow JFrog’s
[Connect your Maven Client to Artifactory](https://jfrog.com/help/r/jfrog-artifactory-documentation/maven-repository)
and Red Hat’s
[Configure your Java build tool](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_java_build_tool).

---

## After the jar resolves

Artifactory makes the remediated jar *available*. It does not tell you whether adopting it
is safe for *your* application, or which tests the bump owes. That grade is upgrade-delta,
a separate project.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Version rejected / not found | Artifactory naming policy vs `.rhlw-0000X`; confirm the GAV exists in the chosen tier URL |
| 401 / 403 from packages.redhat.com | Production service-account format and token; Enable Token Authentication must stay cleared |
| Empty catalog in UI | **List Remote Artifacts** checked; fetch once so the remote caches |
| CI still hits packages.redhat.com | Client `settings.xml` / `pom` still lists the Lightwell URL instead of Artifactory |
| Demo auth fields won’t save blank | Use any placeholder string for public-demo; smoke-test a jar fetch before presenting |
| Jar fetch is Forbidden after a redirect | **Bypass HEAD Requests** must be checked. S3 presigned URLs reject HEAD |
| Copy says the S3 link has expired | Lightwell returned a cached redirect. The remote is already saved; re-run `scripts/copy-sample.sh` later |
| Script waits and prints clicks | The console API did not save the remote. Finish it in the UI, then re-run the script |
