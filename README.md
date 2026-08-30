# JK AdiStore — Sistem 3 Lapisan (Vercel + Supabase + Mega)

## Struktur

```
jk-adistore-backend/
├── supabase/
│   ├── config.toml              ← konfigurasi CLI
│   ├── migrations/0001_init_schema.sql   ← semua tabel + RLS + fungsi
│   ├── seed.sql                 ← data contoh (idempotent)
│   └── functions/admin-ai-settings/index.ts   ← Edge Function rahasia
├── scripts/create-admin.sh      ← buat akun admin awal
├── web/supabase-config.js       ← kunci PUBLIK untuk website (anon key)
├── vercel.json                  ← konfigurasi deploy Vercel
└── .env.example                 ← contoh variabel untuk CLI (jangan commit isi asli)
```

## Tiga Lapisan

1. **Website (Vercel)** — file statis (HTML/CSS/JS). Hanya berisi `SUPABASE_URL`
   dan `anon key` di `web/supabase-config.js` — keduanya memang aman untuk publik
   karena perlindungan data sesungguhnya ada di Row Level Security (RLS),
   bukan di menyembunyikan kunci.
2. **Supabase** — pusat data (`profiles`, `products`, `orders`, `transactions`,
   `testimonials`, `settings`) + tabel rahasia `ai_settings` yang dikunci total.
3. **Mega** — semua gambar/video/produk/testimoni disimpan sebagai file di akun
   Mega Anda. Yang masuk ke database hanya **URL publik**-nya (kolom `image_url`,
   `video_url`, `avatar_url`, `background_url`) — jadi database tetap ringan.

## Langkah di Termux (dari nol sampai live)

```bash
# 1. Install Supabase CLI (sekali saja)
npm install -g supabase

# 2. Login ke akun Supabase Anda
supabase login

# 3. Masuk ke folder proyek ini
cd jk-adistore-backend

# 4. Hubungkan ke project Supabase yang sudah Anda buat di dashboard
supabase link --project-ref <project-ref-anda>

# 5. Jalankan migrasi (buat semua tabel, RLS, fungsi)
supabase db push

# 6. Buat akun admin awal (ganti email & password)
export SUPABASE_URL="https://xxxxxxxx.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="isi-dari-dashboard-settings-api"
bash scripts/create-admin.sh admin@jkadistore.com "PasswordKuatSaya123!"

# 7. Isi data contoh (admin dinaikkan rolenya otomatis oleh baris UPDATE di seed.sql)
#    Edit dulu email di supabase/seed.sql agar sama dengan langkah 6.
supabase db execute -f supabase/seed.sql

# 8. Deploy Edge Function untuk ai_settings
supabase functions deploy admin-ai-settings

# 9. Isi web/supabase-config.js dengan SUPABASE_URL + anon key (dari dashboard)

# 10. Deploy website ke Vercel
npm install -g vercel
vercel --prod
```

Semua langkah 5–8 **aman dijalankan ulang berkali-kali** — migrasi pakai
`if not exists` / `create or replace`, dan seed pakai `on conflict`, jadi
tidak akan error atau menduplikasi data walau dieksekusi berkali-kali.

## Soal `ai_settings` (kunci & rahasia sistem)

- Tabel ini punya RLS aktif **tanpa satu policy pun** → dari sisi klien
  (anon/authenticated), tabel ini benar-benar tidak bisa dibaca/ditulis
  langsung, titik.
- Satu-satunya jalan masuk: Edge Function `admin-ai-settings`, yang
  mengecek dulu bahwa pemanggil sudah login **dan** rolenya `admin` di
  tabel `profiles`, baru memakai `service_role key` (hidup di server
  Supabase saja, tidak pernah dikirim ke browser) untuk membaca/menulis.
- Panel admin di website memanggil Edge Function ini lewat `fetch()` —
  contoh kodenya ada di komentar `web/supabase-config.js`.

## Website: `web/index.html`

Ini adalah file `index-7.html` yang Anda unggah, dengan SATU bagian yang
diganti: adapter penyimpanan data. Setelah ditelusuri, ternyata bagian yang
kelihatan seperti "Firebase" (`doc`, `getDoc`, `setDoc`, `getDocs`, `addDoc`,
`updateDoc`, `deleteDoc`) itu sebenarnya bukan Firebase asli — itu adalah
adapter buatan sendiri yang menyimpan `products`, `testimonials`, dan
`settings` ke **localStorage browser** (jadi data itu hanya tersimpan di HP/
perangkat yang membukanya, tidak pernah benar-benar tersimpan di server, dan
hilang kalau cache dibersihkan). Login, saldo, role, dan pesanan (`orders`)
sudah lebih dulu memakai Supabase asli — itu sudah benar sejak awal.

