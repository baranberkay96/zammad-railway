# NOTICE — Zammad 7 Helpdesk and Ticketing

## Software deployed (not redistributed)

| Component | Source | License |
|---|---|---|
| Zammad | `ghcr.io/zammad/zammad:7.2.2-0002` — https://github.com/zammad/zammad | AGPL-3.0 |
| Elasticsearch | `elasticsearch:9.5.5` — https://github.com/elastic/elasticsearch | AGPL-3.0 / SSPL-1.0 / Elastic License 2.0 (choice) |
| Memcached | `memcached:1.6.45-alpine` | BSD-3-Clause |
| PostgreSQL | `ghcr.io/railwayapp-templates/postgres-ssl:18` (Railway base) | PostgreSQL License |
| Redis | `redis:8.2` (Railway base) | Redis 8 tri-license (RSALv2 / SSPLv1 / AGPLv3) |

This template is a community template. It is not affiliated with or endorsed by the Zammad Foundation or Zammad GmbH.

## Upstream files checked (2026-10-11)

- `zammad/zammad-docker-compose` release `v17.5.2`: `docker-compose.yml` (roles, versions, environment list, initdb hook), `.env.dist`.
- `ghcr.io/zammad/zammad:7.2.2-0002` image: `/opt/zammad/bin/docker-entrypoint` (roles), `contrib/docker/backup.sh`, `contrib/nginx/zammad.conf`, `config/puma.rb`, `/etc/nginx/nginx.conf`, `pg_dump --version` (18.6).
- `zammad/zammad` tag `7.2.2`: `config/zammad/storage.yml.dist`, `app/models/store/provider/s3/config.rb`, `lib/zammad/service/configuration.rb` (S3_URL parsing), `db/seeds.rb` (FQDN/HTTP type/S3 seeding), `lib/zammad/trusted_proxies.rb`, `app/services/service/user/add_first_admin.rb`, `app/models/channel/driver/microsoft_graph_*.rb`.
- `elasticsearch:9.5.5` image: `/usr/local/bin/docker-entrypoint.sh` (keystore handling, relative paths).
- Zammad docs: environment variables, S3 storage settings.

## Adapted material

- **zammad/zammad-docker-compose** — AGPL-3.0 (Copyright Zammad Foundation). The service layout, image versions and role commands follow the official compose file.
- **zammad/zammad** — AGPL-3.0. `services/zammad/railway-zammad` reproduces the logic of the image's `docker-entrypoint` nginx and websocket roles (the same `sed` edits of `contrib/nginx/zammad.conf` and the same readiness check), with the Railway changes described in TEMPLATE.md. Because this file is derived from AGPL-licensed code, it is provided under AGPL-3.0 as well.

## Not used

- `_upstream/gridalpha__zammad-railway` (no license, all rights reserved) and the market templates `zammad`, `zammad-help-desk`, `zammad-or-just-updated-zendesk-alternati`: read for comparison only; nothing copied. All prose is original.
