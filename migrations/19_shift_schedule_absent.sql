-- ============================================================
-- Migration 19: วันทำงานรายคน (work_days) + วันหยุดนักขัตฤกษ์ (public_holiday)
--                + สถานะ "ขาดเช็กอิน" (สีน้ำตาลเข้ม) — MVP แบบง่าย ไม่มีปฏิทินเต็มรูปแบบ
-- ยืนยันกับเจ้าของแล้ว:
--   - หัวหน้าทั้ง 3 คน (auth + PIN ทั้งคู่) แก้ work_days/วันหยุดได้เท่ากัน
--   - ฟันธงว่า "ขาดเช็กอิน" ก็ต่อเมื่อผ่านเวลา 16:30 น. ของวันนั้นไปแล้ว (เผื่อคนมีธุระครึ่งวันเช้า)
-- ============================================================

-- 1) officer.work_days — วันในสัปดาห์ที่ควรทำงาน (1=จันทร์ ... 7=อาทิตย์ ตาม isodow)
--    default = จันทร์-ศุกร์ ปรับได้รายคน เช่น {3,4,5} = พุธ-พฤหัส-ศุกร์
alter table public.officer add column if not exists work_days smallint[] not null default '{1,2,3,4,5}';

alter table public.officer drop constraint if exists officer_work_days_valid;
alter table public.officer add constraint officer_work_days_valid
  check (work_days <@ array[1,2,3,4,5,6,7]::smallint[]);

-- 2) ตารางวันหยุดนักขัตฤกษ์ — หัวหน้าเพิ่ม/ลบเองได้ ไม่ต้องรอแก้โค้ด
create table if not exists public.public_holiday (
  id uuid primary key default gen_random_uuid(),
  holiday_date date not null unique,
  description text,
  created_at timestamptz not null default now()
);

alter table public.public_holiday enable row level security;
-- ไม่เปิด policy ให้ query ตรงจาก client เลย — เข้าถึงได้ผ่าน RPC (SECURITY DEFINER) เท่านั้น

-- 3) เวลาตัดสินว่า "ขาดเช็กอิน" (ผ่านเวลานี้ของวันนั้นไปแล้วถึงจะฟันธง)
alter table public.settings add column if not exists absent_cutoff_time time not null default '16:30';

-- ============================================================
-- 4) RPC: รายชื่อคนขาดเช็กอิน (ควรทำงานวันนั้น + ไม่ใช่วันหยุด + ยังไม่มีเช็กอิน + ผ่านเวลาตัดสินแล้ว)
-- ============================================================
create or replace function public.do_get_absentees(p_date date default null)
returns json
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_is_sup boolean;
  v_set settings%rowtype;
  v_target_date date;
  v_now_local timestamptz;
  v_rows json;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  select * into v_set from settings where id = 1;
  v_now_local := now() at time zone v_set.tz;
  v_target_date := coalesce(p_date, v_now_local::date);

  if v_target_date > v_now_local::date then
    return json_build_object('ok', false, 'error', 'future_date');
  end if;

  if v_target_date = v_now_local::date and v_now_local::time < v_set.absent_cutoff_time then
    return json_build_object('ok', true, 'too_early', true, 'cutoff_time', v_set.absent_cutoff_time, 'rows', '[]'::json);
  end if;

  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (
    select o.id, o.full_name, o.rank_title, o.nickname
    from officer o
    where o.active = true
      and extract(isodow from v_target_date)::smallint = any(o.work_days)
      and not exists (select 1 from public_holiday h where h.holiday_date = v_target_date)
      and not exists (select 1 from check_in c where c.officer_id = o.id and c.local_date = v_target_date)
    order by o.sort_order
  ) t;

  return json_build_object('ok', true, 'too_early', false, 'rows', v_rows);
end;
$function$;

grant execute on function public.do_get_absentees(date) to authenticated;

create or replace function public.do_supervisor_get_absentees(p_officer_id uuid, p_pin text, p_date date default null)
returns json
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype;
  v_set settings%rowtype;
  v_target_date date;
  v_now_local timestamptz;
  v_rows json;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select * into v_set from settings where id = 1;
  v_now_local := now() at time zone v_set.tz;
  v_target_date := coalesce(p_date, v_now_local::date);

  if v_target_date > v_now_local::date then
    return json_build_object('ok', false, 'error', 'future_date');
  end if;

  if v_target_date = v_now_local::date and v_now_local::time < v_set.absent_cutoff_time then
    return json_build_object('ok', true, 'too_early', true, 'cutoff_time', v_set.absent_cutoff_time, 'rows', '[]'::json);
  end if;

  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (
    select o.id, o.full_name, o.rank_title, o.nickname
    from officer o
    where o.active = true
      and extract(isodow from v_target_date)::smallint = any(o.work_days)
      and not exists (select 1 from public_holiday h where h.holiday_date = v_target_date)
      and not exists (select 1 from check_in c where c.officer_id = o.id and c.local_date = v_target_date)
    order by o.sort_order
  ) t;

  return json_build_object('ok', true, 'too_early', false, 'rows', v_rows);
end;
$function$;

grant execute on function public.do_supervisor_get_absentees(uuid, text, date) to anon;
grant execute on function public.do_supervisor_get_absentees(uuid, text, date) to authenticated;

