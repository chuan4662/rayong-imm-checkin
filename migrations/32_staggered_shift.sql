-- ============================================================================
-- Migration 32 — "เหลื่อมเวลา" ระดับกลุ่มงาน (Staggered Shift)
-- วันที่: 20 ส.ค. 2569
--
-- ที่มา: งานครอบครัว/งานธุรกิจ ต้องมีคนพร้อมรับผู้มาติดต่อก่อน 08:30 ("ชุดแรก")
--        ส่วนคนที่เหลือของกลุ่มเหลื่อมเวลาได้เล็กน้อย โดยไม่ถูกระบบตัดสินว่ามาสาย
--
-- กติกาที่เจ้าของยืนยันแล้ว (grill 2 รอบ 20 ส.ค. 2569):
--   1. เปิด/ปิดเป็นรายกลุ่ม (work_group.stagger_enabled) — deploy ครั้งแรกปิดหมด = ไม่มีอะไรเปลี่ยน
--   2. ไม่ต้องตั้งค่าว่าใครอยู่ชุดไหน — ระบบดูจากเวลาเช็กอินจริง
--   3. ปลดล็อกผ่อนผันเมื่อ "คนอื่น" ในกลุ่มเช็กอินทันก่อน core_open_before ครบ core_min_count คน
--   4. คนที่ได้ผ่อนผัน คิดสีด้วยเกณฑ์ +settings.stagger_minutes (default 30 นาที)
--   5. ห้ามเขียนสถานะทับเงียบๆ — เก็บ check_in.stagger_applied ไว้ให้ UI ติดป้าย "เหลื่อมเวลา"
--   6. badge การ์ด "แผนกงานการให้บริการ" (team_ok_before 08:20) ไม่เกี่ยวกัน ไม่แตะ
--
-- ⚠️ ทุกฟังก์ชันในไฟล์นี้เขียนจาก pg_get_functiondef ของจริงบน production (20 ส.ค. 2569)
--    ไม่ได้ลอกจากไฟล์ migration เก่า — ตามกติกา CLAUDE.md ข้อ 2.15
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Schema
-- ----------------------------------------------------------------------------
alter table public.work_group
  add column if not exists stagger_enabled  boolean  not null default false,
  add column if not exists core_open_before time     not null default '08:30',
  add column if not exists core_min_count   smallint not null default 1;

alter table public.settings
  add column if not exists stagger_minutes smallint not null default 30;

alter table public.check_in
  add column if not exists stagger_applied boolean not null default false;

comment on column public.work_group.stagger_enabled  is 'เปิดใช้ระบบเหลื่อมเวลาให้กลุ่มนี้หรือไม่ (หัวหน้าติ๊กเองใน dashboard)';
comment on column public.work_group.core_open_before is 'เส้นตายที่ชุดแรกต้องเช็กอินให้ทัน เพื่อเปิดเคาน์เตอร์ (default 08:30)';
comment on column public.work_group.core_min_count   is 'ต้องมีคนทันเส้นตายกี่คน ถึงจะปลดล็อกผ่อนผันให้คนที่เหลือ (default 1)';
comment on column public.settings.stagger_minutes    is 'จำนวนนาทีที่เลื่อนเกณฑ์สีให้คนชุดหลัง (default 30)';
comment on column public.check_in.stagger_applied    is 'true = แถวนี้ได้สีดีขึ้นเพราะระบบเหลื่อมเวลา (ใช้ติดป้ายและแยกสถิติ)';

