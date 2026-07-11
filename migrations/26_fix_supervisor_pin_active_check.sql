-- =====================================================================
-- Migration 26: แก้บั๊ก check_and_count_pin บล็อกหัวหน้าที่ล็อกอินด้วย PIN
-- วันที่รัน: 11 ก.ค. 2569 (emergency hotfix นอกแผน — เจอจากรายงานจริงของเจ้าของ)
-- ผู้ทำ: agent session (รันตรงผ่าน SQL Editor เพราะเป็น one-line fix เล็กมาก
--        ไม่ผ่าน service_role fetch เหมือน migration 25)
--
-- ⚠️ หมายเหตุเลข migration: 90_ROADMAP_v2_PLAN.md เดิมจอง "26" ไว้ให้ P1.1
-- (work_group + team coverage) แต่เลขนี้ถูกใช้ไปกับ hotfix ฉุกเฉินนี้ก่อนแล้ว
-- (รูปแบบเดียวกับที่ 24 เคยถูก cron timeout fix แซงคิวมาก่อน P0.3)
-- P1.1 เลื่อนเป็น migration 27, P2.2 เลื่อนเป็น 28, P2.3 เลื่อนเป็น 29, P3.1 เลื่อนเป็น 30
-- ดูตารางที่อัปเดตแล้วใน 90_ROADMAP_v2_PLAN.md ข้อ 8
--
-- อาการที่เจ้าของรายงาน: พ.ต.ท.หญิง ศุภัตรา (หัวหน้า login_method='pin') เข้า
-- report.html ไม่ได้ ขึ้น "ไม่พบชื่อนี้ในระบบ หรือถูกปิดใช้งาน" (error officer_not_found)
-- ทั้งที่ dashboard.html (ชวนชัย) ยังโชว์ว่าบัญชียัง active ปกติ
--
-- สาเหตุ (ยืนยันจาก pg_get_functiondef จริง): migration 25 (P0.3 PIN rate
-- limiting) เพิ่ม check_and_count_pin() ที่เช็ก
--   SELECT * INTO v_off FROM public.officer WHERE id = p_officer_id AND active = true;
-- แต่บัญชีหัวหน้าที่ล็อกอินด้วย PIN (ศุภัตรา, ผู้ช่วยแอดมิน) มี active = false
-- โดยตั้งใจมาตั้งแต่ migration 11 (กันไม่ให้โผล่ในดรอปดาวน์เช็กอินของ index.html)
-- จึงตกเงื่อนไขนี้เสมอ ไม่ว่า PIN จะถูกหรือผิด -> ได้ officer_not_found ทุกครั้ง
--
-- ผลกระทบที่แท้จริงกว้างกว่าที่รายงานตอนแรก: check_and_count_pin เป็นฟังก์ชัน
-- กลางที่ RPC ตระกูล do_supervisor_* ทั้งหมด (20 จาก 21 ฟังก์ชันใน migration 25)
-- เรียกใช้ร่วมกัน ดังนั้นไม่ใช่แค่ "ล็อกอินไม่ได้" แต่ทุกการกระทำของหัวหน้า PIN
-- (ดูมอตโต้, override สถานะ, จัดการวันหยุด, รีเซ็ต PIN คนอื่น ฯลฯ) พังหมดตั้งแต่
-- migration 25 รัน (10 ก.ค. 2569) จนถึงตอนแก้นี้ (11 ก.ค. 2569) — เดชะบุญที่
-- ทดสอบ E2E ตอน migration 25 ใช้ officer ทดสอบที่ active=true (ไม่ใช่ PIN
-- supervisor จริง) จึงไม่เจอบั๊กนี้ตอนทดสอบ
--
-- ทำไมไม่กระทบ ชวนชัย: login_method='auth' ไม่เคยเรียก check_and_count_pin เลย
-- (ใช้ Supabase Auth session ตรง ไม่มี p_pin) จึงไม่โดนบั๊กนี้
--
-- ทางแก้: เปลี่ยนเงื่อนไขเป็น "active = true OR is_supervisor = true" —
-- เจ้าหน้าที่ทั่วไปยังต้อง active=true เหมือนเดิม (ป้องกันคนที่ถูกปิดใช้งานแล้ว)
-- แต่บัญชีหัวหน้า (is_supervisor=true) ผ่านเงื่อนไขนี้ได้เสมอไม่ว่า active จะเป็นเท่าไหร่
-- ตรงกับดีไซน์เดิมที่ตั้งใจให้ active=false เฉพาะเพื่อกันโผล่ในดรอปดาวน์เช็กอิน
-- ไม่ได้ตั้งใจให้เป็นการปิดกั้นสิทธิ์ล็อกอินของหัวหน้าเอง
-- =====================================================================

