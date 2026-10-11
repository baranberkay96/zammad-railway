# Deploy and Host Zammad with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/zammad-7-helpdesk-and-ticketing?referralCode=20H68q)

Zammad is an open-source helpdesk that collects customer requests from e-mail, web forms, chat, phone and social channels into one ticket system with SLAs, triggers and a knowledge base. This community template runs the official Zammad 7 image on Railway as the full upstream stack: web, background jobs, websocket, nginx, Elasticsearch search and daily backups.

## About Hosting Zammad

A production Zammad installation is several processes from one image: a Rails server for the UI and API, a scheduler for background jobs such as fetching mail and escalations, a websocket server, and nginx in front of them. It needs PostgreSQL, Redis, Memcached and Elasticsearch for search. This template runs each role as its own Railway service and uses Railway's PostgreSQL and Redis. Database migrations run as a pre-deploy step, the search index is built automatically, and the first administrator is created from your e-mail address, so the setup wizard cannot be claimed by someone else. Attachments are stored in PostgreSQL, Zammad's default, and an S3 bucket can be used instead.

## Common Use Cases

- A shared support inbox where e-mails become tickets with owners, states and SLAs
- Live chat on your website with tickets created from conversations
- Internal IT or HR helpdesk with groups, roles and a self-service knowledge base
- Replacing a hosted helpdesk such as Zendesk or Freshdesk with a self-hosted system
- Customer support reporting with full-text search across all tickets

## Dependencies for Zammad Hosting

- Zammad 7.2.2 (official `ghcr.io/zammad/zammad` image)
- PostgreSQL 18 (Railway Postgres)
- Redis 8.2 (Railway Redis)
- Memcached 1.6
- Elasticsearch 9.5

### Deployment Dependencies

- Zammad Docker Compose (official stack this template follows): https://github.com/zammad/zammad-docker-compose
- Zammad installation and environment variables: https://docs.zammad.org/en/latest/install/docker-compose.html
- Zammad admin documentation (channels, storage): https://admin-docs.zammad.org/
- Elasticsearch Docker image: https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-with-docker

### Implementation Details

| Service | Image | Role |
|---|---|---|
| zammad-nginx | built from `services/zammad` | Public entry point; routes the app, `/cable` and `/ws` |
| zammad-railsserver | built from `services/zammad` | Rails UI and API; its pre-deploy command runs migrations and first-install setup |
| zammad-scheduler | built from `services/zammad` | Background jobs, mail fetching, escalations; builds the search index |
| zammad-websocket | built from `services/zammad` | Legacy websocket server |
| zammad-backup | built from `services/zammad` | Daily database dump to its own volume (10 days kept) |
| Elasticsearch | built from `services/elasticsearch` (`elasticsearch:9.5.5`) | Search index (volume) |
| Memcached | `memcached:1.6.45-alpine` | Rails cache |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl:18` | Tickets, users, attachments (volume) |
| Redis | `redis:8.2` | Sessions and coordination (volume) |

**First login:** enter your e-mail in `ZAMMAD_ADMIN_EMAIL` when deploying. When zammad-nginx is healthy, open its public URL and log in with that e-mail and the generated `ZAMMAD_ADMIN_PASSWORD` from the zammad-railsserver variables, then change the password. Connect a mailbox under Admin → Channels → Email. Fetching mail over IMAP works on every plan; sending replies needs outbound SMTP, which Railway allows on the Pro plan, or the Microsoft 365 channel, which works over HTTPS. Enable the website chat under Admin → Channels → Chat. After adding a custom domain to zammad-nginx, update the FQDN under Admin → System → Base.

**Scaling:** raise `ZAMMAD_WEB_CONCURRENCY` or `MAX_THREADS` on zammad-railsserver, or add replicas to it. The scheduler must stay at one replica. Give Elasticsearch more memory together with a larger `ES_JAVA_OPTS` heap as the ticket count grows.

**Attachments in S3:** to keep attachments out of PostgreSQL, add a Railway Bucket and set `S3_BUCKET`, `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY` on zammad-railsserver before the first deploy.

**Backups:** zammad-backup writes a compressed `pg_dump` every night at `BACKUP_TIME`. To restore, place a dump in `/var/tmp/zammad/restore/` on that service, stop the other Zammad services, redeploy zammad-backup, then start the others again.

**Versions:** Zammad is pinned in `services/zammad/Dockerfile` (`ZAMMAD_VERSION`) and Elasticsearch in `services/elasticsearch/Dockerfile`. Change the tag and redeploy; migrations run automatically before the new Rails server starts.

### Why Deploy Zammad on Railway?

Railway runs every Zammad role, the databases, the search engine and the HTTPS domain in one project, with private networking between them. You get the complete upstream helpdesk stack without managing servers, and you can resize each service as your support team grows.