-- ----------------------------------------------------------------------------
-- 2. do_check_in_impl — คำนวณสีโดยรองรับการเหลื่อมเวลา
--    signature เดิมเป๊ะ → create or replace ตรงได้ ไม่ต้อง DROP
--
--    ⚠️ จุดสำคัญของตรรกะ (กันบั๊ก "มาสายกว่าแล้วได้สีดีกว่า"):
--    - ไม่กั้นด้วยเงื่อนไข v_local >= core_open_before เพราะจะทำให้คนมา 08:25 ได้เหลือง
--      แต่คนมา 08:35 ได้เขียว (ยิ่งสายยิ่งดี) ซึ่งผิดเจตนา
--    - ใช้เงื่อนไขเดียวคือ "มีคนอื่นเช็กอินทันก่อนเส้นตายแล้วกี่คน" ซึ่ง monotonic
--      (พอครบแล้วครบตลอดวัน เพราะเวลาเดินหน้าอย่างเดียว) ⇒ คนแรกของกลุ่มคือชุดแรกเสมอ
--    - ตั้ง stagger_applied = true เฉพาะเมื่อการผ่อนผัน "เปลี่ยนสีจริง" เท่านั้น
--      คนที่มาเช้าอยู่แล้วจะไม่ถูกติดป้ายทั้งที่ไม่ได้ใช้สิทธิ์
-- ----------------------------------------------------------------------------
create or replace function public.do_check_in_impl(p_officer_id uuid, p_pin text, p_photo_path text, p_lat double precision, p_lng double precision, p_note text, p_ready boolean)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype; v_set settings%rowtype; v_now timestamptz := now(); v_local time; v_today date;
  v_status text; v_status_base text; v_dist integer; v_note text := trim(coalesce(p_note, ''));
  v_incomplete boolean := false; v_daily_rank smallint; v_today_complete_count integer;
  v_wg work_group%rowtype; v_wg_found boolean := false; v_cover integer; v_shift interval; v_stagger boolean := false;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  select * into v_set from settings where id = 1;
  v_local := (v_now at time zone v_set.tz)::time; v_today := (v_now at time zone v_set.tz)::date;
  if v_local < v_set.checkin_open_after then return json_build_object('ok', false, 'error', 'too_early', 'open_after', v_set.checkin_open_after); end if;
  if length(v_note) < 5 then return json_build_object('ok', false, 'error', 'note_too_short'); end if;
  if p_ready is null then return json_build_object('ok', false, 'error', 'ready_required'); end if;

  -- สีตามเกณฑ์ปกติ (ฐานอ้างอิง ใช้เทียบว่าการผ่อนผันเปลี่ยนผลจริงไหม)
  if    v_local < v_set.green_before  then v_status_base := 'green';
  elsif v_local < v_set.yellow_before then v_status_base := 'yellow';
  elsif v_local < v_set.orange_before then v_status_base := 'orange';
  else  v_status_base := 'red'; end if;
  v_status := v_status_base;

  -- ===== เหลื่อมเวลาระดับกลุ่มงาน =====
  if v_off.work_group_id is not null then
    select * into v_wg from work_group where id = v_off.work_group_id;
    v_wg_found := found;
    if v_wg_found and v_wg.stagger_enabled then
      -- นับ "คนอื่น" ในกลุ่มเดียวกันที่เช็กอินสมบูรณ์ทันก่อนเส้นตายเปิดเคาน์เตอร์ของวันนี้
      -- (incomplete_checkin = true คือเช็กอินไกลเกิน 50 ม. หรือไม่เปิด GPS ⇒ ไม่ถือว่ามาเปิดเคาน์เตอร์)
      select count(*) into v_cover
        from check_in c
        join officer o on o.id = c.officer_id
       where o.work_group_id = v_off.work_group_id
         and c.officer_id <> p_officer_id
         and c.local_date = v_today
         and c.incomplete_checkin = false
         and (c.checked_in_at at time zone v_set.tz)::time < v_wg.core_open_before;

      if coalesce(v_cover, 0) >= v_wg.core_min_count then
        v_shift := make_interval(mins => coalesce(v_set.stagger_minutes, 0)::int);
        if    v_local < v_set.green_before  + v_shift then v_status := 'green';
        elsif v_local < v_set.yellow_before + v_shift then v_status := 'yellow';
        elsif v_local < v_set.orange_before + v_shift then v_status := 'orange';
        else  v_status := 'red'; end if;
        v_stagger := (v_status is distinct from v_status_base);
      end if;
    end if;
  end if;

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

  insert into check_in(officer_id, checked_in_at, photo_path, lat, lng, distance_m, status, note, ready_for_duty, incomplete_checkin, daily_rank, stagger_applied)
  values (p_officer_id, v_now, p_photo_path, p_lat, p_lng, v_dist, v_status, v_note, p_ready, v_incomplete, v_daily_rank, v_stagger);

  return json_build_object('ok', true, 'status', v_status, 'time', v_now, 'distance_m', v_dist,
    'incomplete', v_incomplete, 'daily_rank', v_daily_rank,
    'stagger_applied', v_stagger, 'stagger_minutes', coalesce(v_set.stagger_minutes, 0),
    'work_group_name', case when v_stagger then v_wg.name else null end);
