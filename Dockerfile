FROM python:3.12-slim AS builder

ARG DUCKDB_VERSION=1.5.5
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends curl unzip \
 && rm -rf /var/lib/apt/lists/*

RUN case "$TARGETARCH" in \
      amd64) DUCKDB_ARCH=linux-amd64 ;; \
      arm64) DUCKDB_ARCH=linux-arm64 ;; \
      *) echo "Unsupported arch: $TARGETARCH" && exit 1 ;; \
    esac \
 && curl -sL "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-${DUCKDB_ARCH}.zip" -o /tmp/duckdb.zip \
 && unzip /tmp/duckdb.zip -d /out/

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --no-compile --prefix=/install -r /tmp/requirements.txt


FROM python:3.12-slim

# socat bridges the DuckDB UI (loopback-only HTTP server) to the published port
RUN apt-get update && apt-get install -y --no-install-recommends socat \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY --from=builder /install /usr/local
COPY --from=builder /out/duckdb /usr/local/bin/duckdb
RUN chmod +x /usr/local/bin/duckdb

CMD ["/bin/bash"]
