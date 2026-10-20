# 02-monitoring — observability

| Service | Container | Port (127.0.0.1) | Fungsi |
|---|---|---|---|
| Portainer CE | `devops_portainer` | 9000 | manajemen container |
| Uptime Kuma | `devops_uptime_kuma` | 3001 | monitor up/down + notifikasi |
| Grafana | `devops_grafana` | 3000 | dashboard (password: `GRAFANA_ADMIN_PASSWORD` di `.env`) |
| Prometheus | `devops_prometheus` | — | metrik, retensi 15 hari / 2 GB |
| cAdvisor | `devops_cadvisor` | — | metrik container |
| Node Exporter | `devops_node_exporter` | — | metrik host |

Semua port hanya di `127.0.0.1`. Akses dari laptop lewat SSH tunnel:

```bash
ssh -L 9000:127.0.0.1:9000 -L 3000:127.0.0.1:3000 -L 3001:127.0.0.1:3001 user@server
# lalu buka http://localhost:9000 (Portainer), :3000 (Grafana), :3001 (Uptime Kuma)
```

Setup pertama:
- **Portainer**: akun admin harus dibuat dalam 5 menit setelah container start; kalau lewat, `docker restart devops_portainer`.
- **Uptime Kuma**: buat akun admin di UI; tambahkan monitor HTTP ke `https://<domain>/api/health` tiap aplikasi.
- **Grafana**: login `admin` / `GRAFANA_ADMIN_PASSWORD`; tambah data source Prometheus `http://devops_prometheus:9090`;
  import dashboard cAdvisor (ID 14282) dan Node Exporter Full (ID 1860).

Password **tidak** ditulis di dokumen ini — ada di `02-monitoring/.env` (dibuat `bootstrap.sh`) dan di UI masing-masing.

File WSL `*:Zone.Identifier` yang kadang ikut tersalin: `find . -name "*:Zone.Identifier" -type f -delete`.
