# 04-apps — layer aplikasi

Setiap aplikasi adalah **repo git sendiri** yang di-clone ke `04-apps/<nama>/` (folder itu di-ignore git di sini).
Repo `devops` hanya menyimpan daftar aplikasinya di `apps.list`.

```
04-apps/
├── apps.list            # <nama> <url git> <branch>  — dibaca bootstrap.sh & scripts/deploy-app.sh
├── wa-gateway/          # (clone, tidak di-commit) → punya docker-compose.yml sendiri
└── portfolio/           # (clone, tidak di-commit) → idem
```

Deploy / update satu aplikasi:

```bash
./scripts/deploy-app.sh wa-gateway          # clone (bila belum) + git pull + docker compose up -d --build
```

Kontrak yang harus dipenuhi aplikasi ada di [`../docs/APPS.md`](../docs/APPS.md) — intinya: join network
`global-gateway-net`, tidak publish port, nama container `<app>_web`, koneksi ke `infra_pgbouncer` /
`infra_redis` / `infra_redis_queue`, dan punya endpoint health.
