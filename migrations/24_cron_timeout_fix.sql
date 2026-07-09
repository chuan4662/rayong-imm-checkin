-- 24_cron_timeout_fix.sql
-- แก้บั๊ก/ข้อควรระวังที่เจอระหว่างทดสอบ E2E บั๊กรูปกำพร้า (10 ก.ค. 2569, ดู CLAUDE.md ข้อ 2.11 + ข้อ 24.1)
--
-- ปัญหา: cron.schedule เดิมของ 'delete-old-photos-daily' (ตั้งใน 23_photo_retention.sql)
-- เรียก net.http_post โดยไม่ได้ระบุ timeout_milliseconds เลย ใช้ค่า default (5 วินาที)
-- ซึ่งสั้นเกินไปสำหรับฟังก์ชัน delete-old-photos เวอร์ชันใหม่ที่ต้อง recursive-list ไฟล์
-- ทั้งบัคเก็ตเพื่อทำ orphan sweep (ใช้เวลานานกว่า 5 วิ) ทำให้ net._http_response.timed_out
-- เป็น true ทุกครั้งที่เรียก แม้ฟังก์ชันฝั่ง server จะทำงานเสร็จสมบูรณ์จริงก็ตาม
-- (ยืนยันจากผลทดสอบจริงใน CLAUDE.md ข้อ 24.1 — เรียกครั้งแรก timeout แต่ orphan ถูกลบจริง)
-- ผลกระทบ: ไม่กระทบผลลัพธ์จริงของ cron job เอง (เป็น fire-and-forget การลบไฟล์ยังสำเร็จ
-- ตามปกติ) แต่ทำให้ net._http_response.content/status_code เป็น NULL ทุกคืน ทำให้ monitor
-- ผลจาก log ยากขึ้น/เข้าใจผิดว่าฟังก์ชันพังได้
--
-- ทางแก้: เรียก cron.schedule() ซ้ำด้วยชื่อ job เดิม ('delete-old-photos-daily') และ schedule
-- เดิม ('0 19 * * *' = 02:00 น. เวลาไทย) แต่เพิ่ม timeout_milliseconds := 60000 (60 วินาที)
-- ใน net.http_post — pg_cron จะอัปเดต command ของ job เดิมแทนที่จะสร้าง job ใหม่ (jobid คงเดิม)

select cron.schedule(
  'delete-old-photos-daily',
  '0 19 * * *',
  $$
  select net.http_post(
      url := 'https://aamzsbuwfdyljdvwaifb.supabase.co/functions/v1/delete-old-photos',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer sb_publishable_5LSUhgfmbb90ckwvNbJwgw_wR2z0ik_',
        'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 60000
  ) as request_id;
  $$
);

-- รันจริงแล้ว 10 ก.ค. 2569 ผ่าน SQL Editor (Claude in Chrome) — verify ผ่านหมด:
-- select jobid, jobname, schedule, active, command::text like '%timeout_milliseconds%' as has_timeout
-- from cron.job where jobname = 'delete-old-photos-daily';
-- ผลลัพธ์: jobid=1 (ไม่เปลี่ยน), jobname='delete-old-photos-daily', schedule='0 19 * * *' (ไม่เปลี่ยน),
-- active=true, has_timeout=true — job เดิมถูกอัปเดต ไม่ได้สร้าง job ใหม่ซ้อน
