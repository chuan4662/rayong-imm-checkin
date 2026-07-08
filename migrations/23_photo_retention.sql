-- =========================================================================
-- Migration 23: นโยบายลบรูปอัตโนมัติ (PDPA) — retention_hold + photo_deleted_at
-- =========================================================================
-- บริบท: PDPA compliance — ลบรูปเซลฟี่เช็กอินอัตโนมัติหลัง 31 วัน (rolling window
-- ไม่ใช่ตามเดือนปฏิทิน) แต่เก็บ metadata อื่นๆ (สถานะ/เวลา/ระยะทาง/override/หมายเหตุ)
-- ไว้ถาวรเหมือนเดิม เจ้าของยืนยันแล้ว (ผ่าน AskUserQuestion รอบก่อนหน้า):
--   1. เพิ่ม "retention hold" flag ที่หัวหน้าทั้ง 3 คนตั้งได้ต่อแถว check_in เพื่อยกเว้น
--      ไม่ให้ลบรูป (ใช้กรณีมีข้อพิพาท/ถูก override ที่ยังอยู่ระหว่างตรวจสอบ) — ตัวเลือกที่แนะนำและเจ้าของเลือก
--   2. เริ่มเขียนโค้ดด้วยเลข 31 วันไปก่อน ปรับได้ทีหลังผ่าน settings.photo_retention_days
--      (เป็น integer column มีอยู่แล้ว ตอนนี้เป็น NULL) — ไม่ต้องรอเช็กระเบียบตำรวจ/ตม.ก่อน
--
-- รันบน Supabase SQL Editor (project ref aamzsbuwfdyljdvwaifb) — ยังไม่เคย DROP FUNCTION
-- ใดๆ ในไฟล์นี้ เพราะทั้ง 4 read RPC ที่แก้ (do_get_today_status, do_supervisor_get_today,
-- do_get_history, do_supervisor_get_history) return type ยังเป็น `json` เหมือนเดิมทุกตัว
-- (json scalar ไม่ใช่ table/composite return — กติกา DROP-ก่อน-ถ้าเปลี่ยน return columns ในข้อ 6.1
-- ของ CLAUDE.md ใช้กับฟังก์ชันที่ return TABLE/SETOF row type เท่านั้น ไม่ใช่กรณีนี้) จึงใช้
-- CREATE OR REPLACE ได้ตรงๆ ทั้งหมด
-- =========================================================================

-- 0) เปิด extension ที่จำเป็นสำหรับ pg_cron + pg_net (ยังไม่เคยเปิดมาก่อนในโปรเจกต์นี้
--    มีแค่ pgcrypto กับ supabase_vault ที่เปิดอยู่แล้ว) — ใช้เรียก Edge Function ทุกวันอัตโนมัติ
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 1) Schema: เพิ่มคอลัมน์ retention_hold + photo_deleted_at ใน check_in
alter table public.check_in
  add column if not exists retention_hold boolean not null default false;

alter table public.check_in
  add column if not exists photo_deleted_at timestamptz;

-- ⚠️ บั๊กที่พบระหว่าง E2E test (แก้แล้วในไฟล์นี้): เดิม photo_path เป็น NOT NULL มาตั้งแต่ v1
-- (บังคับต้องมีรูปตอนเช็กอิน) แต่ฟีเจอร์นี้ต้องตั้ง photo_path = null ได้หลังลบรูปถาวรแล้ว
-- ต้อง drop not null ก่อน ไม่งั้น Edge Function จะ error "null value in column photo_path
-- violates not-null constraint" ทุกครั้งที่พยายามลบรูป (เจอจริงตอนรัน E2E test รอบแรก)
alter table public.check_in alter column photo_path drop not null;

-- 2) ตั้งค่า photo_retention_days = 31 (rolling window นับจาก checked_in_at)
update public.settings set photo_retention_days = 31 where id = 1;

