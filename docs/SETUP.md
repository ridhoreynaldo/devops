# Setup server

## Server baru (Ubuntu 22.04/24.04, root)

```bash
curl -fsSL https://raw.githubusercontent.com/ridhoreynaldo/devops/main/bootstrap.sh | sudo bash
```

`bootstrap.sh` idempotent (aman dijalankan ulang) dan melakukan:

1. Install Docker Engine + Compose plugin (bila belum).
2. Clone/update repo ke `/opt/devops` (override: `BASE_DIR=/opt/lain`).
3. Buat network `global-gateway-net`.
4. Generate semua password ke `<layer>/.env` (`chmod 600`) **hanya bila belum ada**; key yang hilang ditambahkan.
5. Nyalakan layer berurutan: `01-infra` → pasang role PgBouncer → `02-monitoring` → `03-services` → `00-gateway`.
6. Terbitkan SSL untuk `PRIMARY_DOMAIN` (dari `.env` root) bila DNS sudah mengarah ke server.
7. Deploy aplikasi di `04-apps/apps.list` yang sudah punya `.env`.
8. Pasang cron reload nginx harian.

Setelah selesai, lanjut manual:

```bash
cd /opt/devops
cp .env.example .env && nano .env          # PRIMARY_DOMAIN, CERTBOT_EMAIL
make app-db A=wa_gateway                   # database untuk wa-gateway → salin DATABASE_URL
nano 04-apps/wa-gateway/.env               # isi DATABASE_URL, REDIS_URL (REDIS_QUEUE_PASSWORD), superadmin
make deploy A=wa-gateway
cp 00-gateway/nginx/conf.d/wa-gateway.conf.example 00-gateway/nginx/conf.d/wa-gateway.conf
sed -i 's/wa.example.com/wa.domain-anda.com/g' 00-gateway/nginx/conf.d/wa-gateway.conf
make cert D=wa.domain-anda.com && make nginx-reload
crontab -e                                 # backup; lihat docs/OPERATIONS.md
```

## Migrasi dari `/opt/devops-2` (server yang sudah jalan)

Nama container, network, dan **nama volume** tidak berubah (`01-infra_postgres-data`, dst. — compose memakai
nama folder layer sebagai project), jadi data Postgres/SQL Server/Redis tetap terpakai.

```bash
sudo -i
cd /opt
git clone https://github.com/ridhoreynaldo/devops.git /opt/devops
cp /opt/devops-2/01-infra/.env      /opt/devops/01-infra/.env       # password lama tetap dipakai
cp /opt/devops-2/02-monitoring/.env /opt/devops/02-monitoring/.env
cp /opt/devops-2/03-services/.env   /opt/devops/03-services/.env
cp /opt/devops-2/04-apps/.env       /opt/devops/04-apps/.env 2>/dev/null || true
cp -r /opt/devops-2/00-gateway/letsencrypt /opt/devops/00-gateway/   # sertifikat
cp -r /opt/devops-2/00-gateway/ssl         /opt/devops/00-gateway/   # sertifikat manual (jika ada)
cp -r /opt/devops-2/03-services/9router/data /opt/devops/03-services/9router/ 2>/dev/null || true

# matikan stack lama (volume TIDAK dihapus — jangan pakai -v)
for l in 00-gateway 03-services 02-monitoring 01-infra 04-apps; do docker compose -f /opt/devops-2/$l/docker-compose.yml down; done

cd /opt/devops && ./bootstrap.sh     # menambah REDIS_QUEUE_PASSWORD & PGBOUNCER_AUTH_PASSWORD, memasang role pgbouncer_auth
```

Yang berubah untuk aplikasi lama:
- PgBouncer sekarang memakai `auth_query`; user `postgres` tetap bisa login lewat PgBouncer (verifier diambil dari Postgres).
- `wa-gateway` versi JS lama (`03-services/wa-gateway`, port 5000/5001) **dihapus**. Penggantinya repo
  [`wa-gateway`](https://github.com/ridhoreynaldo/wa-gateway) di `04-apps`. Sesi WA lama (folder `sessions/`)
  tidak kompatibel → scan QR ulang. Pemanggil `POST /send-wa` lama sekarang wajib header `Authorization: Bearer <api key>`.
- Setelah yakin semua jalan: `rm -rf /opt/devops-2` (backup `.env`-nya dulu).

## Firewall

```bash
ufw default deny incoming && ufw default allow outgoing
ufw allow OpenSSH && ufw allow 80,443/tcp
ufw enable
```

Database, Redis, Portainer, Grafana, Uptime Kuma hanya di `127.0.0.1`. Akses dari laptop:

```bash
ssh -L 9000:127.0.0.1:9000 -L 3000:127.0.0.1:3000 -L 3001:127.0.0.1:3001 -L 5432:127.0.0.1:5432 user@server
```

## Ukuran server

| Beban | RAM |
|---|---|
| infra + monitoring + 1–2 app kecil | 4 GB |
| + SQL Server Express aktif | 6–8 GB |
| banyak app / banyak nomor WA | 8 GB+, naikkan limit di compose & `postgresql.conf` |
