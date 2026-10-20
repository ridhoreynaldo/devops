#!/bin/bash
# Role + fungsi yang dipakai PgBouncer (auth_query) untuk membaca verifier password user aplikasi.
#
# Dijalankan otomatis oleh image postgres saat volume PERTAMA kali dibuat, dan dijalankan
# ulang oleh bootstrap.sh setiap boot (idempotent) supaya volume lama juga punya role ini:
#   docker exec -e PGBOUNCER_AUTH_PASSWORD=... infra_postgres bash /docker-entrypoint-initdb.d/01-pgbouncer-auth.sh
set -euo pipefail
: "${PGBOUNCER_AUTH_PASSWORD:?PGBOUNCER_AUTH_PASSWORD belum diset}"
PGUSER_ADMIN="${POSTGRES_USER:-postgres}"

# auth_dbname = postgres → fungsi cukup ada di database postgres.
# template1 ikut diisi supaya database baru juga punya (jaga-jaga bila auth_dbname diubah).
for DB in postgres template1; do
  psql -v ON_ERROR_STOP=1 -U "$PGUSER_ADMIN" -d "$DB" <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgbouncer_auth') THEN
    CREATE ROLE pgbouncer_auth LOGIN;
  END IF;
END
\$\$;
ALTER ROLE pgbouncer_auth WITH LOGIN PASSWORD '${PGBOUNCER_AUTH_PASSWORD}' NOSUPERUSER NOCREATEDB NOCREATEROLE;

CREATE SCHEMA IF NOT EXISTS pgbouncer;
CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_usename TEXT)
RETURNS TABLE(usename name, passwd text)
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS
\$\$ SELECT usename, passwd FROM pg_catalog.pg_shadow WHERE usename = p_usename \$\$;
REVOKE ALL ON FUNCTION pgbouncer.get_auth(text) FROM PUBLIC;
GRANT USAGE ON SCHEMA pgbouncer TO pgbouncer_auth;
GRANT EXECUTE ON FUNCTION pgbouncer.get_auth(text) TO pgbouncer_auth;
SQL
done

# Ekstensi statistik query (shared_preload_libraries sudah di postgresql.conf)
psql -v ON_ERROR_STOP=1 -U "$PGUSER_ADMIN" -d postgres -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
echo "[initdb] pgbouncer_auth siap."
