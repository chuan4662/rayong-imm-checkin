-- ============================================================================
-- Migration 33 — เพิ่ม / ปิดใช้งาน / ลบ เจ้าหน้าที่ ผ่านหน้าแดชบอร์ดและรายงาน
-- วันที่: 2 ก.ย. 2569
--
-- ที่มา: เดิมระบบมี do_add_supervisor (เพิ่ม "หัวหน้า") อยู่แล้ว แต่ไม่มีอะไรสำหรับ
--        "เจ้าหน้าที่ธรรมดา" เลย ทุกครั้งที่มีคนย้ายเข้า/ออกต้องให้ agent แก้ที่ DB ให้
--
-- ⚠️ ข้อเท็จจริงที่ตรวจจากฐานข้อมูลจริงก่อนออกแบบ (2 ก.ย. 2569):
--    มี 6 foreign key ชี้มาที่ officer — check_in.officer_id, check_in.override_by,
--    check_out.officer_id, feedback.officer_id, booking.assigned_officer_id,
--    booking_request.asked_by — ทั้งหมดเป็น NO ACTION
--    ⇒ "ลบ" เจ้าหน้าที่ที่มีประวัติแม้แถวเดียว ฐานข้อมูลจะปฏิเสธเสมอ
--    ⇒ ตอนออกแบบ เจ้าหน้าที่ 20/22 คนมีประวัติเช็กอิน 13-41 ครั้ง ลบจริงไม่ได้เลย
--
-- กติกาที่เจ้าของยืนยัน (2 ก.ย. 2569):
--   1. "ลบ" = ปิดใช้งาน (active=false) เป็นหลัก · ลบจริงเฉพาะคนที่ยังไม่มีประวัติเลย
--      หน้าจอต้องบอกล่วงหน้าว่ากำลังจะทำอย่างไหน ไม่ใช่กดแล้วลุ้น
--   2. ทำได้ทั้ง dashboard.html (ชวนชัย/auth) และ report.html (ศุภัตรา/ผู้ช่วยแอดมิน/PIN)
--   3. ฟอร์มเพิ่มกรอกแค่ ยศ + ชื่อ-สกุล + ชื่อเล่น ที่เหลือระบบตั้งให้เอง
--
-- โครงสร้าง (ตามแพทเทิร์นเดิมของโปรเจกต์ทุกจุด):
--   officer_admin_*_json  = ตรรกะกลาง ไม่มี auth check ในตัว REVOKE หมด
--                           (แพทเทิร์นเดียวกับ do_team_coverage_json ใน migration 27)
--   do_admin_*            = ทางเข้าฝั่ง auth (ชวนชัย)
--   do_supervisor_*_impl  = ทางเข้าฝั่ง PIN (ตรวจ is_supervisor + login_method='pin' + crypt)
--   do_supervisor_*       = thin wrapper เรียก check_and_count_pin ก่อน (PIN rate limit, migration 25)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. helper: นับ "ประวัติ" ทั้งหมดของเจ้าหน้าที่ 1 คน (ครบทั้ง 6 FK)
--    ใช้ตัดสินว่าลบจริงได้ไหม + ใช้โชว์ให้หัวหน้าเห็นก่อนกดปุ่ม
-- ----------------------------------------------------------------------------
create or replace function public.officer_history_count(p_officer_id uuid)
 returns bigint
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select (select count(*) from check_in        where officer_id          = p_officer_id)
       + (select count(*) from check_in        where override_by         = p_officer_id)
       + (select count(*) from check_out       where officer_id          = p_officer_id)
       + (select count(*) from feedback        where officer_id          = p_officer_id)
       + (select count(*) from booking         where assigned_officer_id = p_officer_id)
       + (select count(*) from booking_request where asked_by            = p_officer_id);
$function$;
revoke all on function public.officer_history_count(uuid) from public;
revoke all on function public.officer_history_count(uuid) from anon;
revoke all on function public.officer_history_count(uuid) from authenticated;

-- ----------------------------------------------------------------------------
-- 2. ตรรกะกลาง 3 ตัว (ไม่มี auth check — ผู้เรียกต้องตรวจสิทธิ์มาก่อนแล้ว)
-- ----------------------------------------------------------------------------

