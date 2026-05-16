# pubspec.yaml constrains SDK to >=3.0.0 (different from zt-server)
FROM dart:stable AS builder
WORKDIR /app

COPY pubspec.yaml ./
COPY pubspec.lock* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline \
 && dart compile exe bin/main.dart -o /out/indexer

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /out/indexer ./indexer
CMD ["./indexer"]
