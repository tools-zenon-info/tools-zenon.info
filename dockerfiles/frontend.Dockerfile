# Angular 13 is incompatible with Node 18+ (OpenSSL legacy provider).
FROM node:16-bullseye AS builder
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

ARG ZT_API_URL
RUN sed -i "s|https://api.zenon.tools|${ZT_API_URL}|" src/environments/environment.prod.ts \
 && npm run build

FROM alpine:3.19
COPY --from=builder /app/dist/zenon-tools /dist
CMD ["true"]