-- ============================================================
-- 5) RPC: ตั้งวันทำงานรายคน
-- ============================================================
create or replace function public.do_set_officer_workdays(p_target_officer_id uuid, p_work_days smallint[])
returns json
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  if p_work_days is null or not (p_work_days <@ array[1,2,3,4,5,6,7]::smallint[]) then
    return json_build_object('ok', false, 'error', 'invalid_work_days');
  end if;

  update officer set work_days = p_work_days where id = p_target_officer_id;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;

  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_set_officer_workdays(uuid, smallint[]) to authenticated;

create or replace function public.do_supervisor_set_officer_workdays(p_officer_id uuid, p_pin text, p_target_officer_id uuid, p_work_days smallint[])
returns json
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  if p_work_days is null or not (p_work_days <@ array[1,2,3,4,5,6,7]::smallint[]) then
    return json_build_object('ok', false, 'error', 'invalid_work_days');
  end if;

  update officer set work_days = p_work_days where id = p_target_officer_id;
  if not found then
    return json_build_object('ok', false, 'error', 'target_not_found');
  end if;

  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_supervisor_set_officer_workdays(uuid, text, uuid, smallint[]) to anon;
grant execute on function public.do_supervisor_set_officer_workdays(uuid, text, uuid, smallint[]) to authenticated;

-- ============================================================
-- 6) RPC: จัดการวันหยุดนักขัตฤกษ์ (list / add / delete)
-- ============================================================
create or replace function public.do_list_holidays()
returns json
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_is_sup boolean;
  v_rows json;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (select id, holiday_date, description from public_holiday order by holiday_date) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

grant execute on function public.do_list_holidays() to authenticated;

create or replace function public.do_supervisor_list_holidays(p_officer_id uuid, p_pin text)
returns json
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype;
  v_rows json;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (select id, holiday_date, description from public_holiday order by holiday_date) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

grant execute on function public.do_supervisor_list_holidays(uuid, text) to anon;
grant execute on function public.do_supervisor_list_holidays(uuid, text) to authenticated;

create or replace function public.do_add_holiday(p_holiday_date date, p_description text)
returns json
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  if p_holiday_date is null then
    return json_build_object('ok', false, 'error', 'invalid_date');
  end if;

  insert into public_holiday(holiday_date, description) values (p_holiday_date, nullif(trim(coalesce(p_description,'')), ''));
  return json_build_object('ok', true);
exception
  when unique_violation then
    return json_build_object('ok', false, 'error', 'already_exists');
end;
$function$;

grant execute on function public.do_add_holiday(date, text) to authenticated;

create or replace function public.do_supervisor_add_holiday(p_officer_id uuid, p_pin text, p_holiday_date date, p_description text)
returns json
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;
  if p_holiday_date is null then
    return json_build_object('ok', false, 'error', 'invalid_date');
  end if;

  insert into public_holiday(holiday_date, description) values (p_holiday_date, nullif(trim(coalesce(p_description,'')), ''));
  return json_build_object('ok', true);
exception
  when unique_violation then
    return json_build_object('ok', false, 'error', 'already_exists');
end;
$function$;

grant execute on function public.do_supervisor_add_holiday(uuid, text, date, text) to anon;
grant execute on function public.do_supervisor_add_holiday(uuid, text, date, text) to authenticated;

create or replace function public.do_delete_holiday(p_holiday_id uuid)
returns json
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  delete from public_holiday where id = p_holiday_id;
  if not found then
    return json_build_object('ok', false, 'error', 'not_found');
  end if;
  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_delete_holiday(uuid) to authenticated;

create or replace function public.do_supervisor_delete_holiday(p_officer_id uuid, p_pin text, p_holiday_id uuid)
returns json
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  delete from public_holiday where id = p_holiday_id;
  if not found then
    return json_build_object('ok', false, 'error', 'not_found');
  end if;
  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_supervisor_delete_holiday(uuid, text, uuid) to anon;
grant execute on function public.do_supervisor_delete_holiday(uuid, text, uuid) to authenticated;

-- ============================================================
-- 7) แก้ do_list_officers_admin / do_supervisor_list_officers ให้คืน work_days เพิ่ม
--    (ตรวจ signature เดิมจริงจาก pg_get_functiondef แล้ว — DROP ก่อนเพราะเปลี่ยนจำนวนคอลัมน์ที่ return)
-- ============================================================
drop function if exists public.do_list_officers_admin();
create or replace function public.do_list_officers_admin()
returns table(id uuid, full_name text, rank_title text, nickname text, is_supervisor boolean, active boolean, login_method text, needs_pin_setup boolean, work_days smallint[])
language sql
security definer
set search_path to 'public'
as $function$
select o.id, o.full_name, o.rank_title, o.nickname, o.is_supervisor, o.active, o.login_method,
(o.pin_hash is null) as needs_pin_setup, o.work_days
from officer o
where exists (select 1 from officer s where s.id = auth.uid() and s.is_supervisor)
order by o.sort_order, o.full_name;
$function$;

grant execute on function public.do_list_officers_admin() to authenticated;

drop function if exists public.do_supervisor_list_officers(uuid, text);
create or replace function public.do_supervisor_list_officers(p_officer_id uuid, p_pin text)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
v_off officer%rowtype;
v_rows json;
begin
select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
if not found then
return json_build_object('ok', false, 'error', 'officer_not_found');
end if;
if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
return json_build_object('ok', false, 'error', 'bad_pin');
end if;

select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
from (
select id, full_name, rank_title, nickname, active, is_supervisor, login_method,
(pin_hash is null) as needs_pin_setup, work_days
from officer
order by sort_order nulls last, full_name
) t;

return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

grant execute on function public.do_supervisor_list_officers(uuid, text) to anon;
grant execute on function public.do_supervisor_list_officers(uuid, text) to authenticated;
