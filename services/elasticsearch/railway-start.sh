#!/bin/bash
# Railway volumes are mounted root-owned and Elasticsearch refuses to run as
# root. Fix the data directory's ownership, then run the image's own entrypoint
# as uid 1000 (gid 0, as in the official image).
#
# The Elasticsearch 9 image is RHEL UBI based and has no setpriv; GNU chroot with
# --skip-chdir drops privileges while keeping the working directory, which the
# upstream entrypoint needs (it calls bin/elasticsearch-keystore relatively to
# store ELASTIC_PASSWORD).
set -euo pipefail

ES_HOME=/usr/share/elasticsearch
DATA_DIR="${ES_HOME}/data"

mkdir -p "$DATA_DIR"
rm -rf "${DATA_DIR}/lost+found"
chown -R 1000:0 "$DATA_DIR"
chmod 1777 /tmp

cd "$ES_HOME"
exec chroot --userspec=1000:0 --skip-chdir / \
  env HOME="$ES_HOME" /usr/local/bin/docker-entrypoint.sh "$@"
