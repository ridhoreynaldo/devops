# 00-gateway — nginx reverse proxy + SSL

Satu-satunya pintu masuk dari internet (80/443). Semua aplikasi di belakangnya dijangkau lewat network
docker `global-gateway-net` dengan **nama container** sebagai upstream.

```
nginx/nginx.conf            # global: gzip, SSL, rate-limit zone, resolver docker
nginx/conf.d/00-default.conf  # tolak akses via IP / domain tak dikenal (444, ssl_reject_handshake)
nginx/conf.d/<domain>.conf    # satu file per domain (dibuat dari templates/)
nginx/conf.d/*.conf.example   # contoh vhost aplikasi (wa-gateway)
nginx/templates/              # template vhost (sed __DOMAIN__/__UPSTREAM__)
nginx/snippets/               # acme-challenge, proxy header, security header
letsencrypt/                  # sertifikat Let's Encrypt (scripts/issue-cert.sh) — di-ignore
ssl/                          # sertifikat manual (Cloudflare Origin) — di-ignore, lihat ssl/README.md
logs/                         # access.log / error.log — di-ignore
```

## Tambah domain

```bash
cd 00-gateway/nginx
sed 's/__DOMAIN__/app.example.com/g; s/__UPSTREAM__/myapp_web:3000/g' templates/app-ssl.conf.template > conf.d/app-example-com.conf
cd ../.. && make cert D=app.example.com && make nginx-reload
```

Urutan penting: vhost 443 merujuk file sertifikat → sertifikat harus ada dulu, kalau tidak `nginx -t` gagal.
Server port 80 default sudah melayani `/.well-known/acme-challenge/` untuk semua domain, jadi penerbitan
sertifikat tidak perlu mematikan nginx.

## Port tambahan

`docker-compose.yml` juga membuka 1337/8003/8069/8070/8443 untuk aplikasi lama yang diakses lewat port.
Setiap port SSL baru harus ditambahkan juga di `00-default.conf` (`listen <port> ssl default_server`).
Aplikasi baru **tidak** memakai pola ini — pakai subdomain di 443.

## Perintah

```bash
make nginx-test      # docker exec global_gateway nginx -t
make nginx-reload    # tanpa downtime
tail -f 00-gateway/logs/access.log
```
