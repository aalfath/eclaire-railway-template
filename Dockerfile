# Eclaire on Railway: official image, pinned by version and digest.
# Upstream: https://github.com/eclaire-labs/eclaire (MIT)
FROM ghcr.io/eclaire-labs/eclaire:0.6.3@sha256:28cf083aa4fa9dae6c449dedcdcdb3214d607091194dc596df8058d1ebd823d1

USER root
COPY railway/ /app/railway/
# Small, asserted patches to the compiled app (see railway/patch.mjs):
#  - email sign-up closed unless ECLAIRE_ALLOW_SIGNUP=true (the admin is created on first boot)
#  - Docling is optional: without DOCLING_SERVER_URL, documents use the built-in extractors
#  - Postgres pool size from DATABASE_POOL_MAX
#  - viewport-only bookmark screenshots below 2 GB (ECLAIRE_FULLPAGE_SCREENSHOTS)
#  - Chromium and LibreOffice run through oom-first.sh, so under memory pressure the
#    kernel stops that one job instead of the whole app
RUN chmod 755 /app/railway/oom-first.sh \
 && node /app/railway/patch.mjs \
 && chmod 755 /app/railway/start.sh \
 && chown -R nodeapp:nodeapp /app/railway

ENV ECLAIRE_RUNTIME=container \
    ECLAIRE_HOME=/app \
    NODE_ENV=production \
    CONFIG_DIR=/app/config \
    DATABASE_TYPE=postgres \
    QUEUE_BACKEND=postgres \
    SERVICE_ROLE=all \
    PORT=3000

EXPOSE 3000
# Runs as root only long enough to fix volume ownership, then drops to nodeapp.
ENTRYPOINT ["dumb-init", "--", "/app/railway/start.sh"]
