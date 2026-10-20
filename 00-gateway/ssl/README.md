# 00-gateway/ssl — sertifikat manual (Cloudflare Origin CA / beli sendiri)

Folder ini **sengaja kosong di git**. Isinya hanya ada di server:

```
ssl/<domain>/fullchain.pem
ssl/<domain>/privkey.pem
```

`.gitignore` memblokir `*.pem *.crt *.key` di sini. **Private key tidak pernah di-commit** — repo ini publik.
Sertifikat Let's Encrypt otomatis ada di `../letsencrypt/` (juga di-ignore), dibuat oleh `scripts/issue-cert.sh`.

Riwayat: sebelum Oktober 2026 folder ini pernah berisi private key yang ter-commit. Lihat `docs/SECURITY.md`
untuk langkah rotasi.
