-- แก้บั๊ก: "infinite recursion detected in policy for relation officer"
-- สาเหตุ: policy officer_read_supervisor ตรวจสอบสิทธิ์ด้วยการ query ตาราง officer ซ้ำเข้าไปในตัวเอง
--        (select 1 from officer o where o.id = auth.uid() ...) ภายใน policy ของตาราง officer เอง
--        ทำให้ Postgres เรียก policy ตัวเองซ้ำไม่รู้จบ
-- แก้โดย: ย้าย logic ตรวจสอบไปไว้ในฟังก์ชัน SECURITY DEFINER แยกต่างหาก
--        (SECURITY DEFINER รันด้วยสิทธิ์เจ้าของฟังก์ชัน ซึ่งข้าม RLS ของ query ภายในฟังก์ชันได้ จึงไม่วน)

create or replace function public.is_supervisor()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    (select o.is_supervisor from officer o where o.id = auth.uid()),
    false
  );
$$;
grant execute on function public.is_supervisor() to authenticated;

drop policy if exists officer_read_supervisor on public.officer;
create policy officer_read_supervisor on public.officer
  for select to authenticated
  using (public.is_supervisor());

drop policy if exists checkin_read_supervisor on public.check_in;
create policy checkin_read_supervisor on public.check_in
  for select to authenticated
  using (public.is_supervisor());
