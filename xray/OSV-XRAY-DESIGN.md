# Technical design: Lightwell OSV → JFrog (Xray on Artifactory)

This document describes how Red Hat Lightwell OSV advisories are synced onto a
JFrog Platform that already stores Lightwell jars in Artifactory. It is the
design behind [`lightwell-xray-sync`](.). Operator steps are in
[`GUIDE.md`](GUIDE.md). Repository layout for the jars is in
[`../artifactory/README.md`](../artifactory/README.md).

## 1. What is synced, and where it lands

Lightwell publishes two independent feeds. They are not the same API, and this
kit does not merge them into one Artifactory call.

| Plane | What it carries | Who consumes it | Stored as |
|---|---|---|---|
| **Maven** | `.jar` / `.pom` bytes, including `…rhlw-NNNN` builds | Artifactory **remote** repositories | Cached artifacts in `lightwell-java-*`, exposed through the org virtual |
| **OSV** | CVE text, CVSS, affected coordinates, and the `.rhlw` version that claims the fix | `lightwell-xray-sync` | **Xray Custom Issues** (`provider=Lightwell`) |

Artifactory does not have an OSV ingest API. Vulnerability metadata on this
platform lives in **Xray**, which indexes artifacts that Artifactory already
holds. The sync tool therefore:

- **Reads** the Lightwell OSV HTTP index.
- **Writes** JFrog Xray `POST` / `PUT /xray/api/v1/events`.
- **Does not** call the Artifactory repository API, set artifact properties, or
  create watches and policies.

Once a Custom Issue exists, Xray applies it to Maven artifacts in watched
Artifactory repositories by package type, `groupId:artifactId`, and version
range. A build that still resolves `json-path` `2.7.0` from `maven-central`
can be flagged. The same coordinate at `2.7.0.rhlw-00001`, cached from the
Lightwell remote, is the `fixed_versions` entry on that issue.

Artifactory OSS (the local/OpenShift demo image) usually has **no Xray**. The
sync needs a JFrog Platform instance with Xray licensed and the Custom Issues
API enabled.

```
Lightwell OSV index                         JFrog Platform
─────────────────────                       ──────────────────────────────
GET …/osv/java/remediated/                  Xray
        │                                   POST /xray/api/v1/events
        ▼                                   PUT  /xray/api/v1/events/{id}
 lightwell-xray-sync  ──────────────────►   Custom Issue (provider=Lightwell)
 (map OSV → event)                                │
                                                  │ match component + version
Lightwell Maven feed                              ▼
GET …/java/remediated/…jar          Artifactory remote cache
        │                           (lightwell-java-remediated, …)
        ▼                                    │
 org virtual acmebank_java_repo  ◄───────────┘
        │                           Xray watch + existing severity policy
        ▼
 Maven build
```

## 2. Components

| Piece | Role |
|---|---|
| Lightwell OSV index | Directory of OSV JSON documents. Public demo needs no credential. |
| `lightwell_xray_sync.load` | GET the index. If the body is HTML, follow every `href` ending in `.json`. |
| `lightwell_xray_sync.cvss` | Turn a CVSS v3 vector into a base score and a Xray severity word. |
| `lightwell_xray_sync.map` | One OSV document → one or more Custom Issue JSON bodies. |
| `lightwell_xray_sync.client` | Authenticated POST (create) and PUT (update). |
| `lightwell_xray_sync.sync` | Orchestration, 50 ms pause between writes, `xray-sync-summary.json`. |
| Artifactory remotes | Separate path. Cache Lightwell Maven bytes. Configured per [`../artifactory/README.md`](../artifactory/README.md), not by this CLI. |
| Xray watches / policies | Customer-owned. The tool does not create them. Existing severity policies apply to `provider=Lightwell` issues. |

Commands:

| Command | Source of advisories | Xray write |
|---|---|---|
| `lightwell-xray-sync sync` | `LIGHTWELL_OSV_URL`, else `--url`, else the public-demo remediated index | Yes |
| `lightwell-xray-sync push --input PATH` | Local file or directory of `*.json` | Yes |
| `lightwell-xray-sync dry-run` | URL or `--input` | No. Optional `--print-payloads`. |
| `lightwell-xray-sync self-test` | In-process fixture | No network. |

