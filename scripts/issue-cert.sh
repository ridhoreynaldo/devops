#!/usr/bin/env bash
# Terbitkan sertifikat Let's Encrypt untuk domain lewat gateway yang SUDAH berjalan (webroot).
# Tidak perlu stop nginx: server port 80 default sudah melayani /.well-known/acme-challenge/.
#
#   ./scripts/issue-cert.sh wa.example.com [www.wa.example.com ...]
#   CERTBOT_EMAIL=admin@example.com ./scripts/issue-cert.sh example.com www.example.com
#
# Sertifikat: 00-gateway/letsencrypt/live/<domain pertama>/fullchain.pem & privkey.pem
# Auto-renew: container certbot_auto_renew (00-gateway) + cron reload nginx (bootstrap).
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 1 ] || { echo "pakai: issue-cert.sh <domain> [domain2 ...]" >&2; exit 1; }

# ambil CERTBOT_EMAIL dari .env root bila ada
[ -f "$BASE_DIR/.env" ] && { set -a; . "$BASE_DIR/.env"; set +a; }

docker inspect -f '{{.State.Running}}' global_gateway 2>/dev/null | grep -q true \
  || { echo "Container global_gateway belum jalan: cd 00-gateway && docker compose up -d" >&2; exit 1; }

VPS_IP=$(curl -4 -fsSL --max-time 5 ifconfig.me 2>/dev/null || true)
for d in "$@"; do
  DIP=$(getent ahostsv4 "$d" 2>/dev/null | awk '{print $1}' | head -1 || true)
  [ -n "$DIP" ] || { echo "⚠ $d belum punya A record" >&2; }
  [ -n "$VPS_IP" ] && [ -n "$DIP" ] && [ "$DIP" != "$VPS_IP" ] && echo "⚠ $d → $DIP, server ini $VPS_IP (Cloudflare proxy? pakai mode DNS only sementara, atau Origin CA)" >&2
done

DOMAIN_ARGS=(); for d in "$@"; do DOMAIN_ARGS+=(-d "$d"); done
if [ -n "${CERTBOT_EMAIL:-}" ]; then EMAIL_ARGS=(--email "$CERTBOT_EMAIL"); else EMAIL_ARGS=(--register-unsafely-without-email); fi

mkdir -p "$BASE_DIR/00-gateway/letsencrypt" "$BASE_DIR/00-gateway/certbot/www"
docker run --rm \
  -v "$BASE_DIR/00-gateway/letsencrypt:/etc/letsencrypt" \
  -v "$BASE_DIR/00-gateway/certbot/www:/var/www/certbot" \
  certbot/certbot:v2.11.0 certonly --webroot -w /var/www/certbot \
  "${DOMAIN_ARGS[@]}" --non-interactive --agree-tos --keep-until-expiring "${EMAIL_ARGS[@]}"

echo "✔ sertifikat: 00-gateway/letsencrypt/live/$1/"
echo "  Pasang vhost 443 di 00-gateway/nginx/conf.d/ lalu: make nginx-reload"
