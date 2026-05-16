# tools.zenon.info — compose stack

Docker-compose orchestration for the four `tools.zenon.info` services + supporting infrastructure.

## Layout

This repo is the orchestration layer. The four service repos are expected as siblings:

```
Github/tools.zenon.info/
├── tools.zenon.info/      (this repo)
├── zt-frontend/
├── zt-server/
├── nom-indexer/
└── nom-data-refiner/
```

## First-time setup

1. Point DNS A-records for `tools.zenon.info` and `api.tools.zenon.info` at the host.
2. Open ports 80, 443, 443/udp, and 35995 (tcp + udp) on the firewall. Everything else stays internal.
3. Configure secrets:

   ```sh
   cp .env.example .env                                                  # set domains, ACME email, DB password, ZNND_GIT_REF
   for f in configs/*.example; do cp "$f" "${f%.example}"; done
   ```

   Edit each `configs/*` file:
   - `configs/zt-server.config.yaml` — sync `database_password` with `.env`
   - `configs/indexer.config.yaml` — sync `database_password` with `.env`
   - `configs/refiner.config.json` — set `bitquery_api_key`, `ether_scan_api_key`, reference addresses

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

Service names: `frontend`, `zt-server`, `nom-indexer`, `nom-refiner`, `znnd`.

The frontend is a one-shot build container that writes static assets into the `frontend_dist` volume. After rebuilding:

```sh
docker compose run --rm frontend
docker compose restart caddy
```

## Architecture notes

- **Shared Postgres**: `nom-indexer` writes, `zt-server` reads. Same DB.
- **Shared filesystem**: `nom-refiner` writes JSON to `refiner_data` volume (rw); `zt-server` reads it (ro).
- **`pillars_data` and `stats_data` volumes**: operator-supplied, start empty. `zt-server`'s pillar-update endpoint populates pillars data via signed writes; statistics data comes from a separate periodic job not in this stack. Both are irreplaceable — include in backups.
- **`znnd_data` volume**: blockchain data, resyncable — skip in backups.
- **API URL**: baked into the frontend at build time via the `ZT_API_URL` build-arg. Change `.env` → `docker compose build frontend && docker compose run --rm frontend && docker compose restart caddy`.

## Backups

```sh
docker compose exec postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > backup.sql
# Plus: pillars_data and stats_data volumes (docker run --rm -v pillars_data:/v -v $PWD:/out alpine tar czf /out/pillars.tar.gz -C /v .)
```
