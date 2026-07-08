-- ============================================================
-- เฟส A — Backend รากฐาน (1/2): Extension + ตาราง + RLS
-- ระบบเช็กอินเช้าเจ้าหน้าที่ — Spec v1
-- รันไฟล์นี้ก่อน แล้วค่อยรัน 02_phase_a_rpc.sql
-- ============================================================

-- 0. Extension สำหรับ hash PIN
create extension if not exists pgcrypto;

-- ============================================================
-- 1. ตาราง settings (แถวเดียว — ตั้งค่ากลาง)
-- ============================================================
create table public.settings (
  id            int primary key default 1,
  office_lat    double precision not null,
  office_lng    double precision not null,
  green_before  time not null default '08:15',
  yellow_before time not null default '08:30',
  tz            text not null default 'Asia/Bangkok',
  photo_retention_days int,
  constraint settings_singleton check (id = 1)
);

-- พิกัด ตม.ระยอง (ค่าจริงที่ยืนยันแล้ว)
insert into public.settings (id, office_lat, office_lng)
values (1, 12.723990, 101.140954);

-- ============================================================
-- 2. ตาราง officer (ทะเบียนเจ้าหน้าที่)
-- ============================================================
create table public.officer (
  id            uuid primary key default gen_random_uuid(),
  full_name     text not null,
  rank_title    text,
  pin_hash      text not null,
  is_supervisor boolean not null default false,
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

-- เจ้าหน้าที่ทดสอบ 3 คน (PIN ทดสอบ = 1234) — เอาไว้ทดสอบ RPC เท่านั้น
-- *** ก่อนใช้งานจริง ให้ลบแถวทดสอบเหล่านี้ทิ้ง แล้วเพิ่มรายชื่อจริง + PIN จริง ***
insert into public.officer (full_name, rank_title, pin_hash) values
  ('ทดสอบ หนึ่ง', 'เจ้าหน้าที่ทดสอบ', crypt('1234', gen_salt('bf'))),
  ('ทดสอบ สอง',   'เจ้าหน้าที่ทดสอบ', crypt('1234', gen_salt('bf'))),
  ('ทดสอบ สาม',   'เจ้าหน้าที่ทดสอบ', crypt('1234', gen_salt('bf')));

-- หมายเหตุ: บัญชีหัวหน้า (is_supervisor = true) จะเพิ่มในเฟส C
-- เพราะต้องตั้ง officer.id = auth.users.id ของบัญชี Supabase Auth ที่ยังไม่ได้สร้าง

-- ============================================================
-- 3. ตาราง check_in (หัวใจของระบบ)
-- ============================================================
create table public.check_in (
  id              uuid primary key default gen_random_uuid(),
  officer_id      uuid not null references public.officer(id),
  checked_in_at   timestamptz not null default now(),   -- server time เท่านั้น ห้ามรับจาก client
  local_date      date generated always as
                  ((checked_in_at at time zone 'Asia/Bangkok')::date) stored,
  photo_path      text not null,
  lat             double precision,
  lng             double precision,
  distance_m      integer,
  status          text not null check (status in ('green','yellow','red')),
  note            text,
  override_status text check (override_status in ('green','yellow','red')),
  override_by     uuid references public.officer(id),
  override_reason text,
  override_at     timestamptz,
  unique (officer_id, local_date)   -- กันเช็กอินซ้ำ 1 คน/วัน ที่ระดับฐานข้อมูล
);

create index on public.check_in (local_date);
create index on public.check_in (officer_id, local_date);

-- ============================================================
-- 4. RLS — ปิดการเข้าถึงตารางตรงๆ ทั้งหมด บังคับผ่าน RPC เท่านั้น
-- ============================================================
alter table public.settings enable row level security;
alter table public.officer  enable row level security;
alter table public.check_in enable row level security;

-- ไม่เปิด select ตรงบน officer ให้ anon (เพื่อไม่ให้เสี่ยงหลุด pin_hash)
-- ใช้ RPC do_list_officers() แทน (อยู่ในไฟล์ 02_phase_a_rpc.sql)

-- supervisor (authenticated + is_supervisor) อ่าน check_in ทั้งหมดได้
create policy checkin_read_supervisor on public.check_in
  for select to authenticated
  using (exists (select 1 from officer o where o.id = auth.uid() and o.is_supervisor));

-- supervisor อ่าน officer ทั้งหมดได้ (สำหรับ dashboard filter รายคน)
create policy officer_read_supervisor on public.officer
  for select to authenticated
  using (exists (select 1 from officer o where o.id = auth.uid() and o.is_supervisor));

-- ไม่มี insert/update/delete policy ให้ใครเลย -> ทุกการเขียนต้องผ่าน RPC (security definer) เท่านั้น
