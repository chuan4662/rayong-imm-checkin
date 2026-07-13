-- ============================================================================
-- Migration 27: P1a — work_group + badge ทีม OT (backend)
-- รันจริงบน Supabase SQL Editor แล้ว 13 ก.ค. 2569 (ทีละก้อนตามลำดับด้านล่าง)
-- อ้างอิงดีไซน์: 90_ROADMAP_v2_PLAN.md ข้อ P1.1
-- รายละเอียดเต็ม + บั๊กที่เจอ (do_set_settings overload) ดู CLAUDE.md ข้อ 30
-- ⚠️ ไม่ pre-seed กลุ่มงาน — ชวนชัยจัดการเองผ่าน UI (P1.2, ยังไม่เขียน)
-- ============================================================================

-- 1) ตาราง work_group + คอลัมน์ใหม่ ---------------------------------------
create table public.work_group (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  is_ot_team  boolean not null default false,
  created_at  timestamptz not null default now()
);

alter table public.work_group enable row level security;
-- ไม่เปิด policy อ่านตรงให้ anon — เข้าถึงผ่าน RPC (SECURITY DEFINER) เท่านั้น
-- ตามแพทเทิร์นเดิมของโปรเจกต์ (officer/settings ก็เข้าถึงผ่าน RPC เป็นหลัก)

alter table public.officer add column work_group_id uuid references public.work_group(id);

alter table public.settings add column team_ok_before   time not null default '08:20';
alter table public.settings add column team_warn_before time not null default '09:00';


-- 2) ฟังก์ชันกลางคำนวณ coverage (ไม่มี auth check ในตัว — revoke ทุกสิทธิ์) --
create or replace function public.do_team_coverage_json()
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ok_before time;
  v_warn_before time;
  v_today date := (now() at time zone 'Asia/Bangkok')::date;
  v_now_time time := (now() at time zone 'Asia/Bangkok')::time;
  v_groups json;
begin
  select team_ok_before, team_warn_before into v_ok_before, v_warn_before from settings where id = 1;

  select coalesce(json_agg(row_to_json(g)), '[]'::json) into v_groups
  from (
    select
      wg.id as group_id,
      wg.name as group_name,
      min(ci.checked_in_at) as first_checkin_at,
      coalesce(array_agg(o.full_name order by o.full_name) filter (where o.id is not null), '{}') as member_names,
      case
        when min(ci.checked_in_at) is null and v_now_time > v_warn_before then 'none'
        when min(ci.checked_in_at) is null then 'pending' -- ยังไม่มีใครเช็กอิน แต่ยังไม่เลย team_warn_before (สถานะเพิ่มเอง ไม่ใช่ 1 ใน 3 ค่าที่ยืนยันไว้)
        when (min(ci.checked_in_at) at time zone 'Asia/Bangkok')::time < v_ok_before then 'ok'
        else 'warn'
      end as badge
    from work_group wg
    left join officer o on o.work_group_id = wg.id
    left join check_in ci on ci.officer_id = o.id and ci.local_date = v_today
    where wg.is_ot_team = true
    group by wg.id, wg.name
    order by wg.name
  ) g;

  return json_build_object('ok', true, 'groups', v_groups, 'team_ok_before', v_ok_before, 'team_warn_before', v_warn_before);
end;
$function$;

revoke all on function public.do_team_coverage_json() from public, anon, authenticated;


-- 3) RPC สาธารณะ: auth (ชวนชัย) + PIN (ศุภัตรา/ผู้ช่วยแอดมิน) --------------
create or replace function public.do_get_team_coverage()
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
  return public.do_team_coverage_json();
end;
$function$;

grant execute on function public.do_get_team_coverage() to authenticated;

create or replace function public.do_supervisor_get_team_coverage(p_officer_id uuid, p_pin text)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_check record;
begin
  select * into v_check from check_and_count_pin(p_officer_id, p_pin);
  if not v_check.ok then
    return json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until);
  end if;
  return public.do_team_coverage_json();
end;
$function$;

grant execute on function public.do_supervisor_get_team_coverage(uuid, text) to anon, authenticated;


-- 4) แก้ RPC เดิมให้คืน work_group_id + ชื่อกลุ่มเพิ่ม -----------------------

