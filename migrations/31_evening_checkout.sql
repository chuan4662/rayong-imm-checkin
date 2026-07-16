-- migration 31: P1.4 เช็คเอาต์ตอนเย็น (ไม่บังคับ, ให้รางวัลอย่างเดียว)
-- รันจริงบน Supabase SQL Editor แล้ว 16 ก.ค. 2569, verify ผ่าน E2E ครบทุกเคส (ดู CLAUDE.md ข้อ 33)
-- ⚠️ ดีไซน์เบี่ยงจาก 90_ROADMAP_v2_PLAN.md เดิม 2 จุด ตามที่เจ้าของตัดสินใจในเซสชันนี้:
--   (1) ล็อกเช็คเอาต์ได้ครั้งเดียวเด็ดขาดต่อวัน (ไม่ใช่ "กดซ้ำได้ ครั้งล่าสุดชนะ" แบบ roadmap เดิม) — unique constraint, ไม่มี upsert
--   (2) เกณฑ์เวลา tier (18:00/20:00) เขียนตายตัวในตาราง ไม่มี UI แก้ไข (ต่างจาก roadmap ที่เสนอ do_get/set_checkout_tiers)
-- ขอบเขต: ต้องเช็กอินเช้าของวันนั้นก่อนถึงจะเช็คเอาต์ได้ (hard block), GPS ไม่บล็อกการเช็คเอาต์ (เก็บ distance_m เงียบๆ), หมายเหตุไม่บังคับ+ไม่มีขั้นต่ำตัวอักษร

-- ============================================================
-- 1. ตารางใหม่: check_out (เช็คเอาต์ต่อคนต่อวัน, unique — ล็อกครั้งเดียว)
-- ============================================================
create table public.check_out (
  id              uuid primary key default gen_random_uuid(),
  officer_id      uuid not null references public.officer(id),
  checked_out_at  timestamptz not null default now(),
  local_date      date generated always as ((checked_out_at at time zone 'Asia/Bangkok')::date) stored,
  photo_path      text not null,
  lat             double precision,
  lng             double precision,
  distance_m      integer,
  note            text,
  tier_order      smallint,
  tier_label      text,
  tier_emoji      text,
  created_at      timestamptz not null default now(),
  unique (officer_id, local_date)
);
create index on public.check_out (local_date);
create index on public.check_out (officer_id, local_date);
alter table public.check_out enable row level security;
create policy checkout_read_supervisor on public.check_out for select to authenticated using (public.is_supervisor());

-- ============================================================
-- 2. ตารางใหม่: checkout_recognition_tier (เกณฑ์เวลา "อยู่เย็น/อยู่ดึก" — เขียนตายตัวรอบนี้ ไม่มี UI แก้)
-- ============================================================
create table public.checkout_recognition_tier (
  id              uuid primary key default gen_random_uuid(),
  tier_order      smallint not null unique,
  threshold_time  time not null unique,
  label           text not null,
  emoji           text not null default '🌙',
  active          boolean not null default true
);
alter table public.checkout_recognition_tier enable row level security;
insert into public.checkout_recognition_tier (tier_order, threshold_time, label, emoji) values
  (1, '18:00', 'อยู่เย็น', '🌙'),
  (2, '20:00', 'อยู่ดึก', '🌙🌙');

