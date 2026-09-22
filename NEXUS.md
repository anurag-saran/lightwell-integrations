# Integrate Lightwell with Sonatype Nexus

Configure Nexus Repository Manager as a **Maven2 (proxy)** repository that fronts the
Lightwell Network feed, so builds resolve `.rhlw-*` artifacts through your centralized
Nexus instance.

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

`scripts/setup-nexus.sh` creates this proxy over the Nexus REST API (layout policy Strict).

---

## Verify

1. Open the new proxy repository in Nexus.
2. Request a known artifact — e.g. navigate toward `org/springframework/spring-core/` and
   confirm a `.rhlw-` jar is retrievable.
3. From a test Maven build that uses the Nexus group/proxy as its remote, resolve a GAV
   such as `com.jayway.jsonpath:json-path:2.8.0.rhlw-00001` when that version exists in
   the tier.

---

## Point Maven at Nexus

Configure clients to resolve through **your Nexus URL** (proxy or group), not
packages.redhat.com directly. See Red Hat’s
[Configure your Java build tool](https://docs.redhat.com/en/documentation/lightwell_network/current/configure-configure_java_build_tool).

Put Lightwell credentials on the proxy and keep CI pointed at Nexus only.

---

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
