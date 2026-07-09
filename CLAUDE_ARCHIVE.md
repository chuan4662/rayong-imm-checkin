# CLAUDE_ARCHIVE.md — ประวัติละเอียดรายฟีเจอร์/บั๊ก (แยกออกจาก CLAUDE.md เพื่อลดขนาดไฟล์หลัก, 9 ก.ค. 2569)

> ไฟล์นี้เก็บ **รายละเอียดเต็มของแต่ละฟีเจอร์/บั๊กที่ปิดงานแล้ว** (ข้อ 9–22 เดิม) ที่เคยอยู่ใน `CLAUDE.md`
> ย้ายออกมาเพราะ `CLAUDE.md` เดิมยาวเกิน 700 บรรทัด ทำให้ agent ต้องอ่าน/เขียนไฟล์ใหญ่ทุกครั้งที่จะ push ขึ้น git ช้าลงมาก
> (สาเหตุหลักคือบั๊ก bash-mount staleness ในข้อ 6.5 ของ `CLAUDE.md` — ยิ่งไฟล์ใหญ่ยิ่งกระทบเยอะ เพราะต้องอ่านผ่าน `Read` tool แบบแบ่งหน้าแทน shell)
>
> **agent ตัวถัดไปไม่จำเป็นต้องอ่านไฟล์นี้ทุกครั้ง** — เปิดเฉพาะตอนต้องการรายละเอียดเชิงลึกของฟีเจอร์ใดฟีเจอร์หนึ่งที่ระบุไว้ใน `CLAUDE.md` (เช่น "ดูรายละเอียดในข้อ 12" หมายถึงหัวข้อ "## 12." ในไฟล์นี้)
> ข้อมูลสถานะปัจจุบัน/กติกาการทำงาน/backlog/migration table/บั๊กที่พบ ยังคงอยู่ใน `CLAUDE.md` หลักตามเดิม ไฟล์นี้เป็นแค่ส่วนเสริมเชิงประวัติ
>
> เลขข้อ (## 9. ถึง ## 22.) คงเดิมตามที่เคยอยู่ใน `CLAUDE.md` ไม่ได้เรียงใหม่ เพื่อให้ลิงก์อ้างอิงเดิมยังใช้ได้

---

## 9. สถานะสีม่วง (เช็กอินไม่สมบูรณ์) — รายละเอียด

- **เกณฑ์**: ห่างจากที่ทำงาน &gt;50 เมตร หรือไม่มีพิกัด GPS (ปฏิเสธ/ปิด GPS) — คำนวณจริงฝั่ง server ใน `do_check_in` เสมอ ไม่เชื่อค่าจาก client
- **UX**: ก่อน submit จริง client เรียก `do_check_distance` (preview อย่างเดียว ไม่ insert) ถ้าเข้าเงื่อนไขม่วง จะเด้ง modal ให้เจ้าหน้าที่ยืนยันอีกครั้งก่อนบันทึกจริง กดยกเลิกได้เพื่อกลับไปแก้ (เช่น เปิด GPS ใหม่)
- **การแสดงผล**: ม่วงเป็นแฟล็กเสริม (`incomplete_checkin` boolean) แสดง**คู่กับ**สีเวลาเดิมเสมอ ไม่ใช่แทนที่ (เช่น 🟡+🟣) — แสดงในหน้าเจ้าหน้าที่ (ผลลัพธ์ + เช็กอินซ้ำ) และตาราง "เช็กอินวันนี้" ของทั้ง dashboard.html และ report.html
- **Verify แล้ว**: ทดสอบ `do_check_distance` ตรงจุด (0m), ไกล (68m → ok เกิน 50), ไม่มีพิกัด (null) ผ่านหมด, deploy ขึ้น Netlify แล้ว 3 ก.ค. 2569

---

## 10. กล่องม็อตโต้ + สถิติส่วนตัวรายเดือน — รายละเอียด

**คำขอเดิม:** เจ้าของอยากได้ (1) กล่องข้อความม็อตโต้/หลักการให้บริการ ที่หัวหน้าทั้ง 3 คนแก้ได้จากหลังบ้าน ตัวหนังสือใหญ่ชัดเจน ให้เจ้าหน้าที่อ่านทุกวัน และ (2) สถิติส่วนตัวหลังเช็กอิน ให้แต่ละคนเห็นว่าตัวเองได้สีอะไรกี่ครั้งในเดือนนี้ เพื่อสร้างความตระหนักรู้ในตัวเอง — อ้างอิงจากภาพหน้าจอ mockup ที่เจ้าของแนบมา (บล็อกม็อตโต้อยู่เหนือบล็อกสถิติ ทั้งคู่อยู่ต่อจากเนื้อหา/ปุ่มเดิม)

**Backend (migration `16_motto_and_monthly_stats.sql`):**
- `settings.service_motto` (text) — ค่าเดียว ไม่มีประวัติย้อนหลังใน v1 (ตามคำขอ)
- `do_get_motto()` — anon เรียกได้ (ให้ทุกคนเห็นข้อความ)
- `do_set_motto(p_new_motto)` — เฉพาะหัวหน้าที่ล็อกอินด้วย Supabase Auth (เช็กผ่าน `is_supervisor()`)
- `do_supervisor_set_motto(p_officer_id, p_pin, p_new_motto)` — เฉพาะหัวหน้าที่ล็อกอินด้วย PIN
- `do_get_my_month_stats(p_officer_id, p_pin)` — ต้องยืนยัน PIN ก่อนเสมอ (เห็นเฉพาะเจ้าของ) นับตามเดือนปัจจุบันของ **เซิร์ฟเวอร์** (Asia/Bangkok) แบบ auto-reset ทุกเดือนใหม่โดยไม่ต้องมี cron ใดๆ (ใช้ `date_trunc('month', now() at time zone tz)` เป็น range เทียบ `local_date`) นับสถานะจาก `coalesce(override_status, status)` (ยึดสถานะจริงหลัง override) และนับ**ม่วงแยกเป็นยอดรวมต่างหาก ไม่ใช่บรรทัดที่ 5 คู่ขนานกับ 4 สีเวลา** เพราะม่วงซ้อนอยู่กับสีใดสีหนึ่งเสมอ (ถ้านับคู่ขนานผลรวมจะเกินจำนวนวันจริง)
- **Verify แล้ว**: ทดสอบด้วยแถวทดสอบชั่วคราว (officer test + check_in 3 แถว: เขียว/เหลือง+ม่วง/แดง) ได้ผล `{green:1, yellow:1, orange:0, red:1, incomplete:1, total:3}` ตรงตามคาด, PIN ผิดถูก reject ถูกต้อง, ลบข้อมูลทดสอบและรีเซ็ต motto กลับเป็นค่า default เรียบร้อยหลังทดสอบ

**Frontend:**
- `index.html` — เพิ่ม `.motto-box` (การ์ดไล่สีน้ำเงินเข้ม ตัวหนังสือขาวหนา 19px ให้เด่นชัด) และ `.stats-box` (การ์ดพื้นเขียวอ่อน แสดง 4 สีเวลาเป็นแถว + เส้นแบ่ง + แถวม่วงตัวเอียงระบุ "(แฟล็กเสริม)" ชัดเจน + ยอดรวม) วางไว้ **หลัง** ปุ่ม "เสร็จสิ้น"/"ตกลง" เดิม (ตาม mockup) ทั้งในหน้า `screen-result` (เช็กอินสำเร็จครั้งแรก) และ `screen-already` (เช็กอินซ้ำ) — เรียก `do_get_motto()` และ `do_get_my_month_stats()` ทันทีที่แสดงหน้าแต่ละหน้า
- `dashboard.html` / `report.html` — เพิ่มการ์ด "กล่องม็อตโต้/ข้อความบริการ" มี textarea (max 300 ตัวอักษร + ตัวนับ) และปุ่มบันทึก โหลดค่าปัจจุบันมาแสดงตอน login (`dashboard.html` ใช้ `do_set_motto`, `report.html` ใช้ `do_supervisor_set_motto` พร้อม `session.officerId`/`session.pin`)

**Deploy:** อัปโหลด 3 ไฟล์ผ่าน Netlify Drop สำเร็จ 3 ก.ค. 2569 เวลา 14:07 — verify หลัง deploy ด้วย `javascript_tool` เช็กว่า element ใหม่ทั้งหมดขึ้นจริงบนเว็บ (`resultMotto`, `resultStatGreen`, `alreadyMotto`, `mottoInput`, `btnSaveMotto` ฯลฯ) และเช็กว่าฟีเจอร์เดิม (thumbnail รูป, badge สีม่วง, FK query ที่เคยแก้บั๊ก) ไม่มี regression — ผ่านหมด

---

## 11. การทำงานต่อบนเครื่องอื่น / เปิด Cowork project ใหม่ (cross-machine continuity)

เจ้าของแจ้งว่าจะย้ายไปทำงานต่อบนคอมพิวเตอร์อีกเครื่องหนึ่ง โดยเปิด Cowork project ใหม่ (agent คนละตัวกับที่ทำมาตลอด) แต่ต่อโฟลเดอร์เดิมผ่าน OneDrive — มีจุดที่ agent ตัวถัดไปต้องรู้:

1. **สเปกตั้งต้น v1 ฉบับเต็มถูกแยกออกมาเป็นไฟล์แล้ว** — เดิมสเปกนี้อยู่ใน "Project Instructions" ของ Cowork project เดิมเท่านั้น (การตั้งค่าระดับแอป ไม่ใช่ไฟล์) จึง**ไม่ติดไปกับโฟลเดอร์**เวลาเปิด Cowork project ใหม่ ผมจึงคัดลอกมาบันทึกไว้เป็นไฟล์จริงที่ `00_SPEC_v1_ORIGINAL.md` ในโฟลเดอร์นี้ (3 ก.ค. 2569) — agent ตัวใหม่ต้องอ่านไฟล์นี้คู่กับ `CLAUDE.md` เสมอ ถ้าสองไฟล์ขัดกันเรื่องข้อเท็จจริง ให้เชื่อ `CLAUDE.md` เพราะเป็นของปัจจุบันกว่า แต่กติกาเหล็ก 6 ข้อใน `00_SPEC_v1_ORIGINAL.md` ยังบังคับใช้เสมอไม่มีข้อยกเว้น
2. **ไม่แนะนำให้แปลงโปรเจกต์นี้เป็น Skill** — เคยพิจารณาแล้ว (ให้คำแนะนำเจ้าของไปแล้ว 3 ก.ค. 2569) เหตุผล: โปรเจกต์นี้เป็น state ที่เปลี่ยนเร็ว (migration/บั๊ก/backlog ใหม่แทบทุกเซสชัน) ถ้าทำเป็น Skill จะต้อง sync สองที่ (ไฟล์ในโฟลเดอร์ vs Skill ที่เก็บแยกนอกโฟลเดอร์) เสี่ยงเกิดปัญหาเดียวกับที่เคยเจอตอนไฟล์ HTML ในเครื่องเก่ากว่าเว็บจริง (ดูข้อ 6.5 ใน CLAUDE.md) ให้ไฟล์ในโฟลเดอร์ (`CLAUDE.md` + `00_SPEC_v1_ORIGINAL.md`) เป็นความจริงหนึ่งเดียวพอ
3. **ก่อนเริ่มงานบนเครื่องใหม่ ต้องเช็ก:**
   - โฟลเดอร์ OneDrive sync จนขึ้นเครื่องหมายถูกเขียวครบ (ไม่ใช่แค่ cloud-only placeholder) ก่อนให้ agent อ่าน/แก้ไฟล์ — ไม่งั้นจะเจอบั๊กไฟล์เก่ากว่าเว็บจริงซ้ำแบบข้อ 6.5
   - ติดตั้ง/เชื่อมต่อ Claude in Chrome extension บนเครื่องใหม่ — workflow การรัน SQL migration บน Supabase SQL Editor และการ deploy ผ่าน Netlify Drop ที่ใช้มาตลอดทั้งโปรเจกต์ พึ่งเครื่องมือนี้ทั้งหมด ไม่มี extension = ทำงานต่อแบบเดิมไม่ได้
   - ล็อกอิน supabase.com (org "Chuan", project `RayongImm-Service` ref `aamzsbuwfdyljdvwaifb`) และ app.netlify.com (team "okmyfish", site `comfy-gaufre-b6b83e`) ด้วยบัญชีเจ้าของเองในเบราว์เซอร์นั้น — ไม่ใช่หน้าที่ agent สร้าง/ล็อกอินแทน
   - **ห้ามรัน migration 01–16 ซ้ำ** — รันจริงบน production แล้วทั้งหมด ถ้ารันซ้ำจะชน unique constraint หรือ error อื่นๆ อ่านตารางในข้อ 3 ของ CLAUDE.md เป็นประวัติเท่านั้น
4. **ห้ามเปิด Cowork session พร้อมกันสองเครื่องแก้ไฟล์ชุดเดียวกันพร้อมกัน** — OneDrive จะสร้างไฟล์ conflict copy (เช่น `index-PCNAME.html`) แล้วยากจะรู้ว่าอันไหนคือของจริง ให้ใช้ทีละเครื่องเท่านั้น
5. **memory ของ agent (feedback/preference ที่เจ้าของเคยบอกไว้ เช่น "ห้าม deploy ก่อนถาม") อาจไม่ sync ข้ามเครื่อง/ข้าม Cowork project อัตโนมัติ** — กติกาที่สำคัญจริงๆ ถูกเขียนลง `CLAUDE.md` ไว้แล้วทุกข้อ (ดูข้อ 2) จึงไม่ต้องพึ่ง memory เป็นหลัก ถ้ามีกติกาสำคัญใหม่เกิดขึ้นอีกในอนาคต ให้เขียนบันทึกลง `CLAUDE.md` ตรงๆ แทนที่จะหวังว่า memory จะพกไปด้วย

---

## 12. แดชบอร์ดหัวหน้าให้ครบสเปก v1 (ประวัติย้อนหลัง + override UI + Export Excel) — รายละเอียด (4 ก.ค. 2569)

**สถานะ: เขียนโค้ดเสร็จ + verify RPC ผ่านหมดแล้ว + deploy ขึ้น Netlify แล้ว (4 ก.ค. 2569 เวลา 12:58 น. พร้อมกับข้อ 13) verify หลัง deploy ผ่านหมด ไม่มี regression**

**บริบท:** เข้ามาทำงานต่อในเซสชันนี้พบว่ามีไฟล์ `17_history_override_export.sql` อยู่ในโฟลเดอร์แล้ว (drafted ไว้ก่อนหน้า) แต่ตรวจสอบจริงบน Supabase พบว่า**ยังไม่เคยรัน** (query `pg_proc` เจอแค่ `do_override` เดิม) จึงรันให้ครบตามไฟล์ก่อน แล้วค่อยเขียน frontend ต่อ

**Backend (migration 17 — รันบน Supabase แล้วจริง, verify แล้วว่ามีครบ 5 ฟังก์ชัน):**
- `do_override(p_check_in_id, p_new_status, p_reason)` — เดิมมีตั้งแต่ v1 แต่ไม่เคย validate อะไรเลย ตอนนี้เพิ่ม: เช็คสถานะต้องเป็นหนึ่งใน 4 สี (green/yellow/orange/red — ม่วงเป็นแฟล็กแยก ไม่ใช่สถานะหลัก แก้ override ไม่ได้), เช็คเหตุผลต้อง ≥5 ตัวอักษร, เช็คว่า check_in_id มีจริงก่อน update
- `do_supervisor_override(p_officer_id, p_pin, p_check_in_id, p_new_status, p_reason)` — เวอร์ชัน PIN ใหม่ สำหรับหัวหน้าที่ล็อกอินด้วย PIN (ศุภัตรา, ผู้ช่วยแอดมิน) ใช้ใน report.html — logic เดียวกับ `do_override` ทุกอย่าง ต่างแค่ตรวจสิทธิ์ด้วย PIN แทน auth.uid()
- `do_get_history(p_start_date, p_end_date, p_target_officer_id)` — ประวัติย้อนหลัง (auth, dashboard.html) เลือกช่วงวันที่ + กรองรายคนได้ (null = ทุกคน) คืนมาครบ: local_date, ชื่อ, เวลา, effective_status, ระยะห่าง, ความพร้อม, หมายเหตุ, รูป, ม่วง, และข้อมูล override (reason/at/by_name)
- `do_supervisor_get_history(...)` — เหมือนข้อบนแต่เวอร์ชัน PIN สำหรับ report.html
- `do_supervisor_get_today` — แก้เพิ่ม override_reason/override_at/override_by_name เข้าไปในผลลัพธ์ (เดิมมีแค่ effective status ไม่เห็นว่าใครแก้/เมื่อไหร่/เพราะอะไร) — ต้อง `DROP FUNCTION` ก่อนเพราะเปลี่ยนจำนวนคอลัมน์ที่ return (ตามบั๊กคลาสสิกข้อ 6.1 ของ CLAUDE.md)

**Verify แล้ว (ทดสอบด้วยแถวทดสอบชั่วคราว officer test 2 คน + check_in 1 แถว, ลบทิ้งหมดแล้วหลังทดสอบ):**
- `do_supervisor_get_history` คืนข้อมูลถูกต้องครบ (ทดสอบกับทั้งแถวทดสอบและข้อมูลจริงในเดือน ก.ค. 2569 พร้อมกัน — join/date-range logic ใช้ได้จริง)
- `do_supervisor_override`: reason สั้นเกินไป → `reason_too_short`, สถานะไม่ถูกต้อง (ลองส่ง "purple") → `invalid_status`, PIN ผิด → `bad_pin`, ข้อมูลถูกต้อง → `{ok:true}` ทั้ง 4 เคสตรงตามคาด
- หลัง override แล้วเรียก `do_supervisor_get_history` และ `do_supervisor_get_today` ซ้ำ → เห็น override_status/override_reason/override_at/override_by_name ครบถูกต้อง
- `do_override`/`do_get_history` (เวอร์ชัน auth) **ไม่ได้ทดสอบตรงๆ** เพราะต้องมี Supabase Auth session จริง (agent สร้าง/ล็อกอินแทนเจ้าของไม่ได้ตามกติกาความปลอดภัย) แต่ใช้ SQL body เดียวกันกับเวอร์ชัน PIN ที่ทดสอบผ่านแล้วทุกประการ ต่างแค่กลไกตรวจสิทธิ์ (auth.uid() ซึ่งเป็น pattern เดียวกับที่ `do_override` เดิมใช้มาตั้งแต่ v1) — **แนะนำให้เจ้าของ (ชวนชัย) ทดสอบจริงอีกรอบหลัง deploy โดย login เข้า dashboard.html แล้วลอง override + ดูประวัติย้อนหลังจริง**

**Frontend (ยังไม่ deploy):**
- `dashboard.html` และ `report.html` เพิ่มเหมือนกันทั้งคู่:
  - การ์ด "ประวัติย้อนหลัง" — เลือกช่วงวันที่ (default = วันนี้) + dropdown กรองรายคน + ปุ่มค้นหา → เรียก `do_get_history`/`do_supervisor_get_history`
  - ปุ่ม "แก้ไขสถานะ" ในทุกแถว (ทั้งตารางวันนี้และตารางประวัติ) → เปิด modal เลือกสถานะใหม่ (4 สี) + บังคับกรอกเหตุผล (เช็ค ≥5 ตัวอักษรฝั่ง client ด้วยก่อนส่ง) → เรียก `do_override`/`do_supervisor_override` → reload ตารางเดิมที่เปิดอยู่
  - แสดง badge "แก้ไขโดย {ชื่อ} เมื่อ {เวลา}: {เหตุผล}" ใต้สถานะ ถ้าแถวนั้นเคยถูก override
  - ปุ่ม Export Excel 2 จุด (วันนี้ / ประวัติที่ค้นหาอยู่) ใช้ SheetJS จาก CDN (`xlsx@0.18.5`) แปลงข้อมูลที่ดึงมาแล้วเป็นไฟล์ .xlsx ให้ดาวน์โหลดตรง ไม่มี backend เพิ่ม
  - ตาราง "เช็กอินวันนี้" ของ `dashboard.html` แก้ query ให้ดึง `override_reason`/`override_at`/ชื่อผู้ override เพิ่ม (เดิมดึงตรงจาก `.from("check_in")` ไม่ผ่าน RPC จึงต้องเพิ่ม column และ join `officer!check_in_override_by_fkey` เอง — ระวัง ambiguous FK ตามบั๊กข้อ 6.2 ของ CLAUDE.md)
- ตรวจ syntax ผ่าน `node --check` ทั้งสองไฟล์แล้ว (ไม่มี syntax error)
- **Deploy แล้ว** 4 ก.ค. 2569 เวลา 12:58 น. อัปโหลดพร้อมกันทั้ง 3 ไฟล์ (index.html/dashboard.html/report.html) ตามกติกาข้อ 2.3 — verify หลัง deploy ด้วย fetch ตรวจ static HTML + get_page_text ตรวจ dropdown จริง ผ่านหมด ไม่มี regression

**สิ่งที่ยังไม่ทำในรอบนี้ (นอก scope คำขอ "ทำแดชบอร์ดให้ครบสเปก"):**
- คอลัมน์ "สิทธิ์หัวหน้า" ใน `report.html` — จุดเล็กเดิมจาก backlog ไม่เกี่ยวกับงานรอบนี้ ยังไม่แตะ
- นโยบายลบรูปอัตโนมัติ (PDPA) — ยังค้างเหมือนเดิม

---

## 13. แก้ข้อความหน้าเช็กอิน (`index.html`) — motto label + stats label + ตัดคำแฟล็กเสริม (4 ก.ค. 2569 ช่วงบ่าย)

**สถานะ: แก้โค้ดเสร็จ + verify syntax แล้ว + deploy ขึ้น Netlify แล้ว (4 ก.ค. 2569 เวลา 12:58 น.) verify หลัง deploy ผ่านหมด ไม่มี regression**

**คำขอเดิม:** เจ้าของส่งภาพหน้าจอ (มือถือ) ของหน้า `screen-result`/`screen-already` หลังเช็กอินเสร็จ พร้อม 3 จุดที่ขอแก้:
1. กล่องสถิติเดือนนี้มี emoji สีอยู่แล้ว (🟢🟡🟠🔴) ไม่ต้องมีข้อความชื่อสีซ้ำ ("สีเขียว"/"สีเหลือง"/"สีส้ม"/"สีแดง") ให้เปลี่ยนเป็นคำสถานะแทน
2. แถว "เช็กอินไม่สมบูรณ์" ในกล่องสถิติ ตัดคำว่า "(แฟล็กเสริม)" ท้ายประโยคออก
3. หัวกล่องม็อตโต้ เปลี่ยนจาก "ข้อความจากหัวหน้า" เป็น "Rayong Immigration Service" (ยังคง emoji 📢 เดิมไว้)

**รอบแรกใช้คำว่า "ทันเวลาพอดี"/"เลท" ในกล่องสถิติ แล้วพบว่าไม่ตรงกับ badge สถานะหลักด้านบน (ที่ใช้ "ทันพอดี"/"มาเลท" มาแต่เดิม) — เจ้าของ confirm ให้ใช้คำเดิมของ badge หลักเป็นมาตรฐานทั้งหน้าแทน จึงแก้กล่องสถิติกลับให้ตรงกับ badge หลัก**

**สิ่งที่แก้ (เฉพาะ `index.html`, ไม่แตะ backend/RPC):**
- `motto-label` (บรรทัด ~197, ~230): "📢 ข้อความจากหัวหน้า" → "📢 Rayong Immigration Service"
- `stats-row` label ในกล่องสถิติ (บรรทัด ~204-207, ~237-240) ทั้ง `screen-result` และ `screen-already`: 🟢 สีเขียว→ดีเยี่ยม, 🟡 สีเหลือง→ทันพอดี, 🟠 สีส้ม→มาเลท, 🔴 สีแดง→สาย — **ใช้คำเดียวกับ badge สถานะหลัก (`resultBadge`/`alreadyBadge`) ทุกคำแล้ว ไม่มีจุดไม่ตรงกันอีก**
- `stats-flag-row` (บรรทัด ~208, ~241): "🟣 เช็กอินไม่สมบูรณ์ (แฟล็กเสริม)" → "🟣 เช็กอินไม่สมบูรณ์"

**Verify:**
- Grep ยืนยันไม่มีคำเก่า ("ข้อความจากหัวหน้า", "แฟล็กเสริม", "สีเขียว/เหลือง/ส้ม/แดง", "ทันเวลาพอดี", "🟠 เลท") หลงเหลือในไฟล์แล้ว
- เทียบไฟล์ในเครื่องกับของจริงบน Netlify ก่อนแก้ (fetch(location.href) เทียบ line count และคำสำคัญ) ตรงกันครบ ไม่ชนบั๊กไฟล์เก่ากว่าเว็บจริงแบบข้อ 6.5
- `node --check` ผ่าน ไม่มี syntax error
- **Deploy แล้ว** 4 ก.ค. 2569 เวลา 12:58 น. รวมทีเดียวกับข้อ 12 ทั้ง 3 ไฟล์

---

## 14. หมายเหตุเพิ่มเติมหลังเช็กอิน + สรุปหมายเหตุรายเดือนตามคีย์เวิร์ด — รายละเอียด (4 ก.ค. 2569 ช่วงเย็น)

**สถานะ: เขียนโค้ดเสร็จทั้ง 3 ไฟล์ + backend (migration 18) รันบน Supabase แล้วจริงและ verify ผ่านหมด + deploy ขึ้น Netlify แล้ว (4 ก.ค. 2569 เวลา 15:09 น.) verify หลัง deploy ผ่านหมดทั้ง 3 หน้า ไม่มี regression**

**คำขอเดิม (ที่มา):** หลังทดสอบใช้งานจริงวันที่ 3 ก.ค. 2569 มี feedback ว่าเจ้าหน้าที่บางคนทำงานมากกว่าคนอื่น (มา 8:30 แต่ต้องอยู่เคลียร์งานถึง 6 โมง/2 ทุ่ม) เจ้าของอยากได้กล่องหมายเหตุ **ไม่บังคับ** ท้ายสุดของหน้าเช็กอิน (หลังสถิติส่วนตัว) ให้เจ้าหน้าที่เล่าให้หัวหน้าฟังได้ทั้งเรื่องบวก/ลบ/ทำความเข้าใจการทำงานแต่ละคน (เช่น กลับดึกเมื่อคืน, เป้าหมายวันนี้, ร้องเรียนเพื่อนร่วมงาน, ชื่นชมคนที่ช่วยเหลือ) พร้อมขอให้ออกแบบว่าหัวหน้าทั้ง 3 คนควรเห็น/สรุปข้อมูลนี้อย่างไรให้ดูรอบเดือนได้โดยไม่ต้องอ่านทุกวัน

**การตัดสินใจออกแบบที่ยืนยันกับเจ้าของแล้ว (ผ่าน AskUserQuestion หลายรอบ):**
- หัวหน้าทั้ง 3 คน (ชวนชัย auth, ศุภัตรา + ผู้ช่วยแอดมิน PIN) **เห็นหมายเหตุเท่ากันหมด** ไม่มีจำกัดสิทธิ์แม้เนื้อหาจะละเอียดอ่อน (เช่น ร้องเรียนเพื่อนร่วมงาน)
- **บันทึกได้ครั้งเดียวต่อวัน (write-once)** — เจ้าหน้าที่แก้ไข/บันทึกทับไม่ได้หลังกดบันทึกแล้ว
- **แยกจากช่อง "หมายเหตุประจำวัน" เดิมโดยเจตนา** — ช่องเดิม (`note`) ยังคงบังคับกรอกก่อนเช็กอินเหมือนเดิมทุกอย่าง (label/validation ไม่แตะ) เพราะเจ้าของให้เหตุผลว่าก่อนเช็กอินคนรีบ ไม่อยากพิมพ์ยาว ส่วนช่องใหม่อยู่ **หลัง** เช็กอินเสร็จแล้ว มีเวลาพิมพ์ยาวได้
- **สรุปรายเดือน = Tier 2 (จับคีย์เวิร์ดแบบตายตัวฝั่ง client, ไม่พึ่ง AI/API ภายนอก)** — เจ้าของปฏิเสธ Tier 3 (AI สรุปเนื้อหา) เพราะกังวลเรื่องส่งข้อความร้องเรียนที่อาจละเอียดอ่อนออกไปนอกระบบ Supabase และไม่คุ้มกับทีม 19 คน
- **นับซ้ำได้ทุกหมวดที่ตรง** (1 หมายเหตุอาจเข้าได้หลายหมวดพร้อมกัน) ตามที่เจ้าของ confirm ("นับซ้ำได้ทุกกลุ่มที่ตรง (แนะนำ)") เพื่อไม่ให้ข้อมูลหาย
- คีย์เวิร์ด 4 หมวดหลัก + 1 หมวดรวม (เจ้าของขอเพิ่มเอง): 🕐 OT/เลิกดึก, 🎯 เป้าหมาย/แผนวันนี้, ⚠️ ปัญหา/ร้องเรียน, 👍 ชื่นชม/บวก, 📋 อื่นๆ (catch-all ถ้าไม่เข้าหมวดไหนเลย)

**Backend (migration `18_officer_remark.sql` — รันบน Supabase แล้วจริง):**
- `check_in.remark` (text, constraint ≤500 ตัวอักษร)
- `do_save_remark(p_officer_id, p_pin, p_remark)` (anon) — เช็ค PIN → หา check_in ของวันนี้ → ถ้ามี remark อยู่แล้วปฏิเสธ (`already_saved` พร้อมส่งค่าเดิมกลับ) → ถ้าไม่มีเลยปฏิเสธ (`no_checkin_today`) → validate ความยาว (`empty_remark`/`remark_too_long`) → บันทึก
- `do_get_today_status`, `do_supervisor_get_today`, `do_get_history`, `do_supervisor_get_history` — เพิ่มคอลัมน์ `remark` ในผลลัพธ์ทุกตัว

**Verify แล้ว (ใช้แถวทดสอบชั่วคราว officer `...aa`/`...bb` แล้วลบทิ้งหมดหลังทดสอบ):**
- `do_save_remark`: bad_pin, empty_remark, remark_too_long, บันทึกสำเร็จครั้งแรก, บันทึกซ้ำถูกปฏิเสธพร้อมส่งค่าเดิมกลับ — ผ่านหมดทั้ง 5 เคส
- `do_get_today_status` คืน `remark` ถูกต้อง (ทดสอบผ่าน SQL Editor)
- `do_supervisor_get_today` และ `do_supervisor_get_history` คืน `remark` ถูกต้อง (ทดสอบด้วยแถว supervisor ทดสอบชั่วคราว ผ่าน SQL Editor)
- `do_get_history` (เวอร์ชัน auth) ไม่ได้ทดสอบตรงๆ เพราะต้องมี Supabase Auth session จริง แต่ SQL body เหมือน `do_supervisor_get_history` ที่ทดสอบผ่านแล้วทุกประการ (ต่างแค่กลไกตรวจสิทธิ์)
- **⭐ ทดสอบเพิ่มเติมที่สำคัญ**: เรียก `do_get_today_status`/`do_save_remark` จริงผ่าน **anon key จากบราวเซอร์จริง** (ไม่ใช่ SQL Editor ที่รันเป็น postgres role) เพื่อยืนยันว่า GRANT EXECUTE ให้ anon ใช้งานได้จริงจากหน้าเว็บ ไม่ใช่แค่ผ่านได้ตอนรันเป็น superuser — ผลลัพธ์ครบถ้วนตรงตามคาดทุกเคส (save → get เห็นค่า → save ซ้ำถูกปฏิเสธพร้อมค่าเดิม)

**Frontend:**
- `index.html` — เพิ่ม `.remark-box` หลัง `.stats-box` ทั้งใน `screen-result` และ `screen-already` มี textarea (max 500 + ตัวนับ), ปุ่ม "บันทึกหมายเหตุ", ข้อความ error/สำเร็จ, และมุมมอง "บันทึกแล้ว (แก้ไขไม่ได้)" แบบ read-only หลังบันทึกสำเร็จ — `screen-result` เริ่มต้นเป็นฟอร์มว่างเสมอ (เพิ่งเช็กอินสำเร็จ ไม่มีทางมี remark อยู่ก่อน), `screen-already` เช็ค `data.remark` จาก `do_get_today_status` ก่อน ถ้ามีค่าอยู่แล้วโชว์เป็น read-only ทันที ไม่ให้พิมพ์ซ้ำ
- `dashboard.html` / `report.html` — เพิ่มคอลัมน์ "หมายเหตุเพิ่มเติม" ในตาราง (ทั้งวันนี้และประวัติ), เพิ่ม `remark` ใน export Excel, และเพิ่มการ์ด **"สรุปหมายเหตุเพิ่มเติมตามคีย์เวิร์ด"** เหนือผลการค้นหาประวัติ — คำนวณจาก `lastHistRows` ที่ดึงมาแล้ว (ไม่มี RPC เพิ่ม) แสดงตารางราย officer x 5 หมวด + ยอดรวม พร้อมปุ่ม "ดูรายละเอียด" ต่อคนที่กรอง dropdown แล้ว re-run การค้นหาประวัติอัตโนมัติ (drill-down)

**Verify syntax:** `node --check` ผ่านทั้ง 3 ไฟล์ — **หมายเหตุสำคัญสำหรับ agent ตัวถัดไป**: ระหว่าง verify รอบนี้พบว่า bash sandbox (mount ผ่าน OneDrive sync) แสดงไฟล์เก่ากว่าที่ Read tool เห็นจริง (dashboard.html โดน bash มองว่าตัดจบกลางบรรทัดที่ 595 ทั้งที่ไฟล์จริงยาว 675 บรรทัดและปิด `</html>` ถูกต้อง) — สาเหตุคือ OneDrive sync lag ในฝั่ง bash mount ไม่ใช่ไฟล์เสียจริง วิธีแก้: ใช้ `Read` tool (ไม่ใช่ bash) เป็นความจริงหลักเสมอเวลาเช็กเนื้อหาไฟล์ล่าสุดในโฟลเดอร์นี้ ถ้าต้อง syntax-check ด้วย node ให้คัดลอกเนื้อหาจาก Read ไปวางในไฟล์ scratch ที่ outputs (ไม่ใช่ path ที่ sync กับ OneDrive) ก่อนค่อยรัน `node --check`

**Deploy:** อัปโหลด 3 ไฟล์ผ่าน Netlify Drop สำเร็จ 4 ก.ค. 2569 เวลา 15:09 น. — verify หลัง deploy ด้วย `fetch(location.href)` ทั้ง 3 หน้าจริงบนเว็บ (`index.html`, `dashboard.html`, `report.html`) เช็กว่า element/ฟังก์ชันใหม่ทั้งหมดขึ้นจริง (`remark-box`, `resultRemarkInput`/`alreadyRemarkInput`, `do_save_remark`, `remarkSummaryCard`, `tagRemark`) และฟีเจอร์เดิมไม่มี regression (thumbnail รูป, badge สีม่วง, กล่องม็อตโต้/สถิติ) — ผ่านหมด

**สิ่งที่ยังไม่ทำในรอบนี้:**
- คู่มือผู้ใช้ (ข้อ 8 ของ CLAUDE.md) ยังไม่ได้อัปเดตเรื่องกล่องหมายเหตุใหม่นี้

---

## 15. ระบบตารางเวรแบบง่าย (MVP) + วันหยุดนักขัตฤกษ์ + สีน้ำตาลเข้ม "ขาดเช็กอิน" — รายละเอียด (4 ก.ค. 2569 ช่วงค่ำ)

**สถานะ: เขียนโค้ดเสร็จทั้ง 2 ไฟล์ (`dashboard.html`, `report.html`) + backend (migration 19) รันบน Supabase แล้วจริงและ verify ผ่านหมดด้วยข้อมูลทดสอบ (ลบทิ้งหมดหลังทดสอบแล้ว) — syntax check (`node --check`) ผ่านทั้ง 2 ไฟล์ — ✅ deploy ขึ้น Netlify แล้ว 4 ก.ค. 2569 เวลา 22:30 น. (รวมกับข้อ 16, 17) verify หลัง deploy ผ่านหมด ไม่มี regression**

**คำขอเดิม (ที่มา):** เจ้าของถามว่าอยากรู้ "วันนี้ใครขาดที่ไม่ได้แจ้ง" ผมแนะนำให้เริ่มจาก MVP ง่ายๆ (เก็บแค่ "วันทำงานปกติต่อสัปดาห์" ต่อคน) แทนระบบตารางเวรรายเดือนเต็มรูปแบบ เจ้าของ confirm ให้ทำ MVP นี้ก่อน พร้อมระบุเพิ่มเองว่าต้องกำหนดได้ว่าบางคนทำงานแค่บางวัน (เช่น พุธ-พฤหัส-ศุกร์), เสาร์-อาทิตย์เป็นวันหยุด default, และเพิ่มวันหยุดนักขัตฤกษ์ได้

**การตัดสินใจออกแบบที่ยืนยันกับเจ้าของแล้ว (ผ่าน AskUserQuestion):**
- **หัวหน้าทั้ง 3 คนแก้ไข "วันทำงาน" ของแต่ละคน และเพิ่ม/ลบ "วันหยุดนักขัตฤกษ์" ได้เท่ากันหมด** — สอดคล้องกับ precedent เดิมของกล่องม็อตโต้ (ข้อ 10)
- **เวลาฟันธง "ขาดเช็กอิน" = หลัง 16:30 น.** (ไม่ใช่ 08:40 ตามที่ผมแนะนำแต่แรกซึ่งอิงเกณฑ์สีแดง) — เจ้าของเลือกเวลานี้เองเพราะบางคนอาจมีธุระครึ่งวันเช้าที่อื่นก่อนมาทำงานช่วงบ่าย ฟันธงเร็วเกินไปจะไม่เป็นธรรม
- **ขอบเขต MVP**: เก็บแค่ "วันทำงานปกติต่อสัปดาห์" (เช่น จ-ศ, หรือ พ-พฤ-ศ) เป็น flag ต่อคน + วันหยุดนักขัตฤกษ์แบบ exception list ง่ายๆ — **ไม่ใช่** ปฏิทินเต็มรูปแบบที่แก้ได้รายวัน/รายเดือน (ของนั้นเป็นงานเฟสถัดไปถ้าจำเป็นจริง)

**Backend (migration `19_shift_schedule_absent.sql` — รันบน Supabase แล้วจริง, verify ผ่านหมด):**
- `officer.work_days` (smallint[], default `{1,2,3,4,5}` = จันทร์-ศุกร์ ตาม ISO day-of-week คือ 1=จันทร์...7=อาทิตย์) + constraint บังคับเป็นเลข 1-7 เท่านั้น (`work_days <@ array[1,2,3,4,5,6,7]`)
- ตาราง `public_holiday` (id, holiday_date unique, description, created_at) — ไม่มี RLS policy เพราะเข้าถึงผ่าน RPC เท่านั้น (ตามแพทเทิร์นเดียวกับตารางอื่นในโปรเจกต์)
- `settings.absent_cutoff_time` (time, default `16:30`)
- `do_get_absentees(p_date)` (auth) / `do_supervisor_get_absentees(p_officer_id, p_pin, p_date)` (anon) — `p_date` เป็น null = วันนี้ ถ้าเป็นวันในอนาคตปฏิเสธ (`future_date`) ถ้าเป็นวันนี้และยังไม่ถึง `absent_cutoff_time` คืน `{ok:true, too_early:true, cutoff_time, rows:[]}` แทนรายชื่อจริง (กันฟันธงเร็วเกินไป) ถ้าผ่านเงื่อนไขแล้วคืนรายชื่อ officer ที่ `active=true` และ `work_days` ตรงกับ isodow ของวันนั้น และไม่ตรงกับวันหยุดใน `public_holiday` และยังไม่มี `check_in` ของวันนั้น
- `do_set_officer_workdays(p_target_officer_id, p_work_days)` (auth) / `do_supervisor_set_officer_workdays(p_officer_id, p_pin, p_target_officer_id, p_work_days)` (anon) — validate `p_work_days` ต้องเป็น subset ของ 1-7 (`invalid_work_days`)
- `do_list_holidays()` / `do_supervisor_list_holidays(...)`, `do_add_holiday(p_holiday_date, p_description)` / `do_supervisor_add_holiday(...)` (reject ซ้ำด้วย `already_exists`), `do_delete_holiday(p_holiday_id)` / `do_supervisor_delete_holiday(...)`
- DROP + recreate `do_list_officers_admin()` และ `do_supervisor_list_officers(...)` ให้ return คอลัมน์ `work_days` เพิ่ม (ดึง body เดิมจริงผ่าน `pg_get_functiondef` ก่อนแก้ ตามวินัยโปรเจกต์ที่ห้ามเดา SQL ที่ verify ไม่ได้)

**Verify แล้ว (ใช้แถวทดสอบชั่วคราว officer `...cc` เป็นหัวหน้าทดสอบ + `...dd`/`...ee` เป็นเจ้าหน้าที่ทดสอบ, ลบทิ้งหมดหลังทดสอบ):**
- `do_supervisor_get_absentees`: `too_early:true` ถูกต้องเมื่อเวลา Bangkok ยังไม่ถึง cutoff (ทดสอบจริงตอน 16:09 น. คืน too_early ตรงตามคาด), `future_date` reject ถูกต้อง, `bad_pin` reject ถูกต้อง, กรองตาม `work_days` ถูกต้อง (ทดสอบกับวันพุธ 2026-07-01: officer ที่ work_days มีวันพุธขึ้นมาในลิสต์ ที่ไม่มีวันพุธไม่ขึ้น)
- **ทดสอบ exclusion ที่สำคัญที่สุด**: เพิ่ม check_in ให้ officer ทดสอบ `...ee` ในวันที่ทดสอบ แล้วเรียกซ้ำ → `...ee` หายจากลิสต์ (มี checkin แล้วไม่ถือว่าขาด) ในขณะที่ `...dd`/`...cc` (ไม่มี checkin) ยังโชว์อยู่ — ยืนยัน logic ตรงตามคาด
- **ทดสอบ holiday exclusion**: เพิ่มวันหยุดสำหรับวันทดสอบ → ลิสต์ขาดเช็กอินว่างเปล่าทันที (ทุกคนไม่นับว่าขาดเพราะเป็นวันหยุด) ลบวันหยุดออก → ลิสต์กลับมาแสดงตามปกติ
- `do_supervisor_add_holiday`: เพิ่มสำเร็จ, เพิ่มซ้ำ → `already_exists`, PIN ผิด → `bad_pin`
- `do_supervisor_list_holidays`, `do_supervisor_delete_holiday` (ลบสำเร็จ, ลบซ้ำ → `not_found`) — ผ่านหมด
- `do_supervisor_set_officer_workdays`: อัปเดตสำเร็จ, ส่ง `{8}` (ไม่ใช่ 1-7) → `invalid_work_days`, PIN ผิด → `bad_pin`
- `do_supervisor_list_officers` คืนคอลัมน์ `work_days` ถูกต้องตามที่อัปเดตล่าสุด
- `do_get_absentees`/`do_get_history` เวอร์ชัน auth **ไม่ได้ทดสอบตรงๆ** เพราะต้องมี Supabase Auth session จริง (agent สร้าง/ล็อกอินแทนเจ้าของไม่ได้) แต่ SQL body เหมือนเวอร์ชัน PIN ที่ทดสอบผ่านแล้วทุกประการ ต่างแค่กลไกตรวจสิทธิ์

**Frontend (deploy แล้ว 4 ก.ค. 2569 เวลา 22:30 น.):**
- `dashboard.html` และ `report.html` เพิ่มเหมือนกันทั้งคู่ (ต่างแค่ RPC ที่เรียก — auth vs PIN):
  - การ์ด **"🟤 ยังไม่เช็กอินวันนี้ (ขาดเช็กอิน)"** วางไว้ระหว่างการ์ด "เช็กอินวันนี้" กับ "ประวัติย้อนหลัง" — เรียก `do_get_absentees`/`do_supervisor_get_absentees` ทันทีหลัง login แสดง 3 สถานะ: กำลังโหลด / ยังไม่ถึงเวลาฟันธง (แสดงเวลา cutoff) / รายชื่อ (หรือ "ไม่มีใครขาดเช็กอินวันนี้" ถ้าว่าง)
  - ตาราง "รายชื่อเจ้าหน้าที่ทั้งหมด" เพิ่มคอลัมน์ **"วันทำงาน"** (แสดง "ทุกวัน"/"จันทร์-ศุกร์"/หรือย่อวันเป็น จ,อ,พ,พฤ,ศ,ส,อา) + ปุ่ม **"แก้วันทำงาน"** ต่อแถว เปิด modal เลือกวันด้วย checkbox 7 วัน บังคับเลือกอย่างน้อย 1 วัน บันทึกแล้ว refresh ทั้งตารางเจ้าหน้าที่และการ์ดขาดเช็กอิน
  - การ์ดใหม่ **"📅 วันหยุดนักขัตฤกษ์"** ท้ายสุดของหน้า — ฟอร์มเพิ่มวันหยุด (วันที่ + รายละเอียดไม่บังคับ) + ตารางแสดงวันหยุดที่มีอยู่พร้อมปุ่มลบต่อแถว บันทึก/ลบแล้ว refresh การ์ดขาดเช็กอินด้วย
- Syntax verify ด้วย `node --check` ผ่านทั้ง 2 ไฟล์ (ใช้วิธี copy เนื้อหาจาก Read tool ไปสร้าง scratch file ที่ outputs ตามที่ค้นพบปัญหา OneDrive sync lag ในข้อ 14)
- **การทดสอบแบบเปิดไฟล์ในเบราว์เซอร์จริงทำไม่ได้ในรอบนี้**: Claude in Chrome extension ไม่รองรับการ navigate ไปที่ `file://` URL (ลองแล้วเจอ error page) และการ login เข้า dashboard.html/report.html จริงต้องใช้ credential ของเจ้าของ (email+password หรือ PIN จริง) ซึ่ง agent ไม่มีสิทธิ์เข้าถึง/เดา — จึงอาศัยการ verify RPC ผ่าน SQL Editor ด้วยข้อมูลทดสอบครบทุกเคส (ด้านบน) แทน ซึ่งครอบคลุม backend logic ทั้งหมดแล้ว ส่วน frontend ผ่านแค่ syntax check + code review

**สิ่งที่ยังไม่ทำในรอบนี้:**
- คู่มือผู้ใช้ (ข้อ 8 ของ CLAUDE.md) ยังไม่ได้อัปเดตเรื่องฟีเจอร์ใหม่นี้
- สีน้ำตาลเข้มยังเป็นแค่ "รายชื่อในการ์ดแยก" ไม่ได้ผูกเข้ากับ badge สถานะหลัก 4+1 สีเดิม (ม่วง) ในตารางเช็กอินวันนี้/ประวัติ — ถ้าเจ้าของอยากให้แสดงเป็น badge ในตารางเดียวกันด้วย ต้องคุยเพิ่มว่าจะแสดงอย่างไร (เพราะคนที่ขาดเช็กอินไม่มีแถว check_in ให้แสดงในตารางนั้นอยู่แล้ว)

---

## 16. วันเริ่มนับสถิติรายเดือนแบบตั้งค่าได้ + สีน้ำตาลเข้ม "ขาดเช็กอิน" ในสถิติส่วนบุคคล — รายละเอียด (4 ก.ค. 2569 กลางคืน)

**สถานะ: เขียนโค้ดเสร็จทั้ง 3 ไฟล์ (`index.html`, `dashboard.html`, `report.html`) + backend (migration 20) รันบน Supabase แล้วจริงและ verify ผ่านหมดด้วยข้อมูลทดสอบ (ลบทิ้งหมดหลังทดสอบแล้ว) — syntax check (`node --check`) ผ่านทั้ง 3 ไฟล์ — ✅ deploy ขึ้น Netlify แล้ว 4 ก.ค. 2569 เวลา 22:30 น. (รวมกับข้อ 15, 17) verify หลัง deploy ผ่านหมด ไม่มี regression**

**คำขอเดิม (ที่มา):** เจ้าของขอ 3 เรื่องพร้อมกัน: (1) เปลี่ยนชื่อการ์ด "🟤 ยังไม่เช็กอินวันนี้" เป็น "ขาดเช็คอิน" ให้สั้นตรงประเด็นกว่าเดิม (ทำแล้วในรอบก่อน ดูข้อ 15), (2) ให้สถิติส่วนบุคคลรายเดือนของแต่ละคน (ที่เห็นหลังเช็กอินใน `index.html`) แสดงจำนวนครั้งที่ "ขาดเช็กอิน" (สีน้ำตาล) ด้วย ไม่ใช่แค่ 4 สีเวลา + ม่วงเหมือนเดิม, (3) ให้แอดมินกำหนดวันเริ่มนับสถิติของแต่ละเดือนได้ เพราะวันที่ 3 ก.ค. 2569 เปิดให้เช็กอินจริงแล้วแต่ตั้งใจแค่ทดสอบระบบ ไม่อยากให้นับรวมในสถิติ ตั้งใจเริ่มนับจริงสัปดาห์ถัดไป (ถ้าเดือนไหนไม่ได้เริ่มนับวันที่ 1 ให้ใส่วงเล็บบอกวันเริ่มนับในหน้าสถิติส่วนตัวด้วย)

**Backend (migration `20_stats_period_override.sql` — รันบน Supabase แล้วจริง, verify ผ่านหมด):**
- ตาราง `stats_period_override` (year smallint, month smallint check 1-12, start_date date, PK (year,month)) — ไม่มี RLS policy เพราะเข้าถึงผ่าน RPC เท่านั้น (ตามแพทเทิร์นเดียวกับ `public_holiday`)
- แก้ `do_get_my_month_stats(p_officer_id, p_pin)` — **ใช้ `CREATE OR REPLACE` เฉยๆ ไม่ต้อง DROP ก่อน** เพราะ return type ยังเป็น `json` เหมือนเดิม (ต่างจาก migration อื่นที่ return columns เปลี่ยนต้อง DROP) เพิ่ม logic: หาว่าเดือนปัจจุบัน (ตาม server time, Asia/Bangkok) มี `stats_period_override` ตั้งไว้ไหม ถ้ามีและวันที่นั้นอยู่ในเดือนจริง ใช้เป็นจุดเริ่มนับแทนวันที่ 1 (ถ้าไม่มีหรือวันที่ผิดเดือน fallback กลับไปวันที่ 1 ตามปกติ), นับ `absent` เพิ่ม (จำนวนวันตั้งแต่วันเริ่มนับถึงเมื่อวานหรือวันนี้แล้วแต่ผ่าน `absent_cutoff_time` หรือยัง ที่ officer ควรมาตาม `work_days` แต่ไม่ตรงวันหยุดและไม่มี check_in) ครอบคลุมทั้งเดือนไม่ใช่แค่วันนี้ (ต่างจาก `do_get_absentees` ใน migration 19 ที่ดูแค่วันเดียว), คืนคอลัมน์ `count_start_date` เพิ่มเสมอ (ใช้แสดงวงเล็บในหน้าสถิติถ้าไม่ใช่วันที่ 1)
- RPC จัดการวันเริ่มนับ 6 ตัว (auth × 3, PIN × 3): `do_list_stats_period_overrides()` / `do_supervisor_list_stats_period_overrides(p_officer_id, p_pin)`, `do_set_stats_period_override(p_year, p_month, p_start_date)` / เวอร์ชัน PIN (validate เดือนต้อง 1-12 → `invalid_month`, วันที่ต้องอยู่ในเดือนที่ระบุจริง → `date_not_in_month`, ใช้ `insert ... on conflict (year,month) do update` เพื่อ upsert), `do_delete_stats_period_override(p_year, p_month)` / เวอร์ชัน PIN (ไม่พบ → `not_found`)

**Verify แล้ว (ใช้แถวทดสอบชั่วคราว officer `TEST_STATS_OFFICER` + supervisor `TEST_STATS_SUPERVISOR`, ลบทิ้งหมดหลังทดสอบ):**
- สร้าง check_in 2 แถว (1 ก.ค. เขียว, 3 ก.ค. แดง+ไม่สมบูรณ์) เว้น 2 ก.ค. ว่างไว้ → `do_get_my_month_stats` แบบไม่มี override คืน `{green:1, red:1, incomplete:1, absent:2, total:2, count_start_date:"2026-07-01"}` ถูกต้อง (absent=2 นับทั้งวันที่ 2 และวันที่ 4 คือวันนี้ที่ผ่าน cutoff แล้วยังไม่เช็กอิน)
- ตั้ง override เป็นเริ่มนับ 3 ก.ค. → เรียกซ้ำได้ `{green:0, red:1, incomplete:1, absent:1, total:1, count_start_date:"2026-07-03"}` ตรงตามคาดเป๊ะ (ตัดวันที่ 1-2 ออกจากการนับทั้งหมด)
- เพิ่มวันหยุดทดสอบสำหรับวันนี้ → absent ลดลงเหลือ 0 (holiday exclusion ทำงานถูกต้อง)
- ทดสอบ validation: `invalid_month` (ส่งเดือน 13), `date_not_in_month` (ปี/เดือนไม่ตรงกับวันที่), `bad_pin` (PIN ผิด) — ได้ error code ถูกต้องหมด
- ทดสอบ list/delete: list คืนแถวถูกต้อง, ลบครั้งแรกสำเร็จ, ลบซ้ำ (ไม่มีอยู่แล้ว) → `not_found`
- ลบข้อมูลทดสอบทั้งหมดแล้ว (officer, check_in ของ officer นั้น, วันหยุดทดสอบ, แถว stats_period_override ปี 2026 เดือน 7) — verify ว่างเปล่าครบ 0 แถวทุกตาราง
- `do_list_stats_period_overrides`/`do_set_stats_period_override`/`do_delete_stats_period_override` เวอร์ชัน auth **ไม่ได้ทดสอบตรงๆ** เพราะต้องมี Supabase Auth session จริง (agent สร้าง/ล็อกอินแทนเจ้าของไม่ได้) แต่ SQL body เหมือนเวอร์ชัน PIN ที่ทดสอบผ่านแล้วทุกประการ ต่างแค่กลไกตรวจสิทธิ์

**Frontend (deploy แล้ว 4 ก.ค. 2569 เวลา 22:30 น.):**
- `index.html` — เพิ่มแถวสีน้ำตาล "🟤 ขาดเช็กอิน" ในกล่องสถิติส่วนตัว (ทั้ง `screen-result` และ `screen-already`) ต่อจากแถวม่วงเดิม ก่อนยอดรวม, แก้ JS `loadMyStats()` ให้แสดงค่า `d.absent` และถ้า `d.count_start_date` ไม่ใช่วันที่ 1 ของเดือน ให้ต่อท้ายป้ายเดือน (`monthLabelEl`) ด้วยข้อความ "(เริ่มนับวันที่ X เดือน... พ.ศ. ...)" — verify ผ่าน `node --check` แล้ว (ผ่าน scratch file ที่ล้าง Thai text เป็น ASCII placeholder เพื่อเลี่ยงปัญหา bash mount lag)
- `dashboard.html` และ `report.html` — เพิ่มการ์ดใหม่ **"📆 วันเริ่มนับสถิติรายเดือน"** ท้ายสุดของหน้า (หลังการ์ดวันหยุดนักขัตฤกษ์) มีฟอร์มเลือกเดือน (`input type=month`) + วันเริ่มนับ (`input type=date`) + ปุ่ม "ตั้งค่า" (validate ฝั่ง client ว่าวันที่อยู่ในเดือนที่เลือกก่อนส่ง) และตารางแสดงรายการที่ตั้งไว้แล้วพร้อมปุ่มลบต่อแถว — `dashboard.html` เรียก RPC เวอร์ชัน auth (`do_list/set/delete_stats_period_override`), `report.html` เรียกเวอร์ชัน PIN พร้อม `session.officerId`/`session.pin`
- **Syntax verify**: `node --check` ผ่านทั้ง 3 ไฟล์ — bash mount staleness bug (เขียนไปที่ไฟล์ชื่อใหม่แทนการเขียนทับตามที่บันทึกไว้)

**สิ่งที่ยังไม่ทำในรอบนี้:**
- คู่มือผู้ใช้ (ข้อ 8 ของ CLAUDE.md) ยังไม่ได้อัปเดตเรื่องฟีเจอร์ใหม่นี้เช่นกัน

---

## 17. กล่องม็อตโต้หมุนเวียน 3 ข้อความ — รายละเอียด (4 ก.ค. 2569 กลางคืน)

**สถานะ: เขียนโค้ดเสร็จทั้ง 2 ไฟล์ (`dashboard.html`, `report.html`) + backend (migration 21) รันบน Supabase แล้วจริงและ verify ผ่านหมดด้วยข้อมูลทดสอบ (ลบทิ้งหมดหลังทดสอบแล้ว รวมถึงกู้คืนข้อมูล production ที่เผลอเขียนทับระหว่างทดสอบ) — syntax check (`node --check`) ผ่านทั้ง 2 ไฟล์ — ✅ deploy ขึ้น Netlify แล้ว 4 ก.ค. 2569 เวลา 22:30 น. (รวมกับข้อ 15, 16) verify หลัง deploy ผ่านหมด รวมถึงเรียก `do_get_motto()` จริงผ่าน anon key ยืนยัน rotation ทำงานถูกต้อง — `index.html` ไม่ต้องแก้อะไรในรอบนี้**

**คำขอเดิม (ที่มา):** เจ้าของส่งภาพหน้าจอกล่องม็อตโต้บนเว็บจริง พร้อมขอให้สับเปลี่ยนหมุนเวียนทุกวัน สร้างไว้ 3 กล่องข้อความ ให้วนหมุนไปเรื่อยๆ

**การตัดสินใจออกแบบที่ยืนยันกับเจ้าของแล้ว (ผ่าน AskUserQuestion + ถาม-ตอบเพิ่มเติมเพื่อเช็คตรรกะ):**
- หมุนแบบ **รายวัน** ด้วย **3 ช่องตายตัว** (ไม่ใช่รายการยาวไม่จำกัด) — หัวหน้าทั้ง 3 คนแก้ไขได้ทั้ง 3 ช่องเท่ากันหมด
- ยืนยันกับเจ้าของว่า**ลำดับจะเลื่อนไปเรื่อยๆ ไม่ fix ตายตัวว่าวันจันทร์ = ข้อความ 1 เสมอ** เพราะ 5 วันทำงานต่อสัปดาห์ mod 3 = 2 — เจ้าของตอบ **"ยืนยันแบบนี้ ไม่ต้อง fix ตามวันครับ"**
- ทุกคนเห็นข้อความเดียวกันในแต่ละวัน ไม่ขึ้นกับ `work_days` ส่วนตัว

**Backend (migration `21_motto_rotation.sql` — รันบน Supabase แล้วจริง, verify ผ่านหมด):**
- Schema: เพิ่มคอลัมน์ `settings.service_motto_1/2/3` (text) — migrate ค่าเดิมจาก `service_motto` ไปช่อง 1 + seed placeholder ช่อง 2/3
- `do_get_motto()` (CREATE OR REPLACE) — สูตร rotation: `v_business_days` = นับจำนวนวันจันทร์-ศุกร์ ตั้งแต่วันอ้างอิงคงที่ `2024-01-01` ถึงวันนี้ (server time, Asia/Bangkok) แล้ว `v_slot = ((v_business_days - 1) % 3) + 1`
- `do_list_mottos()` / `do_supervisor_list_mottos(...)` — คืนทั้ง 3 ช่อง + active_slot
- `do_set_motto(p_slot, p_new_motto)` / `do_supervisor_set_motto(...)` — DROP FUNCTION ก่อน CREATE (เปลี่ยน signature เพิ่ม p_slot)

**Verify แล้ว:** `do_get_motto()` คืน active_slot ถูกต้องตามวันจริง, `do_supervisor_set_motto` validate ครบทุกเคส (invalid_slot/motto_empty/motto_too_long/bad_pin) — **⚠️ ระวัง**: การทดสอบเขียนจริงลงช่อง 2 กระทบ `settings` แถวจริง (มีแถวเดียว) — restore ค่าเดิมทันทีหลังทดสอบเสร็จ (บทเรียน: การทดสอบ RPC ที่เขียนลงตาราง `settings` ต้อง restore ค่าจริงทันทีหลัง verify เสร็จทุกครั้ง)

**Frontend (deploy แล้ว 4 ก.ค. 2569 เวลา 22:30 น.):** `dashboard.html`/`report.html` แทนที่การ์ดม็อตโต้เดิมด้วยการ์ดใหม่ 3 ช่อง แต่ละช่องมี textarea + ตัวนับ + ปุ่มบันทึกแยก + badge "🟢 กำลังใช้วันนี้" — `index.html` ไม่ต้องแก้อะไร (server-side คำนวณให้อยู่แล้ว)

**สิ่งที่ยังไม่ทำในรอบนี้:** คู่มือผู้ใช้ (ข้อ 8 ของ CLAUDE.md) ยังไม่อัปเดต

---

## 18. ปรับข้อความกล่องหมายเหตุ + ขยายหมวดคีย์เวิร์ดจาก 5 เป็น 6 หมวด (4 ก.ค. 2569 กลางคืน / deploy 5 ก.ค. 2569 เช้า)

**สถานะ: แก้โค้ดเสร็จทั้ง 3 ไฟล์ (`index.html`, `dashboard.html`, `report.html`) + syntax check ผ่านทั้งคู่ — ✅ deploy ขึ้น Netlify แล้ว 5 ก.ค. 2569 เวลา 09:10 น. verify หลัง deploy ผ่านหมด ไม่มี regression**

**คำขอเดิม (ที่มา):** เจ้าของขอ (1) ตัดประโยค "พิมพ์ได้ครั้งเดียว บันทึกแล้วแก้ไขไม่ได้" ออกจากกล่องหมายเหตุ (2) ทบทวน 5 หมวดคีย์เวิร์ดเดิม อยากให้เป็นรายงานเชิงบวกมากขึ้น ตัดเรื่อง "เพื่อนร่วมงานไม่ช่วย/ถูกเอาเปรียบ" ออกทั้งหมด เพิ่มหมวด "ทำเพื่อส่วนรวม" และ "งานที่ได้รับมอบหมายเพิ่มเติม" และให้หมวดปัญหาจับคู่กับ "ข้อเสนอแนะ" แทนที่จะรายงานปัญหาเปล่าๆ

**คีย์เวิร์ดหมวดใหม่ทั้ง 6 หมวด (ใน `REMARK_KEYWORDS` — `dashboard.html`/`report.html`):**
- 🕐 OT/เลิกดึก: `["ดึก","ล่วงเวลา","OT","เลิกงานดึก","ทุ่ม"]` (คงเดิม)
- 🎯 เป้าหมาย/แผนวันนี้: `["ตั้งใจ","เป้าหมาย","ตั้งเป้า","วันนี้จะ"]` (คงเดิม)
- 📌 งานมอบหมายเพิ่มเติม (ใหม่): `["ได้รับมอบหมาย","มอบหมายเพิ่ม","งานพิเศษ","งานเพิ่มเติม","สั่งให้ทำ"]`
- 🤝 ทำเพื่อส่วนรวม (ใหม่): `["เพื่อส่วนรวม","ส่วนรวม","เพื่อทีม","เพื่อหน่วยงาน","นอกเหนือหน้าที่"]`
- 💡 ปัญหา/ข้อเสนอแนะ (ตัดคำ blame ออกหมด): `["ปัญหา","อุปสรรค","ติดขัด","เสนอแนะ","ข้อเสนอแนะ"]`
- 👍 ชื่นชม/บวก: `["ขอบคุณ","ช่วยเหลือ","ภูมิใจ","ดีใจ","ชื่นชม"]`
- 📋 อื่นๆ (catch-all ไม่เปลี่ยน)

**Frontend:** `index.html` แก้ `.remark-sub` + placeholder ของ textarea 2 จุด (screen-result/screen-already) — `dashboard.html`/`report.html` แก้ `REMARK_KEYWORDS` เพิ่ม 2 หมวดใหม่ + ขยายหัวตารางสรุปจาก 5 เป็น 7 คอลัมน์

**Deploy:** อัปโหลด 3 ไฟล์ผ่าน Netlify Drop สำเร็จ 5 ก.ค. 2569 เวลา 09:10 น. — verify หลัง deploy ด้วย `fetch()` จริงบนเว็บ ยืนยันคำเก่าหายหมด คำใหม่ครบ ไม่มี regression กับฟีเจอร์เดิม

**สิ่งที่ยังไม่ทำในรอบนี้:** คู่มือผู้ใช้ (ข้อ 8 ของ CLAUDE.md) ยังไม่อัปเดต

---

## 19. ตั้งค่าระบบผ่าน UI + จัดการบัญชีหัวหน้า PIN ด้วยกันเอง (เฉพาะชวนชัย) — รายละเอียด (5 ก.ค. 2569)

**สถานะ: เขียนโค้ดเสร็จ (`dashboard.html` เท่านั้น) + backend (migration 22) รันบน Supabase แล้วจริงและ verify ผ่านหมด — deploy แล้ว 5 ก.ค. 2569 เวลา 15:23 น. รวมกับข้อ 20**

**คำขอเดิม (ที่มา):** ชวนชัยพูดถึง 3 อย่างที่ "น่าจะเข้าเกณฑ์ชวนชัยควรมีแต่คนเดียว" (มาจาก memory `project_supervisor_privilege_tiers_plan`): (1) จัดการบัญชีหัวหน้าด้วยกันเอง (2) ตั้งค่าระบบผ่าน UI แทน SQL Editor (3) กำหนดว่าใครดูแลแผนกไหน — **ข้อ 3 ไม่ทำรอบนี้** เพราะระบบแผนกยังไม่มีอยู่จริง

**การตัดสินใจออกแบบที่ยืนยันกับเจ้าของแล้ว:**
- รีเซ็ต PIN ให้หัวหน้า PIN — ไม่ต้องเขียนโค้ดใหม่เลย (`do_reset_pin` เดิมใช้ได้อยู่แล้ว)
- ขอบเขตตั้งค่าระบบ v1: พิกัด GPS + เวลาเกณฑ์สี 3 ค่า + เวลาฟันธงขาดเช็กอิน เท่านั้น
- จัดการบัญชีหัวหน้า PIN: เพิ่มบัญชีใหม่ได้ (จำกัดแค่ PIN) + ปิด/เปิดใช้งานบัญชีที่มีอยู่ (ไม่รวมบัญชีชวนชัยเอง ห้ามปิดตัวเอง)
- ทั้งหมดเป็น RPC เฉพาะ auth ไม่มีเวอร์ชัน PIN คู่กัน (ไม่แตะ report.html/index.html)

**Backend (migration `22_admin_settings_supervisor_mgmt.sql`):**
- `do_get_settings()` / `do_set_settings(...)` (auth-only) — validate พิกัด/ลำดับเวลา/ครบทุกช่อง
- `do_add_supervisor(...)` (auth-only) — เพิ่มแถว officer ใหม่ `is_supervisor=true, active=false, login_method='pin', pin_hash=null`
- `do_set_supervisor_status(...)` (auth-only) — validate ห้ามแก้บัญชี auth/ตัวเอง
- **⚠️ บั๊กที่พบและแก้ก่อน deploy จริง**: ดีไซน์แรกให้ toggle คอลัมน์ `is_supervisor` ตรงๆ แต่ `do_list_supervisors()` กรอง `is_supervisor=true` อยู่แล้ว ทำให้ปิดบัญชีแล้วเปิดกลับไม่ได้ผ่าน UI — แก้โดยเพิ่มคอลัมน์ใหม่ `officer.supervisor_enabled` แยกต่างหาก ให้ `is_supervisor` คงเป็น `true` ถาวร ส่วน `supervisor_enabled` เป็นตัวเปิด/ปิดใช้งานจริง

**Verify แล้ว:** ทุก RPC ผ่านครบ (invalid_coordinates/invalid_time_order/missing_field/not_supervisor/name_required/cannot_modify_auth_supervisor/cannot_modify_self/officer_not_found) — **⚠️ ระวัง**: ทดสอบ `do_set_settings` กระทบแถว `settings` จริง ต้องสำรอง+restore ทุกครั้ง — **บทเรียนทางเทคนิค**: ห้ามรวม RPC ที่ mutate ข้อมูลกับการอ่านค่าผลลัพธ์ทันทีใน `json_build_object(...)` เดียวกัน (ลำดับ evaluation ของ PostgreSQL ใน target list ไม่รับประกัน)

**Frontend (`dashboard.html` เท่านั้น):** เพิ่มการ์ด "⚙️ ตั้งค่าระบบ (เฉพาะชวนชัย)" + การ์ด "👤 จัดการบัญชีหัวหน้า (เฉพาะชวนชัย)"

**สิ่งที่ยังไม่ทำในรอบนี้:** ข้อ 3 ของคำขอเดิม (แผนก) — ไม่ทำเพราะระบบแผนกยังไม่มีอยู่จริง; คู่มือผู้ใช้ไม่เกี่ยวข้อง

---

## 20. PDPA auto photo-deletion (ลบรูปเซลฟี่อัตโนมัติ 31 วัน + retention hold) — รายละเอียด (5 ก.ค. 2569, รันอัตโนมัติผ่าน scheduled task)

**สถานะ: เขียนโค้ดเสร็จทั้ง 2 ไฟล์ (`dashboard.html`, `report.html`) + backend (migration 23) รันบน Supabase แล้วจริงและ verify ผ่านหมด + Edge Function `delete-old-photos` deploy แล้วจริงบน Supabase + ตั้ง pg_cron รันทุกวันแล้ว + ทดสอบ end-to-end ผ่านจริง — deploy แล้ว 5 ก.ค. 2569 เวลา 15:23 น. รวมกับงานข้อ 19**

**บริบท (ที่มา):** งานนี้รันแบบอัตโนมัติผ่าน scheduled task มาจากรายการค้างใน backlog เดิม: "นโยบายลบรูปอัตโนมัติ (PDPA)"

**การตัดสินใจออกแบบ:**
- **Retention hold**: แฟล็ก "กันลบรูป" ที่หัวหน้าทั้ง 3 คนตั้งได้ต่อรายการเช็กอิน (กรณีมีข้อพิพาท/ถูก override ที่อยู่ระหว่างตรวจสอบ)
- **ระยะเวลาเก็บ**: 31 วัน แบบ rolling window (นับจาก `checked_in_at`) ปรับได้ผ่าน `settings.photo_retention_days`
- **เก็บ metadata อื่นถาวร**: ลบแค่ตัวไฟล์รูปจาก Storage เท่านั้น

**Backend (migration `23_photo_retention.sql`):**
- ติดตั้ง `pg_cron`, `pg_net`
- `check_in.retention_hold` (boolean), `check_in.photo_deleted_at` (timestamptz)
- **⚠️ แก้ constraint เดิม**: `check_in.photo_path` เปลี่ยนจาก `not null` เป็น nullable (เจอบั๊กจาก error จริงตอนทดสอบ E2E ครั้งแรก)
- `do_set_retention_hold(...)` / `do_supervisor_set_retention_hold(...)` — สิทธิ์เดียวกับ override (หัวหน้าทั้ง 3 คน)
- แก้ 4 RPC อ่านข้อมูลให้ return `retention_hold`/`photo_deleted_at` เพิ่ม

**Supabase Edge Function `delete-old-photos`:**
URL: `https://aamzsbuwfdyljdvwaifb.supabase.co/functions/v1/delete-old-photos`
- อ่าน `photo_retention_days` (fallback 31) → หาแถวเก่ากว่า cutoff + ไม่ hold + มี photo_path + ยังไม่เคยลบ → ลบไฟล์จริงผ่าน **Storage API** (ไม่ raw SQL delete เพราะติด trigger `protect_delete()`) → อัปเดต `photo_path=null, photo_deleted_at=now()`
- สิทธิ์เรียก: header `x-cron-secret` เทียบกับ Function Secret `CRON_SECRET`
- Cron: `cron.schedule('delete-old-photos-daily', '0 19 * * *', ...)` (02:00 น. เวลาไทย) ผ่าน `net.http_post`

**Verify แล้ว:** ทดสอบ end-to-end เต็มรูปแบบ (แถว retention_hold=false ถูกลบไฟล์จริง, แถว retention_hold=true ไม่ถูกแตะ), ทดสอบสิทธิ์เรียกฟังก์ชัน (401 ถ้าไม่ส่ง/ผิด header)

**Frontend (`dashboard.html`/`report.html`):** badge "🔒 กันลบรูป", ช่องรูปแสดง "🗑️ ลบแล้ว (PDPA)" ถ้าถูกลบ, ปุ่ม "🔒/🔓" กันลบรูปต่อแถว

**สิ่งที่ยังไม่ทำในรอบนี้:** คู่มือผู้ใช้ไม่เกี่ยวข้อง; error-message mapping ยังไม่ครบทุก error code (fallback แสดง raw code)

---

## 21. ขยายกล่องหมายเหตุเพิ่มเติมให้สูงขึ้น + ตัดข้อความยาวในตาราง + การ์ด "แจ้งไม่พร้อม" (6 ก.ค. 2569)

**สถานะ: ✅ เสร็จสมบูรณ์ + deploy แล้ว — แก้โค้ดเสร็จทั้ง 3 ไฟล์ + อัปโหลดขึ้น Netlify Drop สำเร็จ 6 ก.ค. 2569 เวลา 10:34 น. verify หลัง deploy ผ่านหมด**

**คำขอเดิม (ที่มา):** เจ้าของขอ (1) ขยายกล่องหมายเหตุเพิ่มเติมหลังเช็กอินให้สูงขึ้นจาก ~2 บรรทัด เป็น 6 บรรทัด (2) ตารางเช็กอินวันนี้/ประวัติ ควรปรับรับข้อความยาวขึ้นไหม + ควรมีตัวกรอง/สรุปว่าหมายเหตุสั้นก่อนเช็กอินพูดถึงเรื่องอะไรไหม

**การตัดสินใจออกแบบ:**
- ตัดข้อความยาวในตาราง + ปุ่มขยายดู (แทนการ wrap เต็ม)
- เน้นจับ "ไม่พร้อม" เป็นหลัก (ใช้ `ready_for_duty` ที่มีอยู่แล้ว ไม่เพิ่ม backend)

**การเปลี่ยนแปลง:**
- `index.html` — CSS scoped `.remark-box textarea{min-height:150px;}` (ไม่แตะ `#noteInput`)
- `dashboard.html`/`report.html` — ฟังก์ชัน `renderRemarkCell(remark)` ตัดข้อความยาวกว่า 70 ตัวอักษร + ปุ่ม "อ่านเพิ่มเติม/ย่อ", การ์ด "⚠️ วันนี้แจ้งไม่พร้อม" กรองแถว `ready_for_duty === false`
- ไม่มี backend/migration ใหม่ในรอบนี้

**Deploy:** อัปโหลด 3 ไฟล์ผ่าน Netlify Drop สำเร็จ 6 ก.ค. 2569 เวลา 10:34 น. — verify หลัง deploy ผ่านหมด ไม่มี regression

**สิ่งที่ยังไม่ทำในรอบนี้:** คู่มือผู้ใช้ไม่เกี่ยวข้องโดยตรง

---

## 22. Badge ระดับทีมสำหรับกลุ่มงานธุรกิจ/ครอบครัว — ดีไซน์ยืนยันแล้ว แต่ตั้งใจ "ยังไม่เริ่มทำ" จนกว่าจะครบ ~2 สัปดาห์ (6 ก.ค. 2569)

**สถานะ: เป็นแค่การคุยออกแบบ (consultation) ไม่มีโค้ด/migration ใดๆ ในรอบนี้ — บันทึกดีไซน์ที่ยืนยันแล้วไว้เป็นแผนรอทำ ห้าม agent เริ่มเขียนโค้ดก่อนถึงกำหนดที่เจ้าของขอ (~20 ก.ค. 2569) เว้นแต่เจ้าของหยิบยกขึ้นมาเอง — รายละเอียดเต็มบันทึกไว้ใน agent memory ไฟล์ `project_team_coverage_badge_design.md` ด้วย (ไม่ใช่แค่ในเอกสารนี้)**

**คำถามเดิม (ที่มา):** ตม.จว.ระยองมี 2 กลุ่มงานที่มีเจ้าหน้าที่กลุ่มละ 2 คน คือกลุ่มงานธุรกิจและกลุ่มงานครอบครัว ทั้งสองกลุ่มมักต้องอยู่เคลียร์งาน/ทำ OT ดึกเป็นประจำ เจ้าของถามว่า ถ้ามีเจ้าหน้าที่หนึ่งคนในทีมมาพร้อมรับประชาชนก่อน 08:20 ควรถือว่า "ดีเยี่ยม" ทั้งคู่ไหม

**ข้อสังเกตที่ผมท้วงติงก่อนตอบตรงๆ:**
1. นี่คือการเปลี่ยนเกณฑ์ scoring ของสีเช็กอิน ไม่ใช่แค่ปรับ UI — สเปกตั้งต้นกำหนดเฟส D ให้รอใช้งานจริงครบ 1 เดือนก่อนตัดสินใจ
2. ถ้าให้ "ดีเยี่ยมทั้งคู่" โดยไม่มีเพดานเวลาสำหรับคนมาทีหลังเลย เสี่ยงเกิดคำถามเรื่องความเป็นธรรมจากอีก 15 คนที่ไม่มีสิทธิ์นี้

**ดีไซน์ที่ยืนยันกับเจ้าของแล้ว (ผ่าน AskUserQuestion 3 ข้อ):**
- **รูปแบบ:** แยก badge ระดับทีมต่างหาก **ไม่แตะสีรายคนเลย**
- **เกณฑ์ badge** (คำนวณจากเวลาเช็กอินเร็วที่สุดของสมาชิกในทีมวันนั้น): ✅ มีคนมาก่อน 08:20 / 🟡 ไม่มีใครมาก่อน 08:20 แต่มีคนมาก่อน 09:00 / ⚠️ เลย 09:00 แล้วยังไม่มีใครเช็กอินเลยทั้งทีม
- **ข้อมูล:** เพิ่มคอลัมน์ `officer.team_name` (ธุรกิจ/ครอบครัว) พอ — RPC ทำนอง `do_get_team_coverage`/`do_supervisor_get_team_coverage`
- **จังหวะเวลา:** เจ้าของขอ **รอ ~2 สัปดาห์ก่อน** (ตกลง 6 ก.ค. 2569 → เริ่มทำได้ราวๆ 20 ก.ค. 2569)

**สิ่งที่ยังไม่ทำ (ตั้งใจ):** ยังไม่มี migration/RPC/โค้ด frontend ใดๆ สำหรับฟีเจอร์นี้ — agent ตัวถัดไปที่มารับงานต่อ **ห้ามเริ่มทำเองก่อนถึง ~20 ก.ค. 2569** เว้นแต่เจ้าของหยิบยกขึ้นมาเอง
