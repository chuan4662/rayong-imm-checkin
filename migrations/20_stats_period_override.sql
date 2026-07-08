-- Migration 20: stats_period_override (กำหนดวันเริ่มนับสถิติรายเดือนได้) + สีน้ำตาลเข้ม "ขาดเช็กอิน" ในสถิติส่วนตัวรายเดือน
-- บริบท: 3 ก.ค. 2569 เริ่มเปิดให้เช็กอินจริงแต่เป็นการทดสอบระบบ เจ้าของอยากตัดวันทดสอบออกจากสถิติ
-- โดยตั้งวันเริ่มนับของเดือน ก.ค. 2569 เป็น 6 ก.ค. 2569 (ตัวอย่าง) ได้เอง จากหลังบ้าน

-- ============================================================
-- CHUNK 1: ตาราง stats_period_override
-- ============================================================
create table if not exists public.stats_period_override (
  year smallint not null,
  month smallint not null check (month between 1 and 12),
  start_date date not null,
  primary key (year, month)
);
-- ไม่มี RLS policy เพราะเข้าถึงผ่าน RPC เท่านั้น (ตามแพทเทิร์นเดียวกับ public_holiday)

-- ============================================================
-- CHUNK 2: แก้ do_get_my_month_stats ให้รองรับ effective start date + นับ absent
-- (ไม่ต้อง DROP เพราะ RETURNS json เหมือนเดิม, args เหมือนเดิม)
-- ============================================================
CREATE OR REPLACE FUNCTION public.do_get_my_month_stats(p_officer_id uuid, p_pin text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_off officer%rowtype;
  v_tz text;
  v_month_start date;
  v_month_end date;
  v_effective_start date;
  v_green int;
  v_yellow int;
  v_orange int;
  v_red int;
  v_incomplete int;
  v_total int;
  v_absent int;
  v_today date;
  v_cutoff time;
  v_absent_end date;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select tz, absent_cutoff_time into v_tz, v_cutoff from settings where id = 1;
  v_month_start := date_trunc('month', (now() at time zone v_tz))::date;
  v_month_end := (v_month_start + interval '1 month')::date;
  v_today := (now() at time zone v_tz)::date;

  -- หา override วันเริ่มนับของเดือนนี้ (ถ้ามี และอยู่ในช่วงเดือนนี้จริง)
  select start_date into v_effective_start
  from stats_period_override
  where year = extract(year from v_month_start)::smallint
    and month = extract(month from v_month_start)::smallint;

  if v_effective_start is null or v_effective_start < v_month_start or v_effective_start >= v_month_end then
    v_effective_start := v_month_start;
  end if;

  select
    count(*) filter (where coalesce(override_status, status) = 'green'),
    count(*) filter (where coalesce(override_status, status) = 'yellow'),
    count(*) filter (where coalesce(override_status, status) = 'orange'),
    count(*) filter (where coalesce(override_status, status) = 'red'),
    count(*) filter (where incomplete_checkin = true),
    count(*)
  into v_green, v_yellow, v_orange, v_red, v_incomplete, v_total
  from check_in
  where officer_id = p_officer_id
    and local_date >= v_effective_start
    and local_date < v_month_end;

  -- นับ "ขาดเช็กอิน" ย้อนหลังตาม work_days/วันหยุด/checkin เหมือน do_get_absentees แต่ทำเป็นช่วงทั้งเดือน
  -- วันนี้จะนับก็ต่อเมื่อผ่าน absent_cutoff_time แล้วเท่านั้น (กันฟันธงเร็วเกินไป เหมือน do_get_absentees)
  if (now() at time zone v_tz)::time >= v_cutoff then
    v_absent_end := v_today;
  else
    v_absent_end := v_today - 1;
  end if;
  v_absent_end := least(v_absent_end, (v_month_end - interval '1 day')::date);

  if v_absent_end >= v_effective_start then
    select count(*) into v_absent
    from generate_series(v_effective_start, v_absent_end, interval '1 day') d
    where extract(isodow from d) = any(v_off.work_days)
      and d::date not in (select holiday_date from public_holiday)
      and d::date not in (select local_date from check_in where officer_id = p_officer_id);
  else
    v_absent := 0;
  end if;

  return json_build_object(
    'ok', true,
    'green', coalesce(v_green,0),
    'yellow', coalesce(v_yellow,0),
    'orange', coalesce(v_orange,0),
    'red', coalesce(v_red,0),
    'incomplete', coalesce(v_incomplete,0),
    'absent', coalesce(v_absent,0),
    'total', coalesce(v_total,0),
    'count_start_date', v_effective_start
  );
end;
$function$;

-- ============================================================
-- CHUNK 3: RPC จัดการ stats_period_override — auth (dashboard.html / ชวนชัย)
-- ============================================================
CREATE OR REPLACE FUNCTION public.do_list_stats_period_overrides()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_is_sup boolean;
  v_rows json;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (select year, month, start_date from stats_period_override order by year desc, month desc) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

CREATE OR REPLACE FUNCTION public.do_set_stats_period_override(p_year smallint, p_month smallint, p_start_date date)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  if p_month is null or p_month < 1 or p_month > 12 then
    return json_build_object('ok', false, 'error', 'invalid_month');
  end if;
  if p_start_date is null or extract(year from p_start_date)::smallint <> p_year or extract(month from p_start_date)::smallint <> p_month then
    return json_build_object('ok', false, 'error', 'date_not_in_month');
  end if;

  insert into stats_period_override(year, month, start_date) values (p_year, p_month, p_start_date)
  on conflict (year, month) do update set start_date = excluded.start_date;

  return json_build_object('ok', true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.do_delete_stats_period_override(p_year smallint, p_month smallint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  delete from stats_period_override where year = p_year and month = p_month;
  if not found then
    return json_build_object('ok', false, 'error', 'not_found');
  end if;
  return json_build_object('ok', true);
end;
$function$;

-- ============================================================
-- CHUNK 4: RPC จัดการ stats_period_override — PIN (report.html / ศุภัตรา, ผู้ช่วยแอดมิน)
-- ============================================================
CREATE OR REPLACE FUNCTION public.do_supervisor_list_stats_period_overrides(p_officer_id uuid, p_pin text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  from (select year, month, start_date from stats_period_override order by year desc, month desc) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

CREATE OR REPLACE FUNCTION public.do_supervisor_set_stats_period_override(p_officer_id uuid, p_pin text, p_year smallint, p_month smallint, p_start_date date)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  if p_month is null or p_month < 1 or p_month > 12 then
    return json_build_object('ok', false, 'error', 'invalid_month');
  end if;
  if p_start_date is null or extract(year from p_start_date)::smallint <> p_year or extract(month from p_start_date)::smallint <> p_month then
    return json_build_object('ok', false, 'error', 'date_not_in_month');
  end if;

  insert into stats_period_override(year, month, start_date) values (p_year, p_month, p_start_date)
  on conflict (year, month) do update set start_date = excluded.start_date;

  return json_build_object('ok', true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.do_supervisor_delete_stats_period_override(p_officer_id uuid, p_pin text, p_year smallint, p_month smallint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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

  delete from stats_period_override where year = p_year and month = p_month;
  if not found then
    return json_build_object('ok', false, 'error', 'not_found');
  end if;
  return json_build_object('ok', true);
end;
$function$;
