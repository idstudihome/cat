# Panduan web-only untuk pemula

## A. Supabase

1. Masuk ke supabase.com dan klik **New project**.
2. Pilih organisasi, beri nama `cat-siap-asn`, buat database password, pilih region terdekat, lalu klik **Create project**.
3. Setelah status siap, buka **SQL Editor**, klik **New query**, salin seluruh `install/01-database.sql`, lalu klik **Run**.
4. Buat query kedua untuk `install/02-seed.sql`, klik **Run** dan tunggu sampai selesai.
5. Buka **Authentication > Users > Add user**, buat email admin dan password minimal 8 karakter. Salin UID-nya.
6. Jalankan `install/03-owner.sql` setelah mengganti `OWNER_UUID` dengan UID tadi.
7. Buka **Project Settings > API** dan salin Project URL serta Publishable key.
8. Buka **Edge Functions**, pilih **Create function**, nama `cat-api`, tempel `install/functions/index.ts`, lalu deploy. Di secrets tambahkan URL project, service role key, dan domain Vercel pada `ALLOWED_ORIGINS`.

## B. GitHub

1. Buat repository baru, misalnya `cat-siap-asn`.
2. Pilih **Add file > Upload files**.
3. Unggah isi folder proyek ini (jangan unggah `node_modules` atau `dist`).
4. Klik **Commit changes**.

## C. Vercel

1. Masuk ke vercel.com, klik **Add New… > Project**, lalu **Import** repository GitHub.
2. Framework pilih **Vite**. Build command `npm run build`, output directory `dist`.
3. Pada **Environment Variables**, isi:
   - `VITE_SUPABASE_URL` = Project URL
   - `VITE_SUPABASE_PUBLISHABLE_KEY` = Publishable key
   - `VITE_API_FUNCTION_URL` = URL Edge Function `cat-api`
4. Klik **Deploy**. Setiap commit GitHub berikutnya akan membuat deployment baru otomatis.
5. Kembali ke Supabase **Authentication > URL Configuration**. Masukkan URL Vercel ke **Site URL** dan tambahkan juga ke **Redirect URLs**.

## D. Cek akhir

Buka URL Vercel, klik **Coba latihan gratis**, pastikan pembahasan tampil. Login memakai akun admin, buka **Admin**, lalu coba tambah satu soal latihan. Jika fungsi API belum terhubung, periksa nama URL function dan tiga environment variable Vercel.
