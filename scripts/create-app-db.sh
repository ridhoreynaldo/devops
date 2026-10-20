#!/usr/bin/env bash
# Buat database + user khusus untuk satu aplikasi (prinsip: satu app = satu role = satu database).
#
#   ./scripts/create-app-db.sh <nama_app> [--reset-password]
#   contoh: ./scripts/create-app-db.sh wa_gateway
#
# Idempotent: role yang sudah ada tidak diubah password-nya kecuali --reset-password.
# Database yang SUDAH ADA (mis. dibuat versi lama oleh superuser) tetap dipakai: kepemilikan
# database, schema, tabel, sequence, dan enum dipindahkan ke role aplikasi supaya migrasi
# aplikasi (ALTER/DROP TABLE) bisa berjalan tanpa superuser.
# Output: baris DATABASE_URL yang bisa langsung ditempel ke .env aplikasi.
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

APP="${1:-}"; RESET="${2:-}"
[[ "$APP" =~ ^[a-z][a-z0-9_]{1,40}$ ]] || { echo "Nama app: huruf kecil/angka/underscore, mis. wa_gateway" >&2; exit 1; }

# shellcheck disable=SC1091
set -a; . "$BASE_DIR/01-infra/.env"; set +a
psql_admin() { docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" infra_postgres psql -v ON_ERROR_STOP=1 -U postgres -d "${1:-postgres}" -tAq; }

role_exists=$(psql_admin <<<"SELECT 1 FROM pg_roles WHERE rolname='$APP'" || true)
db_exists=$(psql_admin <<<"SELECT 1 FROM pg_database WHERE datname='$APP'" || true)

PASS=""
if [ -z "$role_exists" ]; then
  PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-32)
  psql_admin <<<"CREATE ROLE \"$APP\" LOGIN PASSWORD '$PASS' NOSUPERUSER NOCREATEDB NOCREATEROLE;"
  echo "✔ role $APP dibuat"
elif [ "$RESET" = "--reset-password" ]; then
  PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-32)
  psql_admin <<<"ALTER ROLE \"$APP\" PASSWORD '$PASS';"
  echo "✔ password $APP di-reset"
else
  echo "ℹ role $APP sudah ada (password tidak diubah; pakai --reset-password untuk ganti)"
fi

if [ -z "$db_exists" ]; then
  psql_admin <<<"CREATE DATABASE \"$APP\" OWNER \"$APP\" TEMPLATE template1;"
  echo "✔ database $APP dibuat"
else
  echo "ℹ database $APP sudah ada — memindahkan kepemilikan objek ke $APP"
fi

# Kepemilikan (idempotent): database, schema public & drizzle, semua tabel/sequence/enum di dalamnya.
psql_admin <<<"ALTER DATABASE \"$APP\" OWNER TO \"$APP\";"
psql_admin "$APP" <<SQL
DO \$\$
DECLARE r record;
BEGIN
  FOR r IN SELECT nspname FROM pg_namespace WHERE nspname IN ('public','drizzle') LOOP
    EXECUTE format('ALTER SCHEMA %I OWNER TO %I', r.nspname, '$APP');
  END LOOP;
  FOR r IN SELECT schemaname, tablename FROM pg_tables WHERE schemaname IN ('public','drizzle') LOOP
    EXECUTE format('ALTER TABLE %I.%I OWNER TO %I', r.schemaname, r.tablename, '$APP');
  END LOOP;
  FOR r IN SELECT sequence_schema, sequence_name FROM information_schema.sequences WHERE sequence_schema IN ('public','drizzle') LOOP
    EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO %I', r.sequence_schema, r.sequence_name, '$APP');
  END LOOP;
  FOR r IN SELECT n.nspname, t.typname FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
           WHERE t.typtype = 'e' AND n.nspname IN ('public','drizzle') LOOP
    EXECUTE format('ALTER TYPE %I.%I OWNER TO %I', r.nspname, r.typname, '$APP');
  END LOOP;
END
\$\$;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SQL
echo "✔ kepemilikan objek database $APP → role $APP"

echo
if [ -n "$PASS" ]; then
  echo "Tempel ke .env aplikasi (host = nama container di network global-gateway-net):"
  echo "DATABASE_URL=postgres://$APP:$PASS@infra_pgbouncer:5432/$APP"
  echo "DATABASE_URL_DIRECT=postgres://$APP:$PASS@infra_postgres:5432/$APP"
  echo
  echo "⚠ Password hanya ditampilkan sekali ini. Simpan sekarang."
else
  echo "DATABASE_URL=postgres://$APP:<password lama>@infra_pgbouncer:5432/$APP"
  echo "DATABASE_URL_DIRECT=postgres://$APP:<password lama>@infra_postgres:5432/$APP"
fi
