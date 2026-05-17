# pubspec.yaml constrains SDK to >=2.12.0 <3.0.0
FROM dart:2.19-sdk AS builder
WORKDIR /app

COPY pubspec.yaml ./
COPY pubspec.lock* ./
RUN dart pub get

COPY . .
RUN mkdir -p /out \
 && dart pub get --offline \
 && dart compile exe bin/main.dart -o /out/server

# Dart AOT exes need glibc; alpine/musl is not compatible.
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /out/server ./server
EXPOSE 8080
CMD ["./server"]
