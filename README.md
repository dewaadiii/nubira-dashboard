# Nubira Dashboard

Dashboard internal **Nubira Digital Indonesia** di **https://dashboard.nubiraindonesia.com**
Terhubung dengan website **https://nubiraindonesia.com** lewat database Supabase yang sama.

> Repository ini **PRIVATE**. Jangan ubah ke public.

## Isi

| File | Fungsi |
| --- | --- |
| `index.html` | Aplikasi dashboard (login, lead, klien, proyek, pembayaran, undangan, karyawan) |
| `nubira-config.js` | Koneksi Supabase (URL + anon key), **isinya sama** dengan file di website |
| `database/schema.sql` | Struktur database, keamanan (RLS) dan data awal |
| `.htaccess` | Keamanan hosting: https, noindex, anti-frame, blokir file sensitif |
| `robots.txt` | Melarang Google mengindeks dashboard |

## Cara terhubung dengan website

1. Website `nubiraindonesia.com` → form **Tinggalkan pesan** → tabel `leads` di Supabase.
2. Dashboard → menu **Lead** membaca tabel yang sama (status *Baru*, sumber iklan, kata kunci).
3. Keduanya memakai `nubira-config.js` dengan **Project URL** dan **anon public key** yang sama.

## Setup singkat

1. Supabase → New project (Singapore) → SQL Editor → jalankan `database/schema.sql`.
2. Authentication → Email: *Allow new users to sign up* ON, *Confirm email* OFF.
3. Authentication → Users → Add user `dewaadiii@gmail.com` (Auto Confirm) → jalankan perintah **MASTER LOGIN** di akhir schema.sql.
4. Authentication → URL Configuration → **Site URL** `https://dashboard.nubiraindonesia.com/`.
5. Project Settings → API → salin URL + anon key ke `nubira-config.js` (di repo ini **dan** di repo `nubira-web`).
6. cPanel Rumahweb → Domains → buat subdomain `dashboard.nubiraindonesia.com` → upload isi repo ini (tanpa folder `database`) → SSL/TLS Status → Run AutoSSL.

> Jangan pernah menaruh **service_role key** di repository mana pun.

© 2026 Nubira Digital Indonesia. Hak cipta dilindungi.
