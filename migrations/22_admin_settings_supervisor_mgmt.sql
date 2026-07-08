-- 22_admin_settings_supervisor_mgmt.sql
-- ชวนชัยคนเดียว (auth-only, ไม่มีเวอร์ชัน PIN คู่กัน): ตั้งค่าระบบผ่าน UI + จัดการบัญชีหัวหน้า PIN ด้วยกันเอง
-- ขอบเขต v1 ที่ยืนยันกับเจ้าของแล้ว (2026-07-05):
--   1) ตั้งค่าระบบ: พิกัด GPS (office_lat/lng) + เวลาเกณฑ์สี (green/yellow/orange_before) + เวลาฟันธงขาดเช็กอิน (absent_cutoff_time)
--      (ไม่รวม photo_retention_days และระยะ 50 เมตร ตามที่เจ้าของเลือกไม่เอาในรอบนี้)
--   2) จัดการบัญชีหัวหน้า PIN (ศุภัตรา/ผู้ช่วยแอดมิน หรือคนใหม่ในอนาคต): เพิ่มบัญชีใหม่ + ปิด/เปิดใช้งาน
--      (ไม่รวมบัญชี auth เพราะการสร้าง Supabase Auth account ต้องทำผ่าน Dashboard เองตามกติกาเหล็กข้อ 2)
--      รีเซ็ต PIN ให้หัวหน้า PIN ไม่ต้องเพิ่ม RPC ใหม่ — do_reset_pin เดิม (migration 7) ใช้ได้กับทุก officer row
--      อยู่แล้วรวมถึงแถวหัวหน้า เพราะไม่มีเงื่อนไขกันไว้ และ dashboard.html ก็แสดงปุ่ม "รีเซ็ต PIN" ให้แถวหัวหน้า
--      PIN อยู่แล้วในตาราง "รายชื่อเจ้าหน้าที่ทั้งหมด" (เพราะ do_list_officers_admin ไม่กรอง active/is_supervisor)

-- ========= (1) ตั้งค่าระบบผ่าน UI =========
create or replace function public.do_get_settings()
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_sup boolean;
  v_set settings%rowtype;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  select * into v_set from settings where id = 1;
  return json_build_object(
    'ok', true,
    'office_lat', v_set.office_lat,
    'office_lng', v_set.office_lng,
    'green_before', v_set.green_before,
    'yellow_before', v_set.yellow_before,
    'orange_before', v_set.orange_before,
    'absent_cutoff_time', v_set.absent_cutoff_time
  );
end;
$function$;

