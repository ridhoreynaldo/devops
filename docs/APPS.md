# Kontrak aplikasi (04-apps)

Repo `devops` menyediakan infra bersama. Aplikasi hidup di repo-nya sendiri dan "menempel" ke infra ini.
Supaya bisa di-deploy dengan `scripts/deploy-app.sh`, sebuah aplikasi harus memenuhi kontrak berikut.

## 1. Punya `docker-compose.yml` sendiri yang join network global

```yaml
services:
  web:
    build: .
    container_name: myapp_web          # ← dirujuk vhost nginx: proxy_pass http://myapp_web:3000
    restart: unless-stopped
    env_file: .env
    networks: [global-gateway-net]
    # TIDAK ada `ports:` — nginx gateway menjangkau lewat network docker

networks:
  global-gateway-net:
    external: true
```

Aturan:
- **Tidak publish port** ke host. Satu-satunya pintu masuk adalah `00-gateway`.
- **Tidak menjalankan DB/Redis sendiri** di produksi. Pakai layer `01-infra`.
- Nama container unik dan stabil: `<app>_web`, `<app>_worker`, …
- Ada endpoint health (`/api/health` atau `/healthz`) untuk healthcheck & Uptime Kuma.
- Hormati `X-Forwarded-Proto`/`X-Real-IP` dari gateway (cookie `secure`, rate limit per IP).
- Migrasi database dijalankan oleh aplikasi sendiri saat start (service `migrate` one-shot, dsb).

## 2. Koneksi ke infra (nama container = hostname)

| Kebutuhan | Host:port | Catatan |
|---|---|---|
| PostgreSQL (query) | `infra_pgbouncer:5432` | transaction pooling → **matikan prepared statement** |
| PostgreSQL (migrasi/admin) | `infra_postgres:5432` | koneksi langsung |
| Redis cache/session | `infra_redis:6379` | `allkeys-lru`, boleh hilang; password `REDIS_PASSWORD` |
| Redis antrian job | `infra_redis_queue:6379` | `noeviction` + AOF; password `REDIS_QUEUE_PASSWORD` |
| SQL Server | `infra_sqlserver:1433` | aplikasi lama |

Database + user per aplikasi (jangan pakai superuser `postgres`):

```bash
./scripts/create-app-db.sh myapp      # → cetak DATABASE_URL untuk .env aplikasi
```

## 3. Daftarkan di `04-apps/apps.list`

```
myapp   https://github.com/ridhoreynaldo/myapp.git   main
```

`bootstrap.sh` dan `deploy-app.sh` membaca daftar ini. `.env` aplikasi dibuat dari `.env.example`-nya saat
deploy pertama dan **harus diisi manual** (deploy berhenti dengan peringatan sampai diisi).

## 4. Vhost di gateway

```bash
cd 00-gateway/nginx
sed 's/__DOMAIN__/app.example.com/g; s/__UPSTREAM__/myapp_web:3000/g' templates/app-ssl.conf.template > conf.d/app-example-com.conf
cd ../.. && ./scripts/issue-cert.sh app.example.com && make nginx-reload
```

Upstream ditulis sebagai variabel (`set $upstream …`) sehingga nginx tetap hidup walau container aplikasi
belum/tidak jalan — hanya domain itu yang 502.

## 5. Alur deploy

```
git push (repo aplikasi) ──► server: ./scripts/deploy-app.sh myapp
                                      = git fetch + reset --hard FETCH_HEAD
                                        docker compose up -d --build --remove-orphans
```

Server tidak pernah diedit langsung; semua perubahan lewat git. Rollback = checkout commit lama lalu deploy ulang.

## Contoh nyata

[`wa-gateway`](https://github.com/ridhoreynaldo/wa-gateway) — `docker-compose.yml`-nya mengikuti kontrak ini
(service `migrate`, `web`, `worker`; container `wa_gateway_web`; vhost `00-gateway/nginx/conf.d/wa-gateway.conf.example`).
