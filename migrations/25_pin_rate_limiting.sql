-- =====================================================================
-- Migration 25: PIN rate limiting (P0.3 ตาม 90_ROADMAP_v2_PLAN.md)
-- วันที่รัน: 10 ก.ค. 2569
-- ผู้ทำ: agent session (ใช้ service_role key ที่เจ้าของมอบให้ครั้งเดียว
--        เรียกผ่าน Chrome fetch() แทนการพิมพ์ตรงใน SQL Editor ทั้งหมด
--        เพื่อกันบั๊ก auto-bracket-closing ของ SQL Editor กับ SQL ก้อนใหญ่)
--
-- คำขอเดิม: กันโจมตีแบบ brute-force เดา PIN (เดิมไม่มีการจำกัดจำนวนครั้งที่กรอกผิดเลย)
--
-- กลไก: กรอก PIN ผิดติดกันครบ 5 ครั้ง (ต่อ officer 1 คน) จะถูกล็อกชั่วคราว 15 นาที
--        แม้กรอกถูกก็ยังถูกบล็อกจนกว่าจะพ้นเวลาล็อก (กันเคส "เดามั่วจนเจอ" ระหว่างถูกนับ)
--        กรอกถูกครั้งแรกหลังไม่ได้ถูกล็อก -> รีเซ็ต fail_count กลับเป็น 0 ทันที
--
-- ทำไมเลือก "wrapper function" แทนแก้ business logic เดิมทั้ง 21 ฟังก์ชันตรงๆ:
--   เปลี่ยนชื่อฟังก์ชันเดิม do_X -> do_X_impl (RENAME ไม่กระทบ body เลย)
--   แล้วสร้าง do_X ใหม่เป็น thin wrapper ที่เรียก check_and_count_pin() ก่อนเสมอ
--   ถ้าไม่ผ่านค่อย delegate ต่อไปยัง do_X_impl(...) เดิมทุกอย่าง
--   -> ไม่ต้องแตะ business logic ภายในของแต่ละฟังก์ชันเลยแม้แต่บรรทัดเดียว ความเสี่ยง regression ต่ำมาก
--   -> ต้อง REVOKE EXECUTE ของ _impl จาก PUBLIC/anon/authenticated ด้วย (เหลือแค่ postgres/service_role)
--      กันไม่ให้ใครเรียก _impl ตรงๆ ผ่าน REST เพื่อข้ามการนับ rate limit ไปเลย
--
-- ยืนยันแล้วว่ามี 21 ฟังก์ชันที่เช็ก PIN จริง (กรอง pg_proc.prosrc ILIKE '%crypt(p_pin%'):
--   do_check_in, do_get_my_month_stats, do_get_today_status, do_save_remark,
--   do_supervisor_add_holiday, do_supervisor_delete_holiday,
--   do_supervisor_delete_stats_period_override, do_supervisor_get_absentees,
--   do_supervisor_get_history, do_supervisor_get_today, do_supervisor_list_holidays,
--   do_supervisor_list_mottos, do_supervisor_list_officers,
--   do_supervisor_list_stats_period_overrides, do_supervisor_override,
--   do_supervisor_reset_pin, do_supervisor_set_motto, do_supervisor_set_officer_workdays,
--   do_supervisor_set_retention_hold, do_supervisor_set_stats_period_override,
--   do_supervisor_verify_pin_for_photo
--
-- (ฟังก์ชันอื่นที่ "ดูเหมือน" เกี่ยวกับ PIN แต่ไม่เข้าเกณฑ์ ไม่ต้อง wrap เพราะไม่มี crypt(p_pin
--  เช่น do_set_initial_pin/do_supervisor_set_initial_pin (ตั้ง PIN ครั้งแรก ไม่มี PIN เดิมให้เช็ก),
--  do_reset_pin/ฝั่ง auth (ใช้ auth.uid() ไม่ใช้ p_pin), do_list_officers/do_list_supervisors (ไม่รับ PIN)
--
-- ⚠️ พบช่องโหว่เพิ่มเติมระหว่างทำ (แก้ไปพร้อมกันในไฟล์นี้):
--   do_reset_pin (auth-based) และ do_supervisor_reset_pin_impl เดิม set pin_hash = null
--   ตอนรีเซ็ต แต่ไม่ได้ clear pin_fail_count/pin_locked_until ไปด้วย
--   -> ถ้า officer ถูกล็อกอยู่แล้วโดนรีเซ็ต PIN ใหม่ จะยังล็อกต่อแม้ตั้ง PIN ใหม่ถูกต้องแล้วก็ตาม
--   แก้โดยเพิ่ม pin_fail_count = 0, pin_locked_until = null เข้าไปใน UPDATE เดียวกันทั้ง 2 ฟังก์ชัน
-- =====================================================================

-- ---------- Step 1: คอลัมน์ใหม่บน officer ----------
ALTER TABLE public.officer ADD COLUMN IF NOT EXISTS pin_fail_count int NOT NULL DEFAULT 0;
ALTER TABLE public.officer ADD COLUMN IF NOT EXISTS pin_locked_until timestamptz;

-- ---------- Step 2: ฟังก์ชันกลางเช็ก + นับ PIN ผิด ----------
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
  SELECT * INTO v_off FROM public.officer WHERE id = p_officer_id AND active = true;
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

REVOKE ALL ON FUNCTION public.check_and_count_pin(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_count_pin(uuid, text) TO service_role;

-- ---------- Step 3: RENAME ของเดิม -> _impl + REVOKE + สร้าง wrapper ใหม่ (x21) ----------
-- รูปแบบซ้ำกันทั้ง 21 ฟังก์ชัน ต่างกันแค่ชื่อ/พารามิเตอร์/ค่า default ตามฟังก์ชันเดิม

ALTER FUNCTION public.do_check_in(p_officer_id uuid, p_pin text, p_photo_path text, p_lat double precision, p_lng double precision, p_note text, p_ready boolean) RENAME TO do_check_in_impl;
REVOKE ALL ON FUNCTION public.do_check_in_impl(p_officer_id uuid, p_pin text, p_photo_path text, p_lat double precision, p_lng double precision, p_note text, p_ready boolean) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_check_in(p_officer_id uuid, p_pin text, p_photo_path text, p_lat double precision, p_lng double precision, p_note text, p_ready boolean)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_check_in_impl(p_officer_id, p_pin, p_photo_path, p_lat, p_lng, p_note, p_ready);
END; $wrap$;

ALTER FUNCTION public.do_get_my_month_stats(p_officer_id uuid, p_pin text) RENAME TO do_get_my_month_stats_impl;
REVOKE ALL ON FUNCTION public.do_get_my_month_stats_impl(p_officer_id uuid, p_pin text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_get_my_month_stats(p_officer_id uuid, p_pin text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_get_my_month_stats_impl(p_officer_id, p_pin);
END; $wrap$;

ALTER FUNCTION public.do_get_today_status(p_officer_id uuid, p_pin text) RENAME TO do_get_today_status_impl;
REVOKE ALL ON FUNCTION public.do_get_today_status_impl(p_officer_id uuid, p_pin text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_get_today_status(p_officer_id uuid, p_pin text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_get_today_status_impl(p_officer_id, p_pin);
END; $wrap$;

ALTER FUNCTION public.do_save_remark(p_officer_id uuid, p_pin text, p_remark text) RENAME TO do_save_remark_impl;
REVOKE ALL ON FUNCTION public.do_save_remark_impl(p_officer_id uuid, p_pin text, p_remark text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_save_remark(p_officer_id uuid, p_pin text, p_remark text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_save_remark_impl(p_officer_id, p_pin, p_remark);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_add_holiday(p_officer_id uuid, p_pin text, p_holiday_date date, p_description text) RENAME TO do_supervisor_add_holiday_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_add_holiday_impl(p_officer_id uuid, p_pin text, p_holiday_date date, p_description text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_add_holiday(p_officer_id uuid, p_pin text, p_holiday_date date, p_description text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_add_holiday_impl(p_officer_id, p_pin, p_holiday_date, p_description);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_delete_holiday(p_officer_id uuid, p_pin text, p_holiday_id uuid) RENAME TO do_supervisor_delete_holiday_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_delete_holiday_impl(p_officer_id uuid, p_pin text, p_holiday_id uuid) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_delete_holiday(p_officer_id uuid, p_pin text, p_holiday_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_delete_holiday_impl(p_officer_id, p_pin, p_holiday_id);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_delete_stats_period_override(p_officer_id uuid, p_pin text, p_year smallint, p_month smallint) RENAME TO do_supervisor_delete_stats_period_override_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_delete_stats_period_override_impl(p_officer_id uuid, p_pin text, p_year smallint, p_month smallint) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_delete_stats_period_override(p_officer_id uuid, p_pin text, p_year smallint, p_month smallint)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_delete_stats_period_override_impl(p_officer_id, p_pin, p_year, p_month);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_get_absentees(p_officer_id uuid, p_pin text, p_date date) RENAME TO do_supervisor_get_absentees_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_get_absentees_impl(p_officer_id uuid, p_pin text, p_date date) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_get_absentees(p_officer_id uuid, p_pin text, p_date date DEFAULT NULL::date)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_get_absentees_impl(p_officer_id, p_pin, p_date);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_get_history(p_officer_id uuid, p_pin text, p_start_date date, p_end_date date, p_target_officer_id uuid) RENAME TO do_supervisor_get_history_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_get_history_impl(p_officer_id uuid, p_pin text, p_start_date date, p_end_date date, p_target_officer_id uuid) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_get_history(p_officer_id uuid, p_pin text, p_start_date date, p_end_date date, p_target_officer_id uuid DEFAULT NULL::uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_get_history_impl(p_officer_id, p_pin, p_start_date, p_end_date, p_target_officer_id);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_get_today(p_officer_id uuid, p_pin text) RENAME TO do_supervisor_get_today_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_get_today_impl(p_officer_id uuid, p_pin text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_get_today(p_officer_id uuid, p_pin text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_get_today_impl(p_officer_id, p_pin);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_list_holidays(p_officer_id uuid, p_pin text) RENAME TO do_supervisor_list_holidays_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_list_holidays_impl(p_officer_id uuid, p_pin text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_list_holidays(p_officer_id uuid, p_pin text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_list_holidays_impl(p_officer_id, p_pin);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_list_mottos(p_officer_id uuid, p_pin text) RENAME TO do_supervisor_list_mottos_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_list_mottos_impl(p_officer_id uuid, p_pin text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_list_mottos(p_officer_id uuid, p_pin text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_list_mottos_impl(p_officer_id, p_pin);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_list_officers(p_officer_id uuid, p_pin text) RENAME TO do_supervisor_list_officers_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_list_officers_impl(p_officer_id uuid, p_pin text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_list_officers(p_officer_id uuid, p_pin text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_list_officers_impl(p_officer_id, p_pin);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_list_stats_period_overrides(p_officer_id uuid, p_pin text) RENAME TO do_supervisor_list_stats_period_overrides_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_list_stats_period_overrides_impl(p_officer_id uuid, p_pin text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_list_stats_period_overrides(p_officer_id uuid, p_pin text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_list_stats_period_overrides_impl(p_officer_id, p_pin);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_override(p_officer_id uuid, p_pin text, p_check_in_id uuid, p_new_status text, p_reason text) RENAME TO do_supervisor_override_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_override_impl(p_officer_id uuid, p_pin text, p_check_in_id uuid, p_new_status text, p_reason text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_override(p_officer_id uuid, p_pin text, p_check_in_id uuid, p_new_status text, p_reason text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_override_impl(p_officer_id, p_pin, p_check_in_id, p_new_status, p_reason);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_reset_pin(p_officer_id uuid, p_pin text, p_target_officer_id uuid) RENAME TO do_supervisor_reset_pin_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_reset_pin_impl(p_officer_id uuid, p_pin text, p_target_officer_id uuid) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_reset_pin(p_officer_id uuid, p_pin text, p_target_officer_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_reset_pin_impl(p_officer_id, p_pin, p_target_officer_id);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_set_motto(p_officer_id uuid, p_pin text, p_slot smallint, p_new_motto text) RENAME TO do_supervisor_set_motto_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_set_motto_impl(p_officer_id uuid, p_pin text, p_slot smallint, p_new_motto text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_set_motto(p_officer_id uuid, p_pin text, p_slot smallint, p_new_motto text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_set_motto_impl(p_officer_id, p_pin, p_slot, p_new_motto);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_set_officer_workdays(p_officer_id uuid, p_pin text, p_target_officer_id uuid, p_work_days smallint[]) RENAME TO do_supervisor_set_officer_workdays_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_set_officer_workdays_impl(p_officer_id uuid, p_pin text, p_target_officer_id uuid, p_work_days smallint[]) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_set_officer_workdays(p_officer_id uuid, p_pin text, p_target_officer_id uuid, p_work_days smallint[])
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_set_officer_workdays_impl(p_officer_id, p_pin, p_target_officer_id, p_work_days);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_set_retention_hold(p_officer_id uuid, p_pin text, p_check_in_id uuid, p_hold boolean) RENAME TO do_supervisor_set_retention_hold_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_set_retention_hold_impl(p_officer_id uuid, p_pin text, p_check_in_id uuid, p_hold boolean) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_set_retention_hold(p_officer_id uuid, p_pin text, p_check_in_id uuid, p_hold boolean)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_set_retention_hold_impl(p_officer_id, p_pin, p_check_in_id, p_hold);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_set_stats_period_override(p_officer_id uuid, p_pin text, p_year smallint, p_month smallint, p_start_date date) RENAME TO do_supervisor_set_stats_period_override_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_set_stats_period_override_impl(p_officer_id uuid, p_pin text, p_year smallint, p_month smallint, p_start_date date) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_set_stats_period_override(p_officer_id uuid, p_pin text, p_year smallint, p_month smallint, p_start_date date)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_set_stats_period_override_impl(p_officer_id, p_pin, p_year, p_month, p_start_date);
END; $wrap$;

ALTER FUNCTION public.do_supervisor_verify_pin_for_photo(p_officer_id uuid, p_pin text, p_photo_path text) RENAME TO do_supervisor_verify_pin_for_photo_impl;
REVOKE ALL ON FUNCTION public.do_supervisor_verify_pin_for_photo_impl(p_officer_id uuid, p_pin text, p_photo_path text) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.do_supervisor_verify_pin_for_photo(p_officer_id uuid, p_pin text, p_photo_path text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $wrap$
DECLARE v_check record;
BEGIN
  SELECT * INTO v_check FROM check_and_count_pin(p_officer_id, p_pin);
  IF NOT v_check.ok THEN RETURN json_build_object('ok', false, 'error', v_check.error, 'locked_until', v_check.locked_until); END IF;
  RETURN do_supervisor_verify_pin_for_photo_impl(p_officer_id, p_pin, p_photo_path);
END; $wrap$;

-- ---------- Step 4: แก้ do_reset_pin / do_supervisor_reset_pin_impl ให้ clear lockout ด้วยตอนรีเซ็ต PIN ----------
-- (ช่องโหว่ที่พบเพิ่มระหว่างทำ migration นี้ — ดูหมายเหตุด้านบน)

CREATE OR REPLACE FUNCTION public.do_reset_pin(p_officer_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fix$
declare v_is_sup boolean;
begin
  select is_supervisor into v_is_sup from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  update officer set pin_hash = null, pin_fail_count = 0, pin_locked_until = null where id = p_officer_id;
  return json_build_object('ok', true);
end;
$fix$;

CREATE OR REPLACE FUNCTION public.do_supervisor_reset_pin_impl(p_officer_id uuid, p_pin text, p_target_officer_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fix$
declare v_off officer%rowtype;
begin
  select * into v_off from officer where id = p_officer_id and is_supervisor = true and login_method = 'pin';
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;
  if v_off.pin_hash is null or v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  update officer set pin_hash = null, pin_fail_count = 0, pin_locked_until = null where id = p_target_officer_id;
  return json_build_object('ok', true);
end;
$fix$;

-- =====================================================================
-- ผลการทดสอบ E2E จริง (10 ก.ค. 2569, ใช้แถวทดสอบชั่วคราวแล้วลบทิ้ง):
--   1. สร้าง officer ทดสอบ PIN "1234" -> เรียก do_get_today_status ด้วย PIN ผิด "0000" 4 ครั้ง
--      -> ได้ bad_pin ทั้ง 4 ครั้ง, ครั้งที่ 5 -> ได้ pin_locked (pin_fail_count=5, locked_until = +15 นาที)
--      -> ครั้งที่ 6 (ยังอยู่ในช่วงล็อก) -> ยังได้ pin_locked เหมือนเดิม
--   2. ลองใส่ PIN ถูก "1234" ระหว่างยังถูกล็อกอยู่ -> ยังได้ pin_locked (ไม่ bypass แม้ PIN ถูก) ✅
--   3. จำลองการปลดล็อก (เท่ากับผลของ do_reset_pin ที่แก้ใหม่) -> pin_fail_count=0, locked_until=null
--   4. ใส่ PIN ถูก "1234" หลังปลดล็อก -> ผ่านเข้า business logic จริง (ได้ "not_checked_in" ตามปกติ) ✅
--   5. ยืนยัน pin_fail_count/pin_locked_until กลับเป็น 0/null หลังผ่านสำเร็จ ✅
--   6. ยืนยันเรียก do_get_today_status_impl ตรงๆ ผ่าน anon key -> ถูก reject 401 permission denied ✅
--      (ปิดช่องทางข้าม rate limit ผ่านการเรียก _impl ตรงๆ ได้จริง)
--   7. ลบ officer ทดสอบทิ้งหมดแล้ว ไม่เหลือข้อมูลทดสอบค้างในระบบจริง
--
-- Frontend ที่แก้เพิ่ม (คนละไฟล์ ไม่ใช่ SQL แต่เกี่ยวเนื่องกัน):
--   index.html, report.html — เพิ่ม formatPinLockedMessage() + เพิ่ม branch เช็ก
--   error code "pin_locked" ในทุกจุดที่เรียก RPC ที่รับ p_pin (login, checkin, remark,
--   retention hold, override, reset pin, workdays, holidays, stats period, motto)
--   แทนที่จะโชว์โค้ดดิบ "pin_locked" ให้ผู้ใช้เห็น
--   (dashboard.html ไม่ต้องแก้ เพราะเป็น auth-based ล้วน ไม่มี RPC ตัวไหนรับ p_pin เลย)
--
-- Cleanup: ฟังก์ชันชั่วคราว tmp_get_functiondef / tmp_query_json / tmp_exec_sql
-- ที่สร้างไว้ช่วยดึง signature และรัน migration นี้ผ่าน REST ถูก DROP ออกจากระบบแล้วหลังใช้งานเสร็จ
-- ไม่มีฟังก์ชันสิทธิ์สูงตกค้างอยู่ในระบบ
-- =====================================================================
