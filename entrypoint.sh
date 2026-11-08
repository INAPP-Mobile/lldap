#!/usr/bin/env bash
# LLDAP Railway wrapper entrypoint (Alpine bash; the upstream image
# is alpine:3.21 with bash + tzdata, tini, and gosu).
#
# What it does, in order:
# - PORT: Railway injects PORT at runtime. LLDAP reads its HTTP
#   port from LLDAP_HTTP_PORT only (config key http_port, default
#   17170; verified in lldap/lldap v0.6.3
#   lldap_config.docker_template.toml) and ignores the generic
#   PORT. Export LLDAP_HTTP_PORT=$PORT on every boot. Fail loud if
#   the remap did not land — a server listening on the wrong port
#   is a silent dead deploy.
# - STEADY STATE: exec tini (the image's own init, for signal
#   handling) in front of the upstream entrypoint, exactly as the
#   image does (it copies the default config to
#   /data/lldap_config.toml on first boot, chowns /app and /data to
#   UID:GID 1000:1000, then drops privileges with gosu and runs
#   `lldap run --config-file /data/lldap_config.toml`).
#   NOTE: the published image's entrypoint is
#   `tini -- /docker-entrypoint.sh` (verified in the v0.6.3 amd64
#   image config) — the script lives at /docker-entrypoint.sh,
#   not /app/docker-entrypoint.sh as the repo Dockerfile suggests.

set -euo pipefail

PORT_VALUE="${PORT:-17170}"
export LLDAP_HTTP_PORT="$PORT_VALUE"

if [ "$LLDAP_HTTP_PORT" != "$PORT_VALUE" ]; then
  echo "LLDAP: ERROR HTTP port remap failed; refusing to start."
  exit 1
fi

echo "LLDAP: HTTP on :${PORT_VALUE}, LDAP on :${LLDAP_LDAP_PORT:-3890}, data in /data"
exec tini -- /docker-entrypoint.sh run --config-file /data/lldap_config.toml
