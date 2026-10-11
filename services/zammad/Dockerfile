# Zammad for Railway: the official image plus a small role wrapper.
#
# All Zammad services of the template (railsserver, scheduler, websocket, nginx,
# backup) build this same image and select their role with the start command
# `/usr/local/bin/railway-zammad <role>`. The upstream entrypoint is kept: it
# passes unknown commands through, so the start command works either way.
#
# Upgrade: change ZAMMAD_VERSION and redeploy; zammad-railsserver's pre-deploy
# command runs the database migrations.
ARG ZAMMAD_VERSION=7.2.2-0002
FROM ghcr.io/zammad/zammad:${ZAMMAD_VERSION}

USER root

RUN install -d -m 0755 /usr/local/share/railway-zammad
COPY --chmod=0755 railway-zammad /usr/local/bin/railway-zammad
COPY --chmod=0644 railway-post-init.rb /usr/local/share/railway-zammad/railway-post-init.rb

# nginx: a fixed worker count instead of one per host CPU (Railway hosts have many).
RUN sed -i -e 's/^worker_processes auto;/worker_processes 2;/' \
           -e '/^worker_cpu_affinity auto;/d' /etc/nginx/nginx.conf \
    && grep -q '^worker_processes 2;' /etc/nginx/nginx.conf \
    && bash -n /usr/local/bin/railway-zammad

USER zammad

CMD ["/usr/local/bin/railway-zammad", "zammad-railsserver"]