-- 2.1 เพิ่มเจ้าหน้าที่ใหม่ ต่อท้ายรายชื่อเดิม
create or replace function public.officer_admin_add_json(p_rank_title text, p_full_name text, p_nickname text)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_name text := trim(coalesce(p_full_name, ''));
  v_next integer;
  v_id uuid;
begin
  if length(v_name) = 0 then
    return json_build_object('ok', false, 'error', 'name_required');
  end if;
  if exists (select 1 from officer where lower(trim(full_name)) = lower(v_name)) then
    return json_build_object('ok', false, 'error', 'duplicate_name');
  end if;
  -- ต่อท้าย "เจ้าหน้าที่จริง" เท่านั้น (บัญชีหัวหน้า/ทดสอบใช้ sort_order 1000+ ไม่นับ)
  select coalesce(max(sort_order), 0) + 1 into v_next from officer where sort_order < 1000;
  insert into officer(full_name, rank_title, nickname, sort_order, active, is_supervisor,
                      login_method, work_days, supervisor_enabled, pin_hash,
                      show_in_feedback, accepts_online_queue, work_group_id)
  values (v_name,
          nullif(trim(coalesce(p_rank_title, '')), ''),
          nullif(trim(coalesce(p_nickname, '')), ''),
          v_next, true, false,
          'pin', '{1,2,3,4,5}'::smallint[], true, null,
          false, false, null)
  returning id into v_id;
  return json_build_object('ok', true, 'id', v_id, 'sort_order', v_next, 'full_name', v_name);
end;
$function$;
revoke all on function public.officer_admin_add_json(text, text, text) from public;
revoke all on function public.officer_admin_add_json(text, text, text) from anon;
revoke all on function public.officer_admin_add_json(text, text, text) from authenticated;

-- 2.2 เปิด/ปิดใช้งานเจ้าหน้าที่ (ปิด = หายจากดรอปดาวน์เช็กอิน แต่ประวัติอยู่ครบ)
create or replace function public.officer_admin_set_active_json(p_target uuid, p_active boolean)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_target;
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  -- บัญชีหัวหน้ามีการ์ดจัดการของตัวเองอยู่แล้ว (do_set_supervisor_status) กันแตะข้ามกัน
  if v_off.is_supervisor then return json_build_object('ok', false, 'error', 'is_supervisor_account'); end if;
  if p_active is null then return json_build_object('ok', false, 'error', 'missing_field'); end if;
  update officer set active = p_active where id = p_target;
  return json_build_object('ok', true, 'active', p_active, 'full_name', v_off.full_name);
end;
$function$;
revoke all on function public.officer_admin_set_active_json(uuid, boolean) from public;
revoke all on function public.officer_admin_set_active_json(uuid, boolean) from anon;
revoke all on function public.officer_admin_set_active_json(uuid, boolean) from authenticated;

-- 2.3 ลบเจ้าหน้าที่ออกจากระบบจริง — อนุญาตเฉพาะคนที่ยังไม่มีประวัติเลย
--     ถ้ามีประวัติจะไม่ทำอะไรและคืน has_history + จำนวน ให้หน้าจอไปบอกให้ปิดใช้งานแทน
create or replace function public.officer_admin_remove_json(p_target uuid)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_off officer%rowtype; v_hist bigint;
begin
  select * into v_off from officer where id = p_target;
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.is_supervisor then return json_build_object('ok', false, 'error', 'is_supervisor_account'); end if;
  v_hist := officer_history_count(p_target);
  if v_hist > 0 then
    return json_build_object('ok', false, 'error', 'has_history', 'history_count', v_hist, 'full_name', v_off.full_name);
  end if;
  delete from officer where id = p_target;
  return json_build_object('ok', true, 'full_name', v_off.full_name);
end;
$function$;
revoke all on function public.officer_admin_remove_json(uuid) from public;
revoke all on function public.officer_admin_remove_json(uuid) from anon;
revoke all on function public.officer_admin_remove_json(uuid) from authenticated;

-- ----------------------------------------------------------------------------
-- 3. ทางเข้าฝั่ง auth (ชวนชัย — dashboard.html)
-- ----------------------------------------------------------------------------
create or replace function public.do_admin_add_officer(p_rank_title text, p_full_name text, p_nickname text)
 returns json language plpgsql security definer set search_path to 'public'
