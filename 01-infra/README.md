# 01-infra — layer data

| Service | Container | Port internal | Dipakai untuk |
|---|---|---|---|
| PostgreSQL 16 | `infra_postgres` | 5432 | migrasi/admin/backup (koneksi langsung) |
| PgBouncer 1.25 | `infra_pgbouncer` | 5432 | **semua query aplikasi** (transaction pooling) |
| Redis cache | `infra_redis` | 6379 | cache, session, rate-limit — boleh hilang |
| Redis queue | `infra_redis_queue` | 6379 | antrian job (BullMQ) — `noeviction` + AOF |
| SQL Server 2022 Express | `infra_sqlserver` | 1433 | aplikasi lama |

Port host hanya `127.0.0.1` (`BIND_IP` di `.env`). Aplikasi memakai nama container sebagai host lewat network `global-gateway-net`.

## Database per aplikasi

```bash
../scripts/create-app-db.sh nama_app      # role + database, cetak DATABASE_URL
```

PgBouncer memakai `auth_query`: user baru cukup ada di Postgres, `userlist.txt` tidak perlu diubah
(isinya hanya role `pgbouncer_auth`, dibuat oleh `postgres/initdb/01-pgbouncer-auth.sh` dan dipasang ulang
setiap `bootstrap.sh` agar volume lama ikut punya).

## File

```
docker-compose.yml
.env(.example)               # password (bootstrap men-generate)
postgres/postgresql.conf     # tuning untuk container 1.5 GB — naikkan shared_buffers bila RAM lebih besar
postgres/pgbouncer.ini
postgres/userlist.txt(.example)
postgres/initdb/             # dijalankan saat volume pertama dibuat (+ ulang oleh bootstrap)
redis/cache.conf             # allkeys-lru, no persistence
redis/queue.conf             # noeviction, appendonly
backup/                      # hasil scripts/backup-*.sh (di-ignore git)
```

## Log

```bash
docker compose logs -f                     # semua
docker logs -f infra_postgres              # query > 500 ms tercatat (log_min_duration_statement)
docker logs --tail 50 infra_pgbouncer
make -C .. pgbouncer-stats                 # SHOW POOLS / SHOW STATS
make -C .. slow-queries                    # pg_stat_statements
```