CREATE OR REPLACE FUNCTION public.check_and_count_pin(p_officer_id uuid, p_pin text)
RETURNS TABLE(ok boolean, error text, locked_until timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $body$
DECLARE
  v_off public.officer%ROWTYPE;
  v_max_fail int := 5;
  v_lock_minutes int := 15;
BEGIN
  SELECT * INTO v_off FROM public.officer WHERE id = p_officer_id AND (active = true OR is_supervisor = true);
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'officer_not_found'::text, NULL::timestamptz;
    RETURN;
  END IF;

  IF v_off.pin_locked_until IS NOT NULL AND v_off.pin_locked_until > now() THEN
    RETURN QUERY SELECT false, 'pin_locked'::text, v_off.pin_locked_until;
    RETURN;
  END IF;

  IF v_off.pin_hash IS NULL OR v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) THEN
    UPDATE public.officer
       SET pin_fail_count = pin_fail_count + 1,
           pin_locked_until = CASE WHEN pin_fail_count + 1 >= v_max_fail
                                    THEN now() + (v_lock_minutes || ' minutes')::interval
                                    ELSE pin_locked_until END
     WHERE id = p_officer_id
     RETURNING pin_locked_until INTO v_off.pin_locked_until;

    IF v_off.pin_locked_until IS NOT NULL AND v_off.pin_locked_until > now() THEN
      RETURN QUERY SELECT false, 'pin_locked'::text, v_off.pin_locked_until;
    ELSE
      RETURN QUERY SELECT false, 'bad_pin'::text, NULL::timestamptz;
    END IF;
    RETURN;
  END IF;

  UPDATE public.officer SET pin_fail_count = 0, pin_locked_until = NULL WHERE id = p_officer_id;
  RETURN QUERY SELECT true, NULL::text, NULL::timestamptz;
END;
$body$;

-- ไม่ต้องรัน REVOKE/GRANT ซ้ำ — CREATE OR REPLACE ไม่กระทบสิทธิ์ที่ตั้งไว้แล้วจาก migration 25
-- (REVOKE ALL ... FROM PUBLIC, anon, authenticated / GRANT EXECUTE ... TO service_role ยังอยู่ครบ)

-- =====================================================================
-- ผลการทดสอบจริง (11 ก.ค. 2569):
--   1. select ... from officer where full_name ilike '%ศุภัตรา%'
--      -> ยืนยัน active=false, is_supervisor=true, supervisor_enabled=true,
--         login_method='pin', has_pin=true, pin_fail_count=0 (ก่อนแก้)
--   2. อ่าน pg_get_functiondef(check_and_count_pin) จริง -> ยืนยันบรรทัด
--      "WHERE id = p_officer_id AND active = true;" คือสาเหตุ (line 12 ของฟังก์ชัน)
--   3. รัน CREATE OR REPLACE ด้านบนผ่าน SQL Editor -> verify ผลจริงด้วย
--      pg_get_functiondef อีกครั้ง เห็นเงื่อนไขใหม่ "(active = true OR is_supervisor = true)"
--   4. เรียก do_supervisor_get_today ผ่าน REST (publishable key) ด้วย PIN ผิด "0000"
--      -> ได้ {"ok":false,"error":"bad_pin"} (ไม่ใช่ officer_not_found อีกต่อไป) ✅
--   5. เรียก do_supervisor_list_mottos ด้วยวิธีเดียวกัน -> ได้ bad_pin เช่นกัน ✅
--      (ยืนยันว่า RPC อื่นที่ใช้ check_and_count_pin ร่วมกันก็หายด้วย ไม่ต้องแก้แยก)
--   6. ตรวจ settings.service_motto_1/2/3 -> ข้อความที่เจ้าของตั้งไว้ยังอยู่ครบ
--      ไม่ได้หายไปไหน แค่โหลดไม่ขึ้นตอน RPC ยัง error อยู่ (ฝั่ง JS จับ error แบบเงียบ
--      ไม่โชว์ error banner ใดๆ — ดู loadMottoAdmin() ใน report.html/dashboard.html)
--   7. UPDATE officer SET pin_fail_count=0, pin_locked_until=null WHERE id=<ศุภัตรา>
--      -> ล้างผลจากการทดสอบ PIN ผิดในข้อ 4 ทิ้ง ไม่ให้ตกค้างกระทบบัญชีจริง
--   8. เจ้าของยืนยันเองว่าล็อกอินได้ปกติแล้วหลังแก้ (ทดสอบจริงจากฝั่งเจ้าของ ไม่ใช่ agent จำลอง)
--
-- ไม่พบ "active = true" อื่นที่กระทบ caller เอง (ที่เจอเพิ่มใน do_supervisor_*_impl
-- บางตัวเป็นแค่ตัวแปรชื่อ v_active_slot ของฟีเจอร์ม็อตโต้ ไม่เกี่ยวกับ permission check)
-- =====================================================================