as $function$
declare v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then return json_build_object('ok', false, 'error', 'not_supervisor'); end if;
  return officer_admin_add_json(p_rank_title, p_full_name, p_nickname);
end;
$function$;
grant execute on function public.do_admin_add_officer(text, text, text) to authenticated;

create or replace function public.do_admin_set_officer_active(p_target_officer_id uuid, p_active boolean)
 returns json language plpgsql security definer set search_path to 'public'
as $function$
declare v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then return json_build_object('ok', false, 'error', 'not_supervisor'); end if;
  return officer_admin_set_active_json(p_target_officer_id, p_active);
end;
$function$;
grant execute on function public.do_admin_set_officer_active(uuid, boolean) to authenticated;

create or replace function public.do_admin_remove_officer(p_target_officer_id uuid)
 returns json language plpgsql security definer set search_path to 'public'
as $function$
declare v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then return json_build_object('ok', false, 'error', 'not_supervisor'); end if;
  return officer_admin_remove_json(p_target_officer_id);
end;
$function$;
grant execute on function public.do_admin_remove_officer(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. ทางเข้าฝั่ง PIN (ศุภัตรา/ผู้ช่วยแอดมิน — report.html)
--    _impl ตรวจสิทธิ์+PIN ซ้ำในตัวเอง / wrapper ชั้นนอกเรียก check_and_count_pin ก่อน
-- ----------------------------------------------------------------------------
create or replace function public.do_supervisor_add_officer_impl(p_officer_id uuid, p_pin text, p_rank_title text, p_full_name text, p_nickname text)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  return officer_admin_add_json(p_rank_title, p_full_name, p_nickname);
end;
$function$;
revoke all on function public.do_supervisor_add_officer_impl(uuid, text, text, text, text) from public;
revoke all on function public.do_supervisor_add_officer_impl(uuid, text, text, text, text) from anon;

create or replace function public.do_supervisor_add_officer(p_officer_id uuid, p_pin text, p_rank_title text, p_full_name text, p_nickname text)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare v_check record;
begin
  select * into v_check from check_and_count_pin(p_officer_id, p_pin);
  if not v_check.ok then
    return json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until);
  end if;
  return do_supervisor_add_officer_impl(p_officer_id, p_pin, p_rank_title, p_full_name, p_nickname);
end;
$function$;
grant execute on function public.do_supervisor_add_officer(uuid, text, text, text, text) to anon;

create or replace function public.do_supervisor_set_officer_active_impl(p_officer_id uuid, p_pin text, p_target_officer_id uuid, p_active boolean)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  return officer_admin_set_active_json(p_target_officer_id, p_active);
end;
$function$;
revoke all on function public.do_supervisor_set_officer_active_impl(uuid, text, uuid, boolean) from public;
revoke all on function public.do_supervisor_set_officer_active_impl(uuid, text, uuid, boolean) from anon;

create or replace function public.do_supervisor_set_officer_active(p_officer_id uuid, p_pin text, p_target_officer_id uuid, p_active boolean)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare v_check record;
begin
  select * into v_check from check_and_count_pin(p_officer_id, p_pin);
  if not v_check.ok then
    return json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until);
  end if;
  return do_supervisor_set_officer_active_impl(p_officer_id, p_pin, p_target_officer_id, p_active);
end;
$function$;
grant execute on function public.do_supervisor_set_officer_active(uuid, text, uuid, boolean) to anon;

create or replace function public.do_supervisor_remove_officer_impl(p_officer_id uuid, p_pin text, p_target_officer_id uuid)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  return officer_admin_remove_json(p_target_officer_id);
end;
$function$;
revoke all on function public.do_supervisor_remove_officer_impl(uuid, text, uuid) from public;
revoke all on function public.do_supervisor_remove_officer_impl(uuid, text, uuid) from anon;

create or replace function public.do_supervisor_remove_officer(p_officer_id uuid, p_pin text, p_target_officer_id uuid)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare v_check record;
begin
  select * into v_check from check_and_count_pin(p_officer_id, p_pin);
  if not v_check.ok then
    return json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until);
  end if;
  return do_supervisor_remove_officer_impl(p_officer_id, p_pin, p_target_officer_id);
