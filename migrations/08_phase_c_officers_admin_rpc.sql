-- ============================================================
-- เฟส C: RPC สำหรับหน้าแดชบอร์ดหัวหน้า — ดูรายชื่อเจ้าหน้าที่ทั้งหมด
-- (ไม่ select ตรงจากตาราง officer เพราะจะดึง pin_hash ติดมาด้วย แม้จะ hash แล้วก็ไม่ควรหลุดออกจาก DB โดยไม่จำเป็น)
-- คืนเฉพาะ flag needs_pin_setup แทน ไม่คืน pin_hash ดิบ
-- ============================================================
create or replace function public.do_list_officers_admin()
returns table (
  id uuid,
  full_name text,
  rank_title text,
  is_supervisor boolean,
  active boolean,
  needs_pin_setup boolean
)
language sql
security definer
set search_path = public
as $$
  select o.id, o.full_name, o.rank_title, o.is_supervisor, o.active, (o.pin_hash is null) as needs_pin_setup
  from officer o
  where exists (select 1 from officer s where s.id = auth.uid() and s.is_supervisor)
  order by o.full_name;
$$;

grant execute on function public.do_list_officers_admin() to authenticated;
