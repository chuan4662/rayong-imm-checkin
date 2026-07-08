-- ============================================================
-- เฟส B (เพิ่มเติมหลัง feedback รอบ 3): เปลี่ยนไฟสถานะจาก 3 สี เป็น 4 สี
-- เกณฑ์ใหม่ (ยืนยันโดยเจ้าของโปรเจกต์):
--   ก่อน 08:20        = เขียว  (ดีเยี่ยม)
--   08:20 - ก่อน 08:30 = เหลือง (ทันพอดี)
--   08:30 - ก่อน 08:40 = ส้ม   (มาเลท)
--   08:40 ขึ้นไป       = แดง   (สาย)
-- ============================================================

-- 1) เพิ่มคอลัมน์เกณฑ์เวลาใหม่ใน settings + อัปเดตค่าให้ตรง 4 เกณฑ์
alter table public.settings add column if not exists orange_before time not null default '08:40';

update public.settings
   set green_before  = '08:20',
       yellow_before = '08:30',
       orange_before = '08:40'
 where id = 1;

-- 2) แก้ check constraint ให้ค่า status/override_status รับ 'orange' ได้
alter table public.check_in drop constraint check_in_status_check;
alter table public.check_in add constraint check_in_status_check
  check (status in ('green','yellow','orange','red'));

alter table public.check_in drop constraint check_in_override_status_check;
alter table public.check_in add constraint check_in_override_status_check
  check (override_status in ('green','yellow','orange','red'));

-- 3) แก้ do_check_in ให้คำนวณ 4 สถานะ (parameter list เดิม ไม่ต้อง drop function)
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

  insert into check_in(officer_id, checked_in_at, photo_path, lat, lng, distance_m, status, note, ready_for_duty)
  values (p_officer_id, v_now, p_photo_path, p_lat, p_lng, v_dist, v_status, v_note, p_ready);

  return json_build_object('ok', true, 'status', v_status,
                           'time', v_now, 'distance_m', v_dist);
exception
  when unique_violation then
    return json_build_object('ok', false, 'error', 'already_checked_in');
end;
$$;

-- ไม่ต้อง grant ใหม่ เพราะ parameter list เดิม (create or replace แทนที่ของเดิมได้ตรงๆ)