end;
$function$;
grant execute on function public.do_supervisor_remove_officer(uuid, text, uuid) to anon;

-- ----------------------------------------------------------------------------
-- 5. RPC รายชื่อ — คืน history_count + can_delete เพิ่ม
--    เพื่อให้หน้าจอรู้ล่วงหน้าว่าคนนี้จะ "ลบจริง" หรือ "ปิดใช้งาน" ได้ ก่อนกดปุ่ม
-- ----------------------------------------------------------------------------

-- 5.1 ฝั่ง auth — RETURNS TABLE เปลี่ยน ⇒ ต้อง DROP ก่อน (กติกา 2.14 / บั๊กคลาสสิก 6.1)
drop function if exists public.do_list_officers_admin();
create or replace function public.do_list_officers_admin()
 returns table(id uuid, full_name text, rank_title text, nickname text, is_supervisor boolean,
               active boolean, login_method text, needs_pin_setup boolean, work_days smallint[],
               supervisor_enabled boolean, work_group_id uuid, work_group_name text,
               history_count bigint, can_delete boolean)
 language sql
 security definer
 set search_path to 'public'
as $function$
  select o.id, o.full_name, o.rank_title, o.nickname, o.is_supervisor, o.active, o.login_method,
         (o.pin_hash is null) as needs_pin_setup, o.work_days, o.supervisor_enabled,
         o.work_group_id, wg.name as work_group_name,
         officer_history_count(o.id) as history_count,
         (officer_history_count(o.id) = 0 and o.is_supervisor = false) as can_delete
  from officer o
  left join work_group wg on wg.id = o.work_group_id
  where exists (select 1 from officer s where s.id = auth.uid() and s.is_supervisor)
  order by o.sort_order, o.full_name;
$function$;
grant execute on function public.do_list_officers_admin() to authenticated;

-- 5.2 ฝั่ง PIN — คืน json อยู่แล้ว แก้ตรงได้ signature เดิม
create or replace function public.do_supervisor_list_officers_impl(p_officer_id uuid, p_pin text)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare v_off officer%rowtype; v_rows json;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then return json_build_object('ok', false, 'error', 'officer_not_found'); end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then return json_build_object('ok', false, 'error', 'bad_pin'); end if;
  select coalesce(json_agg(row_to_json(t)), '[]'::json) into v_rows
  from (
    select o.id, o.full_name, o.rank_title, o.nickname, o.active, o.is_supervisor, o.login_method,
           (o.pin_hash is null) as needs_pin_setup, o.work_days, o.work_group_id, wg.name as work_group_name,
           officer_history_count(o.id) as history_count,
           (officer_history_count(o.id) = 0 and o.is_supervisor = false) as can_delete
    from officer o
    left join work_group wg on wg.id = o.work_group_id
    order by o.sort_order nulls last, o.full_name
  ) t;
  return json_build_object('ok', true, 'rows', v_rows);
end;
$function$;

-- ============================================================================
-- Verify หลังรัน
--   select proname, count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   where n.nspname='public' and proname in
--     ('officer_history_count','officer_admin_add_json','officer_admin_set_active_json',
--      'officer_admin_remove_json','do_admin_add_officer','do_admin_set_officer_active',
--      'do_admin_remove_officer','do_supervisor_add_officer','do_supervisor_add_officer_impl',
--      'do_supervisor_set_officer_active','do_supervisor_set_officer_active_impl',
--      'do_supervisor_remove_officer','do_supervisor_remove_officer_impl',
--      'do_list_officers_admin','do_supervisor_list_officers_impl')
--   group by proname;   -> ต้องได้ count = 1 ทุกแถว
--
--   ตรรกะกลางต้องเรียกจากภายนอกไม่ได้:
--   select has_function_privilege('anon', 'public.officer_admin_add_json(text,text,text)', 'execute');   -> false
--   select has_function_privilege('anon', 'public.officer_history_count(uuid)', 'execute');              -> false
--   ทางเข้าต้องเรียกได้:
--   select has_function_privilege('anon', 'public.do_supervisor_add_officer(uuid,text,text,text,text)', 'execute'); -> true
-- ============================================================================
