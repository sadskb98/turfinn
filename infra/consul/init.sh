#!/bin/sh
# Populates Consul KV with all Turfinn config. Runs once at stack startup.
# Idempotent — safe to re-run. All writes use PUT (overwrite).
set -e

echo "[consul-init] waiting for consul to be ready..."
until consul members >/dev/null 2>&1; do
  sleep 2
done
echo "[consul-init] consul ready, pushing config..."

kv() {
  consul kv put "turfinn/$1" "${2:-}" >/dev/null
  echo "[consul-init]   turfinn/$1"
}

# ── App ───────────────────────────────────────────────────────────────────
kv app_port                      "${APP_PORT:-8080}"
kv app_base_url                  "${APP_BASE_URL:-http://localhost:8080}"

# ── Database ──────────────────────────────────────────────────────────────
kv db_host                       "${DB_HOST:-postgres}"
kv db_user                       "${DB_USER:-turfinn}"
kv db_password                   "${DB_PASSWORD:-turfinn}"
kv db_name                       "${DB_NAME:-turfinn}"
kv db_port                       "${DB_PORT:-5432}"

# ── Redis / Asynq ─────────────────────────────────────────────────────────
kv redis_addr                    "${REDIS_ADDR:-redis:6379}"
kv asynq_redis_addr              "${ASYNQ_REDIS_ADDR:-redis:6379}"

# ── JWT ───────────────────────────────────────────────────────────────────
kv jwt_secret                    "${JWT_SECRET:-change-me-in-production}"

# ── MinIO ─────────────────────────────────────────────────────────────────
kv minio_endpoint                "${MINIO_ENDPOINT:-minio:9000}"
kv minio_access_key              "${MINIO_ACCESS_KEY:-minioadmin}"
kv minio_secret_key              "${MINIO_SECRET_KEY:-minioadmin}"
kv minio_use_ssl                 "${MINIO_USE_SSL:-false}"

# ── SSLCommerz ────────────────────────────────────────────────────────────
kv sslcz_store_id                "${SSLCZ_STORE_ID:-}"
kv sslcz_store_passwd            "${SSLCZ_STORE_PASSWD:-}"
kv sslcz_base_url                "${SSLCZ_BASE_URL:-https://sandbox.sslcommerz.com}"

# ── Firebase ──────────────────────────────────────────────────────────────
kv firebase_service_account_json "${FIREBASE_SERVICE_ACCOUNT_JSON:-}"

# ── SMS (SSL Wireless) ────────────────────────────────────────────────────
kv sms_api_user                  "${SMS_API_USER:-}"
kv sms_api_pass                  "${SMS_API_PASS:-}"
kv sms_sid                       "${SMS_SID:-}"

# ── CORS ──────────────────────────────────────────────────────────────────
kv cors_origins                  "${CORS_ORIGINS:-}"

# ── Sports content APIs ───────────────────────────────────────────────────
kv api_football_key              "${API_FOOTBALL_KEY:-}"
kv gnews_key                     "${GNEWS_KEY:-}"
kv sports_live_poll_enabled      "${SPORTS_LIVE_POLL_ENABLED:-false}"
kv sports_live_poll_interval     "${SPORTS_LIVE_POLL_INTERVAL:-15s}"

# ── Matchmaking economics + safety policy ─────────────────────────────────
kv match_join_fee_bdt                       "${MATCH_JOIN_FEE_BDT:-20}"
kv match_default_duration_minutes           "${MATCH_DEFAULT_DURATION_MINUTES:-90}"
kv match_late_cancel_hours_threshold        "${MATCH_LATE_CANCEL_HOURS_THRESHOLD:-6}"
kv match_late_cancel_strike_limit           "${MATCH_LATE_CANCEL_STRIKE_LIMIT:-3}"
kv match_late_cancel_strike_window_days     "${MATCH_LATE_CANCEL_STRIKE_WINDOW_DAYS:-30}"
kv match_hosting_ban_days                   "${MATCH_HOSTING_BAN_DAYS:-30}"
kv match_age_gate_min                       "${MATCH_AGE_GATE_MIN:-16}"
kv match_trust_gate_min_successful          "${MATCH_TRUST_GATE_MIN_SUCCESSFUL:-3}"
kv match_auto_suspend_report_threshold      "${MATCH_AUTO_SUSPEND_REPORT_THRESHOLD:-3}"
kv match_external_pitch_verify_min_matches  "${MATCH_EXTERNAL_PITCH_VERIFY_MIN_MATCHES:-3}"
kv match_auto_cancel_buffer_minutes         "${MATCH_AUTO_CANCEL_BUFFER_MINUTES:-30}"
kv match_auto_cancel_min_fill_pct           "${MATCH_AUTO_CANCEL_MIN_FILL_PCT:-50}"

# ── Super-Admin login (email + password) ──────────────────────────────────
# Rotate by editing these values and restarting consul-init (or via
# `consul kv put turfinn/super_admin_password 'new-pass'` directly).
# Viper reads on demand so the next login picks up the new value.
kv super_admin_email    "${SUPER_ADMIN_EMAIL:-admin@turfinn.com}"
kv super_admin_password "${SUPER_ADMIN_PASSWORD:-turfinn@114353}"

COUNT=$(consul kv get -keys turfinn/ | wc -l | tr -d ' ')
echo "[consul-init] done — ${COUNT} keys in turfinn/"