exception when unique_violation then return json_build_object('ok', false, 'error', 'already_checked_in');
end;
$function$;

-- ----------------------------------------------------------------------------
-- 3. RPC อ่านข้อมูล — คืน stagger_applied เพิ่ม (signature เดิมทุกตัว ไม่ต้อง DROP)
-- ----------------------------------------------------------------------------

-- 3.1 do_get_today_status_impl (index.html — ตอนกลับเข้าหน้าเดิมหลังเช็กอินแล้ว)
create or replace function public.do_get_today_status_impl(p_officer_id uuid, p_pin text)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_off officer%rowtype; v_row check_in%rowtype; v_tz text;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  select tz into v_tz from settings where id = 1;
  select * into v_row from check_in where officer_id = p_officer_id and local_date = (now() at time zone v_tz)::date limit 1;
  if not found then return json_build_object('ok', false, 'error', 'not_checked_in'); end if;
  return json_build_object('ok', true, 'status', coalesce(v_row.override_status, v_row.status), 'time', v_row.checked_in_at,
    'distance_m', v_row.distance_m, 'ready_for_duty', v_row.ready_for_duty, 'note', v_row.note,
    'incomplete', v_row.incomplete_checkin, 'remark', v_row.remark, 'retention_hold', v_row.retention_hold,
    'photo_deleted_at', v_row.photo_deleted_at, 'daily_rank', v_row.daily_rank,
    'stagger_applied', v_row.stagger_applied);
end;
$function$;

-- 3.2 do_supervisor_get_today_impl (report.html — ตารางเช็กอินวันนี้ ฝั่ง PIN)
create or replace function public.do_supervisor_get_today_impl(p_officer_id uuid, p_pin text)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
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
           c.retention_hold, c.photo_deleted_at, c.daily_rank, c.stagger_applied,
           co.checked_out_at, co.tier_label, co.tier_emoji
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    left join check_out co on co.officer_id = c.officer_id and co.local_date = c.local_date
    where c.local_date = (now() at time zone v_tz)::date
    order by c.checked_in_at
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

-- 3.3 do_get_history (dashboard.html — ประวัติย้อนหลัง ฝั่ง Auth)
create or replace function public.do_get_history(p_start_date date, p_end_date date, p_target_officer_id uuid default null::uuid)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
           c.retention_hold, c.photo_deleted_at, c.daily_rank, c.stagger_applied,
           co.checked_out_at, co.tier_label, co.tier_emoji
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    left join check_out co on co.officer_id = c.officer_id and co.local_date = c.local_date
    where c.local_date between p_start_date and p_end_date
      and (p_target_officer_id is null or c.officer_id = p_target_officer_id)
    order by c.local_date desc, c.checked_in_at desc
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

-- 3.4 do_supervisor_get_history_impl (report.html — ประวัติย้อนหลัง ฝั่ง PIN)
--     ⚠️ ปิดช่องว่างเดิมด้วย: ฟังก์ชันนี้ "ไม่เคยมี daily_rank" มาตั้งแต่ P1b (migration 30)
--        ทั้งที่ do_get_history ฝั่ง Auth มี — ยืนยันจาก pg_get_functiondef จริง 20 ส.ค. 2569
--        รอบนี้เพิ่มให้ทั้ง daily_rank และ stagger_applied เพราะแก้ไฟล์เดียวกันอยู่แล้ว
create or replace function public.do_supervisor_get_history_impl(p_officer_id uuid, p_pin text, p_start_date date, p_end_date date, p_target_officer_id uuid default null::uuid)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
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
           c.retention_hold, c.photo_deleted_at, c.daily_rank, c.stagger_applied,
           co.checked_out_at, co.tier_label, co.tier_emoji
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    left join check_out co on co.officer_id = c.officer_id and co.local_date = c.local_date
    where c.local_date between p_start_date and p_end_date
      and (p_target_officer_id is null or c.officer_id = p_target_officer_id)
    order by c.local_date desc, c.checked_in_at desc
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

