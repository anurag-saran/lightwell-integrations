# Run Lightwell on this machine

One command starts Artifactory and Nexus, connects them to Lightwell, and copies the
small public catalog. Maven then fetches a jar from those local servers.

Click paths for a server you already run: [`ARTIFACTORY.md`](ARTIFACTORY.md),
[`NEXUS.md`](NEXUS.md). SonarQube is optional and does not fetch Lightwell jars
([`SONARQUBE.md`](SONARQUBE.md)).

## Before you start

- Install [Podman](https://podman.io/) and [Maven](https://maven.apache.org/).
- On a Mac, the first time only: `podman machine init --memory 8192`
- Give the Podman machine about **8 GB** of RAM. A 2 GB machine cannot run these servers.
- Run the scripts from this repository.
- If port 8081, 8082, or 8083 is already taken, the script names the container and stops. Stop that container, then run the script again.

## 1. Public demo

No Lightwell account and no token.

```bash
./scripts/setup-demo.sh
```

When it finishes, open these pages and log in as `admin` / `Lightwell-demo1`.
That password is only for this local demo. Do not reuse it on a shared server.

| | Address | What to open |
|---|---|---|
| Artifactory | http://127.0.0.1:8082/ui/ | Repository `lightwell-java` |
| Nexus | http://127.0.0.1:8083/ | Repository `lightwell-java` |

`lightwell-java` is the URL Maven uses. It searches `lightwell-java-remediated`, then
`lightwell-java-validated`. Python wheels, if you need them, are in
`lightwell-python-validated`.

The script copies the small public catalog. If one file says the S3 link has expired,
the other copies stay. The repositories are still created.

## 2. Ask Maven for a jar

From this repository:

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve
```

`BUILD SUCCESS` means Artifactory downloaded `commons-io` version `2.11.0.rhlw-00001`.
That library is only on the validated feed, so the search had to look past remediated.

[`samples/settings.xml`](samples/settings.xml) is the Artifactory login (`admin` /
`Lightwell-demo1`). It is not a Lightwell token.

The same jar through Nexus:

```bash
mvn -f samples/demo/pom.xml -s samples/settings.xml dependency:resolve \
  -Dlightwell.repo.url=http://127.0.0.1:8083/repository/lightwell-java
```

[`samples/prod/pom.xml`](samples/prod/pom.xml) resolves `snakeyaml` `1.33.0.rhlw-00001`.
That version is on the public demo, so this command works after the demo setup too.
After the production setup below, change `lightwell.version` in that file to the
build you are adopting.

## 3. Production account

Skip this section if you are only trying the public demo.

```bash
./scripts/setup-prod.sh
```

The script asks for the Lightwell user (`XXXXXXX|service-account-name`) and the token.
It does not print the token, and it does not write the token into this git repository.
The token is stored on the Artifactory remotes and the Nexus proxies.

The repository names stay the same. The feeds change to:

- `https://packages.redhat.com/lightwell/java/predisclosure/`
- `https://packages.redhat.com/lightwell/java/remediated/`
- `https://packages.redhat.com/lightwell/java/validated/`

`lightwell-java` then searches predisclosure, then remediated, then validated.
The production catalog is not copied. The first Maven request for a version stores
that jar.

## Names you will see

| Name | What it is |
|---|---|
| `lightwell-java-remediated` | Connection to the remediated feed |
| `lightwell-java-validated` | Connection to the validated feed |
| `lightwell-java-predisclosure` | Production only. The public demo does not have this feed |
| `lightwell-java` | The one URL Maven uses. Artifactory calls it a virtual repository. Nexus calls it a group |
| `lightwell-python-validated` | Public-demo Python wheels. Created by `setup-demo.sh` |

`setup-artifactory.sh` and `setup-nexus.sh` are the scripts the two commands above
call. You do not need to run them yourself.

## Optional: SonarQube

```bash
./scripts/setup-sonarqube.sh
```

Open http://127.0.0.1:9000/ and log in as `admin` / `Lightwell-demo1`. SonarQube checks
your application code. It does not connect to Lightwell.

## Stop

```bash
podman stop lightwell-artifactory lightwell-nexus lightwell-sonarqube
```

Data is kept. Running a setup script again starts the existing servers.

## If you are on RHEL

A boot ISO does not contain these tools. Finish the OS install, then
`sudo dnf install -y podman`, and run `./scripts/setup-demo.sh` from this repository.

Nexus uses port **8083** so Artifactory can keep **8081** and **8082**. The setup
script allows Artifactory’s bundled database for this demo. A shared Artifactory
server should use PostgreSQL.
