# devops — infra bersama untuk semua aplikasi

Satu server, satu repo infra, banyak aplikasi. Repo ini menyediakan **gateway, database, cache, antrian,
monitoring, backup**; setiap aplikasi (mis. [`wa-gateway`](https://github.com/ridhoreynaldo/wa-gateway))
hidup di repo sendiri dan di-deploy ke `04-apps/<nama>` dengan menempel ke infra ini.

```
Internet ──► 00-gateway  nginx :80/:443  (SSL, rate-limit, 1 vhost per domain)
                 │  network docker: global-gateway-net
    ┌────────────┼──────────────┬──────────────────┬───────────────┐
    ▼            ▼              ▼                  ▼               ▼
01-infra     02-monitoring   03-services       04-apps/<app>   04-apps/<app>
postgres     prometheus      9router           wa-gateway      (repo lain…)
pgbouncer    grafana                           ├ web
redis cache  uptime-kuma                       ├ worker
redis queue  portainer                         └ migrate
sqlserver    cadvisor
```

| Layer | Isi | Dokumen |
|---|---|---|
| `00-gateway/` | nginx global, SSL (Let's Encrypt/Origin CA), vhost per domain | [README](00-gateway/README.md) |
| `01-infra/` | PostgreSQL 16 + PgBouncer, Redis cache, Redis queue, SQL Server | [README](01-infra/README.md) |
| `02-monitoring/` | Prometheus, Grafana, Uptime Kuma, Portainer, cAdvisor, node-exporter | [README](02-monitoring/README.md) |
| `03-services/` | layanan pendukung tanpa repo sendiri (9router) | — |
| `04-apps/` | **aplikasi = repo terpisah**, didaftarkan di `apps.list` | [README](04-apps/README.md) · [kontrak](docs/APPS.md) |
| `scripts/` | `create-app-db.sh`, `deploy-app.sh`, `issue-cert.sh`, backup, sync Google Drive | [OPERATIONS](docs/OPERATIONS.md) |
| `bootstrap.sh` | server kosong → semua layer jalan, idempotent | [SETUP](docs/SETUP.md) |
| `Makefile` | pintasan: `make up`, `make deploy A=…`, `make cert D=…`, `make nginx-reload` | `make help` |

## Mulai

```bash
# server baru (root)
curl -fsSL https://raw.githubusercontent.com/ridhoreynaldo/devops/main/bootstrap.sh | sudo bash

# tambah aplikasi (contoh wa-gateway)
cd /opt/devops
make app-db A=wa_gateway                  # database + user → DATABASE_URL
make deploy A=wa-gateway                  # clone dari 04-apps/apps.list, lalu minta isi .env → deploy ulang
cp 00-gateway/nginx/conf.d/wa-gateway.conf.example 00-gateway/nginx/conf.d/wa-gateway.conf
sed -i 's/wa.example.com/wa.domain-anda.com/g' 00-gateway/nginx/conf.d/wa-gateway.conf
make cert D=wa.domain-anda.com && make nginx-reload
```

Detail: [docs/SETUP.md](docs/SETUP.md) (termasuk migrasi dari `/opt/devops-2`), [docs/APPS.md](docs/APPS.md),
[docs/OPERATIONS.md](docs/OPERATIONS.md), [docs/SECURITY.md](docs/SECURITY.md).

## Prinsip

- **Aplikasi tidak publish port dan tidak punya DB sendiri.** Masuk lewat gateway, data di `01-infra`.
- **Satu aplikasi = satu role + satu database Postgres** (`scripts/create-app-db.sh`). Superuser hanya untuk admin.
- **Server tidak diedit langsung.** Semua perubahan lewat git → `git pull` / `deploy-app.sh`.
- **Secret tidak pernah di-commit.** `.env` dibuat `bootstrap.sh`; `make secrets-check` sebelum commit.
- Port DB/Redis/monitoring hanya `127.0.0.1`; dari laptop pakai SSH tunnel.
- Image di-pin versinya; log dirotasi; tiap container punya limit memori/CPU dan `no-new-privileges`.

## ⚠ Catatan keamanan

Sebelum Oktober 2026 repo ini pernah berisi private key SSL dan password database di history git.
File sudah dihapus dari tree, tetapi **history masih menyimpannya** sampai di-rewrite dan semua kredensial
tersebut harus dianggap bocor. Langkah rotasi ada di [docs/SECURITY.md](docs/SECURITY.md).
