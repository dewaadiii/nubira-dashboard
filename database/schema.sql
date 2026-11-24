-- =====================================================================
--  DATABASE NUBIRA DIGITAL INDONESIA
--  PostgreSQL / Supabase  ·  versi 1.0  ·  22 Nov 2026
--
--  Cara pakai (Supabase):
--  1. Buat project baru di supabase.com (region Singapore).
--  2. Buka SQL Editor → tempel seluruh file ini → Run.
--  3. Ikuti bagian "MASTER LOGIN" di paling bawah.
--  5. Isi SUPABASE_URL dan SUPABASE_ANON_KEY di nubira-config.js
--     (website nubiraindonesia.com dan dashboard.nubiraindonesia.com).
--  6. Authentication -> URL Configuration -> Site URL:
--     https://dashboard.nubiraindonesia.com/
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
--  PILIHAN (ENUM)
-- ---------------------------------------------------------------------
create type service_kind   as enum ('website','villa','aplikasi','konsultasi_it','undangan','maintenance','lainnya');
create type lead_source    as enum ('google_ads','google_organik','google_maps','instagram','tiktok','facebook','whatsapp','referensi','lainnya');
create type lead_status    as enum ('baru','dihubungi','penawaran','menang','kalah');
create type project_status as enum ('brief','desain','pengerjaan','review','online','selesai','batal');
create type payment_type   as enum ('dp','pelunasan','cicilan','maintenance','addon');
create type payment_method as enum ('transfer','qris','tunai','lainnya');
create type invoice_status as enum ('draft','terkirim','sebagian','lunas','batal');
create type rsvp_status    as enum ('belum','hadir','tidak_hadir','ragu');
create type sub_status     as enum ('aktif','jeda','berhenti');
create type staff_role     as enum ('owner','admin','staf');

-- ---------------------------------------------------------------------
--  ADMIN (terhubung ke Supabase Auth)
-- ---------------------------------------------------------------------
create table staff (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null,
  email       text unique not null,
  phone_wa    text,
  role        staff_role not null default 'staf',   -- owner = master login
  access      text[] not null default '{}',         -- menu yang boleh dibuka
  is_active   boolean not null default true,
  last_login  timestamptz,
  created_at  timestamptz not null default now()
);

-- Karyawan aktif?
create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from staff where id = auth.uid() and is_active) $$;

-- Master login (owner)?
create or replace function is_owner() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from staff where id = auth.uid() and is_active and role = 'owner') $$;

-- Boleh membuka menu tertentu? Owner selalu boleh.
create or replace function has_access(m text) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from staff where id = auth.uid() and is_active
                  and (role = 'owner' or m = any(access))) $$;

-- Catat waktu login terakhir (dipanggil admin panel setelah login)
create or replace function touch_login() returns void
language sql security definer set search_path = public as
$$ update staff set last_login = now() where id = auth.uid() $$;

-- ---------------------------------------------------------------------
--  KLIEN
-- ---------------------------------------------------------------------
create table clients (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,                 -- nama kontak
  business_name text,                          -- nama usaha
  business_type text,                          -- villa, toko, klinik, pribadi, ...
  phone_wa      text,
  email         text,
  city          text default 'Denpasar',       -- kabupaten/kota
  address       text,
  notes         text,
  created_at    timestamptz not null default now()
);
create index on clients (business_name);

-- ---------------------------------------------------------------------
--  PAKET & HARGA (katalog yang tampil di website)
-- ---------------------------------------------------------------------
create table packages (
  id             uuid primary key default gen_random_uuid(),
  code           text unique not null,          -- STARTER, BISNIS, VILLA, CANANG, ...
  service        service_kind not null,
  name           text not null,
  price          numeric(14,0) not null default 0,   -- Rupiah
  is_addon       boolean not null default false,
  duration_text  text,                          -- "5 hari kerja", "1–3 hari"
  revisions      text,                          -- "2x", "Sepuasnya"
  active_period  text,                          -- "1 tahun"
  features       text[] not null default '{}',
  is_active      boolean not null default true,
  sort_order     int not null default 0
);