## 3. Sync sequence

1. Resolve the OSV URL (`--url`, then `LIGHTWELL_OSV_URL`, then the public-demo default).
2. `GET` that URL with a `requests` session (3 retries, backoff 0.8 s, retry on 429 and 5xx).
3. If the response is HTML, collect `*.json` links and `GET` each one. If it is JSON, accept one document, a list, or a wrapper whose `advisories`, `vulns`, or `results` array holds documents.
4. For each document, build Custom Issue payloads. A document that fails mapping is counted `map_failed` and the run continues.
5. Unless `--dry-run`: for each payload, `POST /xray/api/v1/events`. HTTP 200/201 is `created`. HTTP 409, or HTTP 400 whose body says the id already exists, is followed by `PUT /xray/api/v1/events/{id}` (body omits `id`). 200/201/204 is `updated`. Anything else is `push_failed`.
6. Sleep 50 ms between pushes.
7. Write `xray-sync-summary.json` (`created`, `updated`, `dry_run`, `failed`, `advisories`, per-issue status). Exit `0` only when `failed` is 0 and at least one advisory was loaded.

Re-running `sync` is the update path. Issue ids are stable, so the second run updates the same Custom Issue. The tool does **not** delete an issue that has disappeared from the feed.

## 4. Lightwell APIs

### 4.1 OSV index (this sync)

| | Public demo (default) | Production |
|---|---|---|
| Method | `GET` | `GET` of the URL you set |
| URL | `https://packages.redhat.com/api/pulp-content/public-lightwell-demo/osv/java/remediated/` | `LIGHTWELL_OSV_URL` (entitled feed; not hardcoded) |
| Auth | None | Whatever that endpoint requires. This CLI does not attach a Lightwell token on the OSV GET. |
| Body | HTML directory listing, then one OSV JSON file per `href` | Same shapes: HTML index or JSON |
| Scope of the default | Java **remediated** advisories only. Validated and predisclosure OSV are not fetched unless you point `--url` at them. | Same tool; different URL. |

