#!/usr/bin/env bash
# Buat database + user khusus untuk satu aplikasi (prinsip: satu app = satu role = satu database).
#
#   ./scripts/create-app-db.sh <nama_app> [--reset-password]
#   contoh: ./scripts/create-app-db.sh wa_gateway
#
# Idempotent: kalau role sudah ada, password TIDAK diubah kecuali --reset-password.
# Output: baris DATABASE_URL yang bisa langsung ditempel ke .env aplikasi.
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

APP="${1:-}"; RESET="${2:-}"
[[ "$APP" =~ ^[a-z][a-z0-9_]{1,40}$ ]] || { echo "Nama app: huruf kecil/angka/underscore, mis. wa_gateway" >&2; exit 1; }

# shellcheck disable=SC1091
set -a; . "$BASE_DIR/01-infra/.env"; set +a
PSQL=(docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" infra_postgres psql -v ON_ERROR_STOP=1 -U postgres -d postgres -tA)

role_exists=$("${PSQL[@]}" -c "SELECT 1 FROM pg_roles WHERE rolname='$APP'" || true)
db_exists=$("${PSQL[@]}" -c "SELECT 1 FROM pg_database WHERE datname='$APP'" || true)

PASS=""
if [ -z "$role_exists" ]; then
  PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-32)
  "${PSQL[@]}" -c "CREATE ROLE \"$APP\" LOGIN PASSWORD '$PASS' NOSUPERUSER NOCREATEDB NOCREATEROLE;"
  echo "✔ role $APP dibuat"
elif [ "$RESET" = "--reset-password" ]; then
  PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-32)
  "${PSQL[@]}" -c "ALTER ROLE \"$APP\" PASSWORD '$PASS';"
  echo "✔ password $APP di-reset"
else
  echo "ℹ role $APP sudah ada (password tidak diubah; pakai --reset-password untuk ganti)"
fi

if [ -z "$db_exists" ]; then
  "${PSQL[@]}" -c "CREATE DATABASE \"$APP\" OWNER \"$APP\" TEMPLATE template1;"
  echo "✔ database $APP dibuat"
else
  echo "ℹ database $APP sudah ada"
fi
# Pastikan owner & hak akses benar (idempotent); tutup akses PUBLIC ke schema public
"${PSQL[@]}" -c "ALTER DATABASE \"$APP\" OWNER TO \"$APP\";"
docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" infra_postgres psql -v ON_ERROR_STOP=1 -U postgres -d "$APP" -q \
  -c "ALTER SCHEMA public OWNER TO \"$APP\"; REVOKE CREATE ON SCHEMA public FROM PUBLIC;"

echo
if [ -n "$PASS" ]; then
  echo "Tempel ke .env aplikasi (host = nama container di network global-gateway-net):"
  echo "DATABASE_URL=postgres://$APP:$PASS@infra_pgbouncer:5432/$APP"
  echo "DATABASE_URL_DIRECT=postgres://$APP:$PASS@infra_postgres:5432/$APP"
  echo
  echo "⚠ Password hanya ditampilkan sekali ini. Simpan sekarang."
else
  echo "DATABASE_URL=postgres://$APP:<password lama>@infra_pgbouncer:5432/$APP"
fi
