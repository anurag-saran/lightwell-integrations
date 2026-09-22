# Integrate Lightwell with JFrog Artifactory

Configure Artifactory as a **remote Maven repository** that proxies the Lightwell Network
Java feed, so builds resolve `.rhlw-*` artifacts through your centralized Artifactory
instance instead of every job talking to packages.redhat.com.

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
6. Confirm **Enable Token Authentication** is **cleared**. Leave remaining fields at
   defaults.

Artifactory OSS blocks creating this remote over REST (that API is Pro-only). Use the UI
clicks above. `scripts/setup-artifactory.sh` starts the server and prints the same clicks
when the API refuses.

---

## Verify

1. Open the `lightwell-remote` repository in Artifactory’s browser.
2. Navigate to a known path, e.g. `org/springframework/spring-core/`, and confirm `.rhlw-`
   version directories appear (or cache after a first fetch).
3. From a test Maven build pointed at Artifactory, resolve a coordinate such as
   `org.springframework:spring-core:5.3.18.rhlw-00003` (adjust to a version that exists
   in your tier).

If the public-demo remote fails with empty credentials, try a non-empty placeholder in
User Name / Password. The demo path does not validate credentials for anonymous fetches,
but some Artifactory UIs reject blank auth fields.

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