-- 3.5 do_get_my_month_stats_impl — เพิ่ม stagger_count (บรรทัดย่อยใต้ยอดเขียว)
create or replace function public.do_get_my_month_stats_impl(p_officer_id uuid, p_pin text)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_off officer%rowtype; v_tz text; v_month_start date; v_month_end date; v_effective_start date;
  v_green int; v_yellow int; v_orange int; v_red int; v_incomplete int; v_total int; v_absent int;
  v_today date; v_cutoff time; v_absent_end date; v_gold int; v_silver int;
  v_checkout_json json; v_checkout_total int; v_stagger int;
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
         count(*) filter (where stagger_applied = true),
         count(*)
    into v_green, v_yellow, v_orange, v_red, v_incomplete, v_gold, v_silver, v_stagger, v_total
    from check_in where officer_id = p_officer_id and local_date >= v_effective_start and local_date < v_month_end;
  if (now() at time zone v_tz)::time >= v_cutoff then v_absent_end := v_today; else v_absent_end := v_today - 1; end if;
  v_absent_end := least(v_absent_end, (v_month_end - interval '1 day')::date);
  if v_absent_end >= v_effective_start then
    select count(*) into v_absent from generate_series(v_effective_start, v_absent_end, interval '1 day') d
    where extract(isodow from d) = any(v_off.work_days)
      and d::date not in (select holiday_date from public_holiday)
      and d::date not in (select local_date from check_in where officer_id = p_officer_id);
  else v_absent := 0; end if;
  select coalesce(json_agg(json_build_object('label', tier_label, 'emoji', tier_emoji, 'count', cnt) order by tier_order), '[]'::json)
    into v_checkout_json
    from (
      select tier_order, tier_label, tier_emoji, count(*) as cnt
      from check_out
      where officer_id = p_officer_id and local_date >= v_effective_start and local_date < v_month_end and tier_label is not null
      group by tier_order, tier_label, tier_emoji
    ) t;
  select count(*) into v_checkout_total from check_out where officer_id = p_officer_id and local_date >= v_effective_start and local_date < v_month_end;
  return json_build_object('ok', true, 'green', coalesce(v_green,0), 'yellow', coalesce(v_yellow,0), 'orange', coalesce(v_orange,0),
    'red', coalesce(v_red,0), 'incomplete', coalesce(v_incomplete,0), 'absent', coalesce(v_absent,0), 'total', coalesce(v_total,0),
    'count_start_date', v_effective_start, 'gold_count', coalesce(v_gold,0), 'silver_count', coalesce(v_silver,0),
    'checkout_tiers', coalesce(v_checkout_json,'[]'::json), 'checkout_total', coalesce(v_checkout_total,0),
    'stagger_count', coalesce(v_stagger,0));
end;
$function$;

-- ----------------------------------------------------------------------------
-- 4. RPC ตั้งค่า/จัดการกลุ่ม — เปลี่ยน parameter list / return columns
--    ⚠️ ต้อง DROP signature เดิมก่อนเสมอ ตามกติกา CLAUDE.md ข้อ 2.14 (กัน overload ซ้ำ)
--       และต้อง GRANT ใหม่ เพราะสิทธิ์ไม่สืบทอดมาให้อัตโนมัติ
-- ----------------------------------------------------------------------------

-- 4.1 do_admin_list_work_groups — RETURNS TABLE เปลี่ยน ⇒ DROP ก่อน
drop function if exists public.do_admin_list_work_groups();
create or replace function public.do_admin_list_work_groups()
 returns table(id uuid, name text, is_ot_team boolean, member_count bigint,
               stagger_enabled boolean, core_open_before time, core_min_count smallint)
 language sql
 security definer
 set search_path to 'public'
as $function$
  select wg.id, wg.name, wg.is_ot_team, count(o.id) as member_count,
         wg.stagger_enabled, wg.core_open_before, wg.core_min_count
  from work_group wg
  left join officer o on o.work_group_id = wg.id
  where exists (select 1 from officer s where s.id = auth.uid() and s.is_supervisor)
  group by wg.id, wg.name, wg.is_ot_team, wg.stagger_enabled, wg.core_open_before, wg.core_min_count
  order by wg.name;
$function$;
grant execute on function public.do_admin_list_work_groups() to authenticated;