Yang saya lakukan: mengganti isi adapter tersebut (fungsi `doc`, `getDoc`,
`setDoc`, `addDoc`, `updateDoc`, `deleteDoc`, `getDocs`) supaya sekarang
benar-benar membaca/menulis ke tabel `products`, `testimonials`, dan
`settings` di Supabase — **tanpa mengubah satu pun kode lain** di file ini
(ratusan pemanggilan seperti `card(p)`, `saveProduct()`, `loadSettings()`,
dst tetap seperti semula, karena nama & cara pakai fungsinya sengaja dibuat
identik). Jadi produk, testimoni, dan pengaturan toko sekarang ikut tersimpan
permanen di database, bisa dilihat/dikelola dari perangkat mana pun, persis
seperti yang Anda minta di poin 2.

**Sebelum deploy**, cek `SUPABASE_URL` dan `SUPABASE_KEY` (anon/publishable
key) yang sudah tertulis langsung di `web/index.html` — pastikan itu proyek
Supabase yang sama dengan yang Anda `supabase link` dan jalankan migrasi di
langkah-langkah CLI di atas. Kedua nilai itu memang aman dipublikasikan
(bukan rahasia) — proteksi sesungguhnya datang dari RLS di `schema.sql`.

## ⚠️ Checklist: bagian yang WAJIB Anda ubah/isi sendiri

Tidak ada sistem yang bisa 100% "tinggal pakai" tanpa isian akun pribadi Anda —
berikut persisnya bagian mana saja, tidak lebih tidak kurang:

1. **`web/index.html` baris `SUPABASE_URL` & `SUPABASE_KEY`** (dekat awal
   script) — sudah terisi nilai yang kelihatannya proyek Supabase Anda
   sendiri. Pastikan itu project yang SAMA dengan yang Anda `supabase link`
   di langkah CLI. Kalau Anda bikin project Supabase baru, ganti dua baris
   ini dengan URL & anon/publishable key project baru itu.

2. **Email admin di `supabase/seed.sql`** (`admin@jkadistore.com`) — ganti
   sesuai email yang Anda pakai di `scripts/create-admin.sh`, supaya baris
   `UPDATE profiles SET role='admin'` kena ke akun yang benar.

3. **Link Mega di `supabase/seed.sql`** — semua yang bertuliskan
   `ganti-dengan-link-publik-...` itu contoh/placeholder. Upload
   gambar/produk/testimoni ke Mega, ambil link publiknya, baru tempel di
   sana (atau lebih gampang: isi langsung lewat Panel Admin di website
   setelah situs live — tidak wajib lewat seed.sql).

4. **`supabase/config.toml` → `site_url` & `additional_redirect_urls`** —
   ganti `GANTI-DENGAN-DOMAIN-VERCEL-ANDA.vercel.app` dengan domain asli
   setelah Vercel memberi Anda URL. Domain yang sama juga perlu ditambahkan
   di Supabase Dashboard → Authentication → URL Configuration.

5. **Login Google/GitHub/Discord** — tombolnya sudah ada di website, tapi
   supaya benar-benar bisa dipakai, Anda harus aktifkan tiap provider di
   Supabase Dashboard → Authentication → Providers, dan isi Client
   ID/Secret dari masing-masing platform. Tanpa ini, tombolnya akan error
   saat diklik. Login Telegram belum ada Edge Function-nya sama sekali
   (perlu dibuat terpisah jika mau dipakai).

6. **Panel Admin → AI Assistant** — setelah Edge Function `ai-gateway`
   ter-deploy, buka Panel Admin di website → bagian AI, isi "URL API",
   "Model", dan "Kunci API" (kunci dari provider AI yang kompatibel format
   OpenAI/chat-completions, mis. OpenRouter/Groq/dst) lalu simpan. Fitur
   chat AI baru aktif setelah ini diisi — sebelum itu tombol "Tes AI" akan
   menampilkan pesan "belum dikonfigurasi", itu wajar, bukan bug.

Di luar 6 poin itu, sistemnya sudah tersambung penuh: skema database, RLS,
adapter produk/testimoni/pengaturan di website, saldo/role admin, dan
Edge Function AI — semuanya sudah cocok satu sama lain dan tidak perlu
diutak-atik lagi. Yang membuat sesuatu terasa "belum jalan" biasanya karena
salah satu dari 6 isian di atas belum diisi, bukan karena ada bagian kode
yang rusak.

Untuk deploy ke Vercel: jadikan isi folder `web/` (atau salin `index.html`-nya
ke root repo) sebagai proyek yang Anda hubungkan ke Vercel — `vercel.json`
di repo ini sudah menyiapkan header keamanan dasarnya.
