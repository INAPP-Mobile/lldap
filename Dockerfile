# LLDAP on Railway — wrapper around the pinned upstream image.
#
# Why a wrapper at all (house style: bake constants, keep the deploy
# form minimal, and survive Railway's root-owned volumes):
# - PORT: LLDAP reads its HTTP port from LLDAP_HTTP_PORT (config key
#   http_port, default 17170) and ignores Railway's generic PORT
#   (verified in lldap/lldap v0.6.3 lldap_config.docker_template.toml:
#   "All the values can be overridden through environment variables,
#   prefixed with LLDAP_"). entrypoint.sh exports
#   LLDAP_HTTP_PORT=$PORT on every boot, before handing off to the
#   upstream entrypoint. Fail loud if the remap did not land — a
#   server listening on the wrong port is a silent dead deploy.
# - USER root: the stock image starts as root (no USER directive;
#   its entrypoint chowns /app and /data to UID:GID 1000:1000, set
#   in the image env, then drops privileges with gosu), so the
#   root-owned Railway volume is writable with no change. The
#   wrapper states USER root explicitly so a future upstream
#   non-root switch cannot silently break it.
# - DATA: one Railway volume at /data. The upstream entrypoint
#   copies its default config to /data/lldap_config.toml on first
#   boot, and LLDAP_DATABASE_URL (baked below) puts the SQLite
#   database at /data/users.db, so accounts, groups, and settings
#   survive restarts and redeploys.
# - FIRST RUN: the admin account is seeded from env on first boot
#   (LLDAP_LDAP_USER_PASS + LLDAP_LDAP_BASE_DN; password minimum 8
#   characters). No setup wizard, no email step: open the public
#   URL and log in as admin with the generated password shown on
#   the deploy form. The password is only used when initially
#   creating the admin user — changing the variable later does not
#   reset it (force_ldap_user_pass_reset stays false).
# - LDAP PORT: LLDAP also listens on LDAP 3890 (raw TCP). Railway's
#   public edge is HTTP-only, so the LDAP port is NOT publicly
#   reachable — the public face of this template is the web UI.
#   Other Railway services in the same project can reach LDAP over
#   the private network (service hostname, port 3890) for SSO with
#   apps that support LDAP. LDAPS is off by default.
# - HTTP_URL: derived at boot from the live RAILWAY_PUBLIC_DOMAIN
#   by entrypoint.sh — never a template-expression variable. A
#   https://${{RAILWAY_PUBLIC_DOMAIN}} default resolves to a bare
#   "https://" on first deploy (no domain exists yet) and LLDAP
#   rejects it hard ("empty host"), crash-looping the container
#   (found in e2e 2026-11-08; same shape as the 2026-10-29 Spliit
#   BASE_URL lesson). Unset is safe: LLDAP defaults to
#   http://localhost, and the URL is only used for password-reset
#   links (SMTP off by default).
#   deploy (the image ships a constant placeholder key_seed) — they
#   are generated deploy-form variables, never baked.
# - No Docker HEALTHCHECK: rely on Railway's external
#   healthcheckPath. The Alpine base ships no curl/wget, and the
#   upstream in-image HEALTHCHECK (lldap healthcheck) needs the
#   config file; the platform probe on / (the login page, served
#   without auth) is the health signal.
#
# Upstream: LLDAP v0.6.3 (GPL-3.0), image pinned by manifest digest,
# verified 2026-11-08 via the Docker Hub API (multi-arch manifest-list
# digest below; amd64 image digest
# sha256:90b849059c42ed8f92b95624ae71e38ca137a994736c68fb25dd167f2bbc9808).
# NOTE: the FROM uses the digest WITHOUT a tag — Railpack 0.43.0
# fails to detect a Dockerfile whose FROM carries both a tag and a
# digest (redeploys die in the plan phase with "could not determine
# how to build the app"); the digest-only form builds under both
# the Dockerfile builder and Railpack (verified 2026-11-05 —
# TimeTagger's digest-only FROM is the precedent).

# lldap/lldap:v0.6.3
FROM lldap/lldap@sha256:2a8454b668c1aba7157e832eab0e242e1e7eb5fb7591d7e7774ba05286511ca8

USER root

COPY entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /railway-entrypoint.sh

# Baked constants (see header): base DN, admin email, internal LDAP
# port, and the SQLite database URL on the volume. The HTTP port is
# mapped from Railway's PORT by the entrypoint on every boot.
ENV LLDAP_LDAP_BASE_DN=dc=example,dc=com \
    LLDAP_LDAP_USER_EMAIL=admin@example.com \
    LLDAP_LDAP_PORT=3890 \
    LLDAP_DATABASE_URL=sqlite:///data/users.db?mode=rwc

# Documentation only: Railway routes to $PORT at runtime (see
# entrypoint.sh); 17170 is the upstream default the image would use
# without the wrapper's remap.
EXPOSE 17170

ENTRYPOINT ["/railway-entrypoint.sh"]
