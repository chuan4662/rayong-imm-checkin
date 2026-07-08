-- เพิ่มความสามารถดูรูปย่อให้หัวหน้าที่เข้าด้วย PIN (ศุภัตรา, ผู้ช่วยแอดมิน)
-- กลไก: PIN caller ไม่มี Supabase Auth session จริง จึงสร้าง signed URL แบบปกติไม่ได้
-- แก้ด้วย Edge Function (supervisor-photo-url) ที่ใช้ service role ออก signed URL ให้แทน
-- โดย Edge Function จะเรียก RPC นี้ก่อนเสมอเพื่อตรวจ PIN + ตรวจว่า photo_path นี้มีอยู่จริงในระบบ

-- 1) เพิ่ม photo_path ในผลลัพธ์ do_supervisor_get_today (เดิมตัดออกโดยตั้งใจ ตอนนี้เปลี่ยนใจแล้ว)
drop function if exists public.do_supervisor_get_today(uuid, text);
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
           c.distance_m, c.ready_for_duty, c.note, c.photo_path
    from check_in c
    join officer o on o.id = c.officer_id
    where c.local_date = (now() at time zone v_tz)::date
    order by c.checked_in_at
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$$;
grant execute on function public.do_supervisor_get_today(uuid, text) to anon;

-- 2) RPC สำหรับ Edge Function เรียกตรวจสิทธิ์ก่อนออก signed URL
create or replace function public.do_supervisor_verify_pin_for_photo(
  p_officer_id  uuid,
  p_pin         text,
  p_photo_path  text
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_off officer%rowtype;
  v_exists boolean;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select exists(select 1 from check_in where photo_path = p_photo_path) into v_exists;
  if not v_exists then
    return json_build_object('ok', false, 'error', 'photo_not_found');
  end if;

  return json_build_object('ok', true);
end;
$$;
grant execute on function public.do_supervisor_verify_pin_for_photo(uuid, text, text) to anon;