-- ============================================================
-- 3. do_check_out_impl + do_check_out (thin wrapper ตามแพทเทิร์น PIN rate limiting เดิม, migration 25)
--    hard block: ต้องมี check_in ของวันนี้ก่อน (error not_checked_in_yet)
--    ล็อกครั้งเดียว: unique constraint → error already_checked_out (ไม่มี upsert)
-- ============================================================
create or replace function public.do_check_out_impl(p_officer_id uuid, p_pin text, p_photo_path text, p_lat double precision, p_lng double precision, p_note text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare
  v_off officer%rowtype; v_set settings%rowtype; v_now timestamptz := now(); v_local time; v_today date;
  v_dist integer; v_note text := trim(coalesce(p_note, ''));
  v_tier record;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  select * into v_set from settings where id = 1;
  v_local := (v_now at time zone v_set.tz)::time;
  v_today := (v_now at time zone v_set.tz)::date;
  if not exists (select 1 from check_in where officer_id = p_officer_id and local_date = v_today) then
    return json_build_object('ok', false, 'error', 'not_checked_in_yet');
  end if;
  if exists (select 1 from check_out where officer_id = p_officer_id and local_date = v_today) then
    return json_build_object('ok', false, 'error', 'already_checked_out');
  end if;
  if p_lat is not null and p_lng is not null then
    v_dist := round(6371000 * 2 * asin(sqrt(power(sin(radians(p_lat - v_set.office_lat)/2), 2) + cos(radians(v_set.office_lat)) * cos(radians(p_lat)) * power(sin(radians(p_lng - v_set.office_lng)/2), 2))));
  end if;
  select tier_order, label, emoji into v_tier
    from checkout_recognition_tier
    where active = true and threshold_time <= v_local
    order by tier_order desc limit 1;
  insert into check_out(officer_id, checked_out_at, photo_path, lat, lng, distance_m, note, tier_order, tier_label, tier_emoji)
  values (p_officer_id, v_now, p_photo_path, p_lat, p_lng, v_dist, v_note, v_tier.tier_order, v_tier.label, v_tier.emoji);
  return json_build_object('ok', true, 'time', v_now, 'distance_m', v_dist, 'tier_order', v_tier.tier_order, 'tier_label', v_tier.label, 'tier_emoji', v_tier.emoji);
exception when unique_violation then return json_build_object('ok', false, 'error', 'already_checked_out');
end; $function$;
revoke all on function public.do_check_out_impl(uuid, text, text, double precision, double precision, text) from public, anon, authenticated;

create or replace function public.do_check_out(p_officer_id uuid, p_pin text, p_photo_path text, p_lat double precision, p_lng double precision, p_note text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $wrap$
declare v_check record;
begin
  select * into v_check from check_and_count_pin(p_officer_id, p_pin);
  if not v_check.ok then return json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); end if;
  return do_check_out_impl(p_officer_id, p_pin, p_photo_path, p_lat, p_lng, p_note);
end; $wrap$;
grant execute on function public.do_check_out(uuid, text, text, double precision, double precision, text) to anon;

-- ============================================================
-- 4. do_get_my_checkout_today_impl + do_get_my_checkout_today (สถานะเช็คเอาต์วันนี้ ให้ index.html เช็กก่อนเปิดกล้อง)
-- ============================================================
create or replace function public.do_get_my_checkout_today_impl(p_officer_id uuid, p_pin text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_off officer%rowtype; v_tz text; v_row check_out%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  select tz into v_tz from settings where id = 1;
  select * into v_row from check_out where officer_id = p_officer_id and local_date = (now() at time zone v_tz)::date limit 1;
  if not found then return json_build_object('ok', true, 'checked_out', false); end if;
  return json_build_object('ok', true, 'checked_out', true, 'time', v_row.checked_out_at, 'tier_order', v_row.tier_order, 'tier_label', v_row.tier_label, 'tier_emoji', v_row.tier_emoji);
end; $function$;
revoke all on function public.do_get_my_checkout_today_impl(uuid, text) from public, anon, authenticated;

create or replace function public.do_get_my_checkout_today(p_officer_id uuid, p_pin text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $wrap$
declare v_check record;
begin
  select * into v_check from check_and_count_pin(p_officer_id, p_pin);
  if not v_check.ok then return json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); end if;
  return do_get_my_checkout_today_impl(p_officer_id, p_pin);
end; $wrap$;
grant execute on function public.do_get_my_checkout_today(uuid, text) to anon;

-- ============================================================
-- 5. do_get_my_month_stats_impl — เพิ่ม checkout_tiers (นับต่อ tier) + checkout_total (signature เดิม, CREATE OR REPLACE ตรงได้)
-- ============================================================
create or replace function public.do_get_my_month_stats_impl(p_officer_id uuid, p_pin text)
 returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare
  v_off officer%rowtype; v_tz text; v_month_start date; v_month_end date; v_effective_start date;
  v_green int; v_yellow int; v_orange int; v_red int; v_incomplete int; v_total int; v_absent int;
  v_today date; v_cutoff time; v_absent_end date; v_gold int; v_silver int;
  v_checkout_json json; v_checkout_total int;
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
    'checkout_tiers', coalesce(v_checkout_json,'[]'::json), 'checkout_total', coalesce(v_checkout_total,0));
end; $function$;

-- ============================================================
-- 6. do_supervisor_get_today_impl — LEFT JOIN check_out เพิ่ม checked_out_at/tier_label/tier_emoji (signature เดิม, CREATE OR REPLACE ตรงได้)
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
           c.retention_hold, c.photo_deleted_at, c.daily_rank,
           co.checked_out_at, co.tier_label, co.tier_emoji
    from check_in c
    join officer o on o.id = c.officer_id
    left join officer ob on ob.id = c.override_by
    left join check_out co on co.officer_id = c.officer_id and co.local_date = c.local_date
    where c.local_date = (now() at time zone v_tz)::date
    order by c.checked_in_at
  ) t;
  return json_build_object('ok', true, 'rows', v_rows);
