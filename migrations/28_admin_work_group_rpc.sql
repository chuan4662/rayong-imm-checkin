-- ============================================================================
-- Migration 28: P1a — RPC จัดการกลุ่มงาน (auth-only, เฉพาะชวนชัย)
-- รันจริงบน Supabase SQL Editor แล้ว 13 ก.ค. 2569
-- ที่มา: migration 27 มีแค่ RPC "อ่าน" coverage แต่ยังไม่มี RPC ให้ชวนชัย
-- สร้าง/แก้/ลบกลุ่ม หรือมอบสมาชิกเข้ากลุ่ม (ต้องมีก่อนถึงจะเขียน frontend
-- ส่วนจัดการกลุ่มงานใน dashboard.html ได้ — ดู 90_ROADMAP_v2_PLAN.md P1.2)
-- ============================================================================

-- อ่านรายการกลุ่มทั้งหมด (ไม่กรอง is_ot_team — ใช้แสดงในตารางจัดการ)
create or replace function public.do_admin_list_work_groups()
returns table(id uuid, name text, is_ot_team boolean, member_count bigint)
language sql
security definer
set search_path to 'public'
as $function$
  select wg.id, wg.name, wg.is_ot_team, count(o.id) as member_count
  from work_group wg
  left join officer o on o.work_group_id = wg.id
  where exists (select 1 from officer s where s.id = auth.uid() and s.is_supervisor)
  group by wg.id, wg.name, wg.is_ot_team
  order by wg.name;
$function$;

grant execute on function public.do_admin_list_work_groups() to authenticated;


create or replace function public.do_admin_create_work_group(p_name text, p_is_ot_team boolean default false)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_sup boolean;
  v_id uuid;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    return json_build_object('ok', false, 'error', 'name_required');
  end if;
  insert into work_group(name, is_ot_team) values (trim(p_name), coalesce(p_is_ot_team, false))
  returning id into v_id;
  return json_build_object('ok', true, 'id', v_id);
exception when unique_violation then
  return json_build_object('ok', false, 'error', 'duplicate_name');
end;
$function$;

grant execute on function public.do_admin_create_work_group(text, boolean) to authenticated;


create or replace function public.do_admin_update_work_group(p_id uuid, p_name text, p_is_ot_team boolean)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    return json_build_object('ok', false, 'error', 'name_required');
  end if;
  update work_group set name = trim(p_name), is_ot_team = coalesce(p_is_ot_team, false) where id = p_id;
  if not found then
    return json_build_object('ok', false, 'error', 'group_not_found');
  end if;
  return json_build_object('ok', true);
exception when unique_violation then
  return json_build_object('ok', false, 'error', 'duplicate_name');
end;
$function$;

grant execute on function public.do_admin_update_work_group(uuid, text, boolean) to authenticated;


-- ลบกลุ่ม — unassign officer ทุกคนในกลุ่มก่อน (work_group_id = null) แล้วค่อยลบแถวกลุ่ม
create or replace function public.do_admin_delete_work_group(p_id uuid)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  update officer set work_group_id = null where work_group_id = p_id;
  delete from work_group where id = p_id;
  if not found then
    return json_build_object('ok', false, 'error', 'group_not_found');
  end if;
  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_admin_delete_work_group(uuid) to authenticated;


-- มอบ/ถอด officer เข้า-ออกกลุ่ม (p_work_group_id = null เพื่อถอดออกจากกลุ่ม)
create or replace function public.do_admin_set_officer_group(p_officer_id uuid, p_work_group_id uuid)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;
  update officer set work_group_id = p_work_group_id where id = p_officer_id;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  return json_build_object('ok', true);
end;
$function$;

grant execute on function public.do_admin_set_officer_group(uuid, uuid) to authenticated;


-- ============================================================================
-- Verify ที่ทำจริงหลังรัน:
--   select proname, count(*), bool_and(has_function_privilege('authenticated', oid, 'execute'))
--   from pg_proc where proname in (
--     'do_admin_list_work_groups','do_admin_create_work_group','do_admin_update_work_group',
--     'do_admin_delete_work_group','do_admin_set_officer_group'
--   ) group by proname;
--   -- ทุกตัว count=1, auth_ok=true (ยืนยันแล้ว)
-- ============================================================================
