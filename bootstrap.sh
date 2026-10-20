#!/bin/bash
# Bootstrap server untuk repo devops: install Docker, clone/update repo, generate secret,
# nyalakan semua layer infra, lalu deploy aplikasi di 04-apps/apps.list.
# IDEMPOTENT — aman dijalankan ulang kapan pun (mis. setelah git pull).
#
# Server baru (root):
#   curl -fsSL https://raw.githubusercontent.com/ridhoreynaldo/devops/main/bootstrap.sh | sudo bash
# Opsi lewat env:
#   BASE_DIR=/opt/devops   BRANCH=main   PUBLIC_PORTS=1 (buka port service ke 0.0.0.0 — hindari)
set -euo pipefail

BRANCH="${BRANCH:-main}"
REPO_URL="${REPO_URL:-https://github.com/ridhoreynaldo/devops.git}"
BASE_DIR="${BASE_DIR:-/opt/devops}"
NETWORK="global-gateway-net"
[ "${PUBLIC_PORTS:-0}" = "1" ] && export BIND_IP="0.0.0.0"

log()  { echo -e "\033[1;32m[bootstrap]\033[0m $*"; }
warn() { echo -e "\033[1;33m[bootstrap][WARN]\033[0m $*"; }
die()  { echo -e "\033[1;31m[bootstrap][ERROR]\033[0m $*" >&2; exit 1; }
gen_pass() { openssl rand -base64 24 | tr -d '\n/+='; }

[ "$(id -u)" -eq 0 ] || die "Jalankan sebagai root (sudo -i dulu)."

# Gagal cepat bila disk sempit: build image butuh GB-an.
AVAIL_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
[ "$AVAIL_GB" -ge 5 ] || die "Disk tersisa ${AVAIL_GB}GB < 5GB. Bersihkan dulu: docker system prune, apt clean."
log "Disk tersedia: ${AVAIL_GB}GB."

# ----------------------------------------------------------
# 1. Docker Engine + git
# ----------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Install Docker Engine dari repo resmi..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg git
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
else
  log "Docker: $(docker --version)"
fi
command -v git >/dev/null 2>&1 || apt-get install -y -qq git
command -v make >/dev/null 2>&1 || apt-get install -y -qq make

# ----------------------------------------------------------
# 2. Clone / update repo
# ----------------------------------------------------------
if [ -d "$BASE_DIR/.git" ]; then
  log "Update repo di $BASE_DIR (branch $BRANCH)..."
  git -C "$BASE_DIR" fetch origin "$BRANCH"
  git -C "$BASE_DIR" reset --hard FETCH_HEAD
  git -C "$BASE_DIR" checkout -B "$BRANCH"
else
  log "Clone $REPO_URL ke $BASE_DIR..."
  git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$BASE_DIR"
