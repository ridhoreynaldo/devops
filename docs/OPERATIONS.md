# Operasional harian

Semua perintah dari `/opt/devops`. `make help` menampilkan daftar pintasan.

## Status & log

```bash
make ps                          # semua container + status health
make logs C=infra_postgres       # log satu container (ikuti)
docker compose -f 01-infra/docker-compose.yml ps
docker stats --no-stream         # pemakaian RAM/CPU per container
```

## Gateway nginx

```bash
make nginx-test                  # cek sintaks sebelum reload
make nginx-reload                # terapkan perubahan conf.d/ tanpa downtime
tail -f 00-gateway/logs/access.log
make cert D="app.example.com"    # SSL Let's Encrypt (gateway harus sudah jalan)
```

Tambah domain/aplikasi baru → `docs/APPS.md`.

## Aplikasi

```bash
make deploy A=wa-gateway         # git pull + compose up --build (04-apps/wa-gateway)
docker compose -f 04-apps/wa-gateway/docker-compose.yml -p wa-gateway logs -f worker
make app-db A=nama_app           # database + user baru untuk aplikasi
```

## Database

```bash
make pg                          # psql superuser
make pgbouncer-stats             # SHOW POOLS / SHOW STATS
make slow-queries                # top 15 query lambat (pg_stat_statements)
docker logs infra_postgres 2>&1 | grep "duration:"     # query > 500 ms
```

Backup (harian lewat cron, retensi 14 hari; file di `01-infra/backup/postgresql/<tanggal>/`):

```bash
make backup                                            # manual
crontab -e
30 2 * * * /opt/devops/scripts/backup-postgres.sh
0  3 * * * /opt/devops/scripts/backup-sqlserver.sh
0  4 * * * /opt/devops/scripts/sync-gdrive.sh          # butuh scripts/.env (rclone)
17 3 * * * docker exec global_gateway nginx -s reload >/dev/null 2>&1   # sertifikat hasil renew terpakai
```

Restore satu database dari `pg_dumpall`:

```bash
gunzip -c 01-infra/backup/postgresql/DD-MM-YYYY/pg_dumpall-DD-MM-YYYY.sql.gz \
  | docker exec -i -e PGPASSWORD="$(grep ^POSTGRES_PASSWORD= 01-infra/.env | cut -d= -f2-)" infra_postgres psql -U postgres
```

## Redis

```bash
docker exec -it infra_redis       redis-cli -a "$(grep ^REDIS_PASSWORD= 01-infra/.env | cut -d= -f2-)" info memory
docker exec -it infra_redis_queue redis-cli -a "$(grep ^REDIS_QUEUE_PASSWORD= 01-infra/.env | cut -d= -f2-)" info persistence
```

Redis queue penuh (`OOM command not allowed`, policy `noeviction`) → naikkan `maxmemory` di `01-infra/redis/queue.conf`
dan limit container, lalu `docker compose -f 01-infra/docker-compose.yml up -d redis-queue`.

## Update infra

```bash
git pull --ff-only
make up                          # compose up -d semua layer (hanya yang berubah di-recreate)
make nginx-reload
```

Upgrade major PostgreSQL (16 → 17) **tidak** bisa dengan ganti tag image: perlu `pg_dumpall` → volume baru → restore.
Jadwalkan khusus; jangan ubah `image: postgres:16-alpine` sambil lalu.

## Kapasitas

| Komponen | Default | Naikkan bila |
|---|---|---|
| Postgres `shared_buffers` 384 MB, limit 1.5 GB | VPS 4 GB | banyak app; set ≈25% RAM container |
| PgBouncer `default_pool_size` 15, `max_db_connections` 60 | ≤ 4 app | `SHOW POOLS` menunjukkan `cl_waiting` > 0 terus |
| Redis cache 256 MB | — | hit rate turun (`info stats`) |
| Redis queue 512 MB | — | `used_memory` mendekati `maxmemory` |

## Troubleshooting cepat

| Gejala | Cek |
|---|---|
| App "password authentication failed" via pgbouncer | user ada di Postgres? `make pg` → `\du`; role `pgbouncer_auth` ada? jalankan ulang `sudo ./bootstrap.sh` |
| App "prepared statement does not exist" | app harus matikan prepared statement (transaction pooling) |
| nginx 502 untuk satu domain | container upstream mati: `make ps`; nama container di vhost cocok? |
| nginx tidak mau start | `make nginx-test`; sertifikat yang dirujuk vhost belum ada → terbitkan dulu atau hapus vhost |
| Disk penuh | `docker system df`, `docker image prune -a`, log di `00-gateway/logs/`, backup lama |
