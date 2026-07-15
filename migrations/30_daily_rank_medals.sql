-- migration 30: P1b — เหรียญทอง/เงิน เช็กอินคนแรก-คนที่สองของวัน (daily_rank)
-- รันจริงบน Supabase SQL Editor แล้ว 15-16 ก.ค. 2569, verify ผ่าน E2E ครบทุกเคส (ดู CLAUDE.md ข้อ 32)
-- ขอบเขต: นับรวมทั้งหน่วยงานเป็นกลุ่มเดียว (ไม่แยกตามกลุ่มงาน OT ของ P1a), นับเฉพาะเช็กอิน "สมบูรณ์" (incomplete_checkin = false)

-- ============================================================
-- 1. คอลัมน์ใหม่: check_in.daily_rank (1 หรือ 2 เท่านั้น, null ถ้าไม่ติดอันดับ)
-- ============================================================
alter table public.check_in
  add column if not exists daily_rank smallint check (daily_rank is null or daily_rank in (1,2));

-- ============================================================
-- 2. do_check_in_impl — คำนวณ daily_rank ตอนเช็กอิน (เฉพาะเช็กอินที่ "สมบูรณ์" เท่านั้นที่มีสิทธิ์ติดอันดับ)
-- ============================================================
create or replace function public.do_check_in_impl(p_officer_id uuid, p_pin text, p_photo_path text, p_lat double precision, p_lng double precision, p_note text, p_ready boolean)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare
  v_off officer%rowtype; v_set settings%rowtype; v_now timestamptz := now(); v_local time; v_today date;
  v_status text; v_dist integer; v_note text := trim(coalesce(p_note, '')); v_incomplete boolean := false;
  v_daily_rank smallint; v_today_complete_count integer;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  select * into v_set from settings where id = 1;
  v_local := (v_now at time zone v_set.tz)::time; v_today := (v_now at time zone v_set.tz)::date;
  if v_local < v_set.checkin_open_after then return json_build_object('ok', false, 'error', 'too_early', 'open_after', v_set.checkin_open_after); end if;
  if length(v_note) < 5 then return json_build_object('ok', false, 'error', 'note_too_short'); end if;
  if p_ready is null then return json_build_object('ok', false, 'error', 'ready_required'); end if;
  if v_local < v_set.green_before then v_status := 'green';
  elsif v_local < v_set.yellow_before then v_status := 'yellow';
  elsif v_local < v_set.orange_before then v_status := 'orange';
  else v_status := 'red'; end if;
  if p_lat is not null and p_lng is not null then
    v_dist := round(6371000 * 2 * asin(sqrt(power(sin(radians(p_lat - v_set.office_lat)/2), 2) + cos(radians(v_set.office_lat)) * cos(radians(p_lat)) * power(sin(radians(p_lng - v_set.office_lng)/2), 2))));
  end if;
  v_incomplete := (p_lat is null or p_lng is null) or (v_dist is not null and v_dist > 50);
  if not v_incomplete then
    select count(*) into v_today_complete_count from check_in where local_date = v_today and incomplete_checkin = false;
    if v_today_complete_count = 0 then v_daily_rank := 1;
    elsif v_today_complete_count = 1 then v_daily_rank := 2;
    else v_daily_rank := null; end if;
  else v_daily_rank := null; end if;
  insert into check_in(officer_id, checked_in_at, photo_path, lat, lng, distance_m, status, note, ready_for_duty, incomplete_checkin, daily_rank)
  values (p_officer_id, v_now, p_photo_path, p_lat, p_lng, v_dist, v_status, v_note, p_ready, v_incomplete, v_daily_rank);
  return json_build_object('ok', true, 'status', v_status, 'time', v_now, 'distance_m', v_dist, 'incomplete', v_incomplete, 'daily_rank', v_daily_rank);
exception when unique_violation then return json_build_object('ok', false, 'error', 'already_checked_in');
end; $function$;

-- ============================================================
-- 3. do_get_today_status_impl — คืน daily_rank เพิ่ม (ใช้ signature เดิม, CREATE OR REPLACE ตรงได้)
-- ============================================================
create or replace function public.do_get_today_status_impl(p_officer_id uuid, p_pin text)
 returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_off officer%rowtype; v_row check_in%rowtype; v_tz text;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  select tz into v_tz from settings where id = 1;
  select * into v_row from check_in where officer_id = p_officer_id and local_date = (now() at time zone v_tz)::date limit 1;
  if not found then return json_build_object('ok', false, 'error', 'not_checked_in'); end if;
  return json_build_object('ok', true, 'status', coalesce(v_row.override_status, v_row.status), 'time', v_row.checked_in_at,
    'distance_m', v_row.distance_m, 'ready_for_duty', v_row.ready_for_duty, 'note', v_row.note, 'incomplete', v_row.incomplete_checkin,
    'remark', v_row.remark, 'retention_hold', v_row.retention_hold, 'photo_deleted_at', v_row.photo_deleted_at, 'daily_rank', v_row.daily_rank);
