# Keamanan

## Insiden: secret pernah ter-commit (Oktober 2026)

Repo ini **publik**. Di commit awal `1b2ecc9` (dan semua commit setelahnya sampai perapihan) terdapat:

| File | Isi | Status di tree sekarang |
|---|---|---|
| `00-gateway/ssl/ridhoreynaldo-com/ridhoreynaldo.key` | private key Cloudflare Origin CA `ridhoreynaldo.com` (berlaku s/d 2041) | dihapus |
| `00-gateway/ssl/portaluniversitasquality-ac-id/privkey.pem` | private key sertifikat Sectigo `portaluniversitasquality.ac.id` (s/d Jan 2027) | dihapus |
| `00-gateway/ssl/backup-ssl-portal/private.key` | private key lama domain yang sama | dihapus |
| `01-infra/postgres/userlist.txt` | password superuser Postgres (plaintext) | dihapus |
| `02-monitoring/docs/docs-monitoring.md` | IP internal + password `password12345` Portainer/Kuma/Grafana | ditulis ulang |

Dihapus dari tree **belum cukup** — semuanya masih ada di git history dan bisa dibaca siapa pun.
Anggap semuanya **sudah bocor**. Yang harus dilakukan, urut prioritas:

1. **Private key `portaluniversitasquality.ac.id`** — bukan domain pribadi. Beri tahu pemilik/admin domain,
   terbitkan sertifikat baru dengan key baru, dan **revoke** sertifikat lama di Sectigo.
2. **Cloudflare Origin CA `ridhoreynaldo.com`** — Cloudflare Dashboard → SSL/TLS → Origin Server →
   revoke sertifikat lama, buat yang baru, taruh di server (`00-gateway/ssl/ridhoreynaldo-com/`), reload nginx.
3. **Password Postgres** — di server:
   ```bash
   cd /opt/devops
   NEW=$(openssl rand -base64 24)
   docker exec infra_postgres psql -U postgres -c "ALTER USER postgres PASSWORD '$NEW';"
   sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$NEW|" 01-infra/.env
   # aplikasi lama yang masih memakai user postgres (04-apps/.env portfolio) → bootstrap.sh menyinkronkan otomatis
   sudo ./bootstrap.sh
   ```
4. **Password Portainer / Uptime Kuma / Grafana** — ganti lewat UI masing-masing.
5. **Bersihkan history** (opsional tapi disarankan, agar file tidak terlihat lagi di GitHub):
   ```bash
   pip install git-filter-repo
   git clone --mirror git@github.com:ridhoreynaldo/devops.git devops-mirror && cd devops-mirror
   git filter-repo --invert-paths \
     --path 00-gateway/ssl --path 01-infra/postgres/userlist.txt \
     --path 03-services/wa-gateway --path 03-services/wa-web
   git push --force --mirror
   ```
   Setelah itu **semua clone lama harus di-clone ulang** (termasuk `/opt/devops` di server) — history berubah.
   GitHub juga menyimpan cache; hubungi GitHub Support untuk membersihkan jika perlu.

## Aturan ke depan

- `.gitignore` memblokir `.env`, `*.key`, `*.pem`, `*.crt`, `userlist.txt`, folder `letsencrypt/`, `ssl/`.
- `make secrets-check` — jalankan sebelum commit; gagal bila ada secret yang ter-track.
- Password **tidak pernah** ditulis di dokumentasi. Dokumen hanya menyebut *di mana* password disimpan.
- Satu aplikasi = satu role Postgres dengan hak minimum (`scripts/create-app-db.sh`). Superuser hanya untuk admin/backup.
- Port database/Redis hanya `127.0.0.1` (`BIND_IP`). Dari luar pakai SSH tunnel: `ssh -L 5432:127.0.0.1:5432 server`.
- Gateway: hanya 80/443 terbuka; request ke IP langsung / domain tak dikenal ditolak (`return 444`, `ssl_reject_handshake`).
- Container: `no-new-privileges`, limit memori/CPU, log dirotasi (10 MB × 3).
- Secret dibuat oleh `bootstrap.sh` (`openssl rand`), `chmod 600`, dan tidak pernah ditampilkan di log kecuali sekali saat dibuat.
