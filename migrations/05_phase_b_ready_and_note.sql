-- ============================================================
-- เฟส B (เพิ่มเติมหลัง feedback รอบ 2):
-- เพิ่มสถานะ "พร้อม/ไม่พร้อมปฏิบัติหน้าที่" + บังคับหมายเหตุขั้นต่ำ 5 ตัวอักษร
-- ตัดสินใจโดยเจ้าของโปรเจกต์: ไม่พร้อม = บันทึกไว้เฉยๆ ไม่บล็อกการเช็กอิน
-- ============================================================

alter table public.check_in add column if not exists ready_for_duty boolean;

-- ต้อง drop signature เดิมก่อน เพราะ create or replace กับ parameter list ใหม่
-- จะกลายเป็นสร้างฟังก์ชันซ้อน (overload) แทนที่จะ replace ทำให้ grant กำกวม
drop function if exists public.do_check_in(uuid, text, text, double precision, double precision, text);

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
  v_set     settings%rowtype;
  v_off     officer%rowtype;
  v_now     timestamptz := now();
  v_local   time;
  v_status  text;
  v_dist    integer;
  v_note    text := trim(coalesce(p_note, ''));
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

  insert into check_in(officer_id, checked_in_at, photo_path, lat, lng, distance_m, status, note, ready_for_duty)
  values (p_officer_id, v_now, p_photo_path, p_lat, p_lng, v_dist, v_status, v_note, p_ready);

  return json_build_object('ok', true, 'status', v_status,
                           'time', v_now, 'distance_m', v_dist);
exception
  when unique_violation then
    return json_build_object('ok', false, 'error', 'already_checked_in');
end;
$$;

grant execute on function public.do_check_in(uuid, text, text, double precision, double precision, text, boolean) to anon;

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
    return json_build_object('ok', false, 'error', 'not_found');
  end if;

  return json_build_object(
    'ok', true,
    'status', coalesce(v_row.override_status, v_row.status),
    'time', v_row.checked_in_at,
    'distance_m', v_row.distance_m,
    'ready_for_duty', v_row.ready_for_duty,
    'note', v_row.note
  );
end;
$$;

grant execute on function public.do_get_today_status(uuid, text) to anon;
