#!/bin/bash
# Eclaire start script for Railway. Runs as root only to prepare the volume, then
# everything runs as the image's unprivileged "nodeapp" user.
set -euo pipefail

log() { echo "[railway] $*"; }
die() { echo "[railway] FATAL: $*" >&2; exit 1; }
as_app() { setpriv --reuid=nodeapp --regid=nodeapp --init-groups env HOME=/home/nodeapp "$@"; }

# ---------- required settings ----------
[ -n "${DATABASE_URL:-}" ] || die "DATABASE_URL is empty (expected \${{Postgres.DATABASE_URL}})."
for v in BETTER_AUTH_SECRET API_KEY_HMAC_KEY_V1; do
  val="${!v:-}"; [ "${#val}" -ge 32 ] || die "$v must be at least 32 characters."
done
printf '%s' "${MASTER_ENCRYPTION_KEY:-}" | grep -Eq '^[0-9a-f]{64}$' || die "MASTER_ENCRYPTION_KEY must be 64 hex characters."
[ -n "${ADMIN_EMAIL:-}" ] || die "ADMIN_EMAIL is empty."
[ "$(printf '%s' "${ADMIN_PASSWORD:-}" | wc -c)" -ge 8 ] || die "ADMIN_PASSWORD must be at least 8 characters."

export PORT="${PORT:-3000}" HOST=0.0.0.0
export DATA_DIR=/app/data CONFIG_DIR=/app/config
export BACKEND_URL="http://127.0.0.1:${PORT}"
# FRONTEND_URL comes from https://${{RAILWAY_PUBLIC_DOMAIN}}; ignore an empty or half-resolved value.
case "${FRONTEND_URL:-}" in
  http://?*|https://?*) export FRONTEND_URL="${FRONTEND_URL%/}" ;;
  *) if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then export FRONTEND_URL="https://${RAILWAY_PUBLIC_DOMAIN}"; else unset FRONTEND_URL; fi ;;
esac

# ---------- sizing: follow the service's limits, not the host's ----------
mem_bytes=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
[ "$mem_bytes" = max ] && mem_bytes=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) * 1024 ))
mem_mb=$(( mem_bytes / 1048576 ))
cpus=1
if read -r quota period < /sys/fs/cgroup/cpu.max 2>/dev/null && [ "$quota" != max ]; then
  cpus=$(( (quota + period - 1) / period )); [ "$cpus" -ge 1 ] || cpus=1
fi
heap=$(( mem_mb * 45 / 100 )); [ "$heap" -gt 2048 ] && heap=2048; [ "$heap" -lt 160 ] && heap=160
export NODE_OPTIONS="--enable-source-maps --max-old-space-size=${heap}"
export UV_THREADPOOL_SIZE=$(( cpus < 4 ? 4 : cpus )) VIPS_CONCURRENCY="$cpus" MALLOC_ARENA_MAX=2
export OMP_THREAD_LIMIT="$cpus" MAGICK_THREAD_LIMIT="$cpus"
export WORKER_CONCURRENCY="${WORKER_CONCURRENCY:-$(( mem_mb < 1500 ? 1 : 2 ))}"
export DATABASE_POOL_MAX="${DATABASE_POOL_MAX:-5}"
log "limits: ${mem_mb} MB, ${cpus} CPU -> heap ${heap} MB, workers ${WORKER_CONCURRENCY}, db pool ${DATABASE_POOL_MAX}"

# ---------- volume ----------
mkdir -p /app/data /app/config
# A fresh Railway volume is root-owned; fix ownership once (or after a root-owned leftover).
if [ "$(stat -c %U /app/data)" != nodeapp ] || [ -n "$(find /app/data -maxdepth 2 ! -user nodeapp -print -quit)" ]; then
  chown -R nodeapp:nodeapp /app/data
fi
chown -R nodeapp:nodeapp /app/config
as_app mkdir -p /app/data/users /app/data/logs /app/data/browser-data /app/config/ai

# ---------- AI provider: one OpenAI-compatible endpoint from variables ----------
export LLM_BASE_URL="${LLM_BASE_URL:-https://api.openai.com/v1}"
export LLM_BASE_URL="${LLM_BASE_URL%/}"
export LLM_MODEL="${LLM_MODEL:-gpt-4o-mini}"
[ -n "${LLM_API_KEY:-}" ] || log "WARNING: LLM_API_KEY is empty: the app runs, but AI chat and processing will fail until you set it."
as_app node /app/railway/ai-config.mjs

# ---------- database: wait, then migrate under an advisory lock ----------
as_app node /app/railway/migrate.mjs || die "database setup failed (see above)."

# ---------- first boot: create the admin on a loopback-only port ----------
marker=/app/data/.railway-admin-created
if [ ! -f "$marker" ]; then
  log "first boot: creating the admin account ${ADMIN_EMAIL}"
  boot_port=39099
  as_app env PORT=$boot_port HOST=127.0.0.1 SERVICE_ROLE=api ECLAIRE_ALLOW_SIGNUP=true \
    node dist/src/index.js >/tmp/bootstrap.log 2>&1 &
  boot_pid=$!
  ok=""
  for _ in $(seq 1 120); do
    curl -fsS "http://127.0.0.1:$boot_port/health" >/dev/null 2>&1 && { ok=1; break; }
    kill -0 "$boot_pid" 2>/dev/null || break
    sleep 1
  done
  if [ -z "$ok" ]; then tail -n 40 /tmp/bootstrap.log >&2; kill "$boot_pid" 2>/dev/null || true; die "bootstrap server did not start."; fi
  body=$(node -e 'process.stdout.write(JSON.stringify({email:process.env.ADMIN_EMAIL,password:process.env.ADMIN_PASSWORD,name:"Admin"}))')
  code=$(curl -s -o /tmp/signup.json -w '%{http_code}' -X POST "http://127.0.0.1:$boot_port/api/auth/sign-up/email" \
    -H 'Content-Type: application/json' -H 'Origin: http://localhost:3000' --data "$body" || true)
  kill "$boot_pid" 2>/dev/null || true; wait "$boot_pid" 2>/dev/null || true
  if [ "$code" = 200 ]; then
    log "admin account created."
  elif grep -q 'USER_ALREADY_EXISTS\|already exists' /tmp/signup.json 2>/dev/null; then
    log "admin account already exists."
  else
    head -c 400 /tmp/signup.json >&2 || true
    die "could not create the admin account (HTTP $code). Sign-up stays closed; fix ADMIN_EMAIL/ADMIN_PASSWORD and redeploy."
  fi
  rm -f /tmp/signup.json
  touch "$marker"; chown nodeapp:nodeapp "$marker"
fi

# ---------- run: public server with sign-up closed ----------
unset ECLAIRE_ALLOW_SIGNUP
log "starting Eclaire on 0.0.0.0:${PORT} (public URL: ${FRONTEND_URL:-not set yet})"
as_app node dist/src/index.js &
app_pid=$!
stopping=""
trap 'stopping=1; kill -TERM "$app_pid" 2>/dev/null || true' TERM INT
set +e
wait "$app_pid"; rc=$?
while [ -z "$stopping" ] && kill -0 "$app_pid" 2>/dev/null; do wait "$app_pid"; rc=$?; done
set -e
if [ -n "$stopping" ]; then exit 0; fi
log "Eclaire exited unexpectedly (code $rc)"
[ "$rc" -eq 0 ] && rc=1
exit "$rc"
