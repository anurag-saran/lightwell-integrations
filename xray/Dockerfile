# Customer image for scheduled Lightwell OSV → Xray Custom Issue sync.
# Build from this directory:
#   docker build -t lightwell-xray-sync:1.0 .
# Run:
#   docker run --rm -e JFROG_URL -e JFROG_TOKEN [-e JFROG_USER] [-e LIGHTWELL_OSV_URL] \
#     lightwell-xray-sync:1.0 sync
FROM python:3.12-slim-bookworm

WORKDIR /app
COPY pyproject.toml README.md ./
COPY src ./src
RUN pip install --no-cache-dir .

USER nobody
ENTRYPOINT ["lightwell-xray-sync"]
CMD ["sync"]