end; $function$;

-- ============================================================
-- 4. do_supervisor_get_today_impl — คืน c.daily_rank ในตารางเช็กอินวันนี้ (signature เดิม, CREATE OR REPLACE ตรงได้)
-- ⚠️ พบว่ารอบก่อนหน้า (ก่อน compaction) ไม่ได้รันจริง — ตรวจพบระหว่าง E2E test รอบนี้ แก้แล้วในไฟล์นี้
-- ============================================================
create or replace function public.do_supervisor_get_today_impl(p_officer_id uuid, p_pin text)
 returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_off officer%rowtype; v_tz text; v_rows json;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  select tz into v_tz from settings where id = 1;
  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (
    select c.id, o.full_name, o.rank_title, o.nickname,
           c.checked_in_at, coalesce(c.override_status, c.status) as status,
           c.distance_m, c.ready_for_duty, c.note, c.remark, c.photo_path, c.incomplete_checkin,
           c.override_reason, c.override_at, ob.full_name as override_by_name,
           c.retention_hold, c.photo_deleted_at, c.daily_rank
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    where c.local_date = (now() at time zone v_tz)::date
    order by c.checked_in_at
  ) t;
  return json_build_object('ok', true, 'rows', v_rows);
end; $function$;

-- ============================================================
-- 5. do_get_my_month_stats_impl — เพิ่มยอดสะสมเหรียญทอง/เงินรายเดือน (signature เดิม, CREATE OR REPLACE ตรงได้)
-- ============================================================
create or replace function public.do_get_my_month_stats_impl(p_officer_id uuid, p_pin text)
 returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare
  v_off officer%rowtype; v_tz text; v_month_start date; v_month_end date; v_effective_start date;
  v_green int; v_yellow int; v_orange int; v_red int; v_incomplete int; v_total int; v_absent int;
  v_today date; v_cutoff time; v_absent_end date; v_gold int; v_silver int;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  select tz, absent_cutoff_time into v_tz, v_cutoff from settings where id = 1;
  v_month_start := date_trunc('month', (now() at time zone v_tz))::date;
  v_month_end := (v_month_start + interval '1 month')::date;
  v_today := (now() at time zone v_tz)::date;
  select start_date into v_effective_start from stats_period_override where year = extract(year from v_month_start)::smallint and month = extract(month from v_month_start)::smallint;
  if v_effective_start is null or v_effective_start < v_month_start or v_effective_start >= v_month_end then v_effective_start := v_month_start; end if;
  select count(*) filter (where coalesce(override_status, status) = 'green'),
         count(*) filter (where coalesce(override_status, status) = 'yellow'),
         count(*) filter (where coalesce(override_status, status) = 'orange'),
         count(*) filter (where coalesce(override_status, status) = 'red'),
         count(*) filter (where incomplete_checkin = true),
         count(*) filter (where daily_rank = 1),
         count(*) filter (where daily_rank = 2),
         count(*)
    into v_green, v_yellow, v_orange, v_red, v_incomplete, v_gold, v_silver, v_total
    from check_in where officer_id = p_officer_id and local_date >= v_effective_start and local_date < v_month_end;
  if (now() at time zone v_tz)::time >= v_cutoff then v_absent_end := v_today; else v_absent_end := v_today - 1; end if;
  v_absent_end := least(v_absent_end, (v_month_end - interval '1 day')::date);
  if v_absent_end >= v_effective_start then
    select count(*) into v_absent from generate_series(v_effective_start, v_absent_end, interval '1 day') d
    where extract(isodow from d) = any(v_off.work_days)
      and d::date not in (select holiday_date from public_holiday)
      and d::date not in (select local_date from check_in where officer_id = p_officer_id);
  else v_absent := 0; end if;
  return json_build_object('ok', true, 'green', coalesce(v_green,0), 'yellow', coalesce(v_yellow,0), 'orange', coalesce(v_orange,0),
    'red', coalesce(v_red,0), 'incomplete', coalesce(v_incomplete,0), 'absent', coalesce(v_absent,0), 'total', coalesce(v_total,0),
    'count_start_date', v_effective_start, 'gold_count', coalesce(v_gold,0), 'silver_count', coalesce(v_silver,0));
end; $function$;

-- ============================================================
-- Verify หลังรัน (ผลจริงจากรอบทดสอบ 15-16 ก.ค. 2569):
--   select proname, count(*) from pg_proc where proname in
--   ('do_check_in_impl','do_get_today_status_impl','do_supervisor_get_today_impl','do_get_my_month_stats_impl')
--   group by proname order by proname;
--   -> ทุกฟังก์ชัน count=1 (ไม่มี overload ซ้ำ, signature เดิมทุกตัว ไม่ต้อง DROP ก่อน)
-- ============================================================
