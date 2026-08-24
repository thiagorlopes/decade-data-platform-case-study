FROM python:3.12-slim

ARG DUCKDB_VERSION=1.5.5
ARG TARGETARCH

WORKDIR /workspace

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl unzip make \
 && rm -rf /var/lib/apt/lists/*

RUN case "$TARGETARCH" in \
      amd64) DUCKDB_ARCH=linux-amd64 ;; \
      arm64) DUCKDB_ARCH=linux-arm64 ;; \
      *) echo "Unsupported arch: $TARGETARCH" && exit 1 ;; \
    esac \
 && curl -sL "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-${DUCKDB_ARCH}.zip" -o /tmp/duckdb.zip \
 && unzip /tmp/duckdb.zip -d /usr/local/bin/ \
 && rm /tmp/duckdb.zip \
 && chmod +x /usr/local/bin/duckdb

COPY requirements.txt /workspace/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

CMD ["/bin/bash"]