end; $function$;

-- ============================================================
-- 7. do_supervisor_get_history_impl — LEFT JOIN check_out เพิ่ม checked_out_at/tier_label/tier_emoji (signature เดิม, CREATE OR REPLACE ตรงได้)
--    ⚠️ หมายเหตุ: ฟังก์ชันนี้ไม่มี daily_rank (ช่องว่างเดิมจาก P1b ที่ไม่เคยเพิ่ม ไม่ได้แก้ในรอบนี้ เพราะนอกขอบเขตงาน P1.4)
-- ============================================================
create or replace function public.do_supervisor_get_history_impl(p_officer_id uuid, p_pin text, p_start_date date, p_end_date date, p_target_officer_id uuid DEFAULT NULL::uuid)
 returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_off officer%rowtype; v_rows json;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
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
           c.retention_hold, c.photo_deleted_at,
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
end; $function$;

-- ============================================================
-- 8. do_get_history — LEFT JOIN check_out เพิ่ม checked_out_at/tier_label/tier_emoji + daily_rank (signature เดิม, CREATE OR REPLACE ตรงได้)
--    ⚠️ พบระหว่างทำ P1.4 รอบนี้ว่าเวอร์ชัน auth-only นี้ (ใช้โดย dashboard.html ตารางประวัติ) ไม่มี daily_rank เลยตั้งแต่ P1b
--    (คนละฟังก์ชันกับ do_supervisor_get_history_impl ที่เป็น PIN wrapper) แก้เพิ่มให้พร้อมกันในรอบนี้เพราะอยู่ในไฟล์เดียวกันอยู่แล้ว
-- ============================================================
create or replace function public.do_get_history(p_start_date date, p_end_date date, p_target_officer_id uuid DEFAULT NULL::uuid)
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
           c.retention_hold, c.photo_deleted_at, c.daily_rank,
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

-- ============================================================
-- Verify หลังรัน (ผลจริงจากรอบทดสอบ 16 ก.ค. 2569):
--   select proname, count(*) from pg_proc where proname in
--   ('do_check_out','do_check_out_impl','do_get_my_checkout_today','do_get_my_checkout_today_impl',
--    'do_get_my_month_stats_impl','do_supervisor_get_today_impl','do_supervisor_get_history_impl','do_get_history')
--   group by proname order by proname;
--   -> ทุกฟังก์ชัน count=1 (ไม่มี overload ซ้ำ)
--   check_out: 13 คอลัมน์, 1 RLS policy (checkout_read_supervisor)
--   checkout_recognition_tier: 2 แถว seed (18:00 อยู่เย็น, 20:00 อยู่ดึก)
--   anon มีสิทธิ์ execute do_check_out/do_get_my_checkout_today แต่ไม่มีสิทธิ์ *_impl
-- ============================================================
