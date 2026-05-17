# Angular 13 is incompatible with Node 18+ (OpenSSL legacy provider).
FROM node:16-bullseye AS builder
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

ARG ZT_API_URL
ARG COINGECKO_API_KEY
RUN sed -i "s|https://api.zenon.tools|${ZT_API_URL}|" src/environments/environment.prod.ts \
 && sed -i "s|COINGECKO_DEMO_KEY_PLACEHOLDER|${COINGECKO_API_KEY}|" src/environments/environment.prod.ts \
 && npm run build

FROM alpine:3.19
# Stage dist files at /src so the runtime CMD can overwrite the named volume
# mounted at /dist on every run. Without this, Docker only copies image
# content into the volume on FIRST mount; subsequent rebuilds never reach it.
COPY --from=builder /app/dist/zenon-tools /src
CMD ["sh", "-c", "rm -rf /dist/* /dist/.[!.]* 2>/dev/null; cp -r /src/. /dist/"]