-- ---------------------------------------------------------------------
--  LEAD (calon klien dari iklan, Google, Instagram, WhatsApp)
--  Diisi otomatis oleh tracking website (utm_*, search_term)
-- ---------------------------------------------------------------------
create table leads (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  phone_wa        text,
  service         service_kind not null default 'website',
  package_id      uuid references packages(id) on delete set null,
  source          lead_source not null default 'whatsapp',
  search_term     text,                         -- kata kunci pencarian
  utm_source      text, utm_medium text, utm_campaign text, utm_term text, gclid text,
  status          lead_status not null default 'baru',
  est_value       numeric(14,0) default 0,
  next_follow_up  date,
  lost_reason     text,
  notes           text,
  client_id       uuid references clients(id) on delete set null,  -- terisi saat menang
  created_at      timestamptz not null default now()
);
create index on leads (status);
create index on leads (source);
create index on leads (created_at desc);

-- ---------------------------------------------------------------------
--  PROYEK / ORDER
-- ---------------------------------------------------------------------
create sequence project_seq;
create table projects (
  id           uuid primary key default gen_random_uuid(),
  code         text unique not null default ('NB-' || to_char(now(),'YYYY') || '-' || lpad(nextval('project_seq')::text,3,'0')),
  client_id    uuid not null references clients(id) on delete restrict,
  lead_id      uuid references leads(id) on delete set null,
  package_id   uuid references packages(id) on delete set null,
  title        text not null,
  service      service_kind not null,
  status       project_status not null default 'brief',
  price_total  numeric(14,0) not null default 0,  -- nilai kontrak setelah diskon
  discount     numeric(14,0) not null default 0,
  start_date   date default current_date,
  due_date     date,
  live_url     text,
  domain       text,
  notes        text,
  created_at   timestamptz not null default now()
);
create index on projects (status);
create index on projects (client_id);

-- Rincian item (paket + tambahan seperti domain, express, video)
create table project_items (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references projects(id) on delete cascade,
  package_id  uuid references packages(id) on delete set null,
  description text not null,
  qty         int not null default 1,
  unit_price  numeric(14,0) not null default 0
);

