# Elasticsearch for Zammad on Railway.
# Same version the official zammad-docker-compose pins (ELASTICSEARCH_VERSION).
# Starts as root only to fix ownership of the Railway volume, then drops to the
# elasticsearch user (uid 1000).
ARG ELASTICSEARCH_VERSION=9.5.5
FROM elasticsearch:${ELASTICSEARCH_VERSION}

USER root
COPY --chmod=0755 railway-start.sh /usr/local/bin/railway-start.sh

ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
CMD ["eswrapper"]
