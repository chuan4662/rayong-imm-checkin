-- ============================================================================
-- Migration 29: ห้ามเช็กอินก่อนเวลาที่กำหนด (default 07:00 น. ตั้งค่าแก้ได้โดยชวนชัย)
-- รันจริงบน Supabase SQL Editor แล้ว 13 ก.ค. 2569
-- ที่มา: เจ้าของถามว่าปัจจุบันเปิดให้เช็กอินกี่โมง พบว่าไม่มีขอบเขตเวลาล่างเลย
-- (เช็กอินตอนตี 3 จะได้สีเขียวและกินโควตา "1 คน/วัน" ของวันนั้นไปเลย) จึงสั่งให้
-- ห้ามเช็กอินก่อน 07:00 น. และให้ตั้งค่าเวลานี้แก้ไขได้ภายหลังผ่าน UI เดิม
-- (การ์ด "⚙️ ตั้งค่าระบบ" ใน dashboard.html — เฉพาะชวนชัย)
-- ============================================================================

-- 1) คอลัมน์ใหม่ใน settings
alter table public.settings add column if not exists checkin_open_after time not null default '07:00';

-- 2) แก้ do_check_in_impl (business logic จริงของการเช็กอิน หลัง migration 25 เปลี่ยนชื่อจาก do_check_in)
--    เพิ่มการปฏิเสธก่อนคำนวณสี ถ้าเวลาท้องถิ่น (Asia/Bangkok) ยังไม่ถึง checkin_open_after
--    วางไว้หลังเช็ก officer_not_found/bad_pin (auth ก่อนเสมอ) แต่ก่อนเช็ก note/ready
--    (ไม่ตั้งใจให้คนเห็นข้อความ "หมายเหตุสั้นไป" ทั้งที่ปัญหาจริงคือมาเช็กอินเร็วเกินไป)
create or replace function public.do_check_in_impl(p_officer_id uuid, p_pin text, p_photo_path text, p_lat double precision, p_lng double precision, p_note text, p_ready boolean)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype;
  v_set settings%rowtype;
  v_now timestamptz := now();
  v_local time;
  v_status text;
  v_dist integer;
  v_note text := trim(coalesce(p_note, ''));
  v_incomplete boolean := false;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;
  select * into v_set from settings where id = 1;
  v_local := (v_now at time zone v_set.tz)::time;
  if v_local < v_set.checkin_open_after then
    return json_build_object('ok', false, 'error', 'too_early', 'open_after', v_set.checkin_open_after);
  end if;
  if length(v_note) < 5 then
    return json_build_object('ok', false, 'error', 'note_too_short');
  end if;
  if p_ready is null then
    return json_build_object('ok', false, 'error', 'ready_required');
  end if;
  if v_local < v_set.green_before then
    v_status := 'green';
  elsif v_local < v_set.yellow_before then
    v_status := 'yellow';
  elsif v_local < v_set.orange_before then
    v_status := 'orange';
  else
    v_status := 'red';
  end if;
  if p_lat is not null and p_lng is not null then
    v_dist := round(6371000 * 2 * asin(sqrt(power(sin(radians(p_lat - v_set.office_lat)/2), 2) + cos(radians(v_set.office_lat)) * cos(radians(p_lat)) * power(sin(radians(p_lng - v_set.office_lng)/2), 2))));
  end if;
  v_incomplete := (p_lat is null or p_lng is null) or (v_dist is not null and v_dist > 50);
  insert into check_in(officer_id, checked_in_at, photo_path, lat, lng, distance_m, status, note, ready_for_duty, incomplete_checkin)
  values (p_officer_id, v_now, p_photo_path, p_lat, p_lng, v_dist, v_status, v_note, p_ready, v_incomplete);
  return json_build_object('ok', true, 'status', v_status, 'time', v_now, 'distance_m', v_dist, 'incomplete', v_incomplete);
exception when unique_violation then
  return json_build_object('ok', false, 'error', 'already_checked_in');
end;
$function$;

-- 3) do_get_settings: เพิ่ม checkin_open_after ในผลลัพธ์ (RETURNS json, ไม่เปลี่ยน signature จึงไม่ต้อง DROP)
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
  return json_build_object('ok', true, 'office_lat', v_set.office_lat, 'office_lng', v_set.office_lng, 'green_before', v_set.green_before, 'yellow_before', v_set.yellow_before, 'orange_before', v_set.orange_before, 'absent_cutoff_time', v_set.absent_cutoff_time, 'team_ok_before', v_set.team_ok_before, 'team_warn_before', v_set.team_warn_before, 'checkin_open_after', v_set.checkin_open_after);
end;
$function$;

-- 4) do_set_settings: เพิ่มพารามิเตอร์ที่ 9 (p_checkin_open_after) — ⚠️ ตามกติกาข้อ 2.14
--    ต้อง DROP signature เดิม (8 พารามิเตอร์) ก่อนเสมอ ไม่งั้น CREATE OR REPLACE จะสร้าง
--    overload ซ้ำแทนการแทนที่ของเดิม (บั๊กที่เจอจริงตอน migration 27/do_set_settings)
drop function if exists public.do_set_settings(double precision, double precision, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone);

create or replace function public.do_set_settings(
  p_office_lat double precision,
  p_office_lng double precision,
  p_green_before time without time zone,
  p_yellow_before time without time zone,
  p_orange_before time without time zone,
  p_absent_cutoff_time time without time zone,
  p_team_ok_before time without time zone default null,
  p_team_warn_before time without time zone default null,
  p_checkin_open_after time without time zone default null
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
  if p_office_lat is null or p_office_lng is null or p_green_before is null or p_yellow_before is null or p_orange_before is null or p_absent_cutoff_time is null then
    return json_build_object('ok', false, 'error', 'missing_field');
  end if;
  if p_office_lat < -90 or p_office_lat > 90 or p_office_lng < -180 or p_office_lng > 180 then
    return json_build_object('ok', false, 'error', 'invalid_coordinates');
  end if;
  if not (p_green_before < p_yellow_before and p_yellow_before < p_orange_before) then
    return json_build_object('ok', false, 'error', 'invalid_time_order');
  end if;
  if p_team_ok_before is not null and p_team_warn_before is not null and not (p_team_ok_before < p_team_warn_before) then
    return json_build_object('ok', false, 'error', 'invalid_team_time_order');
  end if;
  if p_checkin_open_after is not null and not (p_checkin_open_after < p_green_before) then
    return json_build_object('ok', false, 'error', 'invalid_checkin_open_time');
  end if;
  update settings set
    office_lat = p_office_lat,
    office_lng = p_office_lng,
    green_before = p_green_before,
    yellow_before = p_yellow_before,
    orange_before = p_orange_before,
    absent_cutoff_time = p_absent_cutoff_time,
    team_ok_before = coalesce(p_team_ok_before, team_ok_before),
    team_warn_before = coalesce(p_team_warn_before, team_warn_before),
    checkin_open_after = coalesce(p_checkin_open_after, checkin_open_after)
  where id = 1;
  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_set_settings(double precision, double precision, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone) to authenticated;

-- ============================================================================
-- Verify หลังรัน (ทำจริงแล้ว 13 ก.ค. 2569):
--   select proname, count(*) from pg_proc where proname in
--     ('do_check_in_impl','do_get_settings','do_set_settings') group by proname;
--   -> ต้องได้ count=1 ทุกแถว (ไม่มี overload ซ้ำ)
--   select checkin_open_after from settings where id=1; -> '07:00:00'
-- ============================================================================
