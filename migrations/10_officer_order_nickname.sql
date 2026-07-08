-- ============================================================
-- เพิ่มชื่อเล่น + ลำดับการแสดงผล ให้ตรงกับเอกสารต้นฉบับ
-- (แก้ตาม feedback: เรียงตามเอกสาร ไม่ใช่ alphabetical, โชว์ "ยศ ชื่อ นามสกุล (ชื่อเล่น)")
-- ============================================================

alter table public.officer add column if not exists nickname text;
alter table public.officer add column if not exists sort_order integer;

update public.officer set nickname = 'ฟาง',  sort_order = 1  where full_name = 'นวลฉวี ศรีบาง';
update public.officer set nickname = 'ธี',   sort_order = 2  where full_name = 'ธีรศักดิ์ ขัตติ';
update public.officer set nickname = 'เต่า', sort_order = 3  where full_name = 'นรินทร์ จูมแพง';
update public.officer set nickname = 'พี',   sort_order = 4  where full_name = 'พีระชัย สมดี';
update public.officer set nickname = 'กฎ',   sort_order = 5  where full_name = 'กรกฏ โครตพัฒน์';
update public.officer set nickname = 'อ้อย', sort_order = 6  where full_name = 'ณฐอร ราชแก้ว';
update public.officer set nickname = 'กิฟ',  sort_order = 7  where full_name = 'ณัฏฐาพร หุนประยูร';
update public.officer set nickname = 'ต้น',  sort_order = 8  where full_name = 'เทพนิมิตร จันทราสินธุ';
update public.officer set nickname = 'มด',   sort_order = 9  where full_name = 'ทชภัท ลียารัตน์';
update public.officer set nickname = 'นก',   sort_order = 10 where full_name = 'กมลชนก สุทธิมาศ';
update public.officer set nickname = 'แม๊ก', sort_order = 11 where full_name = 'รังสิต เทพรักษาฤาชัย';
update public.officer set nickname = 'ฝ้าย', sort_order = 12 where full_name = 'ลดาวรรณ วงศ์เส็ง';
update public.officer set nickname = 'ปอนด์', sort_order = 13 where full_name = 'ภารัณ บุญดำเนิน';
update public.officer set nickname = 'หญิง', sort_order = 14 where full_name = 'จุฑามาศ เพชราเวช';
update public.officer set nickname = 'จอย',  sort_order = 15 where full_name = 'พิชาพรรณ ภิญโญโชคอนันต์';
update public.officer set nickname = 'เม่',  sort_order = 16 where full_name = 'เกศินี นาคแสงทอง';
update public.officer set nickname = 'ปาย',  sort_order = 17 where full_name = 'รุ่งนภา คำเถื่อน';
update public.officer set nickname = 'แพร',  sort_order = 18 where full_name = 'รัชนีกร บุบผาวาส';
update public.officer set nickname = 'อร',   sort_order = 19 where full_name = 'กชพร จี้คีรี';

-- ให้บัญชีทดสอบ/บัญชีที่ไม่มี sort_order (เช่น หัวหน้าที่เพิ่มทีหลัง) ไปต่อท้ายสุด ไม่ปนกับลำดับหลัก
update public.officer set sort_order = 999 where sort_order is null;

-- do_list_officers: คืน nickname เพิ่ม + เรียงตาม sort_order แทน alphabetical
drop function if exists public.do_list_officers();
create or replace function public.do_list_officers()
returns table (id uuid, full_name text, rank_title text, nickname text, needs_pin_setup boolean)
language sql
security definer
set search_path = public
as $$
  select id, full_name, rank_title, nickname, (pin_hash is null) as needs_pin_setup
  from officer
  where active = true
  order by sort_order, full_name;
$$;
grant execute on function public.do_list_officers() to anon;

-- do_list_officers_admin: เรียงตาม sort_order เหมือนกัน + คืน nickname ให้แดชบอร์ดโชว์ด้วย
drop function if exists public.do_list_officers_admin();
create or replace function public.do_list_officers_admin()
returns table (
  id uuid,
  full_name text,
  rank_title text,
  nickname text,
  is_supervisor boolean,
  active boolean,
  needs_pin_setup boolean
)
language sql
security definer
set search_path = public
as $$
  select o.id, o.full_name, o.rank_title, o.nickname, o.is_supervisor, o.active, (o.pin_hash is null) as needs_pin_setup
  from officer o
  where exists (select 1 from officer s where s.id = auth.uid() and s.is_supervisor)
  order by o.sort_order, o.full_name;
$$;
grant execute on function public.do_list_officers_admin() to authenticated;
