# Integrate Lightwell with JFrog Artifactory

After these steps, `lightwell-remote` on your Artifactory server can fetch a Lightwell
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
   | Repository Key | `lightwell-remote` | `lightwell-remote` (or `lightwell-remote-demo`) |
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
   | **Metadata Retrieval Cache Period** | `600` seconds | How soon a newly published `.rhlw` version can show up in `maven-metadata.xml` |
   | **Missed Retrieval Cache Period** | `600` seconds | A version that was missing is retried within 10 minutes |
   | Retrieval cache for release jars | leave the default (hours) | A release file does not change once it is copied |

   Leave every other field at its default.

Artifactory OSS blocks creating this remote over REST (that API is Pro-only). Use the
clicks above. `scripts/setup-artifactory.sh` starts the server, prints the clicks, waits
a few minutes for you to save `lightwell-remote`, then copies a sample jar.

---

## Verify

With Artifactory running and `lightwell-remote` saved:

```bash
./scripts/copy-sample.sh artifactory
```

Success is HTTP 200 and a non-empty file under `.local/integrations/` (the script prints
the path). That file is the local copy. The same jar is now in the Artifactory cache.
Open `lightwell-remote` in the UI and you should see `spring-core` after this fetch.

If the public-demo remote fails with empty credentials, try a non-empty placeholder in
User Name / Password. The demo path does not validate credentials for anonymous fetches,
but some Artifactory UIs reject blank auth fields.

---

## How it stays in sync

Lightwell publishes a new build. After the metadata cache period (10 minutes with the
settings above), a build that asks for that version copies it into Artifactory. Nothing
rewrites your `pom.xml`. You do not recreate `lightwell-remote` to sync, and re-running
the setup script does not download the catalog.

---

## Point Maven at Artifactory

After the remote caches successfully, configure clients to use **your Artifactory URL**,
not packages.redhat.com directly. Follow JFrog’s
[Connect your Maven Client to Artifactory](https://jfrog.com/help/r/jfrog-artifactory-documentation/maven-repository)
and Red Hat’s
[Configure your Java build tool](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_java_build_tool).

Put Lightwell auth on Artifactory and keep CI `settings.xml` pointed at Artifactory only.

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
| Script says the create API is Pro-only | Expected on Artifactory OSS — finish the remote in the UI |
