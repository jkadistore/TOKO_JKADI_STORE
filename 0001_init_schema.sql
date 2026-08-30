-- =========================================================
-- JK AdiStore — Skema Inti Supabase
-- Aman dijalankan berulang kali (idempotent).
-- =========================================================

create extension if not exists pgcrypto;

-- =========================================================
-- 1. PROFILES (data pengguna, terhubung ke auth.users)
-- =========================================================
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null default '',
  email       text,
  whatsapp    text,
  role        text not null default 'user' check (role in ('user','admin')),
  balance     numeric(14,2) not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- =========================================================
-- 2. PRODUCTS / LAYANAN (media disimpan sebagai URL Mega)
-- =========================================================
create table if not exists public.products (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  description  text default '',
  category     text not null default 'Lainnya',
  price        numeric(14,2) not null default 0,
  old_price    numeric(14,2) not null default 0,
  badge        text default '',
  stock_min    integer not null default 800,
  stock_max    integer not null default 10000,
  price_list   jsonb not null default '[]'::jsonb,  -- varian harga [{name,price}]
  image_url    text,          -- URL publik Mega
  video_url    text,          -- URL publik Mega (opsional)
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- =========================================================
-- 3. ORDERS / PESANAN
-- =========================================================
create table if not exists public.orders (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  product_id   uuid references public.products(id) on delete set null,
  product_name text not null,     -- disalin saat order agar riwayat tetap utuh
  quantity     integer not null default 1,
  unit_price   numeric(14,2) not null default 0,
  total        numeric(14,2) not null default 0,
  status       text not null default 'pending'
               check (status in ('pending','diproses','selesai','dibatalkan')),
  note         text default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- =========================================================
-- 4. TRANSACTIONS / RIWAYAT SALDO
-- =========================================================
create table if not exists public.transactions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  amount       numeric(14,2) not null,   -- + topup / - potongan
  type         text not null default 'adjust'
               check (type in ('topup','purchase','adjust','refund')),
  reason       text default '',
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);

-- =========================================================
-- 5. TESTIMONIALS (avatar/media pakai URL Mega)
-- =========================================================
create table if not exists public.testimonials (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references public.profiles(id) on delete set null,
  name         text not null,        -- "n" di frontend
  role         text default '',      -- "c" di frontend (mis. jabatan/kategori)
  message      text not null,        -- "t" di frontend
  photo_url    text,                 -- URL foto/avatar publik Mega
  approved     boolean not null default true,
  created_at   timestamptz not null default now()
);

-- =========================================================
-- 6. SETTINGS (pengaturan toko, background pakai URL Mega)
-- =========================================================
create table if not exists public.settings (
  id           text primary key default 'store',
  name         text not null default 'JK AdiStore',
  whatsapp     text default '',
  telegram     text default '',
  instagram    text default '',
  tiktok       text default '',
  youtube      text default '',
  background_url text default '',   -- URL publik Mega
  ticker       text default '',
  banners      jsonb not null default '[]'::jsonb,  -- URL publik Mega untuk slider
  videos       jsonb not null default '[]'::jsonb,  -- URL publik Mega untuk video
  updated_at   timestamptz not null default now()
);

-- =========================================================
-- 7. AI_SETTINGS — TABEL RAHASIA, DIKUNCI MUTLAK
--    Tidak ada policy SELECT/INSERT/UPDATE/DELETE untuk siapa pun.
--    Satu-satunya jalan masuk adalah fungsi SECURITY DEFINER di bawah,
--    atau service_role key (dipakai server/edge function saja).
-- =========================================================
create table if not exists public.ai_settings (
  id           uuid primary key default gen_random_uuid(),
  key          text not null unique,
  value        text not null,
  description  text default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- =========================================================
-- AKTIFKAN ROW LEVEL SECURITY DI SEMUA TABEL
-- =========================================================
alter table public.profiles      enable row level security;
alter table public.products      enable row level security;
alter table public.orders        enable row level security;
alter table public.transactions  enable row level security;
alter table public.testimonials  enable row level security;
alter table public.settings      enable row level security;
alter table public.ai_settings   enable row level security;
-- ai_settings sengaja TIDAK diberi policy apa pun di bawah ini.
-- RLS aktif + nol policy = default deny total untuk anon & authenticated.

-- =========================================================
-- FUNGSI BANTU: cek apakah user saat ini admin
-- =========================================================
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.profiles where id = auth.uid()) = 'admin',
    false
  );
$$;

