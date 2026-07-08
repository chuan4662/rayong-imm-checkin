-- ============================================================
-- เฟส C (เริ่มแกนหลัก) + ฟีเจอร์ใหม่: PIN ตั้งเองครั้งแรก + หัวหน้ารีเซ็ตได้
-- ตัดสินใจโดยเจ้าของโปรเจกต์:
--   - เจ้าหน้าที่ตั้ง PIN เองตอนล็อกอินครั้งแรก (แอดมินไม่ต้องรู้ PIN ใคร)
--   - ถ้าลืม PIN หัวหน้ากด "รีเซ็ต" ในแดชบอร์ด -> เจ้าหน้าที่ตั้งใหม่เองรอบถัดไป
--   - แดชบอร์ดหัวหน้ารอบนี้ทำแกนหลักก่อน: login + วันนี้ + รีเซ็ต PIN
--     (ประวัติย้อนหลัง + override + export Excel ทำต่อทีหลัง)
-- ============================================================

-- 1) อนุญาตให้ pin_hash เป็น NULL ได้ (แปลว่า "ยังไม่ตั้ง PIN")
alter table public.officer alter column pin_hash drop not null;

-- 2) do_list_officers: เพิ่ม flag บอก frontend ว่าคนนี้ต้องตั้ง PIN ครั้งแรกไหม
drop function if exists public.do_list_officers();
create or replace function public.do_list_officers()
returns table (id uuid, full_name text, rank_title text, needs_pin_setup boolean)
language sql
security definer
set search_path = public
as $$
  select id, full_name, rank_title, (pin_hash is null) as needs_pin_setup
  from officer
  where active = true
  order by full_name;
$$;
grant execute on function public.do_list_officers() to anon;

-- 3) ตั้ง PIN ครั้งแรก — ทำได้เฉพาะตอน pin_hash ยังเป็น null เท่านั้น (กันคนอื่นมาแย่งตั้งทับ)
create or replace function public.do_set_initial_pin(
  p_officer_id uuid,
  p_new_pin    text
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
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
grant execute on function public.do_set_initial_pin(uuid, text) to anon;

-- 4) หัวหน้ารีเซ็ต PIN ของเจ้าหน้าที่ที่ลืม (เคลียร์กลับเป็น null ให้ไปตั้งใหม่เองตอนล็อกอินรอบหน้า)
create or replace function public.do_reset_pin(
  p_officer_id uuid
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  update officer set pin_hash = null where id = p_officer_id;
  return json_build_object('ok', true);
end;
$$;
grant execute on function public.do_reset_pin(uuid) to authenticated;

-- 5) ให้หัวหน้า (authenticated + is_supervisor) ดูรายชื่อเจ้าหน้าที่ทั้งหมดได้ (รวม inactive) เพื่อจัดการในแดชบอร์ด
--    ใช้ policy เดิม officer_read_supervisor ที่มีอยู่แล้ว (select ได้ทุกคอลัมน์ยกเว้นที่ RLS block)
--    หมายเหตุ: policy เดิมไม่ได้ filter active=true ดังนั้นหัวหน้าเห็นครบทุกคนอยู่แล้ว ไม่ต้องเพิ่ม

-- 6) Storage: อนุญาตให้หัวหน้า (authenticated + is_supervisor) สร้าง signed URL ดูรูปได้
create policy checkin_photos_read_supervisor on storage.objects
  for select to authenticated
  using (
    bucket_id = 'checkin-photos'
    and exists (select 1 from officer o where o.id = auth.uid() and o.is_supervisor)
  );
