-- Migration 21: กล่องม็อตโต้หมุนเวียน 3 ข้อความ (rotate ตามวันทำงาน ข้ามเสาร์-อาทิตย์)
-- เพิ่มคอลัมน์ 3 ช่องข้อความ, สูตรหมุนแบบ deterministic (นับวันจันทร์-ศุกร์เท่านั้นตั้งแต่วันอ้างอิงคงที่ mod 3)
-- ไม่ fix ว่าวันจันทร์ = ข้อความ 1 เสมอ (ยืนยันกับเจ้าของแล้วว่าลำดับเลื่อนได้ทุกสัปดาห์ เพราะ 5 วันทำงาน mod 3 = 2)

-- ========== ส่วนที่ 1: schema ==========
alter table settings
  add column if not exists service_motto_1 text,
  add column if not exists service_motto_2 text,
  add column if not exists service_motto_3 text;

-- migrate ค่าเดิมไปช่อง 1, seed placeholder ให้ช่อง 2/3 กันโชว์ข้อความว่างวันที่หมุนไปตกช่องยังไม่มีคนกรอก
update settings
set service_motto_1 = coalesce(nullif(trim(service_motto), ''), 'ยิ้มแย้มแจ่มใส ให้บริการด้วยใจ ทุกคนคือคนสำคัญ'),
    service_motto_2 = coalesce(service_motto_2, 'ตรงต่อเวลา คือความรับผิดชอบขั้นพื้นฐานของทุกงาน'),
    service_motto_3 = coalesce(service_motto_3, 'งานยาก ทำให้ง่าย งานง่าย ทำให้ดี')
where id = 1;

-- คอลัมน์ service_motto เดิมเก็บไว้เฉยๆ ไม่ลบ (เผื่ออ้างอิงย้อนหลัง) แต่โค้ดใหม่จะไม่อ่าน/เขียนแล้ว

-- ========== ส่วนที่ 2: do_get_motto (แก้ให้คำนวณ rotation, ไม่ต้อง DROP เพราะ return type ยังเป็น json) ==========
create or replace function public.do_get_motto()
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_tz text;
  v_today date;
  v_ref date := date '2024-01-01'; -- วันอ้างอิงคงที่ (วันจันทร์) ใช้แค่เป็นจุดเริ่มนับ ไม่มีนัยสำคัญอื่น ห้ามเปลี่ยนหลัง deploy เพราะจะทำให้ลำดับหมุนกระโดด
  v_business_days integer;
  v_slot smallint;
  v_motto text;
begin
  select tz into v_tz from settings where id = 1;
  v_today := (now() at time zone coalesce(v_tz, 'Asia/Bangkok'))::date;

  select count(*) into v_business_days
  from generate_series(v_ref, v_today, interval '1 day') d
  where extract(isodow from d) not in (6, 7);

  v_slot := ((v_business_days - 1) % 3) + 1;

  select case v_slot
    when 1 then service_motto_1
    when 2 then service_motto_2
    else service_motto_3
  end into v_motto
  from settings where id = 1;

  return json_build_object('ok', true, 'motto', coalesce(v_motto, ''), 'active_slot', v_slot);
end;
$function$;

grant execute on function public.do_get_motto() to anon, authenticated;

-- ========== ส่วนที่ 3: do_list_mottos / do_supervisor_list_mottos (ใหม่ — ให้แดชบอร์ดดึงครบ 3 ช่องมาแก้ไข) ==========
create or replace function public.do_list_mottos()
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_slot_1 text;
  v_slot_2 text;
  v_slot_3 text;
  v_active_slot smallint;
begin
  if not public.is_supervisor() then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  select (public.do_get_motto()->>'active_slot')::smallint into v_active_slot;
  select service_motto_1, service_motto_2, service_motto_3
    into v_slot_1, v_slot_2, v_slot_3
  from settings where id = 1;

  return json_build_object(
    'ok', true,
    'slot_1', coalesce(v_slot_1, ''),
    'slot_2', coalesce(v_slot_2, ''),
    'slot_3', coalesce(v_slot_3, ''),
    'active_slot', v_active_slot
  );
