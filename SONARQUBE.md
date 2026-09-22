# Compose SonarQube with a dependency-upgrade grade

There is **no native SonarQube / SonarCloud plugin** that grades a Lightwell dependency
bump. Do not hunt for one in Marketplace. This guide explains how Sonar sits next to
that grade.

upgrade-delta is a separate project. It answers which tests a jar change owes. This
repository does not include it. Index: [`README.md`](README.md).

---

## Who owns what

| Concern | Owner |
|---|---|
| App code smells, duplication, security hotspots, line/branch coverage *trends* | **SonarQube / SonarCloud** quality gate |
| Dependency upgrade delta ∩ *your* bytecode → which tests this bump owes, with reasons | **upgrade-delta** (separate project) |
| Per-test coverage map for that router | Nightly **JaCoCo** → a `coverage.json` produced from the same Surefire run |

Sonar answers “is *our* code healthy?” The upgrade grade answers “given *this jar
change*, what testing do we owe?” Neither replaces the other.

---

## Do not confuse Sonar coverage with an upgrade grade

Sonar’s coverage percentage is a project health metric. An upgrade letter grade measures
how much a *library* changed and whether that change is reachable from your app.
JaCoCo line coverage is not that grade.

Treat Sonar “Coverage” and an upgrade scorecard as different documents for different
audiences (eng quality vs. change board).

---

## Shared nightly pattern (one build, two consumers)

A single nightly (or weekly) `mvn test` with JaCoCo can feed both:

1. Run your usual Surefire suite with the JaCoCo agent. Per-test attribution (a fresh JVM
   per test class) is what a router needs if it joins coverage to changed methods.
2. **Sonar:** publish that build’s coverage report via the SonarScanner / Maven Sonar plugin.
3. **Upgrade router:** turn the per-test exec data into `coverage.json`, keep the embedded
   git SHA, and publish the file where the router fetches it.

You pay the nightly cost once. Sonar keeps trend charts. Do not strip the SHA — staleness
checks depend on it. Sonar’s coverage export is not a substitute for that per-test map.

---

## Deploy / merge gate composition

Require **both** gates on dependency-upgrade pull requests:

| Gate | Fails when |
|---|---|
| Sonar quality gate | New code smells, coverage drop, security issues per your Sonar policy |
| Upgrade grade / deploy gate | The bump’s obligations are not met |

A green Sonar run does not clear a failing upgrade grade, and a green upgrade scorecard
does not waive Sonar.

---

## Out of scope

- Publishing upgrade letter grades as custom Sonar metrics or Quality Gate conditions.
- Replacing Sonar for general code review.
- Using Sonar coverage alone as the router’s per-test map.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Looking for an upgrade plugin in Sonar Marketplace | Expected miss — compose gates instead |
| Sonar coverage up, upgrade scorecard still failing | Different questions — library delta vs. app trends |
| Router says coverage is stale | Nightly map SHA vs. app commit; regenerate `coverage.json` |
| Double CI cost | Share one JaCoCo-bearing nightly; don’t run full per-test forks on every PR |