-- Daftar tugas per proyek
create table tasks (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid references projects(id) on delete cascade,
  title       text not null,
  due_date    date,
  done        boolean not null default false,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
--  INVOICE & PEMBAYARAN
-- ---------------------------------------------------------------------
create sequence invoice_seq;
create table invoices (
  id          uuid primary key default gen_random_uuid(),
  number      text unique not null default ('INV/NB/' || to_char(now(),'YYYYMM') || '/' || lpad(nextval('invoice_seq')::text,4,'0')),
  project_id  uuid not null references projects(id) on delete cascade,
  amount      numeric(14,0) not null,
  issued_at   date not null default current_date,
  due_at      date,
  status      invoice_status not null default 'draft',
  note        text
);

create table payments (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references projects(id) on delete cascade,
  invoice_id  uuid references invoices(id) on delete set null,
  type        payment_type not null default 'dp',
  amount      numeric(14,0) not null check (amount > 0),
  method      payment_method not null default 'transfer',
  paid_at     date not null default current_date,
  proof_url   text,                              -- link bukti transfer (Storage)
  note        text
);
create index on payments (paid_at desc);

-- ---------------------------------------------------------------------
--  UNDANGAN DIGITAL
-- ---------------------------------------------------------------------
create table invitations (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid references projects(id) on delete set null,
  slug          text unique not null,            -- invitation-web/<slug>
  title         text not null,                   -- "Pernikahan Dewa & Ayu"
  event_type    text not null default 'pawiwahan', -- pawiwahan, otonan, ulang tahun, grand opening ...
  tier          text not null default 'Sekar',   -- Canang / Sekar / Gelungan
  event_date    date,
  venue         text,
  active_until  date,                            -- masa aktif 1 tahun
  is_published  boolean not null default false,
  created_at    timestamptz not null default now()
);

create table invitation_guests (
  id             uuid primary key default gen_random_uuid(),
  invitation_id  uuid not null references invitations(id) on delete cascade,
  name           text not null,
  guest_group    text,                           -- keluarga, kantor, VIP
  link_code      text unique not null default substr(md5(random()::text),1,8), -- ?to=<kode>
  rsvp           rsvp_status not null default 'belum',
  pax            int not null default 1,
  message        text,                           -- ucapan
  responded_at   timestamptz
);
create index on invitation_guests (invitation_id);

-- ---------------------------------------------------------------------
--  MAINTENANCE, DOMAIN & HOSTING
-- ---------------------------------------------------------------------
create table subscriptions (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references clients(id) on delete cascade,
  project_id      uuid references projects(id) on delete set null,
  plan            text not null default 'Maintenance Bulanan',
  monthly_fee     numeric(14,0) not null default 250000,
  domain          text,
  domain_expiry   date,
  hosting_expiry  date,
  next_billing    date,
  status          sub_status not null default 'aktif',
  notes           text
);

-- ---------------------------------------------------------------------
--  PORTFOLIO (tampil di website)
-- ---------------------------------------------------------------------
create table portfolio (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid references projects(id) on delete set null,
  title        text not null,
  category     service_kind not null,
  subtitle     text,
  image_url    text,
  demo_url     text,
  is_featured  boolean not null default true,
  sort_order   int not null default 0
);

-- ---------------------------------------------------------------------
--  PENGATURAN & LOG
-- ---------------------------------------------------------------------
create table settings (
  key    text primary key,
  value  text
);

create table activity_log (
  id         bigint generated always as identity primary key,
  actor      uuid default auth.uid(),
  action     text not null,                 -- "tambah", "ubah", "hapus"
  entity     text not null,                 -- nama tabel
  entity_id  text,
  summary    text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
--  VIEW LAPORAN
-- ---------------------------------------------------------------------
-- Piutang per proyek
create or replace view v_receivables with (security_invoker = on) as
select p.id, p.code, p.title, c.business_name, c.name as client_name, c.phone_wa,
       p.price_total,
       coalesce(sum(pay.amount),0)                    as paid,
       p.price_total - coalesce(sum(pay.amount),0)    as outstanding,
       p.status, p.due_date
from projects p
join clients c on c.id = p.client_id
left join payments pay on pay.project_id = p.id
where p.status <> 'batal'
group by p.id, c.id;

-- Pendapatan per bulan
create or replace view v_revenue_monthly with (security_invoker = on) as
select date_trunc('month', paid_at)::date as month, sum(amount) as revenue, count(*) as payments
from payments group by 1 order by 1;

-- Kinerja sumber lead (untuk evaluasi SEO/SEM)
create or replace view v_lead_sources with (security_invoker = on) as
select source,
       count(*)                                        as leads,
       count(*) filter (where status = 'menang')       as won,
       round(100.0 * count(*) filter (where status = 'menang') / nullif(count(*),0), 1) as win_rate,
       coalesce(sum(est_value) filter (where status = 'menang'),0) as won_value
from leads group by source;

-- Domain / hosting yang habis dalam 30 hari
create or replace view v_expiring with (security_invoker = on) as
select s.*, c.business_name, c.phone_wa
from subscriptions s join clients c on c.id = s.client_id
where s.status = 'aktif'
  and (s.domain_expiry <= current_date + 30 or s.hosting_expiry <= current_date + 30);

-- Rekap RSVP per undangan
create or replace view v_rsvp_summary with (security_invoker = on) as
select i.id, i.title, i.event_date,
       count(g.*)                                   as guests,
       count(*) filter (where g.rsvp = 'hadir')     as attending,
       coalesce(sum(g.pax) filter (where g.rsvp = 'hadir'),0) as attending_pax,
       count(*) filter (where g.rsvp = 'tidak_hadir') as declined
from invitations i left join invitation_guests g on g.invitation_id = i.id
group by i.id;

-- ---------------------------------------------------------------------
--  KEAMANAN (Row Level Security)
--  - Master (owner): akses penuh + mengelola karyawan.
--  - Karyawan: hanya tabel dari menu yang dicentang di kolom staff.access.
--  - Publik (website): hanya boleh MENGIRIM lead, membaca paket aktif
--    dan portfolio, serta mengisi RSVP lewat fungsi submit_rsvp().
-- ---------------------------------------------------------------------
-- Setiap tabel dibuka sesuai hak akses menu karyawan.
-- (tabel => menu) ; owner/master selalu boleh semua.
do $$
declare r record;
begin
  for r in select * from (values
      ('clients','clients'), ('packages','packages'), ('leads','leads'), ('projects','projects'),
      ('project_items','projects'), ('tasks','tasks'), ('invoices','payments'), ('payments','payments'),
      ('invitations','invitations'), ('invitation_guests','invitation_guests'),
      ('subscriptions','subscriptions'), ('portfolio','portfolio'), ('settings','settings')) as v(tbl, menu)
  loop
    execute format('alter table %I enable row level security', r.tbl);
    execute format('create policy "akses_%1$s" on %1$I for all to authenticated using (has_access(%2$L)) with check (has_access(%2$L))', r.tbl, r.menu);
  end loop;
end $$;

-- Proyek & klien tetap terbaca (nama saja) oleh karyawan yang membuka menu terkait
create policy "baca_klien_untuk_proyek" on clients for select to authenticated
  using (has_access('projects') or has_access('leads') or has_access('subscriptions'));
create policy "baca_proyek_untuk_menu_lain" on projects for select to authenticated
  using (has_access('payments') or has_access('invitations') or has_access('tasks') or has_access('portfolio') or has_access('subscriptions'));
create policy "baca_paket_untuk_karyawan" on packages for select to authenticated using (is_staff());
create policy "baca_undangan_untuk_tamu" on invitations for select to authenticated using (has_access('invitation_guests'));
create policy "baca_pengaturan" on settings for select to authenticated using (is_staff());

-- Data karyawan: semua karyawan aktif boleh membaca, hanya master yang mengubah
alter table staff enable row level security;
create policy "staff_baca" on staff for select to authenticated using (is_staff() or id = auth.uid());
create policy "staff_kelola" on staff for all to authenticated using (is_owner()) with check (is_owner());

-- Log aktivitas: semua karyawan menulis, hanya master yang membaca
alter table activity_log enable row level security;
create policy "log_tulis" on activity_log for insert to authenticated with check (is_staff());
create policy "log_baca"  on activity_log for select to authenticated using (is_owner());

create policy "publik_kirim_lead" on leads for insert to anon
  with check (status = 'baru' and client_id is null);
create policy "publik_baca_paket" on packages for select to anon using (is_active);
create policy "publik_baca_portfolio" on portfolio for select to anon using (is_featured);

-- RSVP tamu tanpa login: hanya lewat kode link pribadi
create or replace function submit_rsvp(p_code text, p_rsvp rsvp_status, p_pax int, p_message text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  update invitation_guests
     set rsvp = p_rsvp, pax = greatest(1, least(p_pax, 10)),
         message = left(p_message, 500), responded_at = now()
   where link_code = p_code;
  return found;
end $$;
grant execute on function submit_rsvp(text, rsvp_status, int, text) to anon;

-- ---------------------------------------------------------------------
--  DATA AWAL: paket & harga Nubira
-- ---------------------------------------------------------------------
insert into packages (code, service, name, price, is_addon, duration_text, revisions, active_period, features, sort_order) values
('STARTER',  'website',     'Starter',              1500000, false, '5 hari kerja',      '1x', null,      '{Landing page 1 halaman,Tombol chat WhatsApp,Google Maps & jam buka,Tampil rapi di HP}', 1),
('BISNIS',   'website',     'Bisnis',               3500000, false, '7–10 hari kerja',   '2x', '1 tahun', '{Hingga 5 halaman,Domain + hosting 1 tahun,Galeri foto & layanan,SEO dasar Google}', 2),
('VILLA',    'villa',       'Villa & Booking',      6500000, false, '10–14 hari kerja',  '2x', '1 tahun', '{Dua bahasa,Galeri kamar & fasilitas,Form booking ke WhatsApp,Terhubung Instagram}', 3),
('MAINT',    'maintenance', 'Maintenance Bulanan',   250000, false, 'per bulan',         null, null,      '{Update konten,Backup,Perpanjangan domain}', 4),
('CANANG',   'undangan',    'Undangan Canang',        85000, false, '1–3 hari',          '2x', '1 tahun', '{Nama tamu otomatis tanpa batas,Countdown peta & musik,Galeri 6 foto,1 bahasa}', 10),
('SEKAR',    'undangan',    'Undangan Sekar',        185000, false, '1–3 hari',          '2x', '1 tahun', '{Nama tamu otomatis tanpa batas,Galeri 15 foto + 1 video,RSVP & ucapan tamu,Amplop digital}', 11),
('GELUNGAN', 'undangan',    'Undangan Gelungan',     450000, false, '1–3 hari',   'Sepuasnya', '1 tahun', '{Desain custom,Sampul VIP,Galeri tanpa batas,RSVP + rekap Excel,2 bahasa}', 12),
('ADD-EXP',  'undangan',    'Express 24 jam',         50000, true,  '24 jam', null, null, '{}', 20),
('ADD-LANG', 'undangan',    'Tambah bahasa',          50000, true,  null, null, null, '{}', 21),
('ADD-VID',  'undangan',    'Video Story/Reels',      75000, true,  null, null, null, '{}', 22),
('ADD-QR',   'undangan',    'QR check-in tamu',      100000, true,  null, null, null, '{}', 23),
('ADD-DOM',  'undangan',    'Domain sendiri',        350000, true,  null, null, '1 tahun', '{}', 24);

insert into settings (key, value) values
('business_name', 'Nubira Digital Indonesia'),
('tagline',       'Built in Bali. Made to Grow.'),
('city',          'Denpasar, Bali'),
('website',       'https://nubiraindonesia.com'),
('dashboard',     'https://dashboard.nubiraindonesia.com'),
('whatsapp',      '0895-3311-91682'),
('email',         'nubiraindonesia@gmail.com'),
('bank_account',  ''),
('dp_percent',    '50');

-- ---------------------------------------------------------------------
--  MASTER LOGIN
--  1. Authentication → Users → Add user → email dewaadiii@gmail.com
--     dan kata sandi master Anda (centang "Auto Confirm User").
--  2. Jalankan perintah di bawah ini.
-- ---------------------------------------------------------------------
-- insert into staff (id, full_name, email, role, access)
-- select id, 'Dewa Adi', email, 'owner',
--        '{leads,clients,projects,payments,invitations,invitation_guests,subscriptions,packages,portfolio,settings,tasks}'
-- from auth.users where email = 'dewaadiii@gmail.com';
--
--  Karyawan berikutnya dibuat dari menu "Karyawan" di admin panel.
--  Di Supabase: Authentication → Providers → Email: aktifkan "Allow new
--  users to sign up" dan matikan "Confirm email" agar karyawan baru
--  langsung bisa login. Orang yang mendaftar sendiri tetap tidak bisa
--  membuka data apa pun sebelum dimasukkan master ke tabel staff.
