# Zammad 7 Helpdesk and Ticketing — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **Zammad 7 Helpdesk and Ticketing** (version label `7` = Zammad major; Zammad writes versions without a "v") |
| Description | Email, chat and web tickets in one helpdesk. Open Zendesk alternative. (70 chars) |
| Category | Other |
| Tags | zammad, helpdesk, ticketing, customer-support, live-chat, elasticsearch, postgres |
| Icon | https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/zammad.svg |
| User input at deploy | **`ZAMMAD_ADMIN_EMAIL`** (zammad-railsserver) — login of the first administrator. Everything else is generated. |

Listing description kept. E-mail tickets: fetching mail (IMAP, Microsoft 365, Google) works on every plan; *sending* replies needs either outbound SMTP (Railway Pro) or the Microsoft 365 channel (Graph API over HTTPS). This is stated in the README.

## Base market template

- **`zammad-help-desk` "Zammad: Help desk, Zendesk alternative"** (20 projects, 4 active) — the base. Kept: official `ghcr.io/zammad/zammad` image with the upstream roles as separate services (railsserver, scheduler, websocket, nginx), Memcached, `NGINX_SERVER_SCHEME=https`, the IPv6 bracket fix for nginx's resolver, `RAILS_TRUSTED_PROXIES` including Railway's ranges. Fixed: **no Elasticsearch** (`ELASTICSEARCH_ENABLED=false`, while Zammad's search, reporting and many filters expect it); Postgres 17 with its own image instead of Railway's Postgres; Redis without password; migrations in the railsserver start command; **no admin bootstrap** (the first visitor creates the admin in the setup wizard); no backups; IPv4-only websocket server; multi-line inline nginx start command.
- `zammad` (gridalpha repo, no license) — read for comparison (Elasticsearch + S3 bucket variant, per-role env var). Nothing copied.
- `zammad-or-just-updated-zendesk-alternati` (prebuilt third-party image) — read for the admin-seeding idea only. Nothing copied.

## Pinned versions

| Service | Image | Tag | Release date | Checked |
|---|---|---|---|---|
| zammad-* (built from `services/zammad`) | `ghcr.io/zammad/zammad` | `7.2.2-0002` | 2026-10-08 | 2026-10-11 |
| Elasticsearch (built from `services/elasticsearch`) | `elasticsearch` | `9.5.5` | 2026-10 | 2026-10-11 |
| Memcached | `memcached` | `1.6.45-alpine` | 2026 | 2026-10-11 |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl` | `18` | Railway base | 2026-10-11 |
| Redis | `redis` | `8.2` | Railway base | 2026-10-11 |

Upstream reference: `zammad/zammad-docker-compose` release **v17.5.2** (2026-10-08) pins `7.2.2-0000`, Elasticsearch `9.5.5`, Memcached `1.6.45-alpine`, Postgres `17.11-alpine`, Redis `8.10.2-alpine`. `7.2.2-0002` is the latest build of the same 7.2.2 release (published the same day). Postgres 18 (Railway base) is used instead of 17: the image's `pg_dump` is 18.6, so backups work. Redis uses the Railway base definition (8.2, password).

**Upgrades:** change `ARG ZAMMAD_VERSION` in `services/zammad/Dockerfile` (or set a service variable `ZAMMAD_VERSION` on each Zammad service; Railway passes it as a build argument) and redeploy; zammad-railsserver's pre-deploy command runs migrations, and the other roles wait until they are done. Elasticsearch: change `ELASTICSEARCH_VERSION` in `services/elasticsearch/Dockerfile` following Zammad's supported versions.

## Architecture

```
Internet ──HTTPS──▶ zammad-nginx :8080 ──/───────▶ zammad-railsserver :3000 (Puma 2×15)
                                     └─/ws─────▶ zammad-websocket :6042
                          zammad-scheduler (background jobs, mail fetch, escalations)
                          zammad-backup    (daily pg_dump → own volume)
                                │
         Postgres (data + attachments) · Redis (sessions) · Memcached (cache) · Elasticsearch (search)
```

**One image, several roles.** All Zammad services build `services/zammad` (official image + `railway-zammad` wrapper) and choose their role in the start command. The wrapper calls Zammad's own `docker-entrypoint` for railsserver, scheduler and backup, and reproduces the nginx and websocket roles with the Railway fixes listed below.

**Init as pre-deploy.** `railway-zammad zammad-init` is zammad-railsserver's pre-deploy command: it runs upstream's init (create/migrate/seed database, locales, add-on packages) with Elasticsearch handling split off, so the step never blocks on Elasticsearch. A Ruby step then stores the Elasticsearch settings and, on first install, creates the administrator through Zammad's own `Service::User::AddFirstAdmin` (same code path as the setup wizard: Admin + Agent roles, all groups, `system_init_done`). nginx, websocket and scheduler wait until migrations are done (upstream readiness check).

**Search index.** zammad-scheduler waits for the Elasticsearch settings and for Elasticsearch, and runs `zammad:searchindex:rebuild` only when the index does not exist (upstream does this in init). Failures are logged and the scheduler starts anyway; the check repeats on the next start.

**Attachments.** No shared volume is possible on Railway, so attachments stay in PostgreSQL — Zammad's default storage provider (`DB`). Optional: set the five `S3_*` variables on zammad-railsserver (e.g. to a Railway Bucket) before the first deploy; the wrapper assembles a URL-encoded `S3_URL` and Zammad's seed selects the S3 provider.

### Deviations from upstream compose (and why)

- `zammad-init` → pre-deploy command of zammad-railsserver; Elasticsearch index creation moved to zammad-scheduler (pre-deploy has a time limit; Elasticsearch is built later than image services).
- First administrator created from variables (upstream: first visitor runs the setup wizard).
- nginx: resolver line bracketed for IPv6 name servers (Railway's resolver is IPv6), 2 worker processes instead of one per host CPU, upstreams are Railway private domains.
- Websocket server binds `::` (IPv4 + IPv6) instead of `0.0.0.0`; falls back to `0.0.0.0` only in containers without IPv6.
- No shared `zammad-storage`/`zammad-backup` volumes: attachments in PostgreSQL, backup volume only on zammad-backup (`NO_FILE_BACKUP=yes`, the database dump contains the attachments).
- Elasticsearch with security on (generated `elastic` password; upstream compose disables it), `xpack.ml` off, no mmap/memlock (container limits).
- Postgres/Redis from Railway's base definitions (Postgres 18, Redis with password); Zammad uses the Postgres superuser and creates its own `zammad_production` database.

## Services

All Zammad services use **Source:** GitHub repo `baranberkay96/zammad-railway`, root directory `/services/zammad` (Dockerfile build). Variables marked "ref" are references to zammad-railsserver's value of the same name (`${{zammad-railsserver.NAME}}`), so database, cache and search settings are defined once.

### zammad-nginx

- **Start command:** `/usr/local/bin/railway-zammad zammad-nginx`
- **Healthcheck:** `/` (timeout 1200 s; nginx starts once migrations are done)
- **Public domain:** yes → target port `8080`
- **TCP proxy / Volume:** none
- **Restart policy:** ALWAYS · **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| core variables | ref | `POSTGRESQL_*`, `REDIS_URL`, `MEMCACHE_SERVERS`, `ELASTICSEARCH_*`, `RAILS_TRUSTED_PROXIES`, `TZ` (the readiness check boots Rails). |
| `PORT` | `8080` | Port nginx listens on; Railway routes the public domain and its healthcheck here. |
| `NGINX_PORT` | `8080` | Port nginx listens on (IPv4 and IPv6). |
| `NGINX_SERVER_SCHEME` | `https` | Scheme passed to Zammad in X-Forwarded-Proto; Railway terminates TLS, so https (otherwise logins fail with CSRF errors). |
| `NGINX_CLIENT_MAX_BODY_SIZE` | `50M` | Maximum upload size. |
| `ZAMMAD_RAILSSERVER_HOST` | `${{zammad-railsserver.RAILWAY_PRIVATE_DOMAIN}}` | Rails server (private network). |
| `ZAMMAD_RAILSSERVER_PORT` | `${{zammad-railsserver.ZAMMAD_RAILSSERVER_PORT}}` | Rails server port. |
| `ZAMMAD_WEBSOCKET_HOST` | `${{zammad-websocket.RAILWAY_PRIVATE_DOMAIN}}` | Websocket server (private network). |
| `ZAMMAD_WEBSOCKET_PORT` | `${{zammad-websocket.ZAMMAD_WEBSOCKET_PORT}}` | Websocket server port. |

### zammad-railsserver

- **Start command:** `/usr/local/bin/railway-zammad zammad-railsserver`
- **Pre-deploy command:** `/usr/local/bin/railway-zammad zammad-init` (timeout 900 s)
- **Healthcheck:** none (not public; nginx's healthcheck covers it)
- **Public domain / TCP proxy / Volume:** none
- **Restart policy:** ALWAYS · **Replicas:** 1 (stateless; can be raised)

| Variable | Value | Description |
|---|---|---|
| `POSTGRESQL_HOST` | `${{Postgres.PGHOST}}` | PostgreSQL host (private network). |
| `POSTGRESQL_PORT` | `${{Postgres.PGPORT}}` | PostgreSQL port. |
| `POSTGRESQL_USER` | `${{Postgres.PGUSER}}` | PostgreSQL user. |
| `POSTGRESQL_PASS` | `${{Postgres.PGPASSWORD}}` | PostgreSQL password. |
| `POSTGRESQL_DB` | `zammad_production` | Database name; created by zammad-init on first deploy. |
| `POSTGRESQL_DB_CREATE` | `true` | Let zammad-init create the database (the Railway Postgres user may create databases). |
| `POSTGRESQL_OPTIONS` | `?pool=50` | Rails connection pool options (must be at least MAX_THREADS). |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis for websocket sessions and background coordination. |
| `MEMCACHE_SERVERS` | `${{Memcached.RAILWAY_PRIVATE_DOMAIN}}:11211` | Memcached for the Rails cache. |
| `ELASTICSEARCH_ENABLED` | `true` | Use Elasticsearch for search (recommended by Zammad). |
| `ELASTICSEARCH_SCHEMA` | `http` | Elasticsearch scheme (plain HTTP on the private network). |
| `ELASTICSEARCH_HOST` | `${{Elasticsearch.RAILWAY_PRIVATE_DOMAIN}}` | Elasticsearch host. |
| `ELASTICSEARCH_PORT` | `9200` | Elasticsearch port. |
| `ELASTICSEARCH_USER` | `elastic` | Elasticsearch user. |
| `ELASTICSEARCH_PASS` | `${{Elasticsearch.ELASTIC_PASSWORD}}` | Elasticsearch password. |
| `ELASTICSEARCH_NAMESPACE` | `zammad` | Prefix of Zammad's Elasticsearch indexes. |
| `RAILS_TRUSTED_PROXIES` | `127.0.0.1,::1,10.0.0.0/8,100.64.0.0/10,172.16.0.0/12,192.168.0.0/16,fd00::/8` | Proxies (nginx, Railway's edge) whose X-Forwarded-For Zammad trusts, for real client IPs and rate limiting. |
| `TZ` | `UTC` | Container time zone (logs, backup schedule). |
| `ZAMMAD_FQDN` | `${{zammad-nginx.RAILWAY_PUBLIC_DOMAIN}}` | Public host name; applied on first install (later: Admin > System > Base). |
| `ZAMMAD_HTTP_TYPE` | `https` | Public scheme; applied on first install. |
| `ZAMMAD_ADMIN_EMAIL` | **required input** | E-mail address (and login) of the first administrator, created on first deploy. |
| `ZAMMAD_ADMIN_PASSWORD` | `ZaMb7-${{secret(24)}}` | Password of the first administrator (generated; meets Zammad's password policy). Change it after login. |
| `ZAMMAD_ADMIN_FIRSTNAME` | `Admin` | First name of the first administrator. |
| `ZAMMAD_ADMIN_LASTNAME` | `User` | Last name of the first administrator. |
| `ZAMMAD_ORGANIZATION` | *(empty)* | Optional organization name shown in Zammad (Admin > System > Branding). |
| `ZAMMAD_RAILSSERVER_PORT` | `3000` | Port Puma listens on (IPv4 and IPv6). |
| `ZAMMAD_WEB_CONCURRENCY` | `2` | Puma worker processes (about 300-500 MB each). |
| `MAX_THREADS` | `15` | Puma threads per worker. |
| `S3_BUCKET` | *(empty)* | Optional: store attachments in S3 (e.g. a Railway Bucket) instead of PostgreSQL. Bucket name; set all S3_* variables before the first deploy. |
| `S3_ENDPOINT` | *(empty)* | Optional S3 endpoint URL, e.g. https://t3.storageapi.dev. |
| `S3_REGION` | *(empty)* | Optional S3 region (Railway Buckets: auto). |
| `S3_ACCESS_KEY_ID` | *(empty)* | Optional S3 access key. |
| `S3_SECRET_ACCESS_KEY` | *(empty)* | Optional S3 secret key. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Let running requests finish on redeploy. |

### zammad-scheduler

- **Start command:** `/usr/local/bin/railway-zammad zammad-scheduler`
- **Healthcheck / Public domain / TCP proxy / Volume:** none
- **Restart policy:** ALWAYS · **Replicas:** 1 (Zammad runs exactly one scheduler)

| Variable | Value | Description |
|---|---|---|
| core variables, `S3_*` | ref | As on zammad-railsserver (attachments created by mail fetching use the same storage). |
| `ELASTICSEARCH_REINDEX` | `true` | Build the search index when it does not exist yet (first install, new Elasticsearch volume). |
| `ELASTICSEARCH_WAIT_SECONDS` | `900` | How long to wait for Elasticsearch before starting without the index check. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Let running background jobs finish on redeploy. |

### zammad-websocket

- **Start command:** `/usr/local/bin/railway-zammad zammad-websocket`
- **Healthcheck / Public domain / TCP proxy / Volume:** none · **Restart policy:** ALWAYS · **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| core variables | ref | As on zammad-railsserver. |
| `ZAMMAD_WEBSOCKET_PORT` | `6042` | Port of the legacy websocket server. |
| `ZAMMAD_WEBSOCKET_BIND` | `::` | Bind address; '::' accepts IPv4 and IPv6 on Railway's private network. |

### zammad-backup

- **Start command:** `/usr/local/bin/railway-zammad zammad-backup`
- **Healthcheck / Public domain / TCP proxy:** none
- **Volume:** `/var/tmp/zammad`
- **Restart policy:** ALWAYS · **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| core variables | ref | As on zammad-railsserver. |
| `BACKUP_DIR` | `/var/tmp/zammad` | Backup directory (this service's volume). |
| `BACKUP_TIME` | `03:00` | Daily backup time (TZ). |
| `HOLD_DAYS` | `10` | Days to keep backups. |
| `BACKUP_ON_START` | `false` | Also back up whenever the service starts. |
| `NO_FILE_BACKUP` | `yes` | Skip the storage-directory archive: attachments are in PostgreSQL (or S3), so the database dump is the backup. |
| `RAILWAY_RUN_UID` | `0` | Run as root so the backup volume (mounted root-owned) is writable, as upstream runs this container. |

### Elasticsearch

- **Source:** GitHub repo `baranberkay96/zammad-railway`, root directory `/services/elasticsearch` (Dockerfile: `elasticsearch:9.5.5` + `railway-start.sh`)
- **Start command:** image default (fixes volume ownership as root, then runs the upstream entrypoint as uid 1000 via `chroot --skip-chdir`)
- **Healthcheck / Public domain / TCP proxy:** none
- **Volume:** `/usr/share/elasticsearch/data`
- **Restart policy:** ON_FAILURE (max 10) · **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `discovery.type` | `single-node` | Single-node cluster (also skips production bootstrap checks). |
| `xpack.security.enabled` | `true` | Require the elastic user's password. |
| `xpack.security.http.ssl.enabled` | `false` | Plain HTTP inside the private network. |
| `xpack.security.transport.ssl.enabled` | `false` | No transport TLS for a single node. |
| `ELASTIC_PASSWORD` | `${{secret(32, "abc…XYZ0123456789")}}` | Password of the elastic user (generated). |
| `ES_JAVA_OPTS` | `-Xms1g -Xmx1g` | JVM heap (upstream default 1 GB). Keep about half of the RAM you give Elasticsearch. |
| `network.host` | `0.0.0.0` | Bind address. 0.0.0.0, not '::': the image writes these settings to YAML unquoted and '::' breaks the parse. |
| `node.store.allow_mmap` | `false` | Do not depend on the host's vm.max_map_count, which containers cannot change. |
| `bootstrap.memory_lock` | `false` | memlock ulimits cannot be raised on Railway. |
| `ingest.geoip.downloader.enabled` | `false` | Skip GeoIP database downloads (unused by Zammad). |
| `xpack.ml.enabled` | `false` | Machine learning features off (unused, saves memory). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow a clean shutdown on redeploy. |

### Memcached

- **Source:** Docker image `memcached:1.6.45-alpine`
- **Start command:** `/bin/sh -c "exec memcached -m ${MEMCACHED_MEMORY:-256}"` (listens on IPv4 and IPv6 by default — verified)
- **Healthcheck / Public domain / TCP proxy / Volume:** none · **Restart policy:** ON_FAILURE (max 10)

| Variable | Value | Description |
|---|---|---|
| `MEMCACHED_MEMORY` | `256` | Cache size in MB (upstream: 256). |

### Postgres, Redis

Copied unchanged from `templates/_railway-base/postgres.json` (`ghcr.io/railwayapp-templates/postgres-ssl:18`, volume `/var/lib/postgresql/data`) and `templates/_railway-base/redis.json` (`redis:8.2`, password, volume `/data`).

## Improvements over market templates

| # | Change | Why |
|---|---|---|
| 1 | Elasticsearch 9.5.5 (upstream version) with a generated password, index built automatically | Full-text search, reporting and filters work as designed (leader disabled Elasticsearch). |
| 2 | First administrator created from variables via Zammad's own first-admin service; setup wizard closed | Nobody can claim a fresh instance by opening the URL first. |
| 3 | Migrations as pre-deploy of zammad-railsserver; other roles wait | Upgrades are a tag change + redeploy; no init race. |
| 4 | Daily `pg_dump` backups with retention on their own volume (upstream backup role) | Leader had no backups. |
| 5 | Websocket server and Puma reachable over IPv4 and IPv6; nginx resolver IPv6-safe; nginx 2 workers | Works on new and legacy Railway private networks; no 30+ nginx workers on large hosts. |
| 6 | Railway Postgres 18 and password-protected Redis base definitions | Data panel, SSL, consistent with other templates; leader's Redis had no password. |
| 7 | Database/cache/search settings defined once (railsserver) and referenced by the other roles | Change one variable instead of five. |
| 8 | Optional S3/Bucket attachment storage with URL-encoded credentials | Large attachment volumes off the database without manual URL building. |
| 9 | Tested locally (arm64, IPv6-enabled network, `--init`): init as a separate step after the app roles were already waiting, admin login via API, ticket creation, search hits from Elasticsearch, backup run, websocket reachable over IPv4 and IPv6 | Fewer surprises on the first Railway deploy. |

## First login

1. Deploy with your e-mail in `ZAMMAD_ADMIN_EMAIL`. Wait until zammad-nginx is healthy (pre-deploy init ≈ 1 minute; builds take longer).
2. Open the zammad-nginx public URL, log in with that e-mail and `ZAMMAD_ADMIN_PASSWORD` (zammad-railsserver → Variables). Change the password.
3. Admin → Channels → Email: connect a mailbox (IMAP fetch works on all plans; sending needs SMTP on Railway Pro, or use the Microsoft 365 channel, which uses HTTPS). Admin → Channels → Chat for the website chat widget.
4. Custom domain: add it to zammad-nginx, then set it under Admin → System → Base → Fully Qualified Domain Name.

## Scaling

- **Web:** raise `ZAMMAD_WEB_CONCURRENCY` (processes) or `MAX_THREADS` on zammad-railsserver, or its replica count (stateless). Keep `POSTGRESQL_OPTIONS` pool ≥ `MAX_THREADS`, and total connections below Postgres' `max_connections` (100).
- **Background jobs:** zammad-scheduler must stay a single replica. Upstream variables such as `ZAMMAD_PROCESS_DELAYED_JOBS_WORKERS` / `ZAMMAD_PROCESS_SESSIONS_JOBS_WORKERS` can be added to it to raise worker counts.
- **Search:** raise `ES_JAVA_OPTS` heap together with Elasticsearch's memory.

## Backups and restore

zammad-backup writes `{timestamp}_zammad_db.psql.gz` daily to its volume and keeps `HOLD_DAYS` days. To restore: copy a dump to `/var/tmp/zammad/restore/` on zammad-backup (Railway shell), stop zammad-railsserver/scheduler/websocket (remove their deployments or set replicas to 0), redeploy zammad-backup (it restores and moves the folder to `restore_completed_*`), then redeploy the other services. Railway volume backups of Postgres are a second layer.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Idle figures measured locally (arm64) after first boot.

| Service | Idle RAM | Typical RAM (10–30 agents) | Typical CPU |
|---|---|---|---|
| zammad-railsserver (Puma 2×15) | 570 MB | 1.0 GB | 0.2 vCPU |
| zammad-scheduler | 440 MB | 700 MB | 0.15 vCPU |
| zammad-websocket | 260 MB | 350 MB | 0.05 vCPU |
| zammad-nginx | 35 MB | 50 MB | 0.02 vCPU |
| zammad-backup | 10 MB (sleeps between runs) | 10 MB | – |
| Elasticsearch (1 GB heap) | 1.6 GB | 1.8 GB | 0.1 vCPU |
| Postgres | 280 MB | 500 MB | 0.1 vCPU |
| Redis | 12 MB | 50 MB | <0.01 vCPU |
| Memcached | 7 MB | 270 MB | <0.01 vCPU |
| **Total** | **≈3.2 GB** (≈0.15 vCPU) | **≈4.7 GB** | **≈0.6 vCPU** |

- **Idle:** ≈ $32 RAM + $3 CPU + $0.5 volumes ≈ **$36/month**.
- **Typical:** ≈ $47 RAM + $12 CPU + $1.5 volumes (10 GB) ≈ **$60/month**.
- **Minimum plan:** Hobby (Elasticsearch alone needs about 1.6 GB, above Trial's 1 GB per service). Pro if replies are sent over SMTP.

## Verification checklist

- [ ] All five Zammad service builds and the Elasticsearch build succeed.
- [ ] zammad-railsserver pre-deploy log ends with `administrator {email} created; setup wizard closed` and `init finished`.
- [ ] zammad-scheduler logs `Elasticsearch index missing; building it` once, then `starting background services...`.
- [ ] zammad-nginx healthy on `/`; log in with `ZAMMAD_ADMIN_EMAIL` / `ZAMMAD_ADMIN_PASSWORD` (no setup wizard shown).
- [ ] Create a ticket, then find it with the search bar (Elasticsearch).
- [ ] Open the same ticket in two browsers: updates appear live (websocket/cable via nginx).
- [ ] Upload an attachment, redeploy all Zammad services, attachment still downloads.
- [ ] Set `BACKUP_ON_START=true` once on zammad-backup → a `*_zammad_db.psql.gz` appears in `/var/tmp/zammad`.

## Open questions

- **Pre-deploy timeout 900 s:** value used in round-1 tests; first install measured ≈ 45 s locally. Postgres must be reachable within that window (image service, starts quickly).
- **Railway Bucket for attachments** (optional S3) not tested against a real Bucket; the AWS SDK uses virtual-hosted style by default, which matches Railway's documented style.
- **Outbound mail:** Railway allows SMTP only on Pro; the Microsoft 365 (Graph) channel is the HTTPS alternative. Google's channel uses SMTP for sending.
- **Restore** needs the app roles stopped manually (upstream pauses them through a shared backup volume, which Railway cannot provide).

## Deploy test findings (2026-10-11)

First Railway test: zammad-railsserver crashed creating the first admin — Zammad's password policy requires at least 2 lowercase and 2 uppercase characters, and the generated `Zm7-${{secret(24)}}` does not always contain them. The default is now `ZaMb7-${{secret(24)}}`, which always satisfies the policy.