-- =========================================================
-- TRIGGER: buat baris profiles otomatis saat user baru daftar
-- =========================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, name, email, whatsapp, role, balance)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
    new.email,
    coalesce(new.raw_user_meta_data->>'whatsapp', ''),
    'user',
    0
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =========================================================
-- FUNGSI: adjust_balance — satu-satunya jalan sah mengubah saldo
-- Hanya admin yang boleh memanggil (RLS + cek di dalam fungsi).
-- =========================================================
create or replace function public.adjust_balance(
  p_target_id uuid,
  p_delta numeric,
  p_reason text default ''
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_balance numeric(14,2);
begin
  if not public.is_admin() then
    raise exception 'Hanya admin yang dapat mengubah saldo';
  end if;

  update public.profiles
    set balance = balance + p_delta,
        updated_at = now()
    where id = p_target_id
    returning balance into v_new_balance;

  if v_new_balance is null then
    raise exception 'Pengguna tidak ditemukan';
  end if;

  insert into public.transactions (user_id, amount, type, reason, created_by)
  values (p_target_id, p_delta, 'adjust', p_reason, auth.uid());

  return v_new_balance;
end;
$$;

-- =========================================================
-- FUNGSI AI_SETTINGS — akses rahasia HANYA lewat sini, HANYA admin
-- =========================================================
create or replace function public.ai_settings_list_keys()
returns table(key text, description text, updated_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select s.key, s.description, s.updated_at
  from public.ai_settings s
  where public.is_admin();
$$;

create or replace function public.ai_settings_get(p_key text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_value text;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;
  select value into v_value from public.ai_settings where key = p_key;
  return v_value;
end;
$$;

create or replace function public.ai_settings_set(p_key text, p_value text, p_description text default '')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;
  insert into public.ai_settings (key, value, description)
  values (p_key, p_value, p_description)
  on conflict (key) do update
    set value = excluded.value,
        description = excluded.description,
        updated_at = now();
end;
$$;

-- Batasi siapa yang boleh EXECUTE fungsi rahasia (lapisan tambahan)
revoke all on function public.ai_settings_get(text) from public, anon;
revoke all on function public.ai_settings_set(text, text, text) from public, anon;
revoke all on function public.ai_settings_list_keys() from public, anon;
grant execute on function public.ai_settings_get(text) to authenticated;
grant execute on function public.ai_settings_set(text, text, text) to authenticated;
grant execute on function public.ai_settings_list_keys() to authenticated;

-- =========================================================
-- POLICIES: PROFILES
-- =========================================================
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  using (auth.uid() = id or public.is_admin());

drop policy if exists "profiles_update_own_limited" on public.profiles;
create policy "profiles_update_own_limited"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "profiles_admin_update_all" on public.profiles;
create policy "profiles_admin_update_all"
  on public.profiles for update
  using (public.is_admin());

-- =========================================================
-- POLICIES: PRODUCTS
-- =========================================================
drop policy if exists "products_public_read_active" on public.products;
create policy "products_public_read_active"
  on public.products for select
  using (active = true or public.is_admin());

drop policy if exists "products_admin_write" on public.products;
create policy "products_admin_write"
  on public.products for all
  using (public.is_admin())
  with check (public.is_admin());

-- =========================================================
-- POLICIES: ORDERS
-- =========================================================
drop policy if exists "orders_select_own_or_admin" on public.orders;
create policy "orders_select_own_or_admin"
  on public.orders for select
  using (auth.uid() = user_id or public.is_admin());

drop policy if exists "orders_insert_own" on public.orders;
create policy "orders_insert_own"
  on public.orders for insert
  with check (auth.uid() = user_id);

drop policy if exists "orders_admin_update" on public.orders;
create policy "orders_admin_update"
  on public.orders for update
  using (public.is_admin());

-- =========================================================
-- POLICIES: TRANSACTIONS (baca saja bagi user, tulis lewat fungsi)
-- =========================================================
drop policy if exists "transactions_select_own_or_admin" on public.transactions;
create policy "transactions_select_own_or_admin"
  on public.transactions for select
  using (auth.uid() = user_id or public.is_admin());

-- =========================================================
-- POLICIES: TESTIMONIALS
-- =========================================================
drop policy if exists "testimonials_public_read_approved" on public.testimonials;
create policy "testimonials_public_read_approved"
  on public.testimonials for select
  using (approved = true or public.is_admin() or auth.uid() = user_id);

drop policy if exists "testimonials_insert_own" on public.testimonials;
create policy "testimonials_insert_own"
  on public.testimonials for insert
  with check (auth.uid() = user_id or public.is_admin());

drop policy if exists "testimonials_admin_manage" on public.testimonials;
create policy "testimonials_admin_manage"
  on public.testimonials for update
  using (public.is_admin());

drop policy if exists "testimonials_admin_delete" on public.testimonials;
create policy "testimonials_admin_delete"
  on public.testimonials for delete
  using (public.is_admin());

-- =========================================================
-- POLICIES: SETTINGS
-- =========================================================
drop policy if exists "settings_public_read" on public.settings;
create policy "settings_public_read"
  on public.settings for select
  using (true);

drop policy if exists "settings_admin_write" on public.settings;
create policy "settings_admin_write"
  on public.settings for all
  using (public.is_admin())
  with check (public.is_admin());

-- (ai_settings: sengaja tanpa policy apa pun — lihat catatan di atas)
