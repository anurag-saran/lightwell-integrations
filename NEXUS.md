# Integrate Lightwell with Sonatype Nexus

After these steps, `lightwell-remote` on your Nexus server can fetch a Lightwell jar,
and that jar is stored on your server.

A **proxy** is the connection to Lightwell. The **cache** is the local copy made the
first time something requests a file. You still change `pom.xml` yourself when you want
a newer build.

Source procedure: [Configure Nexus to use the Lightwell Network repository](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_nexus_to_use_rhln_repository).
This guide adds the **public demo** URL mode. Index: [`README.md`](README.md).
Local Podman start: [`DEMO-LOCAL.md`](DEMO-LOCAL.md) and `scripts/setup-nexus.sh`.

---

## Before you begin

- Administrator access to Sonatype Nexus Repository Manager.
- For **production**: an active Lightwell Network membership and a
  [service account](https://docs.redhat.com/en/documentation/lightwell_network/current/get_started-create_a_red_hat_lightwell_network_service_account)
  (`XXXXXXX|service-account-name` + token).
- Chosen [repository tier](https://docs.redhat.com/en/documentation/lightwell_network/current/get_started-choose_the_right_repository)
  (Validated / Remediated / Predisclosure).

---

## Procedure

1. **Create a new repository** → type **Maven2 (proxy)**.
2. Set:

   | Field | Production | Public demo |
   |---|---|---|
   | Remote Storage | `https://packages.redhat.com/lightwell/java/remediated/` | `https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/` |
   | Layout Policy | **Strict** | **Strict** |

   The official doc calls out **Strict** specifically: *"to ensure proper resolution of
   `.rhlw` suffixes."* A loose layout policy can mis-resolve the vendor suffix.

   Also set:

   | Field | Value | Why |
   |---|---|---|
   | **Maximum metadata age** | `60` minutes | How soon a newly published `.rhlw` version can show up |
   | **Negative cache TTL** | `60` minutes | A version that was missing is retried within an hour |
   | Maximum component age for release jars | leave it long (hours or more) | A release file does not change once it is copied |

   Swap `remediated` for `validated` or `predisclosure` when needed. For multiple tiers,
   create separate proxies and combine them in a Nexus **group**, typically ordered
   Predisclosure → Remediated → Validated.

3. **Authentication** (production):

   | Field | Value |
   |---|---|
   | Username | `XXXXXXX\|service-account-name` |
   | Password | service-account token |

   For the **public demo** path, leave authentication empty if Nexus allows it. If the UI
   requires non-empty fields, use a placeholder and smoke-test a fetch.

`scripts/setup-nexus.sh` creates this proxy (layout **Strict**, metadata age 60 minutes,
negative cache 60 minutes, auto-block off) and then copies a sample jar through it.
Auto-block stays off so one stale Lightwell redirect does not take the proxy offline.
The script starts the Podman machine when it is stopped.

---

## Verify

With Nexus running:

```bash
./scripts/copy-sample.sh nexus
```

Success is HTTP 200 and a non-empty file under `.local/integrations/` (the script prints
the path). That file is the local copy. Browse `lightwell-remote` in Nexus and you should
see `spring-core` after this fetch. The setup script runs this command for you.

---

## Point Maven at Nexus

Configure clients to resolve through **your Nexus URL** (proxy or group), not
packages.redhat.com directly. See Red Hat’s
[Configure your Java build tool](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_java_build_tool).

Put Lightwell credentials on the proxy and keep CI pointed at Nexus only.

---

## How it stays in sync

Lightwell publishes a new build. After the metadata age (60 minutes with the settings
above), a build that asks for that version copies it into Nexus. Nothing rewrites your
`pom.xml`. You do not recreate `lightwell-remote` to sync, and re-running the setup
script does not download the catalog.

## After the jar resolves

Nexus makes the remediated jar *available*. It does not grade impact on *your* bytecode
or select the owed tests. That grade is upgrade-delta, a separate project.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Odd / missing `.rhlw-` versions | **Layout Policy** must be **Strict** |
| 401 / 403 from packages.redhat.com | Production username format (`orgId\|name`) and token on the proxy |
| Artifact not cached | Hit the proxy once from Maven; confirm Remote Storage URL ends with the correct tier |
| CI still hits packages.redhat.com | Client still lists the Lightwell URL instead of the Nexus proxy/group |
| Demo auth required by UI | Placeholder credentials + smoke-test before presenting |
| Copy says the S3 link has expired | Lightwell returned a cached redirect. The proxy stays online; re-run `scripts/copy-sample.sh nexus` later |
| Proxy is offline after one failed fetch | Re-run `scripts/setup-nexus.sh`. It clears a block and leaves auto-block off |
