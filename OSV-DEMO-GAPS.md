# Public demo OSV gaps (for Lightwell eng)

Checked: **2026-09-23** (UTC). Anonymous public demo only.

Share this file: [OSV-DEMO-GAPS.md on main](https://github.com/anurag-saran/lightwell-integrations/blob/main/OSV-DEMO-GAPS.md).

## Summary

- Public-demo OSV covers **remediated Java** (validated OSV is out of scope for this report).
- Not every published remediated jar has an OSV `fixed` event that matches that jar.
- Each OSV document is a CVE advisory (`aliases`, `fixed` version, `golden_pipeline_id`). It is **not** a full SBOM of what went into the build.

## Feeds to open

| Feed | URL | HTTP on check |
|---|---|---|
| Remediated Maven | [java/remediated/](https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/) | 200 |
| Validated Maven | [java/validated/](https://packages.redhat.com/lightwell/public-lightwell-demo/java/validated/) | 200 |
| Remediated OSV | [osv/java/remediated/](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/) | 200 (11 JSON files) |

## Issue A — spring-core: published build ≠ OSV `fixed`

| Expected | Actual |
|---|---|
| Demo Maven and OSV name the same `.rhlw` build for `spring-core` | Maven publishes `5.3.18.rhlw-00003`. OSV says the CVE is fixed in `5.3.18.rhlw-00010`, which is **not** on the demo feed. |

Click to reproduce:

| What | Link | HTTP |
|---|---|---|
| Maven metadata (only `rhlw-00003`) | [spring-core/maven-metadata.xml](https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/org/springframework/spring-core/maven-metadata.xml) | 200 |
| Published pom | [spring-core-5.3.18.rhlw-00003.pom](https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/org/springframework/spring-core/5.3.18.rhlw-00003/spring-core-5.3.18.rhlw-00003.pom) | 200 |
| OSV for CVE-2025-41249 (`fixed: 5.3.18.rhlw-00010`) | [x_RHLW-CVE-2025-41249-5.3.18.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2025-41249-5.3.18.json) | 200 |
| OSV-named build (missing) | [spring-core-5.3.18.rhlw-00010.pom](https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/org/springframework/spring-core/5.3.18.rhlw-00010/spring-core-5.3.18.rhlw-00010.pom) | **404** |

**Ask:** publish `5.3.18.rhlw-00010` on the public remediated demo feed, **or** change the OSV `fixed` event to the published `5.3.18.rhlw-00003` if that build is the intended fix.

## Issue B — Spring OSV points at packages not on the demo Maven feed

These remediated OSV documents claim `fixed: 5.3.18.rhlw-00010` on `spring-webmvc` or `spring-expression`. Neither GAV appears on the public remediated Maven index.

| CVE | OSV JSON | `fixed` package@version | Missing Maven pom (404) |
|---|---|---|---|
| CVE-2023-20860 | [x_RHLW-CVE-2023-20860-5.3.18.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2023-20860-5.3.18.json) | `org.springframework:spring-webmvc@5.3.18.rhlw-00010` | [spring-webmvc … rhlw-00010.pom](https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/org/springframework/spring-webmvc/5.3.18.rhlw-00010/spring-webmvc-5.3.18.rhlw-00010.pom) |
| CVE-2023-20861 | [x_RHLW-CVE-2023-20861-5.3.18.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2023-20861-5.3.18.json) | `org.springframework:spring-expression@5.3.18.rhlw-00010` | [spring-expression … rhlw-00010.pom](https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/org/springframework/spring-expression/5.3.18.rhlw-00010/spring-expression-5.3.18.rhlw-00010.pom) |
| CVE-2023-20863 | [x_RHLW-CVE-2023-20863-5.3.18.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2023-20863-5.3.18.json) | `org.springframework:spring-expression@5.3.18.rhlw-00010` | same as above |
| CVE-2024-38808 | [x_RHLW-CVE-2024-38808-5.3.18.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2024-38808-5.3.18.json) | `org.springframework:spring-expression@5.3.18.rhlw-00010` | same as above |
| CVE-2024-38816 | [x_RHLW-CVE-2024-38816-5.3.18.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2024-38816-5.3.18.json) | `org.springframework:spring-webmvc@5.3.18.rhlw-00010` | same webmvc 404 |

**Ask:** either publish those Spring modules (and `rhlw-00010`) on the public remediated demo, or drop / retarget these OSV docs so every `fixed` GAV resolves on the same demo feed.

## What matches today

These remediated jars have an OSV `fixed` event equal to the published version.

| GAV | CVE | OSV | Artifact |
|---|---|---|---|
| `com.fasterxml.woodstox:woodstox-core:6.0.3.rhlw-00001` | CVE-2022-40152 | [x_RHLW-CVE-2022-40152-6.0.3.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2022-40152-6.0.3.json) | [pom](https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/com/fasterxml/woodstox/woodstox-core/6.0.3.rhlw-00001/woodstox-core-6.0.3.rhlw-00001.pom) |
| `com.jayway.jsonpath:json-path:2.7.0.rhlw-00001` | CVE-2023-51074 | [x_RHLW-CVE-2023-51074-2.7.0.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2023-51074-2.7.0.json) | [pom](https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/com/jayway/jsonpath/json-path/2.7.0.rhlw-00001/json-path-2.7.0.rhlw-00001.pom) |
| `com.jayway.jsonpath:json-path:2.8.0.rhlw-00001` | CVE-2023-51074 | [x_RHLW-CVE-2023-51074-2.8.0.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2023-51074-2.8.0.json) | [pom](https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/com/jayway/jsonpath/json-path/2.8.0.rhlw-00001/json-path-2.8.0.rhlw-00001.pom) |
| `org.json:json:20220320.0.0.rhlw-00003` | CVE-2022-45688 | [x_RHLW-CVE-2022-45688-20220320.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2022-45688-20220320.json) | [pom](https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/org/json/json/20220320.0.0.rhlw-00003/json-20220320.0.0.rhlw-00003.pom) |
| `org.json:json:20220320.0.0.rhlw-00003` | CVE-2023-5072 | [x_RHLW-CVE-2023-5072-20220320.json](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2023-5072-20220320.json) | same pom |

## What OSV contains vs what it does not

Present in each remediated OSV JSON (example: [woodstox CVE JSON](https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/x_RHLW-CVE-2022-40152-6.0.3.json)):

- `aliases` (CVE / GHSA)
- `affected[].package` + `ranges[].events[].fixed` (the `.rhlw` version that claims the fix)
- `database_specific.lightwell.backport_base_version`
- `database_specific.lightwell.golden_pipeline_id`

Not present:

- A full dependency SBOM / bill of materials for everything that went into the build

## Requested eng actions

1. **Issue A:** Align `spring-core` Maven and OSV (`rhlw-00003` vs `rhlw-00010`).
2. **Issue B:** Publish `spring-webmvc` / `spring-expression` `5.3.18.rhlw-00010` on the remediated demo, or retarget those five OSV docs.
3. **Invariant for demos:** every OSV `fixed` GAV on the public demo should resolve with HTTP 200 on the matching Maven feed.