-- 4.2 do_admin_update_work_group — เพิ่ม 3 พารามิเตอร์ (default null = ไม่แก้ค่านั้น) ⇒ DROP ก่อน
drop function if exists public.do_admin_update_work_group(uuid, text, boolean);
create or replace function public.do_admin_update_work_group(
  p_id uuid,
  p_name text,
  p_is_ot_team boolean,
  p_stagger_enabled boolean default null,
  p_core_open_before time without time zone default null,
  p_core_min_count smallint default null
)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then return json_build_object('ok', false, 'error', 'not_supervisor'); end if;
  if p_name is null or length(trim(p_name)) = 0 then return json_build_object('ok', false, 'error', 'name_required'); end if;
  if p_core_min_count is not null and p_core_min_count < 1 then return json_build_object('ok', false, 'error', 'invalid_core_min_count'); end if;
  update work_group set
    name             = trim(p_name),
    is_ot_team       = coalesce(p_is_ot_team, false),
    stagger_enabled  = coalesce(p_stagger_enabled, stagger_enabled),
    core_open_before = coalesce(p_core_open_before, core_open_before),
    core_min_count   = coalesce(p_core_min_count, core_min_count)
  where id = p_id;
  if not found then return json_build_object('ok', false, 'error', 'group_not_found'); end if;
  return json_build_object('ok', true);
exception when unique_violation then return json_build_object('ok', false, 'error', 'duplicate_name');
end;
$function$;
grant execute on function public.do_admin_update_work_group(uuid, text, boolean, boolean, time without time zone, smallint) to authenticated;

-- 4.3 do_get_settings — คืน stagger_minutes เพิ่ม (signature เดิม ไม่ต้อง DROP)
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
  return json_build_object('ok', true, 'office_lat', v_set.office_lat, 'office_lng', v_set.office_lng,
    'green_before', v_set.green_before, 'yellow_before', v_set.yellow_before, 'orange_before', v_set.orange_before,
    'absent_cutoff_time', v_set.absent_cutoff_time, 'team_ok_before', v_set.team_ok_before,
    'team_warn_before', v_set.team_warn_before, 'checkin_open_after', v_set.checkin_open_after,
    'stagger_minutes', v_set.stagger_minutes);
end;
$function$;

-- 4.4 do_set_settings — เพิ่ม p_stagger_minutes เป็นพารามิเตอร์ที่ 10 ⇒ DROP signature 9 ตัวเดิมก่อน
drop function if exists public.do_set_settings(double precision, double precision, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone);
create or replace function public.do_set_settings(
  p_office_lat double precision,
  p_office_lng double precision,
  p_green_before time without time zone,
  p_yellow_before time without time zone,
  p_orange_before time without time zone,
  p_absent_cutoff_time time without time zone,
  p_team_ok_before time without time zone default null,
  p_team_warn_before time without time zone default null,
  p_checkin_open_after time without time zone default null,
  p_stagger_minutes smallint default null
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
  if p_stagger_minutes is not null and (p_stagger_minutes < 0 or p_stagger_minutes > 120) then
    return json_build_object('ok', false, 'error', 'invalid_stagger_minutes');
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
    checkin_open_after = coalesce(p_checkin_open_after, checkin_open_after),
    stagger_minutes = coalesce(p_stagger_minutes, stagger_minutes)
  where id = 1;
  return json_build_object('ok', true);
end;
$function$;
grant execute on function public.do_set_settings(double precision, double precision, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone, smallint) to authenticated;

-- ============================================================================
-- Verify หลังรัน (ต้องได้ตามนี้ทุกข้อ)
--
--   select proname, count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   where n.nspname='public' and proname in
--     ('do_check_in_impl','do_get_today_status_impl','do_supervisor_get_today_impl',
--      'do_get_my_month_stats_impl','do_get_history','do_supervisor_get_history_impl',
--      'do_get_settings','do_set_settings','do_admin_list_work_groups','do_admin_update_work_group')
--   group by proname;
--   -> ต้องได้ count = 1 ทุกแถว (ไม่มี overload ซ้ำ)
--
--   select name, stagger_enabled, core_open_before, core_min_count from work_group order by name;
--   -> ต้องเป็น false / 08:30:00 / 1 ทั้ง 6 กลุ่ม (ไม่มีอะไรเปลี่ยนพฤติกรรมทันทีหลัง deploy)
--
--   select stagger_minutes from settings where id = 1;   -> 30
--   select count(*) from check_in where stagger_applied;  -> 0
-- ============================================================================
