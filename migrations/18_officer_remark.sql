-- Migration 18: หมายเหตุเพิ่มเติมหลังเช็กอิน (ไม่บังคับ, write-once)
-- เจ้าหน้าที่กรอกได้ไม่เกิน 500 ตัวอักษร หลังเห็นผลเช็กอิน/สถิติส่วนตัว
-- แยกจากคอลัมน์ note เดิม (บังคับกรอกก่อนเช็กอิน ผูกกับ ready_for_duty) โดยเจตนา ไม่แตะของเดิม

-- 1) เพิ่มคอลัมน์ remark ใน check_in
alter table check_in add column if not exists remark text;

alter table check_in drop constraint if exists check_in_remark_maxlen;
alter table check_in add constraint check_in_remark_maxlen check (remark is null or char_length(remark) <= 500);

-- 2) RPC บันทึกหมายเหตุ (write-once: ถ้ามีอยู่แล้วปฏิเสธ พร้อมส่งค่าเดิมกลับไปให้ frontend แสดง)
create or replace function public.do_save_remark(
  p_officer_id uuid,
  p_pin text,
  p_remark text
) returns json
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype;
  v_tz text;
  v_row check_in%rowtype;
  v_remark text := trim(coalesce(p_remark, ''));
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select tz into v_tz from settings where id = 1;

  select * into v_row from check_in
  where officer_id = p_officer_id and local_date = (now() at time zone v_tz)::date
  limit 1;
  if not found then
    return json_build_object('ok', false, 'error', 'no_checkin_today');
  end if;

  if v_row.remark is not null and length(trim(v_row.remark)) > 0 then
    return json_build_object('ok', false, 'error', 'already_saved', 'remark', v_row.remark);
  end if;

  if length(v_remark) = 0 then
    return json_build_object('ok', false, 'error', 'empty_remark');
  end if;

  if length(v_remark) > 500 then
    return json_build_object('ok', false, 'error', 'remark_too_long');
  end if;

  update check_in set remark = v_remark where id = v_row.id;

  return json_build_object('ok', true, 'remark', v_remark);
end;
$function$;

grant execute on function public.do_save_remark(uuid, text, text) to anon;
grant execute on function public.do_save_remark(uuid, text, text) to authenticated;

-- 3) do_get_today_status: return type ยังเป็น json เดิม แค่เพิ่ม key ไม่ต้อง DROP
create or replace function public.do_get_today_status(p_officer_id uuid, p_pin text)
returns json
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype;
  v_row check_in%rowtype;
  v_tz text;
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
    'remark', v_row.remark
  );
end;
$function$;

-- 4) do_supervisor_get_today: DROP ก่อนตามกติกาโปรเจกต์ (กันบั๊กคลาสสิกเปลี่ยนคอลัมน์ return)
drop function if exists public.do_supervisor_get_today(uuid, text);
create or replace function public.do_supervisor_get_today(p_officer_id uuid, p_pin text)
returns json
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype;
  v_tz text;
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
      c.override_reason, c.override_at, ob.full_name as override_by_name
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    where c.local_date = (now() at time zone v_tz)::date
    order by c.checked_in_at
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

grant execute on function public.do_supervisor_get_today(uuid, text) to anon;
grant execute on function public.do_supervisor_get_today(uuid, text) to authenticated;

-- 5) do_get_history (auth, dashboard.html): DROP + recreate เพิ่ม remark
drop function if exists public.do_get_history(date, date, uuid);
create or replace function public.do_get_history(p_start_date date, p_end_date date, p_target_officer_id uuid default null::uuid)
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

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    return json_build_object('ok', false, 'error', 'invalid_date_range');
  end if;

  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (
    select c.id, c.local_date, o.full_name, o.rank_title, o.nickname,
      c.checked_in_at, c.status, c.override_status,
      coalesce(c.override_status, c.status) as effective_status,
      c.distance_m, c.ready_for_duty, c.note, c.remark, c.photo_path, c.incomplete_checkin,
      c.override_reason, c.override_at, ob.full_name as override_by_name
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    where c.local_date between p_start_date and p_end_date
      and (p_target_officer_id is null or c.officer_id = p_target_officer_id)
    order by c.local_date desc, c.checked_in_at desc
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

grant execute on function public.do_get_history(date, date, uuid) to authenticated;

-- 6) do_supervisor_get_history (PIN, report.html): DROP + recreate เพิ่ม remark
drop function if exists public.do_supervisor_get_history(uuid, text, date, date, uuid);
create or replace function public.do_supervisor_get_history(p_officer_id uuid, p_pin text, p_start_date date, p_end_date date, p_target_officer_id uuid default null::uuid)
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

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    return json_build_object('ok', false, 'error', 'invalid_date_range');
  end if;

  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (
    select c.id, c.local_date, o.full_name, o.rank_title, o.nickname,
      c.checked_in_at, c.status, c.override_status,
      coalesce(c.override_status, c.status) as effective_status,
      c.distance_m, c.ready_for_duty, c.note, c.remark, c.photo_path, c.incomplete_checkin,
      c.override_reason, c.override_at, ob.full_name as override_by_name
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    where c.local_date between p_start_date and p_end_date
      and (p_target_officer_id is null or c.officer_id = p_target_officer_id)
    order by c.local_date desc, c.checked_in_at desc
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

grant execute on function public.do_supervisor_get_history(uuid, text, date, date, uuid) to anon;
grant execute on function public.do_supervisor_get_history(uuid, text, date, date, uuid) to authenticated;
