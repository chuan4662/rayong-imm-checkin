-- ============================================================
-- เฟส A — Backend รากฐาน (2/2): RPC functions
-- รันไฟล์นี้หลังจาก 01_phase_a_schema.sql สำเร็จแล้วเท่านั้น
-- ============================================================

-- ============================================================
-- 1. do_list_officers() — anon เรียกได้ คืนเฉพาะข้อมูลที่ปลอดภัย (ไม่มี pin_hash)
-- ============================================================
create or replace function public.do_list_officers()
returns table (id uuid, full_name text, rank_title text)
language sql
security definer
set search_path = public
as $$
  select id, full_name, rank_title
  from officer
  where active = true
  order by full_name;
$$;

grant execute on function public.do_list_officers to anon;

-- ============================================================
-- 2. do_check_in() — ด่านเดียวที่ anon เขียนข้อมูลได้
--    verify PIN -> server time -> คำนวณ status (Bangkok) -> haversine distance -> insert
-- ============================================================
create or replace function public.do_check_in(
  p_officer_id uuid,
  p_pin        text,
  p_photo_path text,
  p_lat        double precision,
  p_lng        double precision,
  p_note       text
) returns json
language plpgsql
security definer
set search_path = public, extensions   -- extensions: crypt()/gen_salt() อยู่ schema นี้บน Supabase ไม่ใช่ public
as $$
declare
  v_set     settings%rowtype;
  v_off     officer%rowtype;
  v_now     timestamptz := now();          -- server time = แหล่งความจริง ห้ามรับเวลาจาก client
  v_local   time;
  v_status  text;
  v_dist    integer;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;

  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select * into v_set from settings where id = 1;

  -- แปลงเป็นเวลา Bangkok ก่อนเทียบเกณฑ์ (ห้ามลืม — จุดที่พลาดบ่อยที่สุด)
  v_local := (v_now at time zone v_set.tz)::time;
  if    v_local < v_set.green_before  then v_status := 'green';
  elsif v_local < v_set.yellow_before then v_status := 'yellow';
  else                                     v_status := 'red';
  end if;

  -- ระยะห่างจากที่ทำงาน (haversine, เมตร) — บันทึกเฉยๆ ไม่บล็อกการเช็กอิน
  if p_lat is not null and p_lng is not null then
    v_dist := round(
      6371000 * 2 * asin(sqrt(
        power(sin(radians(p_lat - v_set.office_lat)/2), 2) +
        cos(radians(v_set.office_lat)) * cos(radians(p_lat)) *
        power(sin(radians(p_lng - v_set.office_lng)/2), 2)
      ))
    );
  end if;

  insert into check_in(officer_id, checked_in_at, photo_path, lat, lng, distance_m, status, note)
  values (p_officer_id, v_now, p_photo_path, p_lat, p_lng, v_dist, v_status, p_note);

  return json_build_object('ok', true, 'status', v_status,
                           'time', v_now, 'distance_m', v_dist);
exception
  when unique_violation then
    return json_build_object('ok', false, 'error', 'already_checked_in');
end;
$$;

grant execute on function public.do_check_in to anon;

-- ============================================================
-- 3. do_override() — เฉพาะหัวหน้า (authenticated + is_supervisor)
--    ใช้งานจริงได้ในเฟส C หลังสร้างบัญชี Supabase Auth แล้ว
-- ============================================================
create or replace function public.do_override(
  p_check_in_id uuid,
  p_new_status  text,
  p_reason      text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_is_sup boolean;
begin
  select is_supervisor into v_is_sup
  from officer where id = auth.uid();

  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  update check_in
     set override_status = p_new_status,
         override_by     = auth.uid(),
         override_reason = p_reason,
         override_at     = now()
   where id = p_check_in_id;

  return json_build_object('ok', true);
end;
$$;

grant execute on function public.do_override to authenticated;
