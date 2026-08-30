-- =========================================================
-- JK AdiStore — Seed Data
-- Aman dijalankan berulang kali (idempotent): pakai ON CONFLICT.
--
-- CATATAN PENTING soal admin awal:
-- Supabase mengelola auth.users lewat sistem Auth-nya sendiri
-- (GoTrue), bukan lewat SQL biasa — jadi akun admin TIDAK dibuat
-- di sini. Urutan yang benar:
--   1) Jalankan scripts/create-admin.sh (lihat berkas itu) untuk
--      membuat akun admin lewat Auth Admin API.
--   2) BARU jalankan seed.sql ini — baris di bawah akan otomatis
--      menaikkan role akun dengan email tsb menjadi 'admin'.
-- Jika email belum terdaftar saat seed dijalankan, baris ini
-- tidak melakukan apa-apa (aman, tidak error) — jalankan ulang
-- `supabase db execute -f supabase/seed.sql` kapan pun setelah
-- akun admin dibuat.
-- =========================================================

update public.profiles
   set role = 'admin'
 where email = 'jkadistore2@gmail.com';

-- =========================================================
-- PENGATURAN TOKO DEFAULT
-- =========================================================
insert into public.settings (id, name, whatsapp, telegram, instagram, tiktok, youtube, background_url, ticker)
values (
  'store',
  'JK AdiStore',
  '6281234567890',
  'jkadistore',
  'jkadistore',
  'jkadistore',
  'jkadistore',
  '',
  'Selamat datang di JK AdiStore — Top Up MLBB • VPN • Aplikasi Premium • Layanan Digital'
)
on conflict (id) do update
  set name = excluded.name
  where public.settings.name is null; -- tidak menimpa pengaturan yang sudah diubah admin

-- =========================================================
-- PRODUK / LAYANAN CONTOH (UUID tetap agar tidak duplikat saat diulang)
-- =========================================================
insert into public.products (id, name, description, category, price, old_price, badge, price_list, image_url, active)
values
  ('00000000-0000-0000-0000-000000000101',
   'Top Up Mobile Legends',
   'Top up Diamond Mobile Legends, proses instan 24 jam.',
   'MLBB', 22000, 0, 'Terlaris',
   '[{"name":"86 Diamond","price":22000},{"name":"172 Diamond","price":44000},{"name":"257 Diamond","price":66000}]',
   'https://mega.nz/file/ganti-dengan-link-publik-1', true),

  ('00000000-0000-0000-0000-000000000201',
   'VPN Premium',
   'Akun VPN premium kuota unlimited, garansi penuh.',
   'VPN', 35000, 45000, 'Promo',
   '[{"name":"30 Hari","price":35000},{"name":"90 Hari","price":95000}]',
   'https://mega.nz/file/ganti-dengan-link-publik-3', true),

  ('00000000-0000-0000-0000-000000000301',
   'Aplikasi Premium Bulanan',
   'Akses aplikasi premium pilihan, aktivasi manual kurang dari 1 jam.',
   'Aplikasi', 25000, 0, '',
   '[{"name":"1 Bulan","price":25000}]',
   'https://mega.nz/file/ganti-dengan-link-publik-4', true)

on conflict (id) do update
  set name = excluded.name,
      description = excluded.description,
      category = excluded.category,
      price = excluded.price,
      old_price = excluded.old_price,
      badge = excluded.badge,
      price_list = excluded.price_list,
      image_url = excluded.image_url,
      updated_at = now();

-- =========================================================
-- TESTIMONI CONTOH
-- =========================================================
insert into public.testimonials (id, user_id, name, role, message, photo_url, approved)
values (
  '00000000-0000-0000-0000-000000000901',
  null,
  'Pelanggan JK AdiStore',
  'Pembeli MLBB',
  'Proses cepat, harga bersaing, recommended banget!',
  'https://mega.nz/file/ganti-dengan-link-avatar',
  true
)
on conflict (id) do update
  set message = excluded.message;
