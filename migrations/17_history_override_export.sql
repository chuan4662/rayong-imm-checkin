-- ============================================================
-- Migration 17: แดชบอร์ดหัวหน้าให้ครบสเปก v1
--   (1) do_override เดิม (auth) เพิ่ม validate เหตุผล/สถานะ/เช็คว่า checkin มีจริง
--   (2) do_supervisor_override ใหม่ (PIN-based override สำหรับ report.html)
--   (3) do_get_history ใหม่ (auth) — ประวัติย้อนหลังเลือกช่วงวันที่ + กรองรายคน
--   (4) do_supervisor_get_history ใหม่ (PIN) — เหมือนข้อ 3 แต่สำหรับ report.html
--   (5) do_supervisor_get_today ปรับให้ส่ง override_reason/override_at/override_by_name เพิ่ม
--       (เดิมมีแค่ override_status ฝังอยู่ใน effective status ไม่เห็นว่าใครแก้/เมื่อไหร่)
-- หมายเหตุ: ทุกฟังก์ชันในไฟล์นี้ returns json (ไม่ใช่ table) จึงไม่ต้อง DROP FUNCTION ก่อน
-- Export Excel ทำฝั่ง frontend ล้วน (SheetJS) ไม่ต้องมี backend เพิ่ม
-- ============================================================

-- 1) do_override — เพิ่ม validate เหตุผลขั้นต่ำ 5 ตัวอักษร, ตรวจสถานะที่รับได้ (4 สี), เช็คว่า checkin_id มีจริง
create or replace function public.do_override(
  p_check_in_id uuid,
  p_new_status  text,
  p_reason      text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_sup boolean;
  v_reason text := trim(coalesce(p_reason, ''));
  v_updated int;
begin
  select is_supervisor into v_is_sup
  from officer where id = auth.uid();

  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  if p_new_status not in ('green','yellow','orange','red') then
    return json_build_object('ok', false, 'error', 'invalid_status');
  end if;

  if length(v_reason) < 5 then
    return json_build_object('ok', false, 'error', 'reason_too_short');
  end if;

  update check_in
     set override_status = p_new_status,
         override_by     = auth.uid(),
         override_reason = v_reason,
         override_at     = now()
   where id = p_check_in_id;

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    return json_build_object('ok', false, 'error', 'checkin_not_found');
  end if;

  return json_build_object('ok', true);
end;
$$;
grant execute on function public.do_override(uuid, text, text) to authenticated;

-- 2) do_supervisor_override — เวอร์ชัน PIN (ศุภัตรา / ผู้ช่วยแอดมิน ใน report.html)
create or replace function public.do_supervisor_override(
  p_officer_id  uuid,
  p_pin         text,
  p_check_in_id uuid,
  p_new_status  text,
  p_reason      text
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_off    officer%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
  v_updated int;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  if p_new_status not in ('green','yellow','orange','red') then
    return json_build_object('ok', false, 'error', 'invalid_status');
  end if;

  if length(v_reason) < 5 then
    return json_build_object('ok', false, 'error', 'reason_too_short');
  end if;

  update check_in
     set override_status = p_new_status,
         override_by     = p_officer_id,
         override_reason = v_reason,
         override_at     = now()
   where id = p_check_in_id;

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    return json_build_object('ok', false, 'error', 'checkin_not_found');
  end if;

  return json_build_object('ok', true);
end;
$$;
grant execute on function public.do_supervisor_override(uuid, text, uuid, text, text) to anon;

-- 3) do_get_history — เวอร์ชัน auth (dashboard.html) ประวัติย้อนหลังเลือกช่วงวันที่ + กรองรายคน
create or replace function public.do_get_history(
  p_start_date        date,
  p_end_date          date,
  p_target_officer_id uuid default null
) returns json
language plpgsql
security definer
set search_path = public
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
           c.distance_m, c.ready_for_duty, c.note, c.photo_path, c.incomplete_checkin,
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
$$;
grant execute on function public.do_get_history(date, date, uuid) to authenticated;

-- 4) do_supervisor_get_history — เวอร์ชัน PIN (report.html)
create or replace function public.do_supervisor_get_history(
  p_officer_id        uuid,
  p_pin               text,
  p_start_date        date,
  p_end_date          date,
  p_target_officer_id uuid default null
) returns json
language plpgsql
security definer
set search_path = public, extensions
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
           c.distance_m, c.ready_for_duty, c.note, c.photo_path, c.incomplete_checkin,
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
$$;
grant execute on function public.do_supervisor_get_history(uuid, text, date, date, uuid) to anon;

-- 5) do_supervisor_get_today — เพิ่ม override_reason / override_at / override_by_name
--    (เดิมมีแค่ effective status ผ่าน coalesce(override_status,status) ไม่เห็นว่าใครแก้/เมื่อไหร่/เพราะอะไร)
drop function if exists public.do_supervisor_get_today(uuid, text);
create or replace function public.do_supervisor_get_today(
  p_officer_id uuid,
  p_pin        text
) returns json
language plpgsql
security definer
set search_path = public, extensions
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
           c.distance_m, c.ready_for_duty, c.note, c.photo_path, c.incomplete_checkin,
           c.override_reason, c.override_at, ob.full_name as override_by_name
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    where c.local_date = (now() at time zone v_tz)::date
    order by c.checked_in_at
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$$;
grant execute on function public.do_supervisor_get_today(uuid, text) to anon;
