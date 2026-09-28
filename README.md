# CAT Siap ASN

PWA simulasi SKD CPNS dengan mode belajar, simulasi bertimer, riwayat, panel admin bank soal, impor JSON/CSV, dan API Supabase yang menerapkan RLS.

## Jalur instalasi web

1. Buat project Supabase baru.
2. Buka **SQL Editor > New query**, jalankan `install/01-database.sql`, lalu `install/02-seed.sql`.
3. Buat akun pemilik di **Authentication > Users > Add user**. Salin User UID, ganti `OWNER_UUID` pada `install/03-owner.sql`, lalu jalankan file itu.
4. Jalankan `install/04-verify.sql`; hasil yang diharapkan adalah 110 soal (30 TWK, 35 TIU, 45 TKP).
5. Di **Edge Functions > Create function**, buat function bernama `cat-api`, tempel isi `install/functions/index.ts`, dan set secrets `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ALLOWED_ORIGINS`.
6. Di Vercel, impor repository GitHub, gunakan **Vite**, build `npm run build`, output `dist`.
7. Isi environment variable Vercel: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_API_FUNCTION_URL` (URL function `cat-api`). Redeploy.

Jangan masukkan `SUPABASE_SERVICE_ROLE_KEY` ke Vercel atau kode browser. Gunakan publishable key saja di aplikasi.

## Perintah lokal

```bash
npm install
npm run build
npm test
npm run dev
```