end;
$function$;

grant execute on function public.do_list_mottos() to authenticated;

create or replace function public.do_supervisor_list_mottos(p_officer_id uuid, p_pin text)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_off record;
  v_slot_1 text;
  v_slot_2 text;
  v_slot_3 text;
  v_active_slot smallint;
begin
  select id, pin_hash into v_off
  from officer
  where id = p_officer_id and is_supervisor = true and login_method = 'pin' and active = true;

  if v_off.id is null then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or crypt(p_pin, v_off.pin_hash) <> v_off.pin_hash then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select (public.do_get_motto()->>'active_slot')::smallint into v_active_slot;
  select service_motto_1, service_motto_2, service_motto_3
    into v_slot_1, v_slot_2, v_slot_3
  from settings where id = 1;

  return json_build_object(
    'ok', true,
    'slot_1', coalesce(v_slot_1, ''),
    'slot_2', coalesce(v_slot_2, ''),
    'slot_3', coalesce(v_slot_3, ''),
    'active_slot', v_active_slot
  );
end;
$function$;

grant execute on function public.do_supervisor_list_mottos(uuid, text) to anon;

-- ========== ส่วนที่ 4: do_set_motto (auth) — เปลี่ยน signature เพิ่ม p_slot ต้อง DROP ก่อน ==========
drop function if exists public.do_set_motto(text);

create or replace function public.do_set_motto(p_slot smallint, p_new_motto text)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_motto text := trim(coalesce(p_new_motto, ''));
begin
  if not public.is_supervisor() then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  if p_slot not in (1, 2, 3) then
    return json_build_object('ok', false, 'error', 'invalid_slot');
  end if;
  if length(v_motto) = 0 then
    return json_build_object('ok', false, 'error', 'motto_empty');
  end if;
  if length(v_motto) > 300 then
    return json_build_object('ok', false, 'error', 'motto_too_long');
  end if;

  if p_slot = 1 then
    update settings set service_motto_1 = v_motto where id = 1;
  elsif p_slot = 2 then
    update settings set service_motto_2 = v_motto where id = 1;
  else
    update settings set service_motto_3 = v_motto where id = 1;
  end if;

  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_set_motto(smallint, text) to authenticated;

-- ========== ส่วนที่ 5: do_supervisor_set_motto (PIN) — เปลี่ยน signature เพิ่ม p_slot ต้อง DROP ก่อน ==========
drop function if exists public.do_supervisor_set_motto(uuid, text, text);

create or replace function public.do_supervisor_set_motto(p_officer_id uuid, p_pin text, p_slot smallint, p_new_motto text)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_off record;
  v_motto text := trim(coalesce(p_new_motto, ''));
begin
  select id, pin_hash into v_off
  from officer
  where id = p_officer_id and is_supervisor = true and login_method = 'pin' and active = true;

  if v_off.id is null then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or crypt(p_pin, v_off.pin_hash) <> v_off.pin_hash then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  if p_slot not in (1, 2, 3) then
    return json_build_object('ok', false, 'error', 'invalid_slot');
  end if;
  if length(v_motto) = 0 then
    return json_build_object('ok', false, 'error', 'motto_empty');
  end if;
  if length(v_motto) > 300 then
    return json_build_object('ok', false, 'error', 'motto_too_long');
  end if;

  if p_slot = 1 then
    update settings set service_motto_1 = v_motto where id = 1;
  elsif p_slot = 2 then
    update settings set service_motto_2 = v_motto where id = 1;
  else
    update settings set service_motto_3 = v_motto where id = 1;
  end if;

  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_supervisor_set_motto(uuid, text, smallint, text) to anon;
