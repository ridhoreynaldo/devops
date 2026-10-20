#!/usr/bin/env bash
# Deploy / update satu aplikasi di 04-apps/<nama>: git pull (fast-forward) + compose up --build.
#
#   ./scripts/deploy-app.sh <nama> [branch]
#   contoh: ./scripts/deploy-app.sh wa-gateway
#
# Aplikasi harus punya docker-compose.yml sendiri yang join network global-gateway-net
# (lihat docs/APPS.md). Kalau belum di-clone, baca URL dari 04-apps/apps.list.
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?pakai: deploy-app.sh <nama> [branch]}"
BRANCH="${2:-}"
DIR="$BASE_DIR/04-apps/$NAME"

if [ ! -d "$DIR/.git" ]; then
  LINE=$(grep -E "^$NAME[[:space:]]" "$BASE_DIR/04-apps/apps.list" 2>/dev/null | head -1 || true)
  [ -n "$LINE" ] || { echo "Aplikasi '$NAME' belum di-clone dan tidak ada di 04-apps/apps.list" >&2; exit 1; }
  URL=$(awk '{print $2}' <<<"$LINE"); BRANCH="${BRANCH:-$(awk '{print $3}' <<<"$LINE")}"
  echo "→ clone $URL ($BRANCH) ke $DIR"
  git clone --branch "${BRANCH:-main}" --depth 1 "$URL" "$DIR"
else
  BRANCH="${BRANCH:-$(git -C "$DIR" rev-parse --abbrev-ref HEAD)}"
  echo "→ update $NAME ($BRANCH)"
  git -C "$DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$DIR" reset --hard FETCH_HEAD   # server tidak pernah di-edit langsung; selalu ikut remote
fi

if [ ! -f "$DIR/.env" ]; then
  if [ -f "$DIR/.env.example" ]; then
    cp "$DIR/.env.example" "$DIR/.env"; chmod 600 "$DIR/.env"
    echo "⚠ $DIR/.env dibuat dari .env.example — ISI dulu (DATABASE_URL, REDIS_URL, ...) lalu jalankan ulang." >&2
    exit 2
  fi
fi

[ -f "$DIR/docker-compose.yml" ] || { echo "Tidak ada docker-compose.yml di $DIR" >&2; exit 1; }
docker compose -f "$DIR/docker-compose.yml" --project-name "$NAME" up -d --build --remove-orphans
docker image prune -f >/dev/null
echo "✔ $NAME ter-deploy:"
docker compose -f "$DIR/docker-compose.yml" --project-name "$NAME" ps --format 'table {{.Name}}\t{{.Status}}'
