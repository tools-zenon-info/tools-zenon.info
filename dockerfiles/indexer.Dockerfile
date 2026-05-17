# pubspec.yaml constrains SDK to >=3.0.0 (different from zt-server).
# Pinned to 3.5 because dart:stable (3.7+) made `Platform` abstract, breaking
# the transitive dcli_core 1.36.2 (pulled in via settings_yaml). The repo's
# pubspec.lock is gitignored, so each fresh `dart pub get` re-resolves and
# hits the broken version. Pinning the SDK is the smallest-footprint fix.
FROM dart:3.5-sdk AS builder
WORKDIR /app

COPY pubspec.yaml ./
COPY pubspec.lock* ./
RUN dart pub get

COPY . .
RUN mkdir -p /out \
 && dart pub get --offline \
 && dart compile exe bin/main.dart -o /out/indexer

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /out/indexer ./indexer
CMD ["./indexer"]