Each file is an [OSV](https://ossf.github.io/osv-schema/) document. Fields this mapper reads:

| OSV field | Used |
|---|---|
| `id` | Required. Becomes the Xray issue id. |
| `summary`, `details` | Summary line and description body. |
| `severity[].type` / `severity[].score` | CVSS v3 vector, or a numeric score string. Highest score wins. |
| `aliases` | Only values starting with `CVE-`. |
| `affected[].package.ecosystem` | Mapped to Xray `package_type`. |
| `affected[].package.name` | Maven coordinate `groupId:artifactId` (also the Xray component `id`). |
| `affected[].versions` | Explicit vulnerable versions. |
| `affected[].ranges[].events[]` | `introduced` and `fixed`. |

Fields present on the public-demo documents that are **not** copied into Xray:

| OSV field | Why it is dropped |
|---|---|
| `aliases` that are not `CVE-*` (for example `GHSA-…`) | Xray `cves` / `sources` are filled from CVE aliases only. |
| `references`, `credits`, `modified`, `schema_version` | Not part of the Custom Issue body. |
| `affected[].package.purl` | Name + ecosystem are enough for the Maven component id. |
| `database_specific.lightwell.backport_base_version` | Not sent. The fixed version string is what Xray matches. |
| `database_specific.lightwell.golden_pipeline_id` | Not sent. |
| `database_specific.lightwell.source` | Not sent. |

### 4.2 Maven feed (Artifactory remotes, not this CLI)

Artifactory pulls bytes. The sync CLI never calls these URLs.

| Mode | Remote URL |
|---|---|
| Public demo, remediated | `https://packages.redhat.com/lightwell/public-lightwell-demo/java/remediated/` |
| Public demo, validated | `https://packages.redhat.com/lightwell/public-lightwell-demo/java/validated/` |
| Production | `https://packages.redhat.com/lightwell/java/{predisclosure,remediated,validated}/` with the Lightwell service account on the remote |

A request for `com.jayway.jsonpath:json-path:2.7.0.rhlw-00001` is a normal Maven path under that remote:

```text
com/jayway/jsonpath/json-path/2.7.0.rhlw-00001/json-path-2.7.0.rhlw-00001.jar
```

Artifactory stores the first successful GET in the remote cache. Later builds hit the cache. The org virtual `acmebank_java_repo` searches `lightwell-java` (remediated, then validated) before `maven-central`, so a `.rhlw` version resolves from Lightwell and an ordinary Central version still falls through.

Production Lightwell credentials belong on those Artifactory remotes. They are not environment variables of `lightwell-xray-sync`.

## 5. Mapping: OSV document → Xray Custom Issue

One OSV document becomes one Custom Issue per package type. A Maven-only advisory (the public demo) becomes one event. If `affected` lists two ecosystems, the tool emits two events and suffixes the issue id with the package type so the ids stay unique.

### 5.1 Issue identity and classification

| Xray field | Rule |
|---|---|
| `id` | OSV `id`, then strip characters outside `[A-Za-z0-9_.:\-+]`. If the id starts with `xray` (any case), prefix `LW-` because Xray reserves that prefix. If the document maps to more than one package type, append `-maven`, `-pypi`, and so on. |
| `type` | Always `Security`. |
| `provider` | Always `Lightwell`. |
| `package_type` | From `affected[].package.ecosystem`. See the table below. |
| `summary` | OSV `summary`, else the first line of `details` (max 200 chars), else the OSV id. Truncated to 512 characters. |
| `description` | `details`, then `CVSS v3 vector: …` when a vector was parsed, then `Lightwell fixed builds: [ver], …`. |
| `sources` | `{ "source_id": "<CVE>" }` for each CVE alias. If there is no CVE alias, one source whose id is the OSV id. |
| `properties.lightwell_osv_id` | Original OSV `id` (before the package-type suffix). |
| `properties.lightwell_cvss_vector` | Raw CVSS v3 vector, or `""`. |

Ecosystem → `package_type`:

| OSV `ecosystem` (case-insensitive) | Xray `package_type` |
|---|---|
| `Maven` | `maven` |
| `PyPI` | `pypi` |
| `npm` | `npm` |
| `Go`, `Golang` | `go` |
| `NuGet` | `nuget` |
| `RubyGems` | `gems` |
| `crates.io`, `Cargo` | `cargo` |
| `Debian` | `debian` |
| `Alpine` | `alpine` |
| `Docker` | `docker` |
| `generic`, empty, or anything else | `generic` |

### 5.2 Severity

`severity` on the Custom Issue is a Xray qualitative word, not the vector.

| CVSS v3 base score | `severity` |
|---|---|
| missing | `Medium` |
| `0` or `< 4.0` | `Low` |
| `< 7.0` | `Medium` |
| `< 9.0` | `High` |
| `>= 9.0` | `Critical` |

The vector is parsed locally (`AV`, `AC`, `PR`, `UI`, `S`, `C`, `I`, `A`). When several `severity` entries exist, the highest base score is kept. A numeric `score` string is accepted as the score with no vector.

`cves[]` (only when at least one CVE alias exists, or when there is a score and no alias):

| Xray field | Rule |
|---|---|
| `cves[].cve` | The `CVE-*` alias. If the document has a score but no CVE alias, this is the OSV id when it already starts with `CVE-`, otherwise `LW-` + OSV id. |
| `cves[].cvss_v3` | Base score as a short decimal string (`7.5`), included only when a score was parsed. The vector itself is not placed here. |

### 5.3 Components and versions

Each `affected[]` entry with a package name becomes one object in `components`. Entries with neither a vulnerable range nor a Lightwell fixed version are skipped. If every entry is skipped, mapping fails for that document.

| Xray field | Rule |
|---|---|
| `components[].id` | `affected.package.name`, unchanged. For Maven that is `groupId:artifactId`. |
| `components[].vulnerable_versions` | See below. If nothing was derived, `[0,]` (all versions) when a Lightwell fixed version still exists. |
| `components[].fixed_versions` | Present only when at least one fixed version matches `\.(rhlw\|redhat)-<digits>` at the end of the version. |

Version strings are wrapped in Xray range brackets. A bare version `1.2.3` is sent as `[1.2.3]` (that version only).

| OSV input | Xray `vulnerable_versions` entry | Also `fixed_versions`? |
|---|---|---|
| `versions: ["2.7.0"]` | `[2.7.0]` | No |
| range event `introduced` + `fixed` | `[introduced,fixed)` | Only if `fixed` ends in `.rhlw-N` or `.redhat-N`, and then as `[fixed]` |
| `introduced` set, no `fixed` | `[introduced,)` | No |
| `introduced` omitted | Treated as `0`, so `[0,fixed)` when `fixed` is set | Same rule as above |
| `fixed` is a community version such as `2.8.0` | Upper bound of the vulnerable range | **No.** Only Lightwell rebuild suffixes are recorded as the fix. |

A single range walks events in order and keeps the last `introduced` and the last `fixed` in that range. Multiple ranges on one package append more vulnerable strings. Duplicates are removed, order preserved.

## 6. Xray Custom Issues API

Base URL from `JFROG_URL` with no trailing slash.

| `JFROG_URL` | Events collection |
|---|---|
| `https://acme.jfrog.io` | `https://acme.jfrog.io/xray/api/v1/events` |
| `https://acme.jfrog.io/xray` | `https://acme.jfrog.io/xray/api/v1/events` |

Auth, from the environment. There are no CLI flags for the token.

| Variables | Request |
|---|---|
| `JFROG_URL` + `JFROG_TOKEN` | `Authorization: Bearer <token>` |
| those, plus `JFROG_USER` | HTTP Basic (`JFROG_USER` / `JFROG_TOKEN`), no Bearer header |

The token needs permission to manage Xray metadata (Custom Issues). Prefer a short-lived identity token.

| Call | When | Body | Success |
|---|---|---|---|
| `POST {events}` | First time this issue id is seen | Full payload, including `id` | `200` or `201` → `created` |
| `PUT {events}/{id}` | POST returned `409`, or `400` and the body contains `already` or `exist` | Same payload **without** `id` | `200`, `201`, or `204` → `updated` |

Headers on both calls: `Content-Type: application/json`, `Accept: application/json`. Timeout default 60 s (`--timeout`). Transport retries: 3 attempts on 429, 500, 502, 503, 504 for GET, POST, and PUT.

Other HTTP statuses fail that issue and the loop continues. Exit status of the process is non-zero if any issue failed.

## 7. How this shows up on Artifactory artifacts

The Custom Issue is global Xray metadata. It is not an Artifactory property on the jar and it is not a file in the remote cache.

Xray associates it with an artifact when all of the following are true:

1. The artifact lives in an Artifactory repository that an Xray **watch** covers. This kit does not create that watch.
2. Xray has indexed the artifact (Maven `package_type`).
3. The component id matches, for example `com.jayway.jsonpath:json-path`.
4. The artifact version falls in `vulnerable_versions` and is not the bracketed `fixed_versions` entry.

Typical layout after both planes are configured:

| Artifactory repository | Type | What Xray can see there |
|---|---|---|
| `lightwell-java-remediated` | Remote cache of the Lightwell remediated Maven feed | `.rhlw` builds. These versions are the fix strings. |
| `lightwell-java-validated` | Remote cache of the validated feed | Validated drop-in rebuilds. They are on the Maven plane only, unless you also sync a validated OSV URL. |
| `lightwell-java` | Virtual: remediated, then validated | Resolve view. Watches are usually placed on the repos that actually store files. |
| `maven-central` | Remote | Community versions that the vulnerable range is meant to flag. |
| `acmebank_java_repo` | Virtual: `lightwell-java`, then Central | The URL Maven uses. A `.rhlw` coordinate is fetched into the Lightwell remote; a community coordinate is fetched from Central. |

Policies stay the customer's existing severity rules. There is no Lightwell-specific policy type. A High Custom Issue is subject to the same gate as any other High issue.

Version ordering is Xray's. The tool sends Maven ranges exactly as derived above (`[0,2.7.0.rhlw-00001)` vulnerable, `[2.7.0.rhlw-00001]` fixed). It does not rewrite those strings to a community version, and it does not ask Artifactory whether that `.rhlw` file exists. If OSV names a build the Maven feed does not publish, Xray still records the fix and Artifactory returns 404 on resolve. That split is tracked for the public demo in [`OSV-DEMO-GAPS.md`](OSV-DEMO-GAPS.md).

## 8. Worked example

Public-demo document `x_RHLW-CVE-2023-51074-2.7.0` (json-path), reduced to the fields the mapper reads:

```json
{
  "id": "x_RHLW-CVE-2023-51074-2.7.0",
  "details": "json-path v2.8.0 was discovered to contain a stack overflow via the Criteria.parse() method.",
  "aliases": ["GHSA-pfh2-hfmq-phg5", "CVE-2023-51074"],
  "affected": [{
    "package": {
      "ecosystem": "Maven",
      "name": "com.jayway.jsonpath:json-path"
    },
    "ranges": [{
      "type": "ECOSYSTEM",
      "events": [
        {"introduced": "0"},
        {"fixed": "2.7.0.rhlw-00001"}
      ]
    }]
  }]
}
```

That file has no `severity` block, so the issue is `Medium` and `cvss_v3` is omitted. `GHSA-pfh2-hfmq-phg5` is dropped. The POST body is:

```json
{
  "id": "x_RHLW-CVE-2023-51074-2.7.0",
  "type": "Security",
  "provider": "Lightwell",
  "package_type": "maven",
  "severity": "Medium",
  "summary": "json-path v2.8.0 was discovered to contain a stack overflow via the Criteria.parse() method.",
  "description": "json-path v2.8.0 was discovered to contain a stack overflow via the Criteria.parse() method.\n\nLightwell fixed builds: [2.7.0.rhlw-00001]",
  "components": [{
    "id": "com.jayway.jsonpath:json-path",
    "vulnerable_versions": ["[0,2.7.0.rhlw-00001)"],
    "fixed_versions": ["[2.7.0.rhlw-00001]"]
  }],
  "sources": [{ "source_id": "CVE-2023-51074" }],
  "cves": [{ "cve": "CVE-2023-51074" }],
  "properties": {
    "lightwell_osv_id": "x_RHLW-CVE-2023-51074-2.7.0",
    "lightwell_cvss_vector": ""
  }
}
```

The same CVE at the 2.8.0 line is a **different** OSV id (`x_RHLW-CVE-2023-51074-2.8.0`) and therefore a second Custom Issue, with `fixed_versions` `[2.8.0.rhlw-00001]`.

When the OSV document includes a CVSS v3 vector, the mapper scores it and sets both `severity` and `cves[].cvss_v3`. The offline fixture uses `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H`, which scores **7.5** and is sent as severity **High**. The vector is appended to `description` and stored in `properties.lightwell_cvss_vector`.

On the Artifactory side, a resolve of `com.jayway.jsonpath:json-path:2.7.0.rhlw-00001` through `acmebank_java_repo` is a cache fill of `lightwell-java-remediated` from the Maven feed. It is not produced by the OSV POST. Xray then treats that cached version as the fix on the Custom Issue above, and treats earlier versions of the same component as vulnerable, for any watch that includes the repository where those binaries sit.

## 9. Operations

| Topic | Behavior |
|---|---|
| Cadence | Weekly is enough for the public demo. Daily if the entitled feed moves often. Examples: `xray/examples/github-actions.yml`, `gitlab-ci.yml`, `cronjob.yaml` (Mondays 06:00). |
| Concurrency | The CronJob sets `concurrencyPolicy: Forbid`. Overlapping syncs are not coordinated inside the CLI. |
| Summary | `xray-sync-summary.json` next to the process working directory, unless `--no-summary` or `--summary PATH`. |
| Dry run | Loads and maps. Prints payloads only with `--print-payloads`. Does not read `JFROG_*`. |
| Stale issues | Not deleted. Close or delete them in Xray if an advisory is withdrawn. |
| Partial failure | One bad document does not stop the rest. Non-zero exit if any `failed` count is non-zero. |
| Secrets | `JFROG_TOKEN` is a CI secret. Lightwell Maven credentials stay on Artifactory remotes. The public-demo OSV GET uses neither. |

## 10. Out of scope

- Creating Artifactory remotes, virtual repositories, or the Bypass-HEAD / cache settings those remotes need.
- Opening GitHub or GitLab pull requests. That is the SCM plugin, which reads the same catalog to propose pom bumps.
- Uploading jars into Artifactory. Builds populate the remote cache on demand.
- Creating Xray watches, policies, or curation rules.
- Mirroring `database_specific.lightwell` pipeline ids into Xray.
- Syncing anything other than the URL you give it. The default is one index: public-demo Java remediated OSV.
