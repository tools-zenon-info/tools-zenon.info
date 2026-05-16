# Builds go-zenon (znnd) from source. No official upstream Docker image exists.
# Verify the build target name against https://github.com/zenon-network/go-zenon
# before pinning a release in production.
FROM golang:1.21-bookworm AS builder

ARG ZNND_GIT_REF=master
WORKDIR /src
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && git clone https://github.com/zenon-network/go-zenon.git . \
 && git checkout "${ZNND_GIT_REF}"

RUN CGO_ENABLED=0 go build -o /out/znnd ./cmd/znnd

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /root
COPY --from=builder /out/znnd /usr/local/bin/znnd

# 35995/tcp+udp: p2p; 35997: HTTP-RPC; 35998: WebSocket
EXPOSE 35995/tcp 35995/udp 35997/tcp 35998/tcp

CMD ["znnd", "--data", "/root/.znn"]