-- 4a) do_list_officers_admin — ต้อง DROP ก่อน (เปลี่ยน RETURNS TABLE columns, บั๊กคลาสสิก 6.1)
drop function if exists public.do_list_officers_admin();
create or replace function public.do_list_officers_admin()
returns table(id uuid, full_name text, rank_title text, nickname text, is_supervisor boolean, active boolean, login_method text, needs_pin_setup boolean, work_days smallint[], supervisor_enabled boolean, work_group_id uuid, work_group_name text)
language sql
security definer
set search_path to 'public'
as $function$
  select o.id, o.full_name, o.rank_title, o.nickname, o.is_supervisor, o.active, o.login_method, (o.pin_hash is null) as needs_pin_setup, o.work_days, o.supervisor_enabled, o.work_group_id, wg.name as work_group_name
  from officer o
  left join work_group wg on wg.id = o.work_group_id
  where exists (select 1 from officer s where s.id = auth.uid() and s.is_supervisor)
  order by o.sort_order, o.full_name;
$function$;

grant execute on function public.do_list_officers_admin() to authenticated;

-- 4b) do_supervisor_list_officers_impl — RETURNS json, CREATE OR REPLACE ตรงๆ ได้ (ไม่ต้อง DROP)
create or replace function public.do_supervisor_list_officers_impl(p_officer_id uuid, p_pin text)
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
    select o.id, o.full_name, o.rank_title, o.nickname, o.active, o.is_supervisor, o.login_method,
      (o.pin_hash is null) as needs_pin_setup, o.work_days, o.work_group_id, wg.name as work_group_name
    from officer o
    left join work_group wg on wg.id = o.work_group_id
    order by o.sort_order nulls last, o.full_name
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

-- 4c) do_get_settings — RETURNS json, เพิ่ม team_ok_before/team_warn_before
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
  return json_build_object('ok', true, 'office_lat', v_set.office_lat, 'office_lng', v_set.office_lng, 'green_before', v_set.green_before, 'yellow_before', v_set.yellow_before, 'orange_before', v_set.orange_before, 'absent_cutoff_time', v_set.absent_cutoff_time, 'team_ok_before', v_set.team_ok_before, 'team_warn_before', v_set.team_warn_before);
end;
$function$;

-- 4d) do_set_settings — ⚠️ ต้อง DROP signature เดิมก่อนเสมอ เพราะเพิ่มพารามิเตอร์
--     (CREATE OR REPLACE เฉยๆ จะสร้าง overload ใหม่แยกต่างหาก ไม่ใช่แทนที่ —
--      เจอบั๊กนี้จริงตอนรัน ดู CLAUDE.md ข้อ 30.2 / กติกาข้อ 2.14)
drop function if exists public.do_set_settings(double precision, double precision, time without time zone, time without time zone, time without time zone, time without time zone);

create or replace function public.do_set_settings(
  p_office_lat double precision,
  p_office_lng double precision,
  p_green_before time without time zone,
  p_yellow_before time without time zone,
  p_orange_before time without time zone,
  p_absent_cutoff_time time without time zone,
  p_team_ok_before time without time zone default null,
  p_team_warn_before time without time zone default null
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
  update settings set
    office_lat = p_office_lat,
    office_lng = p_office_lng,
    green_before = p_green_before,
    yellow_before = p_yellow_before,
    orange_before = p_orange_before,
    absent_cutoff_time = p_absent_cutoff_time,
    team_ok_before = coalesce(p_team_ok_before, team_ok_before),
    team_warn_before = coalesce(p_team_warn_before, team_warn_before)
  where id = 1;
  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_set_settings(double precision, double precision, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone, time without time zone) to authenticated;


-- ============================================================================
-- Verify ที่ทำจริงหลังรัน (ดูผลเต็มใน CLAUDE.md ข้อ 30.3):
--   select proname, count(*) from pg_proc where proname in (
--     'do_set_settings','do_get_settings','do_list_officers_admin',
--     'do_supervisor_list_officers_impl','do_supervisor_list_officers',
--     'do_team_coverage_json','do_get_team_coverage','do_supervisor_get_team_coverage'
--   ) group by proname order by 2 desc;
--   -- ต้องได้ count=1 ทุกแถว (ยืนยันแล้วหลังแก้บั๊ก overload)
--
--   select team_ok_before, team_warn_before,
--     (select count(*) from work_group) as wg_count,
--     (select count(*) from officer where work_group_id is not null) as officers_with_group
--   from settings where id = 1;
--   -- ต้องได้ 08:20:00 / 09:00:00 / 0 / 0 (ยืนยันแล้ว)
-- ============================================================================
