-- ============================================================
-- เพิ่มบัญชีผู้ดูแลระบบ 3 บัญชี:
--   1) ชวนชัย (พ.ต.ท.)      — ดูแลระบบสูงสุด, ผูกกับ Supabase Auth ที่สร้างไว้แล้ว (email+password)
--   2) ศุภัตรา (พ.ต.ท.หญิง) — หัวหน้าคนที่สอง, เข้าด้วย PIN (ตั้งเองครั้งแรก)
--   3) ผู้ช่วยแอดมิน          — สิทธิ์เหมือนข้อ 2, เข้าด้วย PIN, ไม่ผูกชื่อจริง
--
-- ทั้งสามคนไม่ต้องเช็กอิน (active = false) จึงไม่โผล่ในดรอปดาวน์เช็กอินของเจ้าหน้าที่
--
-- ข้อจำกัดที่ตกลงกับเจ้าของโปรเจกต์: บัญชีที่เข้าด้วย PIN (ศุภัตรา, ผู้ช่วยแอดมิน)
-- จะเห็นได้เฉพาะรายงานตัวหนังสือ (เวลา/สถานะ/ระยะห่าง/ความพร้อม/หมายเหตุ) และรีเซ็ต PIN ได้
-- แต่ "ดูรูปถ่าย" ทำไม่ได้ในโหมดนี้ เพราะ Supabase Storage ต้องมี Auth session จริงถึงจะสร้าง signed URL ได้
-- ถ้าต้องการดูรูปด้วย ต้องอัปเกรดเป็นบัญชี Supabase Auth (email+password) เท่านั้น
-- ============================================================

-- 1) แยกวิธีล็อกอิน: 'auth' = Supabase Auth (email+password), 'pin' = PIN ผ่าน RPC
alter table public.officer add column if not exists login_method text not null default 'pin'
  check (login_method in ('pin','auth'));

-- 2) ผูก ชวนชัย เข้ากับ Supabase Auth ที่สร้างไว้แล้ว (UID จาก auth.users)
insert into public.officer (id, full_name, rank_title, is_supervisor, active, login_method, sort_order)
values ('a160a3f3-0d26-497b-b3f4-f9866d00a40c', 'ชวนชัย', 'พ.ต.ท.', true, false, 'auth', 999);

-- 3) ศุภัตรา — เข้าด้วย PIN (ตั้งเองครั้งแรก)
insert into public.officer (full_name, rank_title, is_supervisor, active, login_method, sort_order)
values ('ศุภัตรา', 'พ.ต.ท.หญิง', true, false, 'pin', 999);

-- 4) ผู้ช่วยแอดมิน — สิทธิ์เหมือนศุภัตรา เข้าด้วย PIN ไม่ผูกชื่อจริง
insert into public.officer (full_name, rank_title, is_supervisor, active, login_method, sort_order)
values ('ผู้ช่วยแอดมิน', null, true, false, 'pin', 999);

-- ============================================================
-- RPC ชุดใหม่สำหรับ "หัวหน้าที่เข้าด้วย PIN" (anon เรียกได้ ตรวจ PIN เองข้างในทุกครั้ง)
-- ============================================================

-- 5) รายชื่อหัวหน้าที่เข้าด้วย PIN (สำหรับดรอปดาวน์หน้า report.html)
create or replace function public.do_list_supervisors()
returns table (id uuid, full_name text, rank_title text, needs_pin_setup boolean)
language sql
security definer
set search_path = public
as $$
  select id, full_name, rank_title, (pin_hash is null) as needs_pin_setup
  from officer
  where is_supervisor = true and login_method = 'pin'
  order by full_name;
$$;
grant execute on function public.do_list_supervisors() to anon;

-- 6) ตั้ง PIN ครั้งแรกสำหรับหัวหน้า (แยกจาก do_set_initial_pin ของเจ้าหน้าที่ เพราะเงื่อนไขต่างกัน)
create or replace function public.do_supervisor_set_initial_pin(
  p_officer_id uuid,
  p_new_pin    text
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is not null then
    return json_build_object('ok', false, 'error', 'pin_already_set');
  end if;
  if p_new_pin is null or length(p_new_pin) < 4 then
    return json_build_object('ok', false, 'error', 'pin_too_short');
  end if;

  update officer set pin_hash = crypt(p_new_pin, gen_salt('bf')) where id = p_officer_id;
  return json_build_object('ok', true);
end;
$$;
grant execute on function public.do_supervisor_set_initial_pin(uuid, text) to anon;

-- 7) ดึงรายการเช็กอินวันนี้ (ไม่รวม photo_path — ตามข้อจำกัดที่ตกลงกัน)
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
           c.distance_m, c.ready_for_duty, c.note
    from check_in c
    join officer o on o.id = c.officer_id
    where c.local_date = (now() at time zone v_tz)::date
    order by c.checked_in_at
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$$;
grant execute on function public.do_supervisor_get_today(uuid, text) to anon;

-- 8) รายชื่อเจ้าหน้าที่ทั้งหมด (สำหรับตารางจัดการ + ปุ่มรีเซ็ต PIN)
create or replace function public.do_supervisor_list_officers(
  p_officer_id uuid,
  p_pin        text
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_off  officer%rowtype;
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
    select id, full_name, rank_title, nickname, active, is_supervisor, login_method,
           (pin_hash is null) as needs_pin_setup
    from officer
    order by sort_order nulls last, full_name
  ) t;

  return json_build_object('ok', true, 'rows', v_rows);
end;
$$;
grant execute on function public.do_supervisor_list_officers(uuid, text) to anon;

-- 9) รีเซ็ต PIN ของใครก็ได้ในระบบ (verify ตัวเองด้วย PIN ก่อนเสมอ)
create or replace function public.do_supervisor_reset_pin(
  p_officer_id        uuid,
  p_pin                text,
  p_target_officer_id  uuid
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  update officer set pin_hash = null where id = p_target_officer_id;
  return json_build_object('ok', true);
end;
$$;
grant execute on function public.do_supervisor_reset_pin(uuid, text, uuid) to anon;
