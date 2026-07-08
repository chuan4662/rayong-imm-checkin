-- เพิ่มสถานะ "สีม่วง" = เช็คอินไม่สมบูรณ์ (ห่างจากที่ทำงานเกิน 50 ม. หรือไม่เปิด/อนุญาต GPS)
-- ออกแบบ: ม่วงเป็น "แฟล็กเสริม" คู่กับสีเวลาเดิม (เขียว/เหลือง/ส้ม/แดง) ไม่ใช่แทนที่
-- flow: เจ้าหน้าที่กดยืนยันเช็คอิน -> client เช็คระยะทาง/GPS ก่อน -> ถ้าเข้าเงื่อนไขม่วง เด้ง modal
--       ให้ยืนยันอีกครั้ง -> ถ้ายืนยัน ค่อยเรียก do_check_in จริง (server คำนวณ incomplete_checkin เองอีกที เป็น source of truth)

-- 1) เพิ่มคอลัมน์
alter table public.check_in add column if not exists incomplete_checkin boolean not null default false;

-- 2) RPC ใหม่: เช็คระยะทางล่วงหน้า (ไม่ insert อะไร) ให้ client ใช้ตัดสินใจว่าจะเด้ง modal ไหม
create or replace function public.do_check_distance(
  p_lat double precision,
  p_lng double precision
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_set  settings%rowtype;
  v_dist integer;
begin
  if p_lat is null or p_lng is null then
    return json_build_object('ok', true, 'distance_m', null);
  end if;
  select * into v_set from settings where id = 1;
  v_dist := round(
    6371000 * 2 * asin(sqrt(
      power(sin(radians(p_lat - v_set.office_lat)/2), 2) +
      cos(radians(v_set.office_lat)) * cos(radians(p_lat)) *
      power(sin(radians(p_lng - v_set.office_lng)/2), 2)
    ))
  );
  return json_build_object('ok', true, 'distance_m', v_dist);
end;
$$;
grant execute on function public.do_check_distance(double precision, double precision) to anon;

-- 3) แก้ do_check_in ให้คำนวณ incomplete_checkin เองฝั่ง server (ไม่เชื่อค่าจาก client)
create or replace function public.do_check_in(
  p_officer_id uuid,
  p_pin        text,
  p_photo_path text,
  p_lat        double precision,
  p_lng        double precision,
  p_note       text,
  p_ready      boolean
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_off        officer%rowtype;
  v_set        settings%rowtype;
  v_now        timestamptz := now();
  v_local      time;
  v_status     text;
  v_dist       integer;
  v_note       text := trim(coalesce(p_note, ''));
  v_incomplete boolean := false;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;

  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  if length(v_note) < 5 then
    return json_build_object('ok', false, 'error', 'note_too_short');
  end if;

  if p_ready is null then
    return json_build_object('ok', false, 'error', 'ready_required');
  end if;

  select * into v_set from settings where id = 1;

  v_local := (v_now at time zone v_set.tz)::time;
  if    v_local < v_set.green_before  then v_status := 'green';
  elsif v_local < v_set.yellow_before then v_status := 'yellow';
  elsif v_local < v_set.orange_before then v_status := 'orange';
  else                                     v_status := 'red';
  end if;

  if p_lat is not null and p_lng is not null then
    v_dist := round(
      6371000 * 2 * asin(sqrt(
        power(sin(radians(p_lat - v_set.office_lat)/2), 2) +
        cos(radians(v_set.office_lat)) * cos(radians(p_lat)) *
        power(sin(radians(p_lng - v_set.office_lng)/2), 2)
      ))
    );
  end if;

  -- สีม่วง: ไม่มีพิกัด GPS หรือห่างจากที่ทำงานเกิน 50 เมตร
  v_incomplete := (p_lat is null or p_lng is null) or (v_dist is not null and v_dist > 50);

  insert into check_in(officer_id, checked_in_at, photo_path, lat, lng, distance_m, status, note, ready_for_duty, incomplete_checkin)
  values (p_officer_id, v_now, p_photo_path, p_lat, p_lng, v_dist, v_status, v_note, p_ready, v_incomplete);

  return json_build_object('ok', true, 'status', v_status,
                           'time', v_now, 'distance_m', v_dist, 'incomplete', v_incomplete);
exception
  when unique_violation then
    return json_build_object('ok', false, 'error', 'already_checked_in');
end;
$$;

-- 4) เพิ่ม incomplete ในผลลัพธ์ do_get_today_status (หน้า "เช็กอินแล้ววันนี้" ของเจ้าหน้าที่เอง)
create or replace function public.do_get_today_status(
  p_officer_id uuid,
  p_pin        text
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_off officer%rowtype;
  v_row check_in%rowtype;
  v_tz  text;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;

  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select tz into v_tz from settings where id = 1;

  select * into v_row from check_in
    where officer_id = p_officer_id
      and local_date = (now() at time zone v_tz)::date
    limit 1;

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
    'incomplete', v_row.incomplete_checkin
  );
end;
$$;

-- 5) เพิ่ม incomplete_checkin ในผลลัพธ์ do_supervisor_get_today (หน้าหัวหน้าที่เข้าด้วย PIN)
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
           c.distance_m, c.ready_for_duty, c.note, c.photo_path, c.incomplete_checkin
    from check_in c
    join officer o on o.id = c.officer_id
    where c.local_date = (now() at time zone v_tz)::date
    order by c.checked_in_at
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$$;
