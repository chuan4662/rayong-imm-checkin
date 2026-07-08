-- ============================================================
-- เฟส A — สคริปต์ทดสอบ (รันหลัง 01 และ 02 สำเร็จแล้ว)
-- เกณฑ์ผ่านเฟส A ตาม spec ข้อ 10:
--   1) เรียก do_check_in แล้ว insert ได้จริง
--   2) เรียกซ้ำวันเดียวกัน -> error already_checked_in
--   3) status ตรงกับเวลา Bangkok จริง (ไม่ใช่ UTC)
-- ============================================================

-- ทดสอบ 1: รายชื่อเจ้าหน้าที่ที่ anon เห็นได้ (ไม่มี pin_hash ปน)
select public.do_list_officers();

-- ทดสอบ 2: PIN ผิด -> ต้องได้ error bad_pin
select public.do_check_in(
  (select id from officer where full_name = 'ทดสอบ สอง'),
  '0000',
  'test/officer2/wrong-pin.jpg',
  null, null, null
);

-- ทดสอบ 3: เช็กอินสำเร็จ (PIN ถูก, มีพิกัด)
select public.do_check_in(
  (select id from officer where full_name = 'ทดสอบ หนึ่ง'),
  '1234',
  'test/officer1/test1.jpg',
  12.723990, 101.140954,
  'ทดสอบระบบเฟส A'
);

-- ทดสอบ 4: เช็กอินซ้ำวันเดียวกัน -> ต้องได้ error already_checked_in
select public.do_check_in(
  (select id from officer where full_name = 'ทดสอบ หนึ่ง'),
  '1234',
  'test/officer1/test2.jpg',
  12.723990, 101.140954,
  null
);

-- ทดสอบ 5: เช็กอินไม่มีพิกัด (จำลองผู้ใช้ปฏิเสธ GPS) -> ต้องยัง insert ได้ distance_m = null
select public.do_check_in(
  (select id from officer where full_name = 'ทดสอบ สอง'),
  '1234',
  'test/officer2/no-gps.jpg',
  null, null, null
);

-- ทดสอบ 6: ตรวจสอบผลจริงในตาราง — เทียบ UTC vs Bangkok time ให้เห็นด้วยตา
-- *** จุดสำคัญ: ดูว่า local_date และ status ตรงกับเวลาไทยตอนรัน ไม่ใช่ UTC ***
select
  o.full_name,
  c.checked_in_at as utc_time,
  c.checked_in_at at time zone 'Asia/Bangkok' as bangkok_time,
  c.local_date,
  c.status,
  c.distance_m,
  c.note
from check_in c
join officer o on o.id = c.officer_id
order by c.checked_in_at;

-- ทดสอบ 7 (อ้างอิง): ลองเปลี่ยนเวลาเครื่อง Supabase ไม่ได้ (ตั้งใจ) — ยืนยันว่า
-- checked_in_at มาจาก now() ฝั่งเซิร์ฟเวอร์เท่านั้น ไม่มีช่องให้ client ส่งเวลาเข้ามาเลย
-- (ดูใน do_check_in ว่าไม่มีพารามิเตอร์ p_time ใดๆ)
