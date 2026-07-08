-- เพิ่ม login_method ในผลลัพธ์ do_list_officers_admin ให้แดชบอร์ดของ ชวนชัย (Auth-based)
-- เห็นด้วยว่าใครเข้าด้วย PIN / ใครเข้าด้วย Email เหมือนกับ report.html
create or replace function public.do_list_officers_admin()
returns table (
  id uuid,
  full_name text,
  rank_title text,
  nickname text,
  is_supervisor boolean,
  active boolean,
  login_method text,
  needs_pin_setup boolean
)
language sql
security definer
set search_path = public
as $$
  select o.id, o.full_name, o.rank_title, o.nickname, o.is_supervisor, o.active, o.login_method,
         (o.pin_hash is null) as needs_pin_setup
  from officer o
  where exists (select 1 from officer s where s.id = auth.uid() and s.is_supervisor)
  order by o.sort_order, o.full_name;
$$;
grant execute on function public.do_list_officers_admin() to authenticated;