-- 3) do_set_retention_hold — เวอร์ชัน auth (ชวนชัย, dashboard.html)
--    Gate เหมือน do_override: ต้องเป็น supervisor (is_supervisor=true ผ่าน auth.uid())
--    หัวหน้าทั้ง 3 คนใช้ได้เท่ากัน ไม่ใช่ชวนชัยคนเดียว (ต่างจากฟีเจอร์ settings/supervisor mgmt ใน migration 22)
create or replace function public.do_set_retention_hold(
  p_check_in_id uuid,
  p_hold        boolean
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_sup boolean;
  v_exists boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  select exists(select 1 from check_in where id = p_check_in_id) into v_exists;
  if not v_exists then
    return json_build_object('ok', false, 'error', 'checkin_not_found');
  end if;

  update check_in set retention_hold = coalesce(p_hold, false) where id = p_check_in_id;

  return json_build_object('ok', true, 'retention_hold', coalesce(p_hold, false));
end;
$$;

grant execute on function public.do_set_retention_hold to authenticated;

-- 4) do_supervisor_set_retention_hold — เวอร์ชัน PIN (ศุภัตรา/ผู้ช่วยแอดมิน, report.html)
--    ⚠️ บั๊กที่พบระหว่าง verify (แก้แล้วในไฟล์นี้): ฟังก์ชันนี้เรียก crypt() เพื่อตรวจ PIN แต่ pgcrypto
--    อยู่ใน schema 'extensions' ไม่ใช่ 'public' — ถ้า set search_path = public เฉยๆ (ไม่ใส่ extensions)
--    จะเจอ error "function crypt(text, text) does not exist" ตอนเรียกจริง ต้อง
--    set search_path to 'public', 'extensions' เหมือนฟังก์ชัน PIN อื่นๆ ในโปรเจกต์เสมอ (do_supervisor_get_today ฯลฯ)
create or replace function public.do_supervisor_set_retention_hold(
  p_officer_id  uuid,
  p_pin         text,
  p_check_in_id uuid,
  p_hold        boolean
) returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_off    officer%rowtype;
  v_exists boolean;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select exists(select 1 from check_in where id = p_check_in_id) into v_exists;
  if not v_exists then
    return json_build_object('ok', false, 'error', 'checkin_not_found');
  end if;

  update check_in set retention_hold = coalesce(p_hold, false) where id = p_check_in_id;

  return json_build_object('ok', true, 'retention_hold', coalesce(p_hold, false));
end;
$$;

grant execute on function public.do_supervisor_set_retention_hold to anon;

-- 5) แก้ do_get_today_status ให้ return retention_hold + photo_deleted_at เพิ่ม
--    (CREATE OR REPLACE เฉยๆ — return type ยังเป็น json เหมือนเดิม)
create or replace function public.do_get_today_status(p_officer_id uuid, p_pin text)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_off officer%rowtype;
  v_row check_in%rowtype;
  v_tz  text;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;
  select tz into v_tz from settings where id = 1;
  select * into v_row from check_in where officer_id = p_officer_id and local_date = (now() at time zone v_tz)::date limit 1;
  if not found then
    return json_build_object('ok', false, 'error', 'not_checked_in');
  end if;
  return json_build_object(
    'ok', true,
    'status', coalesce(v_row.override_status, v_row.status),
    'time', v_row.checked_in_at,
    'distance_m', v_row.distance_m,
    'ready_for_duty', v_row.ready_for_duty,
    'note', v_row.note,
    'incomplete', v_row.incomplete_checkin,
    'remark', v_row.remark,
    'retention_hold', v_row.retention_hold,
    'photo_deleted_at', v_row.photo_deleted_at
  );
end;
$$;