create or replace function public.do_set_settings(
  p_office_lat double precision,
  p_office_lng double precision,
  p_green_before time,
  p_yellow_before time,
  p_orange_before time,
  p_absent_cutoff_time time
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  if p_office_lat is null or p_office_lng is null or p_green_before is null
     or p_yellow_before is null or p_orange_before is null or p_absent_cutoff_time is null then
    return json_build_object('ok', false, 'error', 'missing_field');
  end if;
  if p_office_lat < -90 or p_office_lat > 90 or p_office_lng < -180 or p_office_lng > 180 then
    return json_build_object('ok', false, 'error', 'invalid_coordinates');
  end if;
  if not (p_green_before < p_yellow_before and p_yellow_before < p_orange_before) then
    return json_build_object('ok', false, 'error', 'invalid_time_order');
  end if;
  update settings set
    office_lat = p_office_lat,
    office_lng = p_office_lng,
    green_before = p_green_before,
    yellow_before = p_yellow_before,
    orange_before = p_orange_before,
    absent_cutoff_time = p_absent_cutoff_time
  where id = 1;
  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_get_settings() to anon, authenticated;
grant execute on function public.do_set_settings(double precision, double precision, time, time, time, time) to anon, authenticated;

-- ========= (2) จัดการบัญชีหัวหน้า PIN ด้วยกันเอง =========
create or replace function public.do_add_supervisor(
  p_full_name text,
  p_rank_title text,
  p_nickname text
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_sup boolean;
  v_new_id uuid;
  v_next_sort integer;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  if p_full_name is null or length(trim(p_full_name)) = 0 then
    return json_build_object('ok', false, 'error', 'name_required');
  end if;
  select coalesce(max(sort_order), 0) + 1 into v_next_sort from officer;
  insert into officer(full_name, rank_title, nickname, sort_order, is_supervisor, active, login_method, pin_hash)
  values (trim(p_full_name), nullif(trim(coalesce(p_rank_title,'')),''), nullif(trim(coalesce(p_nickname,'')),''),
          v_next_sort, true, false, 'pin', null)
  returning id into v_new_id;
  return json_build_object('ok', true, 'id', v_new_id);
end;
$function$;

-- ⚠️ แก้ไขแล้วหลัง review (2026-07-05): เวอร์ชันแรกด้านล่าง toggle is_supervisor ตรงๆ ซึ่งมีบั๊ก
-- (ปิดบัญชีแล้ว = หายจาก do_list_officers_admin ด้วย เพราะ query กรอง is_supervisor เดียวกัน
-- ทำให้เปิดกลับไม่ได้อีกเลยผ่าน UI นี้) แก้โดยเพิ่มคอลัมน์ supervisor_enabled แยกต่างหาก:
--   alter table officer add column if not exists supervisor_enabled boolean not null default true;
-- และ toggle คอลัมน์นี้แทน (is_supervisor คงเป็น true ถาวรเป็นแค่ตัวบ่งชี้ "แถวนี้เป็นหัวหน้า")
-- ทั้ง do_list_supervisors() (ใช้ใน report.html dropdown) และ do_list_officers_admin() ถูกแก้เพิ่ม
-- filter/คอลัมน์ supervisor_enabled ด้วยแล้วเช่นกัน (ดู CLAUDE.md ข้อ 19 สำหรับรายละเอียดเต็ม)
-- เวอร์ชันที่รันจริงบน Supabase คือเวอร์ชันที่แก้แล้วนี้ ไม่ใช่เวอร์ชันด้านล่าง:
create or replace function public.do_set_supervisor_status(
  p_target_officer_id uuid,
  p_enabled boolean
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_sup boolean;
  v_target officer%rowtype;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  select * into v_target from officer where id = p_target_officer_id;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_target.login_method = 'auth' then
    return json_build_object('ok', false, 'error', 'cannot_modify_auth_supervisor');
  end if;
  if v_target.id = auth.uid() then
    return json_build_object('ok', false, 'error', 'cannot_modify_self');
  end if;
  update officer set supervisor_enabled = p_enabled where id = p_target_officer_id;  -- แก้จาก is_supervisor = p_enabled
  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_add_supervisor(text, text, text) to anon, authenticated;
grant execute on function public.do_set_supervisor_status(uuid, boolean) to anon, authenticated;

-- ========= (3) ส่วนเสริมที่รันจริงบน Supabase แต่ไม่ได้อยู่ใน draft เดิมด้านบน =========
alter table officer add column if not exists supervisor_enabled boolean not null default true;

create or replace function public.do_list_supervisors()
returns table(id uuid, full_name text, rank_title text, needs_pin_setup boolean)
language sql
security definer
set search_path to 'public'
as $function$
  select id, full_name, rank_title, (pin_hash is null) as needs_pin_setup
  from officer
  where is_supervisor = true and login_method = 'pin' and supervisor_enabled = true
  order by full_name;
$function$;

drop function if exists public.do_list_officers_admin();
create function public.do_list_officers_admin()
returns table(
  id uuid, full_name text, rank_title text, nickname text, is_supervisor boolean,
  active boolean, login_method text, needs_pin_setup boolean, work_days smallint[],
  supervisor_enabled boolean
)
language sql
security definer
set search_path to 'public'
as $function$
  select o.id, o.full_name, o.rank_title, o.nickname, o.is_supervisor, o.active, o.login_method,
    (o.pin_hash is null) as needs_pin_setup, o.work_days, o.supervisor_enabled
  from officer o
  where exists (select 1 from officer s where s.id = auth.uid() and s.is_supervisor)
  order by o.sort_order, o.full_name;
$function$;
