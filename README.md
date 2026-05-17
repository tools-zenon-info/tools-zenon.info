# tools.zenon.info — compose stack

Docker-compose orchestration for the `tools.zenon.info` services + supporting infrastructure.

## Build & deploy modes

The stack supports two modes via `COMPOSE_FILE`:

| Mode | `COMPOSE_FILE` value | Service builds |
|---|---|---|
| **Default** (standalone server) | unset (just `compose.yaml`) | git-context, pulled from GitHub |
| **Local dev** | `compose.yaml:compose.local.yaml` | local sibling clones |

In both modes the bundled Caddy handles TLS — Let's Encrypt on a real domain,
or Caddy's internal CA for `*.localhost` in local dev.

Sibling layout for local mode:

```
Github/tools.zenon.info/
├── tools.zenon.info/      (this repo)
├── zt-frontend/
├── zt-server/
├── nom-indexer/
├── nom-data-refiner/
└── eth-pool-indexer/
```

Each service repo owns its own `Dockerfile`. The compose repo only carries
Dockerfiles for `znnd` (builds go-zenon from upstream) and `znnd-bootstrap`
(a one-shot init container with no separate source repo).

## First-time setup

1. Point DNS A-records for `tools.zenon.info` and `api.tools.zenon.info` at the host.
2. Open ports 80, 443, 443/udp, and 35995 (tcp + udp) on the firewall. Everything else stays internal.
3. Configure secrets:

   ```sh
   cp .env.example .env
   ```

   Then **edit `.env`** to fill in:
   - `POSTGRES_PASSWORD` — any string
   - `ETHERSCAN_API_KEY` — required (eth-pool-indexer fails to start without it). Free at https://etherscan.io/apis
   - `COINGECKO_API_KEY` — required for the SPA's price charts. Free Demo key at coingecko.com → Developer Dashboard
   - `ZNND_GIT_REF`, `ZNND_BOOTSTRAP_URL`, etc. as described in the file

   `.env` is the **single source of truth** for secrets. On every `docker
   compose up`, a one-shot `config-renderer` service runs first and fills
   in `configs/*.tmpl` → `configs/*.{yaml,json}` (gitignored) by substituting
   your env vars. The rendered files are bind-mounted into each service.

   Templates committed in `configs/*.tmpl`. To customize non-secret fields
   (e.g. real reference ZNN addresses in `refiner.config.json.tmpl`), edit
   the template — those edits are committed and apply on every render.

4. Bootstrap:

   ```sh
   docker compose up -d postgres znnd
   docker compose logs -f znnd-bootstrap  # snapshot download + verify (skipped if /data/nom exists)
   docker compose logs -f znnd            # wait until syncing, then Ctrl+C
   docker compose up -d
   ```

   On first launch, `zt-server` may crash-loop a few times until `nom-indexer` creates the Postgres schema. This is expected — `restart: unless-stopped` handles it.

### Chain data bootstrap

`znnd-bootstrap` runs as an init container before `znnd` and seeds the chain data from a community snapshot (e.g. Digital Ocean Spaces). It is a no-op if `/data/nom` already exists.

- **Snapshot URL**: set `ZNND_BOOTSTRAP_URL` in `.env`. The sibling `.hash` URL must contain the sha256 of the zip. Leave blank to sync from genesis.
- **Default behavior**: skip if data dir is populated; download + verify + extract if empty.
- **Force a one-time re-bootstrap** (existing chain data is moved aside with a timestamp suffix):

  ```sh
  docker compose stop znnd
  docker compose run --rm -e FORCE_BOOTSTRAP=true znnd-bootstrap
  docker compose start znnd
  ```

  After this completes, the old `nom_<timestamp>/`, `network_<timestamp>/`, `consensus_<timestamp>/` dirs sit alongside the new ones inside the `znnd_data` volume. Delete them once you've confirmed the new data is healthy.

5. Verify:

   ```sh
   curl -sf "https://$(grep ^DOMAIN_API .env | cut -d= -f2)/" && echo "API up"
   curl -sf "https://$(grep ^DOMAIN_FRONTEND .env | cut -d= -f2)/" | grep -q '<app-root>' && echo "Frontend up"
   docker compose logs -f nom-indexer     # backfill takes hours-to-days
   ```

## Updating a single service

Each service repo is developed independently. To deploy a change:

```sh
docker compose build <service>
docker compose up -d <service>
```

Service names: `frontend`, `zt-server`, `nom-indexer`, `nom-refiner`, `eth-pool-indexer`, `znnd`.

In git-context mode (default), `docker compose build <service>` re-clones from
GitHub. To force a re-pull (skip BuildKit cache), use `--no-cache`.

The frontend is a one-shot build container that writes static assets into the `frontend_dist` volume. After rebuilding:

```sh
docker compose run --rm frontend
docker compose restart caddy
```

## Architecture notes

- **Services**: `caddy` (TLS termination + reverse proxy), `frontend` (Angular SPA, one-shot build), `zt-server` (Dart HTTP API), `nom-indexer` (Dart blockchain indexer), `nom-refiner` (Python data aggregator), `eth-pool-indexer` (Python; reads WZNN/WETH pool from Etherscan, writes JSON caches the refiner consumes — replaces Bitquery), `znnd` (Zenon node, go-zenon), `znnd-bootstrap` (one-shot init), `postgres`, `config-renderer` (one-shot init that runs envsubst on `configs/*.tmpl`).
- **Shared Postgres**: `nom-indexer` writes, `zt-server` reads. Same DB. MD5 auth (older Dart `postgresql2` client doesn't support SCRAM).
- **Shared filesystem**: `nom-refiner` and `eth-pool-indexer` both write JSON files into the `refiner_data` volume; `zt-server` reads them (ro). eth-pool-indexer keeps the pool-related cache files fresh so the refiner never falls back to its Bitquery/Etherscan code paths.
- **`pillars_data` and `stats_data` volumes**: operator-supplied, start empty. `zt-server`'s pillar-update endpoint populates pillars data via signed writes; statistics data comes from a separate periodic job not in this stack. Both are irreplaceable — include in backups.
- **`znnd_data` volume**: blockchain data, resyncable — skip in backups.
- **API URL + CoinGecko key**: baked into the frontend at build time via `ZT_API_URL` and `COINGECKO_API_KEY` build-args. Change `.env` → `docker compose build frontend && docker compose run --rm frontend && docker compose restart caddy`.
- **API origin lockdown**: Caddy enforces `Origin: https://$DOMAIN_FRONTEND` on every `api.$DOMAIN`-bound request. 403 for missing/wrong origin. Spoofable by non-browser clients, but blocks casual cross-origin abuse.

## Backups

```sh
docker compose exec postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > backup.sql
# Plus: pillars_data and stats_data volumes (docker run --rm -v pillars_data:/v -v $PWD:/out alpine tar czf /out/pillars.tar.gz -C /v .)
```