-- 6) แก้ do_supervisor_get_today ให้ return retention_hold + photo_deleted_at เพิ่ม
create or replace function public.do_supervisor_get_today(p_officer_id uuid, p_pin text)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_off  officer%rowtype;
  v_tz   text;
  v_rows json;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select tz into v_tz from settings where id = 1;

  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (
    select c.id, o.full_name, o.rank_title, o.nickname,
           c.checked_in_at, coalesce(c.override_status, c.status) as status,
           c.distance_m, c.ready_for_duty, c.note, c.remark, c.photo_path, c.incomplete_checkin,
           c.override_reason, c.override_at, ob.full_name as override_by_name,
           c.retention_hold, c.photo_deleted_at
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    where c.local_date = (now() at time zone v_tz)::date
    order by c.checked_in_at
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- 7) แก้ do_get_history ให้ return retention_hold + photo_deleted_at เพิ่ม
create or replace function public.do_get_history(p_start_date date, p_end_date date, p_target_officer_id uuid default null::uuid)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_is_sup boolean;
  v_rows   json;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    return json_build_object('ok', false, 'error', 'invalid_date_range');
  end if;

  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (
    select c.id, c.local_date, o.full_name, o.rank_title, o.nickname,
           c.checked_in_at, c.status, c.override_status,
           coalesce(c.override_status, c.status) as effective_status,
           c.distance_m, c.ready_for_duty, c.note, c.remark, c.photo_path, c.incomplete_checkin,
           c.override_reason, c.override_at, ob.full_name as override_by_name,
           c.retention_hold, c.photo_deleted_at
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    where c.local_date between p_start_date and p_end_date
      and (p_target_officer_id is null or c.officer_id = p_target_officer_id)
    order by c.local_date desc, c.checked_in_at desc
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- 8) แก้ do_supervisor_get_history ให้ return retention_hold + photo_deleted_at เพิ่ม
create or replace function public.do_supervisor_get_history(p_officer_id uuid, p_pin text, p_start_date date, p_end_date date, p_target_officer_id uuid default null::uuid)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_off  officer%rowtype;
  v_rows json;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    return json_build_object('ok', false, 'error', 'invalid_date_range');
  end if;

  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (
    select c.id, c.local_date, o.full_name, o.rank_title, o.nickname,
           c.checked_in_at, c.status, c.override_status,
           coalesce(c.override_status, c.status) as effective_status,
           c.distance_m, c.ready_for_duty, c.note, c.remark, c.photo_path, c.incomplete_checkin,
           c.override_reason, c.override_at, ob.full_name as override_by_name,
           c.retention_hold, c.photo_deleted_at
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    where c.local_date between p_start_date and p_end_date
      and (p_target_officer_id is null or c.officer_id = p_target_officer_id)
    order by c.local_date desc, c.checked_in_at desc
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- grant execute เดิมของ 4 ฟังก์ชันนี้มีอยู่แล้วตั้งแต่ migration ก่อนหน้า (authenticated/anon ตามคู่)
-- CREATE OR REPLACE ไม่ล้าง grant เดิม จึงไม่ต้อง grant ซ้ำ

-- =========================================================================
-- 9) Edge Function `delete-old-photos` — deploy แยกผ่าน Supabase Dashboard "Via Editor"
--    (โค้ดเต็มอยู่ที่ไฟล์ edge_function_delete-old-photos.ts ในโฟลเดอร์นี้) — deploy แล้วจริง
--    ตรวจสิทธิ์เรียกด้วย custom header "x-cron-secret" เทียบกับ Function Secret ชื่อ CRON_SECRET
--    (ตั้งค่าผ่าน Dashboard > Edge Functions > Secrets ไม่ได้เก็บ plaintext ไว้ในไฟล์นี้)
--    ใช้ service role key (inject อัตโนมัติ ไม่ต้องตั้งเอง) คุย Storage API จริง — ไม่ raw-delete
--    storage.objects เพราะ Supabase มี trigger `storage.protect_delete()` กันไว้อยู่แล้ว (ยืนยันแล้ว
--    ว่า raw delete ผ่าน SQL ทำไม่ได้จริง เจอ error "Direct deletion from storage tables is not
--    allowed. Use the Storage API instead." ระหว่างทำความสะอาดข้อมูลทดสอบ — เป็นหลักฐานยืนยันว่า
--    ดีไซน์ที่ใช้ Storage API ในฟังก์ชันถูกต้องแล้วตั้งแต่แรก)
--
-- 10) เก็บ CRON_SECRET (ค่าเดียวกับ Function Secret) ไว้ใน supabase_vault เพื่อไม่ต้องฝัง
--     plaintext ซ้ำในไฟล์นี้ตรงๆ — รันครั้งเดียวตอน provision จริงด้วยค่าที่ generate แบบสุ่ม
--     (เช่น `python3 -c "import secrets; print(secrets.token_hex(32))"`) แล้วแทนที่ placeholder
--     ด้านล่างก่อนรัน (ไม่ commit ค่าจริงไว้ในไฟล์นี้ถาวร):
-- select vault.create_secret('REPLACE_WITH_GENERATED_SECRET', 'cron_secret',
--   'Shared secret header for delete-old-photos daily cron job (matches Edge Function secret CRON_SECRET)');

-- 11) ตั้ง pg_cron ให้เรียก Edge Function ทุกวัน 02:00 น. เวลาไทย (= 19:00 UTC วันก่อนหน้า)
--     ใช้ publishable/anon key เป็น Authorization Bearer (public key อยู่แล้วใน index.html/dashboard.html
--     ปลอดภัยที่จะฝังตรงๆ) — สิทธิ์จริงตรวจด้วย x-cron-secret ข้างในฟังก์ชันเอง ไม่ใช่ anon key
select cron.schedule(
  'delete-old-photos-daily',
  '0 19 * * *',
  $$
  select net.http_post(
      url := 'https://aamzsbuwfdyljdvwaifb.supabase.co/functions/v1/delete-old-photos',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer sb_publishable_5LSUhgfmbb90ckwvNbJwgw_wR2z0ik_',
        'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
      ),
      body := '{}'::jsonb
  ) as request_id;
  $$
);

-- ทำจริงแล้ว 5 ก.ค. 2569: เปิด pg_cron/pg_net, เก็บ cron_secret ใน vault, ตั้ง cron job สำเร็จ
-- (jobid=1, active=true, schedule='0 19 * * *') verify แล้วว่า cron.job มีจริงและ net.http_post
-- เรียก Edge Function ได้จริงผ่าน E2E test (ดูรายละเอียดผลทดสอบใน CLAUDE.md ข้อ 20)