fi
cd "$BASE_DIR"
chmod +x bootstrap.sh scripts/*.sh 01-infra/postgres/initdb/*.sh

# ----------------------------------------------------------
# 3. Network global
# ----------------------------------------------------------
docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK"
log "Network $NETWORK siap."

# ----------------------------------------------------------
# 4. Secrets — buat bila belum ada; key yang hilang ditambahkan (self-healing)
# ----------------------------------------------------------
ensure_env() { # ensure_env <file> <KEY> <value-bila-belum-ada>
  local f="$1" k="$2" v="$3"
  touch "$f"; chmod 600 "$f"
  grep -q "^${k}=" "$f" || { printf '%s=%s\n' "$k" "$v" >> "$f"; log "  + $k → $f"; }
}
env_get() { grep "^$2=" "$1" 2>/dev/null | head -1 | cut -d= -f2-; }

log "Secrets..."
I="01-infra/.env"
ensure_env "$I" POSTGRES_PASSWORD        "$(gen_pass)"
ensure_env "$I" PGBOUNCER_AUTH_PASSWORD  "$(gen_pass)"
ensure_env "$I" REDIS_PASSWORD           "$(gen_pass)"
ensure_env "$I" REDIS_QUEUE_PASSWORD     "$(gen_pass)"
ensure_env "$I" MSSQL_SA_PASSWORD        "$(gen_pass)Aa1!"
ensure_env "$I" BIND_IP                  "${BIND_IP:-127.0.0.1}"
[ -n "${BIND_IP:-}" ] && sed -i "s|^BIND_IP=.*|BIND_IP=$BIND_IP|" "$I"
ensure_env "02-monitoring/.env" GRAFANA_ADMIN_PASSWORD "$(gen_pass)"
ensure_env "03-services/.env"   NINEROUTER_PASSWORD    "$(gen_pass)"
[ -f scripts/.env ] || { cp scripts/.env.example scripts/.env; chmod 600 scripts/.env; warn "scripts/.env masih placeholder — isi kredensial rclone untuk sync backup ke Google Drive."; }
[ -f .env ] || { cp .env.example .env; chmod 600 .env; }

# userlist PgBouncer: hanya role pgbouncer_auth. Penggantian string bash (bukan sed) → aman untuk karakter apa pun.
PGB_PASS=$(env_get "$I" PGBOUNCER_AUTH_PASSWORD)
while IFS= read -r line; do printf '%s\n' "${line//PGBOUNCER_AUTH_PASSWORD_DARI_ENV/$PGB_PASS}"; done \
  < 01-infra/postgres/userlist.txt.example > 01-infra/postgres/userlist.txt
chmod 644 01-infra/postgres/userlist.txt   # dibaca user non-root di container pgbouncer
mkdir -p 01-infra/backup/postgresql 01-infra/backup/sqlserver 00-gateway/logs 00-gateway/letsencrypt 00-gateway/certbot/www 00-gateway/ssl 03-services/9router/data

# ----------------------------------------------------------
# 5. Layer berurutan
# ----------------------------------------------------------
wait_healthy() { # wait_healthy <container> <timeout_detik>
  local c="$1" t="$2" i=0 s
  while [ "$i" -lt "$t" ]; do
    s=$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo none)
    [ "$s" = healthy ] && { log "$c healthy."; return 0; }
    [ "$s" = none ] && return 0
    sleep 5; i=$((i+5))
  done
  warn "$c belum healthy setelah ${t}s — cek: docker logs $c"
}

log "== Layer 1: 01-infra =="
docker compose -f 01-infra/docker-compose.yml up -d
wait_healthy infra_postgres 180

# Sinkron password superuser dengan .env (volume lama bisa punya password lain) + pasang role PgBouncer.
PG_PASS=$(env_get "$I" POSTGRES_PASSWORD)
docker exec infra_postgres psql -U postgres -qc "ALTER USER postgres PASSWORD '$PG_PASS';" >/dev/null 2>&1 \
  && log "Password postgres sinkron dengan 01-infra/.env." || warn "Gagal sinkron password postgres."
docker exec -e PGBOUNCER_AUTH_PASSWORD="$PGB_PASS" infra_postgres bash /docker-entrypoint-initdb.d/01-pgbouncer-auth.sh \
  && log "Role pgbouncer_auth siap." || warn "Gagal memasang role pgbouncer_auth — PgBouncer tidak akan bisa autentikasi."
docker restart infra_pgbouncer >/dev/null   # baca userlist baru
wait_healthy infra_pgbouncer 60

log "== Layer 2: 02-monitoring =="
docker compose -f 02-monitoring/docker-compose.yml up -d

log "== Layer 3: 03-services =="
docker compose -f 03-services/docker-compose.yml up -d

log "== Layer 4: 00-gateway =="
# shellcheck disable=SC1091
set -a; . ./.env; set +a
PRIMARY_DOMAIN="${PRIMARY_DOMAIN:-}"
SSL_CONF="00-gateway/nginx/conf.d/${PRIMARY_DOMAIN//./-}-ssl.conf"
LE_LIVE="00-gateway/letsencrypt/live/$PRIMARY_DOMAIN"
# vhost 443 domain utama hanya bila sertifikatnya ada (agar nginx -t tidak gagal)
if [ -n "$PRIMARY_DOMAIN" ] && [ -f "$LE_LIVE/fullchain.pem" ]; then
  sed "s/__DOMAIN__/$PRIMARY_DOMAIN/g" 00-gateway/nginx/templates/primary-domain-ssl.conf.template > "$SSL_CONF"
else
  rm -f 00-gateway/nginx/conf.d/*-ssl.conf
fi
docker compose -f 00-gateway/docker-compose.yml up -d
docker exec global_gateway nginx -t

# Terbitkan sertifikat domain utama lewat webroot (gateway sudah jalan), lalu pasang vhost 443
if [ -n "$PRIMARY_DOMAIN" ] && [ ! -f "$LE_LIVE/fullchain.pem" ]; then
  VPS_IP=$(curl -4 -fsSL --max-time 5 ifconfig.me 2>/dev/null || true)
  DOM_IP=$(getent ahostsv4 "$PRIMARY_DOMAIN" 2>/dev/null | awk '{print $1}' | head -1 || true)
  if [ -n "$VPS_IP" ] && [ "$DOM_IP" = "$VPS_IP" ]; then
    if ./scripts/issue-cert.sh "$PRIMARY_DOMAIN" "www.$PRIMARY_DOMAIN"; then
      sed "s/__DOMAIN__/$PRIMARY_DOMAIN/g" 00-gateway/nginx/templates/primary-domain-ssl.conf.template > "$SSL_CONF"
      docker exec global_gateway nginx -t && docker exec global_gateway nginx -s reload
      log "HTTPS $PRIMARY_DOMAIN aktif."
    else
      warn "Sertifikat $PRIMARY_DOMAIN gagal terbit — lanjut tanpa HTTPS."
    fi
  else
    warn "$PRIMARY_DOMAIN tidak mengarah ke IP server ini ($VPS_IP) — lewati SSL. (Cloudflare proxy? pakai Origin CA di 00-gateway/ssl/)"
  fi
fi

# Cron: reload nginx harian supaya sertifikat hasil auto-renew terpakai
if command -v crontab >/dev/null 2>&1 && ! crontab -l 2>/dev/null | grep -q "global_gateway nginx -s reload"; then
  (crontab -l 2>/dev/null; echo "17 3 * * * docker exec global_gateway nginx -s reload >/dev/null 2>&1 || true") | crontab -
  log "Cron reload nginx dipasang."
fi

# ----------------------------------------------------------
# 6. Layer 5: aplikasi
# ----------------------------------------------------------
log "== Layer 5: 04-apps =="

# (a) legacy: portfolio — tanpa compose sendiri, dibangun oleh 04-apps/docker-compose.yml
if [ -d 04-apps/portfolio/.git ] || git ls-remote -q https://github.com/ridhoreynaldo/portfolio >/dev/null 2>&1; then
  if [ ! -d 04-apps/portfolio/.git ]; then
    git clone --depth 1 https://github.com/ridhoreynaldo/portfolio 04-apps/portfolio || warn "Clone portfolio gagal."
  else
    git -C 04-apps/portfolio fetch --depth 1 origin main >/dev/null 2>&1 && git -C 04-apps/portfolio reset -q --hard FETCH_HEAD || warn "Update portfolio gagal — pakai versi lokal."
  fi
  if [ -d 04-apps/portfolio/.git ]; then
    A="04-apps/.env"
    ensure_env "$A" PGHOST infra_pgbouncer; ensure_env "$A" PGPORT 5432; ensure_env "$A" PGUSER postgres
    ensure_env "$A" PGPASSWORD "$PG_PASS"; ensure_env "$A" PGDATABASE portfolio
    ensure_env "$A" JWT_SECRET "$(openssl rand -hex 32)"; ensure_env "$A" ADMIN_EMAIL admin@local
    ensure_env "$A" ADMIN_PASSWORD "$(gen_pass)"; ensure_env "$A" PORTFOLIO_PORT 3002
    sed -i "s|^PGPASSWORD=.*|PGPASSWORD=$PG_PASS|" "$A"   # ikut password superuser aktif
    docker exec -e PGPASSWORD="$PG_PASS" infra_postgres psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='portfolio'" | grep -q 1 \
      || docker exec -e PGPASSWORD="$PG_PASS" infra_postgres psql -U postgres -c "CREATE DATABASE portfolio" >/dev/null
    docker compose -f 04-apps/docker-compose.yml up -d --build || warn "Deploy portfolio gagal."
  fi
fi

# (b) aplikasi dengan compose sendiri — 04-apps/apps.list
while read -r name url branch; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  log "-- $name"
  if ./scripts/deploy-app.sh "$name" "${branch:-main}"; then :; else
    rc=$?
    [ "$rc" -eq 2 ] && warn "$name: isi 04-apps/$name/.env lalu jalankan: make deploy A=$name" || warn "$name: deploy gagal (exit $rc)."
  fi
done < 04-apps/apps.list

# ----------------------------------------------------------
# 7. Firewall & ringkasan
# ----------------------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 80,443/tcp >/dev/null
  [ "${PUBLIC_PORTS:-0}" = "1" ] && ufw allow 3002,5432,1433,3000,3001,9000,20128/tcp >/dev/null && warn "PUBLIC_PORTS=1: port DB/monitoring terbuka ke publik."
fi

log "Selesai. Container:"
docker ps --format '  {{.Names}}  {{.Status}}' | sort
echo
log "Password dashboard: 02-monitoring/.env (Grafana), 03-services/.env (9Router), 04-apps/.env (portfolio ADMIN_PASSWORD)."
log "Berikutnya: make app-db A=<app>  →  isi 04-apps/<app>/.env  →  make deploy A=<app>  →  vhost + make cert D=<domain>"
[ -z "$PRIMARY_DOMAIN" ] && warn "PRIMARY_DOMAIN kosong di .env — HTTPS domain utama belum dipasang."
warn "Amankan SSH: pakai key, matikan login password; firewall hanya 22/80/443."
