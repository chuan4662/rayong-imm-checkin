-- เพิ่ม 2 ฟีเจอร์:
-- 1) กล่องม็อตโต้/แบนเนอร์บริการ ที่หัวหน้าทั้ง 3 คน (auth + 2 PIN) แก้ไขได้จากหลังบ้าน
--    แสดงให้เจ้าหน้าที่เห็นหลังเช็กอิน (ทั้งหน้าเช็กอินสำเร็จ และหน้าเช็กอินซ้ำ)
-- 2) สถิติส่วนตัวรายเดือน (เห็นเฉพาะตัวเอง) นับตามสีเวลา 4 สี + ม่วงเป็น "แฟล็กเสริม" แยกบรรทัด ไม่ใช่บรรทัดที่ 5 คู่ขนาน
--    (กันปัญหาผลรวมเกินจำนวนวันจริง เพราะม่วงซ้อนอยู่กับสีเวลาเดิมเสมอ)

-- 1) คอลัมน์ม็อตโต้ใน settings — ใส่ placeholder ไว้ก่อน ให้แอดมินไปตั้งข้อความจริงเอง
alter table public.settings add column if not exists service_motto text
  default 'ยินดีต้อนรับ — แอดมินยังไม่ได้ตั้งข้อความม็อตโต้ กรุณาตั้งค่าในหน้าแดชบอร์ด';

-- 2) RPC อ่านม็อตโต้ (anon เรียกได้ — ให้ทุกคนเห็นข้อความหลังเช็กอิน)
create or replace function public.do_get_motto()
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_motto text;
begin
  select service_motto into v_motto from settings where id = 1;
  return json_build_object('ok', true, 'motto', v_motto);
end;
$$;
grant execute on function public.do_get_motto() to anon;

-- 3) RPC ตั้งม็อตโต้ — สำหรับหัวหน้าที่ login ด้วย Supabase Auth (ชวนชัย)
create or replace function public.do_set_motto(
  p_new_motto text
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_motto text := trim(coalesce(p_new_motto, ''));
begin
  if not public.is_supervisor() then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  if length(v_motto) = 0 then
    return json_build_object('ok', false, 'error', 'motto_empty');
  end if;
  if length(v_motto) > 300 then
    return json_build_object('ok', false, 'error', 'motto_too_long');
  end if;

  update settings set service_motto = v_motto where id = 1;
  return json_build_object('ok', true);
end;
$$;
grant execute on function public.do_set_motto(text) to authenticated;

-- 4) RPC ตั้งม็อตโต้ — สำหรับหัวหน้าที่ login ด้วย PIN (ศุภัตรา, ผู้ช่วยแอดมิน)
create or replace function public.do_supervisor_set_motto(
  p_officer_id uuid,
  p_pin        text,
  p_new_motto  text
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_off   officer%rowtype;
  v_motto text := trim(coalesce(p_new_motto, ''));
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;
  if length(v_motto) = 0 then
    return json_build_object('ok', false, 'error', 'motto_empty');
  end if;
  if length(v_motto) > 300 then
    return json_build_object('ok', false, 'error', 'motto_too_long');
  end if;

  update settings set service_motto = v_motto where id = 1;
  return json_build_object('ok', true);
end;
$$;
grant execute on function public.do_supervisor_set_motto(uuid, text, text) to anon;

-- 5) RPC สถิติส่วนตัวรายเดือน (เห็นเฉพาะตัวเอง ต้องยืนยัน PIN ก่อนเสมอ)
--    นับตามเดือนปัจจุบันของเซิร์ฟเวอร์ (Asia/Bangkok) — ไม่ต้องมี logic รีเซ็ตเอง เพราะเดือนใหม่ตัว filter ก็เปลี่ยนเองอัตโนมัติ
--    สถานะที่นับ = coalesce(override_status, status) (สถานะจริงหลัง override ถ้ามี)
--    ม่วง (incomplete_checkin) นับแยกเป็นยอดรวม ไม่ใช่บรรทัดคู่ขนานกับ 4 สีเวลา เพราะม่วงซ้อนอยู่กับสีใดสีหนึ่งใน 4 สีเสมอ
create or replace function public.do_get_my_month_stats(
  p_officer_id uuid,
  p_pin        text
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_off officer%rowtype;
  v_tz  text;
  v_month_start date;
  v_month_end   date;
  v_green int; v_yellow int; v_orange int; v_red int; v_incomplete int; v_total int;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select tz into v_tz from settings where id = 1;

  v_month_start := date_trunc('month', (now() at time zone v_tz))::date;
  v_month_end   := (v_month_start + interval '1 month')::date;

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
    and local_date >= v_month_start
    and local_date <  v_month_end;

  return json_build_object(
    'ok', true,
    'green', coalesce(v_green,0),
    'yellow', coalesce(v_yellow,0),
    'orange', coalesce(v_orange,0),
    'red', coalesce(v_red,0),
    'incomplete', coalesce(v_incomplete,0),
    'total', coalesce(v_total,0)
  );
end;
$$;
grant execute on function public.do_get_my_month_stats(uuid, text) to anon;
