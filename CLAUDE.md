# CLAUDE.md — บันทึกความคืบหน้าโปรเจกต์ระบบเช็กอินเช้าเจ้าหน้าที่

> เอกสารนี้คือ **agent handoff log** — บันทึกสิ่งที่ทำไปแล้วจริง (ไม่ใช่สเปกตั้งต้น) เพื่อให้ agent ตัวถัดไปที่มารับงานต่อ
> เข้าใจสถานะปัจจุบันได้ทันที โดยไม่ต้องขุด SQL/HTML เองทั้งหมด
> สเปกตั้งต้น (v1 spec, กติกาเหล็ก 6 ข้อ, ขอบเขต v1) ยังคงใช้เป็นหลักอยู่ — เอกสารนี้เสริม ไม่ใช่แทนที่
> **⚠️ (7 ก.ค. 2569) มีเอกสารแผนพัฒนาระยะ 2 เพิ่มเติมแล้ว: `90_ROADMAP_v2_PLAN.md`** (จัดทำโดย agent วางแผนอีกเซสชันหนึ่งตามคำสั่งเจ้าของ 6 ก.ค. 2569) — อ่านคู่กับไฟล์นี้เสมอถ้าจะทำงานต่อจาก v1 ไปเฟส P0–P3 (git+CI, PIN rate limit, badge ทีม, scoring, multi-office) **✅ P0.2 (git+CI) ทำเสร็จ 9 ก.ค. 2569 (ข้อ 23), ✅ P0.1 (คอลัมน์สิทธิ์หัวหน้า + error mapping ปุ่มกันลบรูป) ทำเสร็จ 10 ก.ค. 2569 (ข้อ 25), ✅ P0.3 (PIN rate limiting, migration 25) เขียนโค้ด+รัน SQL จริง+ทดสอบ E2E ผ่านหมด+push frontend สำเร็จแล้ว (ดูข้อ 27) + P0.4 (backup) เจ้าของสั่ง**พักไว้ก่อน 11 ก.ค. 2569** ผูกกับเงื่อนไข P3/multi-office แทน ห้าม agent เริ่มเองก่อนเจ้าของหยิบยก (ดูข้อ 28)** ✅ P0.5 (จัดกลุ่มการ์ด + mobile card layout report.html) เสร็จสมบูรณ์+push แล้ว 11 ก.ค. 2569 — **⚠️ เจอ+แก้บั๊กจริงบน production วันเดียวกัน: `check_and_count_pin` (migration 25) บล็อกหัวหน้า PIN ล็อกอินไม่ได้ แก้เป็น migration 26 แล้ว (ดูข้อ 29) ทำให้เลข migration ของ P1.1 เลื่อนจาก 26 เป็น 27**

> **📦 (9 ก.ค. 2569) ไฟล์นี้แยกเป็น 2 ไฟล์แล้ว เพื่อลดขนาด/เวลาที่ agent ต้องอ่าน-เขียนทุกครั้งที่ push:**
> - `CLAUDE.md` (ไฟล์นี้) = กติกาการทำงาน + migration table + บั๊กที่เจอ + backlog + งานที่ยัง active อยู่ (ข้อ 1–8, 23–24)
> - `CLAUDE_ARCHIVE.md` = รายละเอียดเต็มของฟีเจอร์ที่ปิดงานแล้ว (ข้อ 9–22 เดิม) — เปิดเฉพาะตอนต้องการรายละเอียดเชิงลึกของฟีเจอร์ใดฟีเจอร์หนึ่ง ไม่ต้องอ่านทุกครั้ง
> **ทุกที่ในไฟล์นี้ที่เขียนว่า "ดูข้อ N" โดยที่ N อยู่ในช่วง 9–22 หมายถึงหัวข้อ "## N." ใน `CLAUDE_ARCHIVE.md`** ส่วน N ≤ 8 หรือ N = 23–24 อยู่ในไฟล์นี้ตามเดิม

**✅✅ (9 ก.ค. 2569) ย้าย deploy จาก Netlify Drop เป็น Git + Netlify CI อัตโนมัติแล้ว — เปลี่ยนกติกาการทำงานสำคัญ ดูข้อ 23:** push โค้ดขึ้น GitHub แล้ว Netlify build+publish ให้เองอัตโนมัติ ไม่ต้องอัปโหลดไฟล์มือทาง Netlify Drop อีกต่อไป **กติกาการขอ confirm เปลี่ยนจาก "ถามก่อน deploy" เป็น "ถามก่อน push ขึ้น git" แทน** (ดูข้อ 2.1 ที่แก้ไขแล้ว) ทดสอบ auto-deploy และ rollback ผ่าน Netlify UI แล้วทั้งคู่ผ่านหมด repo เปลี่ยนเป็น public แล้ว (จำเป็นเพื่อแก้บั๊ก "Unrecognized Git contributor") และดาวน์เกรด Netlify จาก Personal ($9/เดือน) เป็น Free ($0/เดือน) แล้ว มีผลจริง 7 ส.ค. 2569

**✅ (9-10 ก.ค. 2569) บั๊ก "รูปเช็กอินกำพร้าใน Storage" ปิดงานสมบูรณ์แล้ว — push, deploy, และ E2E test ผ่านหมดจริง:** ดูรายละเอียดเต็มในข้อ 24 (สถานะล่าสุด: เสร็จสมบูรณ์ ไม่มีงานค้าง)

**⚠️ บทเรียนสำคัญจากรอบนี้ (10 ก.ค. 2569) — ดูกติกาใหม่ข้อ 2.11:** เซสชันก่อนหน้าพยายาม deploy Edge Function ผ่านหน้า Supabase Dashboard ด้วยเบราว์เซอร์แล้วโดน safeguard ตัดเซสชันกลางคัน จนเจ้าของต้องเข้าไป deploy เองด้วยมือแทน **ห้าม agent พยายามแก้ไข/deploy อะไรผ่านหน้า "Edge Functions" ใน Supabase Dashboard อีกเด็ดขาด** — ถ้าจำเป็นต้องแก้ Edge Function ให้เตรียมโค้ดให้พร้อมแล้วให้เจ้าของเป็นคน paste+deploy เอง ส่วนการ**ทดสอบ**ฟังก์ชันหลัง deploy ยังทำได้ปกติผ่านหน้า **SQL Editor** (คนละหน้ากัน ไม่ติดข้อห้ามนี้) ด้วยการเรียก `net.http_post` ตรงๆ ตามวิธีในข้อ 24.1

**✅ (10 ก.ค. 2569) แก้ timeout สั้นเกินไปของ cron `delete-old-photos-daily` เสร็จแล้ว:** เพิ่ม `timeout_milliseconds := 60000` ใน `net.http_post` ของ cron job ผ่าน SQL Editor ตรง (migration `24_cron_timeout_fix.sql`) verify แล้ว jobid/schedule/active ไม่เปลี่ยน — ปิดประเด็นนี้สมบูรณ์ ไม่มีงานค้างจากบั๊กรูปกำพร้าเหลืออยู่เลย

**✅✅ (10 ก.ค. 2569) P0.1 push ขึ้น git สำเร็จแล้วจริง (commit `37827bc`) + GPS timeout quick win push แยกอีก commit (`f58cd48`) — verify บนเว็บจริงผ่านหมด:** เจ้าของสร้าง fine-grained PAT เองแล้วส่งให้ใช้ครั้งเดียวตามขั้นตอนเดิม (ข้อ 23.4) ทั้งสอง commit deploy อัตโนมัติผ่าน Netlify และ verify ด้วย `fetch()` จริงบน `rayongimm.link` แล้วว่า `report.html` มีคอลัมน์ "สิทธิ์หัวหน้า"+`RETENTION_ERROR_MAP`, `dashboard.html` มี `RETENTION_ERROR_MAP`, และ `index.html` มี GPS `timeout: 20000` ครบทุกจุด — **⚠️ เจอบั๊กเชิงกระบวนการระหว่างรอบนี้ กันเจอซ้ำ ดูกติกาใหม่ข้อ 2.12:** ตอน sync ไฟล์เข้า `/tmp` git clone รอบแรก ลืมคัดลอก `index.html` (ที่แก้ GPS timeout ไปแล้วในโฟลเดอร์โปรเจกต์จริง) เข้าไปด้วย ทำให้ commit แรกไม่มีการเปลี่ยนแปลงของไฟล์นี้เลย ตรวจพบเพราะ verify บนเว็บจริงหลัง push แล้วเจอว่า `index.html` ไม่มี `timeout: 20000` ทั้งที่ commit ไปแล้ว จึงต้อง sync+commit+push แก้เพิ่มอีกรอบ (`f58cd48`) — **บทเรียน: ทุกครั้งก่อน `git add -A && git commit` ต้องเช็ก `git status --short` ในเซสชันนั้นเทียบกับ "รายการไฟล์ทั้งหมดที่แก้จริงในเซสชันนี้" (ไม่ใช่แค่ไฟล์ที่อยู่ในขอบเขตงานที่เพิ่งพูดถึง) และต้อง verify บนเว็บจริงหลัง push ทุกไฟล์ที่อ้างว่าแก้ไป ไม่ใช่แค่ไฟล์ที่จำได้ว่า sync ไปแล้ว**

**✅ (10 ก.ค. 2569) P0.1 ตาม `90_ROADMAP_v2_PLAN.md` เสร็จสมบูรณ์แล้ว:** เพิ่มคอลัมน์ "สิทธิ์หัวหน้า" ใน `report.html` + แก้ error mapping ปุ่มกันลบรูปทั้ง `dashboard.html`/`report.html` ให้ครบทุก error code (ดูข้อ 25) เจ้าของ confirm push แล้ว

**✅ (10 ก.ค. 2569) UX quick win รอบ 2 push แล้ว (commit `5f7cac2`) — verify บนเว็บจริงผ่าน:** `index.html` เพิ่ม 3 อย่าง (1) จำชื่อล่าสุดที่เลือกใน localStorage มาเป็นค่า default ครั้งถัดไป (2) ปุ่มลัดหมายเหตุ "⚡ ปฏิบัติงานปกติ" กรอกข้อความให้อัตโนมัติ (3) แสดงสถานะ GPS (🟡/🟢/🔴/⚪) ในหน้า "ตรวจสอบก่อนยืนยัน" ไม่ใช่แค่ตอน modal ม่วงเด้งเท่านั้น — ทั้งสามอย่างอยู่ไฟล์เดียว ไม่แตะ RPC risk ต่ำ

**✅✅✅ (13 ก.ค. 2569) P1a เสร็จสมบูรณ์ทั้งหมด — backend (migration 27+28) + frontend (dashboard.html/report.html) + E2E test 4 สถานะ badge + push ขึ้น git สำเร็จแล้ว — ดูข้อ 30:** เจ้าของยืนยันให้เริ่ม P1a (badge ทีม OT + work_group) ได้ทันทีโดยไม่ต้องรอ 20 ก.ค. ตามเดิม — Backend: ตาราง `work_group` (ไม่ pre-seed), `officer.work_group_id`, `settings.team_ok_before`/`team_warn_before`, RPC อ่าน coverage 3 ตัว (migration 27) + RPC จัดการกลุ่ม auth-only 5 ตัว (migration 28) — **เจอ+แก้บั๊กจริงระหว่างทำ: `CREATE OR REPLACE FUNCTION do_set_settings` ที่เพิ่มพารามิเตอร์ใหม่ต่อท้ายกลายเป็นสร้าง overload ซ้ำ ตรวจพบจาก verification query แล้วแก้ด้วย DROP ของเดิมทิ้ง (ดูกติกาใหม่ข้อ 2.14)** — Frontend: การ์ด "🤝 จุดบริการกลุ่มงาน OT" ทั้ง 2 ไฟล์ + การ์ด "จัดการกลุ่มงาน OT" (เฉพาะ dashboard.html) + คอลัมน์ "กลุ่มงาน" ในตารางเจ้าหน้าที่ทั้ง 2 ไฟล์ + mobile CSS ครบ, verify syntax ผ่าน `node --check` ทั้งคู่ — E2E: ทดสอบครบ 4 สถานะ badge (ok/warn/none/pending) ด้วยข้อมูลจำลอง + ยืนยัน snapshot ก่อน-หลังว่าสีเช็กอินรายบุคคลของเจ้าหน้าที่จริง 18 คนไม่เปลี่ยนแปลงเลย ผ่านหมดทุกเคส ลบข้อมูลทดสอบ+ฟังก์ชันชั่วคราวออกครบ — **push ขึ้น git สำเร็จ 13 ก.ค. 2569 (ดู git log สำหรับ hash), verify บนเว็บจริงผ่าน** **⚠️ ข้อสังเกตที่เจ้าของแจ้งไว้ (13 ก.ค. 2569): ไม่ชอบชื่อการ์ด "🤝 จุดบริการกลุ่มงาน OT" ต้องการให้ชวนชัยเปลี่ยนชื่อเองได้ภายหลัง — เป็นแค่ข้อความ HTML 1 บรรทัดในทั้ง 2 ไฟล์ (dashboard.html/report.html) แก้ง่าย ไม่กระทบ backend/RPC เลย ยังไม่ได้แก้ในรอบนี้ รอเจ้าของบอกชื่อใหม่**

อัปเดตล่าสุด: 13 กรกฎาคม 2569 (P1a เสร็จสมบูรณ์ครบ backend+frontend+E2E test+push แล้ว ดูข้อ 30 — ก่อนหน้านี้ 11 ก.ค.) (พบ+แก้บั๊กจริงบน production: ศุภัตราเข้า report.html ไม่ได้ เพราะ `check_and_count_pin` migration 25 บล็อกหัวหน้า PIN ทุกคน — วินิจฉัยจริงผ่าน SQL Editor, แก้เป็น migration 26, verify ผ่าน REST จริง, เจ้าของยืนยันเข้าได้ปกติแล้ว, push ขึ้น git แล้ว (commit `310f123`) ดูข้อ 29 — ก่อนหน้านั้นวันเดียวกัน: P0.5 จัดกลุ่มการ์ด dashboard/report.html + mobile card layout report.html เสร็จสมบูรณ์+push แล้ว (commit `5d146fd`, `310f123`), เพิ่มดีไซน์ P1.3 Grace Card ใน roadmap (ยังไม่เขียนโค้ด), P0.4 backup ตรวจสอบสดแล้วเจ้าของสั่งพักไว้ก่อนผูกกับ P3 ดูข้อ 28 — ก่อนหน้านี้ (10 ก.ค. บ่าย): P0.3 PIN rate limiting SQL migration 25 รันจริง+ทดสอบ E2E+แก้ frontend+push ขึ้น git สำเร็จครบ (commit `4ccfa23`) ดูข้อ 27 — ก่อนหน้านั้นเช้า 10 ก.ค.: ปิดงานบั๊กรูปกำพร้า + แก้ cron timeout + P0.1 เสร็จครบทั้งหมด + GPS timeout quick win + UX quick win รอบ 2 push แล้ว + บันทึกกระบวนการทำงาน/บทเรียน PAT-credit ลงข้อ 26 ดูข้อ 24/24.1/25/26/27/28/29)

**📌 มีแผนงานใหม่ที่ยืนยันดีไซน์แล้วแต่ตั้งใจ "ยังไม่เริ่มทำ" — ดูข้อ 22 ใน CLAUDE_ARCHIVE.md:** ระบบ badge ระดับทีมสำหรับกลุ่มงานธุรกิจ/ครอบครัว (2 คน/กลุ่ม ที่มักต้อง OT ดึกเป็นประจำ) ดีไซน์ยืนยันกับเจ้าของแล้ว 6 ก.ค. 2569 — **(อัปเดต 13 ก.ค. 2569: P1a เริ่มทำแล้วจริงตามที่เจ้าของยืนยันให้เริ่มก่อนกำหนดเดิม 20 ก.ค. — ดูข้อ 30 ไม่ต้องรออีกต่อไป)**

---

## 1. สถานะปัจจุบัน (สรุปสั้น)

ระบบ **ใช้งานจริงแล้ว** (live) — เจ้าหน้าที่เช็กอินจริงตั้งแต่เช้าวันที่ 3 กรกฎาคม 2569 (18+ คนเช็กอินสำเร็จ) หัวหน้าเข้าดูแดชบอร์ดได้ทั้ง 2 แบบ (Auth และ PIN) รวมถึงดูรูปย่อได้แล้วทั้งคู่ มีสถานะ **สีม่วง (เช็กอินไม่สมบูรณ์)** — แสดงคู่กับสีเวลาเดิม เมื่อเช็กอินห่างจากที่ทำงาน &gt;50 ม. หรือไม่เปิด/อนุญาต GPS (ข้อ 9 ใน archive) เพิ่ม **กล่องม็อตโต้หมุนเวียน 3 ข้อความ** (ข้อ 10, 17 ใน archive) และ **สถิติส่วนตัวรายเดือน** (เห็นเฉพาะตัวเอง รวมสีน้ำตาล "ขาดเช็กอิน", ข้อ 10, 16 ใน archive) แสดงหลังเช็กอินเสร็จทุกครั้ง **+ badge ทีม OT สำหรับกลุ่มงาน (P1a, ข้อ 30) ตั้งแต่ 13 ก.ค. 2569**

**ฟีเจอร์หลักที่ deploy แล้วและใช้งานจริง** (รายละเอียดเต็มทั้งหมดอยู่ใน `CLAUDE_ARCHIVE.md` ข้อ 9–22):
- แดชบอร์ดหัวหน้าครบสเปก v1 — ประวัติย้อนหลัง, override สถานะ, Export Excel (archive ข้อ 12)
- หมายเหตุเพิ่มเติมหลังเช็กอิน (write-once) + สรุปตามคีย์เวิร์ด 6 หมวด (archive ข้อ 14, 18)
- ระบบตารางเวรแบบง่าย (work_days) + วันหยุดนักขัตฤกษ์ + สีน้ำตาลเข้ม "ขาดเช็กอิน" (archive ข้อ 15)
- วันเริ่มนับสถิติรายเดือนแบบตั้งค่าได้ (archive ข้อ 16)
- ตั้งค่าระบบผ่าน UI + จัดการบัญชีหัวหน้า PIN (เฉพาะชวนชัย, archive ข้อ 19)
- PDPA auto photo-deletion (31 วัน rolling + retention hold, archive ข้อ 20)
- ตัดข้อความยาวในตาราง + การ์ด "วันนี้แจ้งไม่พร้อม" (archive ข้อ 21)
- **Git + Netlify CI (deploy อัตโนมัติ)** — ดูข้อ 23 ด้านล่าง (ยังอยู่ในไฟล์นี้ เพราะเป็นข้อมูล operational ที่ใช้ทุกเซสชัน)
- **Badge ทีม OT + work_group (P1a)** — ดูข้อ 30 ด้านล่าง

**⚠️ ถ้ากำลังเปิดโปรเจกต์นี้จาก Cowork project ใหม่ (เช่น ย้ายมาทำต่อบนเครื่องอื่น):** อ่าน `00_SPEC_v1_ORIGINAL.md` ในโฟลเดอร์นี้ก่อนเสมอ — เป็นสเปกตั้งต้น v1 ฉบับเต็ม (กติกาเหล็ก 6 ข้อ) ที่แยกออกมาจาก Cowork Project Instructions เดิม เพราะ Project Instructions ไม่ติดไปกับโฟลเดอร์เวลาเปิดโปรเจกต์ใหม่ (รายละเอียดเต็มอยู่ใน `CLAUDE_ARCHIVE.md` ข้อ 11)

**✅ (4 ก.ค. 2569) แก้ข้อมูลเจ้าหน้าที่ในฐานข้อมูลจริง (ไม่ต้อง deploy เพราะไม่ใช่โค้ด):** แก้นามสกุล ร.ต.อ.หญิง กชพร จากสะกดผิด "จี้คีรี" (ไม้โท) เป็นถูกต้อง "จี๋คีรี" (ไม้จัตวา), ย้าย sort_order ให้อยู่ระหว่างนรินทร์กับพีระชัย, เพิ่มรายชื่อทดสอบ "สมาชิกใหม่" ไว้ล่างสุดของ dropdown (ยังไม่ตั้ง PIN — ใช้ทดสอบขั้นตอนตั้ง PIN ครั้งแรกได้) มีผลทันทีบนเว็บจริงเพราะเป็นการแก้ข้อมูลใน Supabase ตรงๆ

**✅ (12 ก.ค. 2569) เพิ่มบัญชีทดสอบหัวหน้า PIN ถาวรสำหรับใช้ทดสอบ P1a-c: "สมาชิกใหม่ที่ขยันขันแข็ง"** (`id = 20f2b74f-e15b-4b77-94a7-eb8e8adb1650`, nickname "ทดสอบหัวหน้า") — insert ตรงผ่าน REST ด้วย service_role key (ไม่ผ่าน `do_add_supervisor` RPC เพราะ RPC นั้นเช็ก auth session ของชวนชัยเป็นผู้เรียก เรียกจาก SQL Editor context ไม่ได้) ตั้งค่าให้ตรงกับโครงสร้างจริงของ ศุภัตรา/ผู้ช่วยแอดมิน ทุกจุด: `active=false, is_supervisor=true, login_method='pin', supervisor_enabled=true, pin_hash=NULL` (ยังไม่ตั้ง PIN — ใช้ทดสอบขั้นตอนตั้ง PIN ครั้งแรกของหัวหน้าได้ด้วยในตัว) **ที่มา:** ตามกติกาข้อ 2.13 (migration ที่แตะ PIN/auth logic ต้องทดสอบด้วยบัญชีจำลองหัวหน้า PIN เสมอ ไม่ใช่แค่ officer ทั่วไปที่ `active=true`) เจ้าของขอให้เตรียมบัญชีนี้ไว้ล่วงหน้าก่อนเริ่ม P1 (work_group/badge ทีม/Grace Card/เช็คเอาท์) — **agent ตัวถัดไปที่ต้องทดสอบ RPC ตระกูล `do_supervisor_*` หรือฟีเจอร์ใดก็ตามที่ต้องจำลอง "หัวหน้า PIN" ให้ใช้บัญชีนี้แทนการสร้าง-ลบแถวทดสอบเองทุกรอบ** (ส่วน "สมาชิกใหม่" ตัวเดิมยังใช้ทดสอบ officer ทั่วไปแบบ `active=true` ต่อไปตามเดิม ไม่ใช่หัวหน้า)

**ลิงก์ใช้งานจริง (Netlify):**
| หน้า | URL | ใช้โดย |
|---|---|---|
| เช็กอินเช้า | https://comfy-gaufre-b6b83e.netlify.app/ | เจ้าหน้าที่ 19 คน |
| แดชบอร์ดหัวหน้า (Auth) | https://comfy-gaufre-b6b83e.netlify.app/dashboard.html | ชวนชัย (พ.ต.ท.) — ดูแลระบบสูงสุด |
| ดูรายงาน (PIN) | https://comfy-gaufre-b6b83e.netlify.app/report.html | ศุภัตรา (พ.ต.ท.หญิง), ผู้ช่วยแอดมิน |

โดเมนจริงที่ใช้งาน: `rayongimm.link` (ผูกกับ Netlify site เดียวกัน)

**Supabase project:** `RayongImm-Service` (project ref `aamzsbuwfdyljdvwaifb`, org: Chuan)
**Netlify site:** `comfy-gaufre-b6b83e` (custom domain `rayongimm.link`) — **✅ (9 ก.ค. 2569) เปลี่ยนเป็น deploy แบบ Git + Netlify CI แล้ว ไม่ใช่ Netlify Drop อีกต่อไป** push ขึ้น GitHub repo `chuan4662/rayong-imm-checkin` (**Public**) แล้ว Netlify build+publish ให้เองอัตโนมัติ — ดูรายละเอียดเต็ม + วิธี commit ที่ถูกต้องในข้อ 23 **แพลน Netlify: กำหนดดาวน์เกรดจาก Personal ($9/เดือน) เป็น Free ($0/เดือน) แล้ว มีผลจริง 7 ส.ค. 2569**

---
## 2. ⚠️ กติกาการทำงานที่ agent ตัวถัดไปต้องรู้

1. **⚠️ (9 ก.ค. 2569 — แก้กติกาข้อนี้ใหม่) ห้าม `git push` ทันทีหลังแก้โค้ด** — เดิมกติกานี้คือ "ห้าม deploy ขึ้น Netlify Drop ทันที" แต่ตอนนี้ระบบเปลี่ยนเป็น **git + Netlify CI แล้ว** (ดูข้อ 23) ทุก push ขึ้น `main` จะ trigger ให้ Netlify build+publish อัตโนมัติทันที **ดังนั้นจุดที่ต้องขอ confirm คือ "ก่อน push" ไม่ใช่ "ก่อน deploy" อีกต่อไป** — แก้โค้ดเสร็จแล้วสรุปการเปลี่ยนแปลงให้เจ้าของโปรเจกต์ก่อน แล้ว**ถามว่าจะ push เลยไหม** รอ confirm ก่อนค่อย commit+push จริง (เหตุผลเดียวกับเดิม: เจ้าของกังวลเรื่องเปลือง Netlify build credit เพราะมักมีของแก้หลายอย่างสะสมก่อนค่อย push รวมกัน — เฉลี่ย ~15 เครดิต/ครั้งที่ push, ดูรายละเอียดเครดิตในข้อ 23)
   - ข้อยกเว้น: SQL migration บน Supabase **ยังรันทันทีได้ตามปกติ** ไม่ต้องรอ confirm เพราะไม่กระทบ Netlify credit และฝั่งหน้าเว็บมักต้องพึ่ง schema/RPC ใหม่ถึงจะทดสอบได้
   - **วิธี push ที่ถูกต้อง**: ห้าม `git init`/commit ตรงในโฟลเดอร์โปรเจกต์นี้เด็ดขาด (sandbox บล็อกการลบ/rename ไฟล์ในโฟลเดอร์ที่ sync กับ OneDrive) ต้องทำตามขั้นตอนในข้อ 23.4 เสมอ (sync ไปที่ `/tmp` ก่อน แล้ว commit+push จากตรงนั้น)
2. **ห้ามสร้างบัญชี Supabase Auth (email+password) ให้เจ้าของโปรเจกต์เอง** — เป็นกติกาความปลอดภัยของ agent (ห้ามพิมพ์/สร้างรหัสผ่านแทนผู้ใช้) เจ้าของต้องสร้างเองใน Supabase Dashboard เสมอ agent ช่วยได้แค่ตรวจสอบผลลัพธ์ (เช่น query `auth.users` ว่า confirm แล้วหรือยัง) **หลักการเดียวกันนี้ใช้กับ GitHub fine-grained PAT ด้วย: เจ้าของเป็นคนสร้าง+ส่งให้ agent ใช้ครั้งเดียวเสมอ (ดูข้อ 23.1/23.4) agent ไม่มีสิทธิ์สร้าง credential ให้ตัวเอง**
3. **~~Netlify deploy ทุกครั้งต้องอัปโหลด 3 ไฟล์พร้อมกันเสมอ~~ — ข้อนี้ไม่จำเป็นอีกต่อไปตั้งแต่ 9 ก.ค. 2569** เดิมเป็นกติกาเฉพาะ Netlify Drop (ต้องอัปโหลดไฟล์ทั้งชุดมือทุกครั้ง) ตอนนี้ git push ทั้ง repo ไปพร้อมกันเสมออัตโนมัติอยู่แล้ว (ดูข้อ 23) ไม่มีความเสี่ยงไฟล์หายจากการอัปโหลดไม่ครบอีกต่อไป
4. **ก่อนสรุปว่า "เสร็จแล้ว" ต้อง verify จริงเสมอ** — เรียก RPC จริง / เปิดหน้าเว็บจริงดู / ล็อกอินทดสอบจริง (ใช้แถวทดสอบชั่วคราวแล้วลบทิ้ง) ห้ามเดาว่าใช้ได้จากการอ่านโค้ดอย่างเดียว
5. **6 กติกาเหล็กของสเปกตั้งต้น (server time, timezone Bangkok, กล้องสดเท่านั้น, GPS ไม่บล็อก, 1 คน/วัน, ห้าม scope creep) ยังใช้อยู่เต็มรูปแบบ**
6. **⚠️ ก่อนแก้ `dashboard.html`/`report.html`/`index.html` ทุกครั้ง ต้องเช็กก่อนว่าไฟล์ในโฟลเดอร์นี้ตรงกับที่ deploy จริงบน Netlify หรือไม่** — เคยเจอเคสที่ไฟล์ในโฟลเดอร์เก่ากว่าของจริงบนเว็บ (ฟีเจอร์รูปย่อหายไปจากไฟล์ในเครื่อง ทั้งที่ deploy ไปแล้วจริง) ถ้าแก้ทับไฟล์เก่าแล้ว deploy จะเท่ากับ**ลบฟีเจอร์ที่ใช้งานจริงอยู่ออกโดยไม่ตั้งใจ** วิธีเช็ก: `fetch(location.href).then(r=>r.text())` จากแท็บที่เปิดหน้าเว็บจริงอยู่ เทียบกับไฟล์ในเครื่อง ถ้าไม่ตรงให้ดึงของจริงมาเป็นฐานก่อนแก้ (รายละเอียดเหตุการณ์อยู่ใน `CLAUDE_ARCHIVE.md` ข้อ 12 หัวข้อ "บริบท")
7. **⚠️ ทุกครั้งที่แก้ไฟล์เสร็จ (ก่อนถามว่าจะ push ไหม) ต้องส่งไฟล์/ลิงก์ให้เจ้าของตรวจสอบก่อนเสมอ** (เจ้าของขอไว้ 4 ก.ค. 2569) — ใช้ `present_files` ส่งไฟล์ HTML ที่แก้ให้เจ้าของเปิดดูเองในเบราว์เซอร์ (เปิดจาก path ในเครื่อง ก็เรียก Supabase จริงได้ปกติเพราะเป็น static file + public anon key) **(9 ก.ค. 2569)** ตอนนี้ Netlify ผูก git แล้วในทางเทคนิคสามารถทำ branch deploy/deploy preview ได้ แต่ **โปรเจกต์นี้ยังคง push ตรงไปที่ `main` เสมอ ไม่ได้ใช้ branch/PR flow** เพราะงั้นวิธีตรวจสอบก่อน push ยังคงเป็นการเปิดไฟล์ในเครื่องเหมือนเดิม ไม่ใช่ลิงก์ preview
8. **⚠️ ถ้ามีการแก้ไฟล์ค้างไว้ (verify ผ่านแล้วแต่ยังไม่ push) ต้องเตือนเจ้าของทุกครั้งที่เริ่มงานใหม่ในโปรเจกต์นี้** — เช็คได้จากหัวข้อ "อัปเดตล่าสุด" ด้านบนและข้อ 1 ว่ามีข้อความ "ยังไม่ deploy/push" ค้างอยู่หรือไม่ ห้ามปล่อยผ่านเงียบๆ
9. **⚠️ ห้ามรัน `git init`/`git commit`/`git add` ตรงในโฟลเดอร์โปรเจกต์นี้ (`Service Rayong Imm app`) เด็ดขาด** — sandbox ที่ agent ใช้บล็อกการลบ/rename ไฟล์ในโฟลเดอร์ที่ sync กับ OneDrive ทำให้ `.git` internals (lock files, refs) ใช้งานไม่ได้ ทุกครั้งที่จะ commit ต้อง sync ไปที่ `/tmp` ก่อนเสมอตามขั้นตอนในข้อ 23.4
10. **⚠️ (ใหม่ 9 ก.ค. 2569) บั๊ก bash-mount staleness — ห้ามเชื่อ bash/shell เวลาอ่านไฟล์ในโฟลเดอร์นี้ (`Service Rayong Imm app`) เด็ดขาด ให้ใช้ `Read` tool เป็นความจริงหลักเสมอ** — เจอซ้ำหลายครั้ง (`cat`/`wc -l`/`python open()`/`dd` ทุกวิธีให้ผลค้างเก่าเหมือนกันหมด บางครั้ง staleness นี้ครอบคลุมถึง byte size/mtime ด้วย ไม่ใช่แค่เนื้อหา) แม้จะ `sleep` รอนานหรือลองหลายวิธีก็ไม่การันตีว่าจะได้ข้อมูลสด — Grep tool และ Read tool ดูเหมือนจะไม่ติดบั๊กนี้ (เชื่อถือได้กว่า raw bash) ถ้าต้อง syntax-check ไฟล์ด้วย `node --check` ให้คัดลอกเนื้อหาจาก `Read` tool ไปสร้างไฟล์ scratch **ชื่อใหม่ที่ไม่เคยใช้มาก่อน** ใน outputs ก่อนเสมอ (อย่าเขียนทับไฟล์ scratch เดิม เจอบั๊กเดียวกันซ้ำได้แม้เป็นไฟล์ที่เพิ่งสร้างเองในเซสชันเดียวกัน) **⚠️ (13 ก.ค. 2569) เจอรูปแบบรุนแรงกว่าเดิม — mount cache ค้างได้นานถึง 3 วัน (ยืนยันจาก `stat` เห็น mtime ย้อนหลัง 3 วันจากที่แก้จริง) ไม่ใช่แค่ค้างชั่วคราว** วิธีแก้ที่ใช้ได้ผลจริงตอนนั้น: แทนที่จะ `cp`/`cat` ไฟล์ที่เพิ่งแก้ในเซสชันนี้จาก mount ตรงๆ ให้ (1) `git clone` โค้ดจาก GitHub สดใหม่มาที่ `/tmp` แทน (ไม่ผ่าน mount เลย) แล้ว (2) เขียน Python script replay ลำดับ `(old_string, new_string)` ของทุก Edit-tool call ที่ทำในเซสชันนั้น (คัดลอกมาจาก tool-call history ตรงๆ ไม่เดา) ไปใช้กับไฟล์ที่ clone มา แล้ว verify ด้วยจำนวนบรรทัด/marker string/`node --check` — ไฟล์ที่ไม่เคยถูก Edit ในเซสชันนั้นเลย (เช่น .sql ที่สร้างด้วย Write ครั้งเดียวไม่เคยแก้ต่อ) ยังพอเชื่อ `cp` จาก mount ได้ระดับหนึ่ง แต่ปลอดภัยกว่าถ้าอ่านผ่าน `Read` tool แล้ว `Write` ไปที่ outputs (ซึ่งไม่ติดบั๊กนี้) ก่อนแล้วค่อย `cp` จาก outputs เข้า `/tmp` git clone
11. **⚠️ (ใหม่ 10 ก.ค. 2569) ห้าม agent พยายามแก้ไข/deploy Edge Function ผ่านหน้า "Edge Functions" ใน Supabase Dashboard ด้วยเบราว์เซอร์ (Chrome/computer-use) อีกเด็ดขาด** — เซสชันก่อนหน้า (9 ก.ค. 2569) พยายาม deploy `edge_function_delete-old-photos.ts` เวอร์ชันใหม่ผ่านหน้านี้ด้วยเบราว์เซอร์ แล้วโดน safeguard ของระบบตัดเซสชันกลางคัน จนเจ้าของต้องเข้าไป deploy เองด้วยมือแทน (ยืนยันว่า deploy สำเร็จ + Verify JWT ยังปิดอยู่ตามที่ต้องการ) **บทเรียน:** งาน deploy/แก้ไขโค้ด Edge Function ผ่านเบราว์เซอร์มีความเสี่ยงโดน safeguard ตัดกลางคันสูง ควรให้เจ้าของทำเองเสมอ (agent เตรียมโค้ดให้พร้อม paste) แทนที่ agent จะคุมเบราว์เซอร์ทำการ deploy เองทั้งหมด — ส่วนการ **ทดสอบ/verify** ฟังก์ชันหลัง deploy ยังทำได้ปกติผ่านหน้า **SQL Editor** (คนละหน้ากับ Edge Functions ไม่ติดข้อห้ามนี้) โดยเรียก `net.http_post` ตรงๆ พร้อม header `x-cron-secret` จาก `vault.decrypted_secrets` เหมือนวิธีทดสอบเดิมใน migration 23 (ตัวอย่างจริงดูข้อ 24.1)
    - **⚠️ ข้อควรระวังที่เจอจริงระหว่างทดสอบ (10 ก.ค. 2569):** `net.http_post` ค่า default timeout คือ 5 วินาที ซึ่ง**สั้นเกินไป**สำหรับ orphan sweep ใหม่ (ต้อง recursive-list ทุกไฟล์ในทุกโฟลเดอร์ officer/date) ทำให้ `net._http_response.timed_out = true` แม้ฟังก์ชันจะยังทำงานต่อจนเสร็จจริงฝั่ง server ก็ตาม (ยืนยันจากผลทดสอบจริงในข้อ 24.1) **ถ้าจะเรียกฟังก์ชันนี้ผ่าน SQL Editor เพื่อทดสอบ/monitor ในอนาคต ต้องระบุ `timeout_milliseconds := 60000` (หรือมากกว่า) ใน `net.http_post` เสมอ ไม่งั้นจะได้ `content`/`status_code` เป็น NULL ทั้งที่ฟังก์ชันทำงานถูกต้อง** — **✅ (10 ก.ค. 2569) แก้แล้ว:** อัปเดต `cron.schedule('delete-old-photos-daily', ...)` ให้ใส่ `timeout_milliseconds := 60000` ด้วยเช่นกัน (ดู migration `24_cron_timeout_fix.sql`) รันตรงผ่าน SQL Editor แล้ว verify ผ่าน — jobid=1 เดิม, schedule `'0 19 * * *'` เดิม, active=true, `has_timeout=true` ไม่มีงานค้างเรื่องนี้อีกต่อไป
12. **⚠️ (ใหม่ 10 ก.ค. 2569) ก่อน `git add -A && git commit` ในขั้นตอน `/tmp` sync (ข้อ 23.4) ต้องเช็กให้ครบว่าคัดลอกไฟล์ที่แก้จริง "ทุกไฟล์" ในเซสชันนั้นแล้ว ไม่ใช่แค่ไฟล์ในขอบเขตงานที่กำลังพูดถึง** — เจอจริง 10 ก.ค. 2569: แก้ GPS timeout ใน `index.html` เสร็จไปแล้วแยกจากงาน P0.1 (คนละไฟล์ คนละบทสนทนาย่อย) พอถึงขั้น sync เข้า git clone ลืมคัดลอก `index.html` ไปด้วย ทำให้ commit แรกไม่มีการเปลี่ยนแปลงไฟล์นี้เลยทั้งที่บอกผู้ใช้ว่าทำแล้ว ต้อง push แก้เพิ่มอีกรอบ วิธีป้องกัน: ก่อน commit ให้ไล่ทวนรายการไฟล์ที่แก้จริงทั้งหมดในเซสชัน (ไม่ใช่แค่ที่เกี่ยวกับ task ล่าสุด) แล้ว **verify บนเว็บจริงหลัง push ทุกไฟล์ที่อ้างว่าแก้ไปเสมอ** (ใช้ `fetch()` เช็ก marker string ของแต่ละไฟล์ อย่าเชื่อว่า sync ไปแล้วเพราะจำได้)
13. **⚠️ (ใหม่ 11 ก.ค. 2569) migration ใดก็ตามที่แตะ logic การล็อกอิน/ยืนยันตัวตน (PIN หรือ auth) ต้องทดสอบ E2E ด้วยบัญชีที่จำลองสภาพ "หัวหน้า PIN" จริง (`active=false, is_supervisor=true`) เสมอ ไม่ใช่แค่ officer ทดสอบทั่วไปที่ `active=true`** — ที่มา: migration 25 (P0.3 PIN rate limiting) ทดสอบ E2E ผ่านหมดตอนแรกเพราะใช้ officer ทดสอบที่ `active=true` แต่ `check_and_count_pin` ที่เขียนขึ้นดันเช็กเงื่อนไข `active=true` ตรงๆ ซึ่งบัญชีหัวหน้า PIN จริง (ศุภัตรา, ผู้ช่วยแอดมิน) มี `active=false` โดยตั้งใจมาตั้งแต่ migration 11 (กันไม่ให้โผล่ในดรอปดาวน์เช็กอิน) ทำให้บั๊กหลุดรอดไปถึง production จริง บล็อกหัวหน้า PIN ล็อกอินไม่ได้เลยอยู่ 1 วันเต็ม (10-11 ก.ค. 2569) กว่าจะมีคนรายงานแล้วแก้เป็น migration 26 (ดูข้อ 29) — **บทเรียน:** โครงสร้างข้อมูลของโปรเจกต์นี้มีคอลัมน์ที่ความหมายไม่ตรงไปตรงมา (`active` ควบคุมทั้ง "โผล่ในดรอปดาวน์เช็กอินไหม" และถูกเข้าใจผิดว่าควบคุม "ยืนยันตัวตนได้ไหม" ด้วย) การทดสอบด้วย row ทดสอบทั่วไปที่ตั้งค่าเริ่มต้น (`active=true`) จึงไม่ครอบคลุมเคสจริงของบัญชีหัวหน้า ต่อไปนี้ทุก migration ที่แก้/เพิ่ม RPC ตระกูล `do_supervisor_*` หรือฟังก์ชันกลางที่ RPC เหล่านั้นเรียกร่วมกัน (เช่น `check_and_count_pin`) ต้องมีขั้นตอนทดสอบแยกด้วย officer ทดสอบที่ตั้ง `active=false, is_supervisor=true` (หรือ `supervisor_enabled=false` ถ้าเกี่ยวข้องกับ feature ที่ทดสอบ) อย่างน้อย 1 เคส ก่อนสรุปว่า "ทดสอบ E2E ผ่านหมด"
14. **⚠️ (ใหม่ 13 ก.ค. 2569) `CREATE OR REPLACE FUNCTION` ไม่ได้ "แทนที่" ฟังก์ชันเดิมเสมอไป ถ้าเปลี่ยน parameter list — ต้องเช็ก overload ซ้ำหลังแก้ RPC ที่เพิ่ม/ลด/เปลี่ยนชนิดพารามิเตอร์ทุกครั้ง** — Postgres ระบุตัวตนฟังก์ชันจาก **ชื่อ + ชนิดพารามิเตอร์แบบเรียงลำดับ** (function signature) ไม่ใช่แค่ชื่อ ถ้า `CREATE OR REPLACE FUNCTION do_x(...)` มี parameter list ต่างจากฟังก์ชันเดิม (เช่น เพิ่มพารามิเตอร์ใหม่ต่อท้ายแม้จะใส่ `DEFAULT NULL` ก็ตาม) Postgres จะไม่ replace ของเดิม แต่จะ **สร้าง overload ใหม่แยกต่างหาก** ทำให้มี 2 ฟังก์ชันชื่อเดียวกันพร้อมกัน (เจอจริงตอนทำ migration 27/P1a: เพิ่ม `p_team_ok_before`/`p_team_warn_before` ต่อท้าย `do_set_settings` เดิม 6 พารามิเตอร์ กลายเป็นมี 2 overload ค้างอยู่ ตรวจพบเพราะ query verification ที่ทำ `select ... from pg_proc where proname = 'do_set_settings'` แล้วได้ `ERROR: 21000: more than one row returned by a subquery` — ถ้าไม่ verify แบบนี้จะไม่รู้เลยว่ามี 2 ฟังก์ชันซ้อนกัน) **บทเรียน/วิธีป้องกัน:** (1) ถ้าตั้งใจจะ "เพิ่มพารามิเตอร์แบบ optional ให้ backward compatible" ต้อง **DROP ฟังก์ชันเดิมด้วย signature เดิมทิ้งก่อนเสมอ** แล้วค่อย CREATE ตัวใหม่ที่มี parameter ครบ (เดิม + ใหม่ที่มี DEFAULT) — วิธีนี้ได้ผลลัพธ์เดียวกับที่ตั้งใจ (เรียกด้วย arg ครบเท่าเดิมได้ ไม่พัง) แต่ไม่ทิ้ง overload ซ้ำ (2) ทุกครั้งหลังรัน `CREATE OR REPLACE FUNCTION` ที่เปลี่ยน parameter list ให้รัน `select proname, count(*) from pg_proc where proname = 'ชื่อฟังก์ชัน' group by proname;` ทันทีเพื่อยืนยันว่ายังเหลือแค่ 1 แถว (3) ฟังก์ชันที่แค่เปลี่ยน **เนื้อหา/return columns โดย parameter list เดิมเป๊ะ** ไม่ติดปัญหานี้ ใช้ `CREATE OR REPLACE` ตรงๆ ได้ปลอดภัย (ยกเว้นกรณี `RETURNS TABLE` เปลี่ยนคอลัมน์ ต้อง DROP ก่อนอยู่ดีตามบั๊กคลาสสิกข้อ 6.1)

---

## 3. โครงสร้างฐานข้อมูล — ไฟล์ migration ทั้งหมด (รันตามลำดับ 01→28)

ไฟล์อยู่ในโฟลเดอร์นี้ (ทั้งหมดรันจริงบน Supabase SQL Editor แล้ว):

| ไฟล์ | ทำอะไร |
|---|---|
| `01_phase_a_schema.sql` | extension (pgcrypto), ตาราง `settings`/`officer`/`check_in`, insert ค่า settings เริ่มต้น |
| `02_phase_a_rpc.sql` | RPC `do_check_in`, `do_override`, `do_list_officers` + เปิด RLS |
| `03_phase_a_test.sql` | สคริปต์ทดสอบผ่านเกณฑ์เฟส A |
| `04_phase_b_rpc_today_status.sql` | ปรับ RPC เรื่องสถานะวันนี้ |
| `05_phase_b_ready_and_note.sql` | เพิ่มคอลัมน์ `ready_for_duty` + บังคับหมายเหตุขั้นต่ำ 5 ตัวอักษร |
| `06_phase_b_orange_status.sql` | เปลี่ยนจาก 3 สี → **4 สี** (เพิ่มสีส้ม) เกณฑ์: 🟢 ก่อน 08:20 / 🟡 08:20–08:30 / 🟠 08:30–08:40 / 🔴 หลัง 08:40 |
| `07_phase_c_pin_selfservice_and_dashboard.sql` | `pin_hash` เป็น nullable, เพิ่ม `needs_pin_setup`, RPC `do_set_initial_pin`/`do_reset_pin`, storage policy ให้ supervisor อ่านรูปได้ |
| `08_phase_c_officers_admin_rpc.sql` | RPC `do_list_officers_admin` (สำหรับตารางจัดการเจ้าหน้าที่ในแดชบอร์ด) |
| `09_real_officers.sql` | insert รายชื่อเจ้าหน้าที่จริง 19 คน (จาก PDF ที่เจ้าของอัปโหลด) + ปิดใช้งานบัญชีทดสอบ 3 คน |
| `10_officer_order_nickname.sql` | เพิ่มคอลัมน์ `nickname` + `sort_order` ให้เรียงตามลำดับเอกสารต้นฉบับ ไม่ใช่ตามตัวอักษร |
| `11_supervisors.sql` | เพิ่มคอลัมน์ `login_method` ('pin'/'auth'), เพิ่มบัญชีหัวหน้า 3 คน (ชวนชัย=auth, ศุภัตรา+ผู้ช่วยแอดมิน=pin), RPC ตระกูล `do_supervisor_*` ทั้งหมด |
| `12_officers_admin_login_method.sql` | เพิ่ม `login_method` ในผลลัพธ์ `do_list_officers_admin` |
| `13_fix_rls_recursion.sql` | **แก้บั๊ก**: policy `officer_read_supervisor` query ตัวเองซ้ำเข้าไปในตัวเอง → infinite recursion แก้ด้วยฟังก์ชัน `is_supervisor()` แบบ SECURITY DEFINER |
| `14_photo_thumbnails.sql` | เพิ่ม `photo_path` ใน `do_supervisor_get_today` + RPC `do_supervisor_verify_pin_for_photo` (ให้ Edge Function เรียกตรวจสิทธิ์ก่อนออก signed URL) |
| `15_purple_incomplete_checkin.sql` | เพิ่มคอลัมน์ `incomplete_checkin` (boolean, default false) ใน `check_in`, RPC ใหม่ `do_check_distance(lat,lng)` (preview ระยะทางฝั่ง client ก่อน submit, ไม่ insert), แก้ `do_check_in` ให้คำนวณ `incomplete_checkin` เองฝั่ง server (ระยะ &gt;50ม. หรือไม่มีพิกัด), แก้ `do_get_today_status` + `do_supervisor_get_today` ให้ return ค่านี้ด้วย |
| `16_motto_and_monthly_stats.sql` | เพิ่มคอลัมน์ `settings.service_motto` (text, มี default placeholder), RPC `do_get_motto()` (anon), `do_set_motto(p_new_motto)` (authenticated), `do_supervisor_set_motto(...)` (anon), `do_get_my_month_stats(p_officer_id, p_pin)` (anon) |
| `17_history_override_export.sql` | **แดชบอร์ดหัวหน้าให้ครบสเปก v1** — แก้ `do_override`, เพิ่ม `do_supervisor_override`, เพิ่ม `do_get_history`/`do_supervisor_get_history`, แก้ `do_supervisor_get_today` ให้คืน override info เพิ่ม |
| `18_officer_remark.sql` | **หมายเหตุเพิ่มเติมหลังเช็กอิน (ไม่บังคับ, write-once)** — เพิ่มคอลัมน์ `check_in.remark`, RPC ใหม่ `do_save_remark(...)`, แก้ 4 RPC อ่านข้อมูลให้ return คอลัมน์ `remark` เพิ่ม |
| `19_shift_schedule_absent.sql` | **ระบบตารางเวรแบบง่าย (MVP) + วันหยุดนักขัตฤกษ์ + สีน้ำตาลเข้ม (ขาดเช็กอิน)** — เพิ่ม `officer.work_days`, ตาราง `public_holiday`, `settings.absent_cutoff_time`, RPC `do_get_absentees`/`do_supervisor_get_absentees` ฯลฯ |
| `20_stats_period_override.sql` | **วันเริ่มนับสถิติรายเดือนแบบตั้งค่าได้ + นับ absent ในสถิติส่วนบุคคล** — เพิ่มตาราง `stats_period_override`, แก้ `do_get_my_month_stats`, RPC จัดการ 6 ตัว |
| `21_motto_rotation.sql` | **กล่องม็อตโต้หมุนเวียน 3 ข้อความ** — เพิ่ม `settings.service_motto_1/2/3`, แก้ `do_get_motto()` ให้คำนวณ `active_slot` จากสูตร business-day, RPC ใหม่ `do_list_mottos()`/`do_supervisor_list_mottos(...)`, DROP+recreate `do_set_motto`/`do_supervisor_set_motto` |
| `22_admin_settings_supervisor_mgmt.sql` | **ตั้งค่าระบบผ่าน UI + จัดการบัญชีหัวหน้า PIN (เฉพาะชวนชัย)** — `do_get_settings`/`do_set_settings`, `do_add_supervisor`/`do_set_supervisor_status` + คอลัมน์ `officer.supervisor_enabled` |
| `23_photo_retention.sql` | **PDPA auto photo-deletion (ลบรูปเซลฟี่อัตโนมัติ 31 วัน + retention hold)** — เพิ่ม `check_in.retention_hold`/`check_in.photo_deleted_at`, RPC `do_set_retention_hold`/`do_supervisor_set_retention_hold`, ติดตั้ง `pg_cron`+`pg_net`, deploy Edge Function `delete-old-photos` |
| `24_cron_timeout_fix.sql` | **แก้ timeout สั้นเกินไปของ cron `delete-old-photos-daily`** — เรียก `cron.schedule()` ซ้ำด้วยชื่อ/schedule เดิม (jobid=1 ไม่เปลี่ยน) เพิ่ม `timeout_milliseconds := 60000` ใน `net.http_post` (เดิมใช้ default 5 วิ ซึ่งสั้นเกินไปสำหรับ orphan sweep ที่ต้อง recursive-list ทั้งบัคเก็ต — ดูข้อ 24.1/2.11) |
| `25_pin_rate_limiting.sql` | **PIN rate limiting (P0.3)** — thin wrapper `check_and_count_pin()` เรียกก่อน RPC ที่รับ `p_pin` ทั้ง 21 ตัว (RENAME เดิมเป็น `_impl` + REVOKE), ล็อก 15 นาทีหลังผิดครบ 5 ครั้ง, คอลัมน์ใหม่ `officer.pin_fail_count`/`pin_locked_until` — ดูข้อ 27 |
| `26_fix_supervisor_pin_active_check.sql` | **⚠️ hotfix แก้บั๊ก regression จาก migration 25** — `check_and_count_pin()` เช็ก `active=true` ทำให้หัวหน้า PIN (active=false โดยตั้งใจ) ล็อกอินไม่ได้เลย แก้เป็น `(active=true OR is_supervisor=true)` — ดูข้อ 29 |
| `27_work_group_p1a.sql` | **P1a: work_group + badge ทีม OT (backend)** — ตาราง `work_group`, คอลัมน์ `officer.work_group_id`, `settings.team_ok_before`/`team_warn_before` (ไม่ pre-seed กลุ่ม), ฟังก์ชันกลาง `do_team_coverage_json()` (revoke จาก anon/authenticated), RPC `do_get_team_coverage()`/`do_supervisor_get_team_coverage(...)`, แก้ `do_list_officers_admin`(DROP+recreate)/`do_supervisor_list_officers_impl`/`do_get_settings`/`do_set_settings` ให้รองรับกลุ่มงาน — ดูข้อ 30 |
| `28_admin_work_group_rpc.sql` | **P1a: RPC จัดการกลุ่มงาน (auth-only)** — `do_admin_list_work_groups()`, `do_admin_create_work_group(name, is_ot_team)`, `do_admin_update_work_group(id, name, is_ot_team)`, `do_admin_delete_work_group(id)` (unassign officer ก่อนลบ), `do_admin_set_officer_group(officer_id, work_group_id)` — ทั้งหมดเฉพาะชวนชัย (auth) ตาม P1.2 |

**⚠️ หมายเหตุเลข migration ถัดไป:** เลข 24 ถูกใช้ไปกับ cron timeout fix, เลข 26 ถูกใช้ไปกับ hotfix ฉุกเฉิน, เลข **27–28 ใช้ไปกับ P1a (work_group + RPC จัดการกลุ่ม) แล้ว** (13 ก.ค. 2569 — ดูข้อ 30) migration ถัดไปจริงคือ **29** — ดูตารางเต็มใน `90_ROADMAP_v2_PLAN.md` ข้อ 8

**ตารางหลัก:** `settings` (แถวเดียว), `officer` (19 เจ้าหน้าที่ + 3 หัวหน้า, `active=false` สำหรับหัวหน้าเพื่อไม่ให้โผล่ในดรอปดาวน์เช็กอิน), `check_in`, `work_group` (ใหม่ P1a — ยังว่างเปล่า ยังไม่ pre-seed)

รายละเอียดเชิงลึกของแต่ละ migration (การตัดสินใจออกแบบ, ผลการ verify, บั๊กที่เจอระหว่างทำ) อยู่ใน `CLAUDE_ARCHIVE.md` ข้อ 9–22 ตามหัวข้อที่เกี่ยวข้อง

---

## 4. Supabase Edge Function

**`supervisor-photo-url`** (deploy ผ่าน Dashboard "Via Editor" ไม่ใช่ CLI)
URL: `https://aamzsbuwfdyljdvwaifb.supabase.co/functions/v1/supervisor-photo-url`

**ทำไมต้องมี:** หัวหน้าที่ล็อกอินด้วย PIN (ศุภัตรา, ผู้ช่วยแอดมิน) ไม่มี Supabase Auth session จริง จึงสร้าง Storage signed URL ตรงๆ แบบ client-side ไม่ได้ (signed URL ต้องมี auth session ตาม RLS ของ `storage.objects`)

**วิธีทำงาน:** รับ `{officer_id, pin, photo_path}` → เรียก RPC `do_supervisor_verify_pin_for_photo` ตรวจ PIN + ตรวจว่า path มีจริงในระบบ → ถ้าผ่านค่อยใช้ **service role key** (inject เป็น env var อัตโนมัติจาก Supabase ไม่ต้องพิมพ์ secret เอง) ออก signed URL อายุ 60 วิ ให้

**ตั้งค่าสำคัญ:** ปิด "Verify JWT with legacy secret" ในหน้า Settings ของฟังก์ชัน (เพราะ PIN caller ไม่มี legacy JWT) — ถ้า deploy ใหม่หรือแก้โค้ดฟังก์ชันนี้ ต้องเช็กว่า toggle นี้ยังปิดอยู่

ทดสอบแล้ว: signed URL ที่ออกมาโหลดรูปจริงได้ (200, image/jpeg), PIN ผิดถูก reject (403, `bad_pin`)

**`delete-old-photos`** — ดู migration 23 ในข้อ 3 ด้านบน + รายละเอียดเต็มใน `CLAUDE_ARCHIVE.md` ข้อ 20 + งานแก้บั๊ก orphan photo ล่าสุดในข้อ 24 ด้านล่าง

---

## 5. Deviations จากสเปกตั้งต้น (สิ่งที่เปลี่ยนไปจาก v1 spec เดิม)

- **3 สี → 4 สี**: เพิ่มสีส้ม "มาเลท" ระหว่างเหลืองกับแดง (เกณฑ์เวลาดูข้อ 3 แถว `06_phase_b_orange_status.sql`)
- **PIN self-service**: เดิม spec ไม่ได้ระบุรายละเอียด ตอนนี้ใช้กลไก `pin_hash IS NULL` = ต้องตั้งใหม่ ใช้ร่วมกันทั้ง "ตั้งครั้งแรก" และ "ลืมรหัสแล้วโดนแอดมินรีเซ็ต"
- **โครงสร้างหัวหน้า 3 ระดับ** (เดิม spec พูดถึงแค่ "หัวหน้า" คนเดียว): ชวนชัย (auth, สูงสุด) + ศุภัตรา (pin) + ผู้ช่วยแอดมิน (pin, ไม่ผูกชื่อคนจริงตามคำขอ) — ทั้งสามแบบตอนนี้ **เห็นข้อมูลเท่ากันหมด** รวมรูปถ่าย (ปิดช่องว่างเรื่องรูปด้วย Edge Function ในข้อ 4)
- **ชื่อเล่นในดรอปดาวน์**: เพิ่มตามคำขอ ("ยศ ชื่อ นามสกุล (ชื่อเล่น)") และเรียงตามลำดับเอกสาร PDF ต้นฉบับ ไม่ใช่ตามตัวอักษร
- **6 สีไม่ได้อยู่ในสเปกเดิม**: สเปก v1 ระบุแค่ 3 สี ตอนนี้ขยายเป็น 6: 🟢🟡🟠🔴 (สีเวลา) + 🟣 (เช็กอินไม่สมบูรณ์) + 🟤 (ขาดเช็กอิน)
- **Badge ทีม OT (P1a)**: เดิม spec ไม่มีแนวคิด "กลุ่มงาน" เลย ตอนนี้เพิ่มระบบ `work_group` + badge 4 สถานะ (ok/warn/none/pending) แยกต่างหากจากสีเช็กอินรายบุคคลโดยสิ้นเชิง (ดูข้อ 30)

---

## 6. บั๊กที่เจอและแก้แล้ว (กันเจอซ้ำ)

1. **`CREATE OR REPLACE FUNCTION` เปลี่ยน return columns ไม่ได้** — ต้อง `DROP FUNCTION IF EXISTS` ก่อนเสมอถ้าจะเปลี่ยนจำนวน/ชนิดคอลัมน์ที่ return (เจอซ้ำหลายรอบ: `do_check_in`, `do_list_officers`, `do_list_officers_admin`, `do_supervisor_get_today`)
2. **PostgREST embed ambiguous foreign key** — ตาราง `check_in` มี FK ไป `officer` 2 เส้น (`officer_id`, `override_by`) ถ้า query แบบ `.select("...officer(...)")` เฉยๆ จะ error "more than one relationship found" ต้องระบุ `officer!check_in_officer_id_fkey(...)` ชัดเจน
3. **RLS infinite recursion** — policy ที่ query ตารางตัวเองใน USING clause (แม้จะดูปกติ) ทำให้วนไม่รู้จบ ต้องย้าย logic ไปฟังก์ชัน SECURITY DEFINER แยก (ดูข้อ 13 ในตาราง migration)
4. **Supabase SQL Editor UI**: การพิมพ์/paste query ครั้งแรกในแท็บใหม่บางทีไม่โฟกัสจริง ทำให้ keystroke กลายเป็น keyboard shortcut ของ dashboard แทน (เช่น เผลอกด g+r แล้วเด้งไปหน้า Realtime) วิธีป้องกัน: คลิกเข้า editor แล้ว screenshot ยืนยันว่า cursor อยู่ในนั้นจริงก่อนพิมพ์ยาวๆ ทุกครั้ง
5. **⚠️ ไฟล์ในโฟลเดอร์โปรเจกต์ไม่ตรงกับที่ deploy จริง (เจอ 3 ก.ค. 2569)** — ไฟล์ในเครื่องเป็นเวอร์ชันเก่ากว่าที่ deploy บน Netlify จริง วิธีแก้: ดึง HTML จริงจากเว็บด้วย `fetch(location.href)` ก่อนแก้ต่อ (ดูกติกาป้องกันซ้ำในข้อ 2.6) — รายละเอียดเต็มอยู่ใน `CLAUDE_ARCHIVE.md` ข้อ 12
6. **UUID ทดสอบต้องเป็น hex ที่ valid จริง** — เคยพิมพ์ UUID ทดสอบแบบ `'00000000-0000-0000-0000-00000000test'` (ใส่คำว่า "test" ต่อท้ายเพื่อให้จำง่าย) แต่ `test` ไม่ใช่ hex digit ทำให้ insert error ทันที ให้ใช้ UUID ที่เป็น hex ล้วนเสมอ เช่น `'00000000-0000-0000-0000-0000000000aa'`
7. **Supabase SQL Editor: คลิก "View full cell content" ที่ผลลัพธ์ query แล้วโฟกัสหลุดจาก editor** — หลังรัน query แล้วคลิกดูค่าเต็มในผลลัพธ์ ถ้า `ctrl+a` แล้วพิมพ์ทับต่อทันทีโดยไม่คลิกกลับเข้า editor ก่อน ข้อความจะไม่ถูกพิมพ์เข้า editor จริง กด Run ซ้ำจะรันคำสั่งเดิมอีกรอบโดยไม่รู้ตัว วิธีป้องกัน: คลิกเข้าไปใน editor area ก่อนเสมอ แล้ว screenshot/get_page_text ยืนยันเนื้อหาที่พิมพ์จริงก่อนกด Run ทุกครั้งที่เพิ่งคลิกดูผลลัพธ์มา
8. **รูปเช็กอินกำพร้าใน Storage (เจอ 9 ก.ค. 2569)** — `index.html` อัปโหลดรูปขึ้น Storage bucket ก่อนเรียก RPC `do_check_in` เสมอ ถ้า RPC ตอบ error (เช่นเช็กอินซ้ำ/PIN ผิด) รูปที่เพิ่งอัปโหลดไปจะไม่มีแถว `check_in.photo_path` อ้างอิงเลย ค้างอยู่ใน bucket ถาวรเพราะ Edge Function `delete-old-photos` เดิมลบตามแถว `check_in` เท่านั้น มองไม่เห็นไฟล์กำพร้า — แก้แล้ว 2 จุด (เช็ก `do_get_today_status` ก่อนอัปโหลดรูป + เพิ่ม orphan sweep ใน Edge Function) ดูรายละเอียดเต็มในข้อ 24
9. **⚠️ (9 ก.ค. 2569) บั๊ก bash-mount staleness** — ดูข้อ 2.10 ด้านบน (ยกระดับเป็นกติกาถาวรแล้ว เพราะเจอซ้ำแทบทุกเซสชันตั้งแต่ข้อ 6.5)
10. **⚠️ (10 ก.ค. 2569) ลืม sync ไฟล์ที่แก้ไปแล้วเข้า git clone ก่อน commit** — ดูข้อ 2.12 ด้านบน (ยกระดับเป็นกติกาถาวรแล้ว)

---

## 7. งานที่ยังไม่ทำ / รอ (backlog รวมจากทุกเซสชัน — เรียงตามที่เจ้าของพูดถึงล่าสุดก่อน)

**ปิดงานแล้ว (13 ก.ค. 2569):** P1a (badge ทีม OT + work_group, migration 27+28 + frontend + E2E test) — push ขึ้น git สำเร็จแล้ว ดูข้อ 30

**ปิดงานแล้ว (10 ก.ค. 2569):** บั๊ก "รูปเช็กอินกำพร้าใน Storage" — push, deploy, และ E2E test ผ่านหมดแล้ว ดูข้อ 24 | P0.1 (คอลัมน์สิทธิ์หัวหน้าใน report.html + error mapping ปุ่มกันลบรูป 2 ไฟล์) — push แล้ว ดูข้อ 25 | GPS geolocation timeout ใน `index.html` (8 วิ → 20 วิ) — push แล้ว (commit `f58cd48`) | UX quick win รอบ 2 ใน `index.html` (จำชื่อล่าสุด localStorage + ปุ่มลัดหมายเหตุ + สถานะ GPS ในหน้าตรวจสอบก่อนยืนยัน) — push แล้ว (commit `5f7cac2`), verify บนเว็บจริงผ่านทั้งหมด | **P0.3 PIN rate limiting (migration 25)** — SQL รันจริงบน Supabase แล้ว + ทดสอบ E2E ผ่านหมด + แก้ frontend (`index.html`/`report.html`) เสร็จ + push แล้ว (commit `4ccfa23`) ดูข้อ 27

**⏸️ พักไว้ก่อนตามคำสั่งเจ้าของ (11 ก.ค. 2569):** P0.4 backup — ตรวจสอบสดยืนยันแล้วว่า Supabase แพลน Free ไม่มี backup อัตโนมัติเลย เสนอทางเลือก (อัปเกรด Pro $25/เดือน vs DIY) แล้ว เจ้าของเลือก **"ยังไม่ตัดสินใจตอนนี้ ควรมีระบบ backup เมื่อมีการขยายการใช้งานแผนอื่นๆเพิ่มเติม หรือให้ตม.จังหวัดอื่นๆใช้งาน"** = ผูกเงื่อนไขกับ P3 (multi-office) ห้าม agent เริ่มเองก่อนเจ้าของหยิบยก ดูข้อ 28

**✅ (11 ก.ค. 2569) `.gitignore` สำหรับ `.service_role_key.local.txt` เพิ่มแล้ว** — ทำพร้อมกับ push P0.3 (commit `4ccfa23`) ไม่มีความเสี่ยงหลุดขึ้น GitHub อีกต่อไป

**✅ (11 ก.ค. 2569) P0.5 — จัดกลุ่มการ์ด dashboard.html + report.html + mobile card layout เสร็จสมบูรณ์ทั้งหมดแล้ว push แล้ว (commit `5d146fd`, `310f123`) ไม่มีงานค้าง**

**แผนใหม่ที่ยืนยันดีไซน์แล้ว แต่ตั้งใจรอก่อน (บันทึก 6 ก.ค. 2569 — รายละเอียดเต็มใน `CLAUDE_ARCHIVE.md` ข้อ 22):**
- **Badge ระดับทีมสำหรับกลุ่มงานธุรกิจ/ครอบครัว** — **(อัปเดต 13 ก.ค. 2569) เริ่มทำแล้วจริงเป็น P1a ดูข้อ 30 — ไม่ต้องรอกำหนดเดิม 20 ก.ค. อีกต่อไป งานนี้ปิดจากหมวด "รอก่อน" แล้ว**

**ค้างจาก spec เดิม (ยังไม่ทำ):**
- เช็กเอาต์ตอนเย็น — อยู่นอก scope v1 ตามสเปกเดิม (ดีไซน์ P1.4 ร่างไว้แล้วใน roadmap ยังไม่เขียนโค้ด)
- Grace Card (P1.3) — ดีไซน์ร่างไว้แล้วใน roadmap ยังไม่เขียนโค้ด
- **เฟส D ตาม spec เดิม**: ให้ใช้งานจริงต่อเนื่อง 1 เดือนก่อน แล้วค่อยตัดสินใจเรื่องระบบให้คะแนน/รางวัลจากข้อมูลจริง — **ห้ามเพิ่มฟีเจอร์นี้ก่อนถึงเวลา**
- ฟีดแบ็กประชาชน + QR เคาน์เตอร์ — ต้องรออนุมัติเป็นลายลักษณ์อักษรจากผู้บังคับบัญชาก่อน ตามสเปกเดิม
- คู่มือผู้ใช้ (ข้อ 8) — ยังไม่ได้อัปเดตให้ครบทุกฟีเจอร์ใหม่ (เจ้าของอัปเดตเองเป็นหลัก ไม่ต้องหยิบยกเว้นแต่เจ้าของถามเอง — ดูข้อ 8)
- P1.2 (UI จัดการกลุ่มงาน — ทำไปแล้วจริงๆ เป็นส่วนหนึ่งของ P1a ดูข้อ 30.7), P2–P3 ใน `90_ROADMAP_v2_PLAN.md` ยังไม่เริ่มทำ (นอกเหนือจาก P0.1/P0.2/P0.3/P1a ที่เสร็จแล้ว, P0.4 ที่พักไว้ตามคำสั่งเจ้าของ ดูข้อ 28)
- ชื่อการ์ด "🤝 จุดบริการกลุ่มงาน OT" — เจ้าของแจ้งว่าไม่ชอบชื่อนี้ ต้องการเปลี่ยนภายหลัง (13 ก.ค. 2569) รอเจ้าของบอกชื่อใหม่ แล้วแก้ HTML 1 บรรทัดในทั้ง 2 ไฟล์ (ไม่กระทบ backend)
- Branch deploy / deploy preview ของ Netlify — มีให้ใช้ได้แล้วในทางเทคนิคเพราะผูก git แล้ว แต่โปรเจกต์นี้ตัดสินใจ push ตรงไป `main` เหมือนเดิมไปก่อน ไม่ใช้ PR flow

---

## 8. คู่มือผู้ใช้

มีคู่มือสั้นสำหรับส่งไลน์ให้เจ้าหน้าที่แล้วที่ `คู่มือการใช้งาน เช็กอินเช้า (ส่งไลน์).txt` ในโฟลเดอร์นี้ — **เจ้าของ (ชวนชัย) อัปเดตคู่มือนี้เองแล้ว** รวมถึงร่างข้อความประกาศไลน์กลุ่มเรื่องโดเมนใหม่ก็ทำเองแล้วเช่นกัน (5 ก.ค. 2569) **agent ไม่ต้องหยิบยกหรือเตือนเรื่องนี้ขึ้นมาอีกในเซสชันถัดไป** เว้นแต่เจ้าของถามเอง

---
## 23. ย้ายจาก Netlify Drop เป็น Git + Netlify CI (deploy อัตโนมัติ) + ดาวน์เกรดแพลน Netlify — รายละเอียด (8-9 ก.ค. 2569)

**สถานะ: ✅ เสร็จสมบูรณ์ทุกขั้นตอน — GitHub repo สร้างแล้ว, Netlify ผูก git แล้ว, push+auto-deploy ทดสอบผ่านจริง, rollback ทดสอบผ่านจริง, แพลน Netlify ดาวน์เกรดจาก Personal เป็น Free แล้ว (มีผล 7 ส.ค. 2569) — นี่คือการเปลี่ยนแปลง infrastructure ครั้งใหญ่ที่สุดของโปรเจกต์นับตั้งแต่เริ่มทำ v1 (เปลี่ยนวิธี deploy ทั้งหมด) ต้องอ่านข้อนี้ให้ครบก่อนแก้ไฟล์ต่อในเซสชันถัดไป**

**ที่มา:** ทำตามแผน P0.2 ของ `90_ROADMAP_v2_PLAN.md` (git+CI) เจ้าของสั่งให้เข้าไปดูหน้าจอควบคุมคอมโดยตรงเพื่อดำเนินการขั้นตอน GitHub/Netlify ที่ agent ทำเองได้ทั้งหมด ("ถ้าขั้นตอนไหนคุณทำแทนได้ ทำเลย ถ้าทำไม่ได้แจ้งให้ฉันทราบ")

### 23.1 สิ่งที่สร้าง/ตั้งค่าใหม่

- **GitHub repo:** `chuan4662/rayong-imm-checkin` — สร้างเป็น Private ก่อน แล้วเปลี่ยนเป็น **Public** ภายหลัง (เหตุผลดูข้อ 23.3)
- **Fine-grained Personal Access Token:** scope เฉพาะ repo นี้ repo เดียว, หมดอายุสั้น, สิทธิ์แค่ "Contents: Read and write" + "Metadata: Read-only" (ขั้นต่ำที่จำเป็น ไม่ให้สิทธิ์เกินความจำเป็น) — ใช้แค่ตอน push แล้วแนะนำให้เจ้าของ revoke/delete ทิ้งหลังใช้เสร็จทุกครั้ง ไม่ได้บันทึกไว้ที่ไหนในไฟล์โปรเจกต์เลย (เจ้าของเป็นคนสร้าง+ส่งให้ agent ใช้ครั้งเดียวตามกติกาความปลอดภัย ข้อ 2 ด้านบน — agent ไม่มีสิทธิ์สร้าง credential ให้ตัวเอง)
- **โครงสร้าง repo ใหม่** (จัดใหม่จากที่กองอยู่ในโฟลเดอร์เดียวกันหมด — ใช้เฉพาะใน git working copy ที่ `/tmp` เท่านั้น โฟลเดอร์โปรเจกต์จริงบน OneDrive ยังคงแบนราบเหมือนเดิม):
  ```
  index.html, dashboard.html, report.html   (อยู่ root เหมือนเดิม — Netlify publish directory ว่าง/root)
  CLAUDE.md, CLAUDE_ARCHIVE.md, README.md, .gitignore   (root)
  migrations/01_*.sql ... 28_*.sql           (ย้ายเข้าโฟลเดอร์ย่อย)
  edge-functions/edge_function_delete-old-photos.ts
  docs/00_SPEC_v1_ORIGINAL.md, 90_ROADMAP_v2_PLAN.md, คู่มือการใช้งาน...txt
  ```
- **Netlify ↔ GitHub link:** ทำผ่านหน้า Netlify "Link repository" — ต้องผ่าน 2 ขั้นยินยอมจาก GitHub ที่ **เจ้าของต้องกดเองเท่านั้น** (agent กดแทนไม่ได้ตามกติกาความปลอดภัย): (1) OAuth authorize แอป Netlify ให้อ่านบัญชี GitHub พื้นฐาน (2) ติดตั้ง GitHub App "Netlify" ลง repo จริง (เลือก "Only select repositories" → เฉพาะ `rayong-imm-checkin` ไม่เลือก "All repositories" เพื่อความปลอดภัย)

### 23.2 ⚠️ ข้อจำกัดสำคัญของ sandbox ที่ agent ใช้ — ต้องรู้ก่อนแก้ไฟล์ต่อ

**ห้ามรัน `git init`/`git add`/`git commit` ตรงในโฟลเดอร์โปรเจกต์นี้ (`Service Rayong Imm app`) หรือโฟลเดอร์ outputs ชั่วคราวใดๆ ที่ sync กับ OneDrive เด็ดขาด** — ทดสอบแล้วพบว่า sandbox ของ agent บล็อกการลบ/rename ไฟล์ (`Operation not permitted`) ในทุก mount ที่ผูกกับ OneDrive/outputs ทำให้ `.git` internals (lock files, refs) ทำงานไม่ได้เลย ลอง `rm -rf .git` เพื่อเริ่มใหม่ก็ error เหมือนกันทุกไฟล์

**ทดสอบแล้วว่า `/tmp` (sandbox disk แท้ ไม่ใช่ mount) ใช้ git ได้ปกติ** จึงเป็นทางแก้ถาวรที่ต้องใช้ทุกครั้ง (ดูขั้นตอน 23.4)

### 23.3 บั๊กที่เจอ + แก้แล้ว: "Unrecognized Git contributor"

หลังผูก Netlify ↔ GitHub สำเร็จและ push commit ทดสอบตัวแรก Netlify **ปฏิเสธ build** ด้วย error:
> "Build blocked: Unrecognized Git contributor. This plan allows only verified account members to push to private repos"

**สาเหตุ:** แพลน Netlify ที่ใช้อยู่ตอนนั้น (Personal $9/เดือน) จำกัดให้ private repo มีแค่ "ผู้ push ที่ยืนยันตัวตนแล้ว" คนเดียว การ push ผ่าน PAT (ไม่ใช่ login ผ่านเว็บ GitHub ตรงๆ) ทำให้ Netlify มองว่าเป็น contributor ที่ไม่รู้จัก แม้อีเมล commit จะตรงกับเจ้าของบัญชีก็ตาม เช็กหน้า `https://app.netlify.com/teams/okmyfish/contributors` แล้วพบว่าฟีเจอร์ "เชื่อม Git account" นี้เป็นของแพลน **Pro ($20/เดือน) ขึ้นไปเท่านั้น** (ปุ่ม "Edit settings" ในหน้านั้นพาไปหน้าอัปเกรดแพลนตรงๆ)

**ทางแก้ที่เลือก (เจ้าของตัดสินใจ):** เปลี่ยน repo เป็น **Public** แทนการอัปเกรดเป็น Pro — เพราะ error message เองก็ระบุว่า "make the repo public" เป็นทางแก้ได้เหมือนกัน และข้อมูลจริงของเจ้าหน้าที่/รูปถ่ายอยู่ใน Supabase คนละที่ (ปลอดภัยด้วย RLS) ไม่ได้อยู่ใน repo — **สิ่งที่เปิดเผยคือ source code/logic ล้วนๆ** (เกณฑ์เวลา, สูตรคำนวณระยะ GPS, RPC signature) เจ้าของรับความเสี่ยงนี้แล้ว

**⚠️ ขั้นตอนแก้บั๊กที่ใช้ได้จริง (สำคัญ ถ้าเจอซ้ำ):** แค่เปลี่ยน repo เป็น public ที่ GitHub **ไม่พอ** — Netlify แคชสถานะ "private" ไว้ตั้งแต่ตอน link ครั้งแรก ต้อง **unlink repo ออกจาก Netlify แล้ว link กลับใหม่** (หน้า Project configuration → Build & deploy → Continuous deployment → "Manage repository" → "Unlink..." แล้ว "Link repository" → "Link to an existing repository" → เลือก repo เดิม) ถึงจะบังคับให้ Netlify เช็กสถานะ public สดใหม่และปลดบล็อก build ได้จริง — ทดสอบยืนยันแล้วว่าหลัง unlink/relink build ที่เคย fail ผ่านทันที

### 23.4 ⭐ วิธี commit/push ที่ต้องใช้ทุกครั้ง (บังคับ ไม่มีทางลัด)

เพราะ git รันตรงในโฟลเดอร์โปรเจกต์ไม่ได้ (ข้อ 23.2) ทุกครั้งที่จะ push การเปลี่ยนแปลงใหม่ ต้อง:

1. sync ไฟล์ปัจจุบันจากโฟลเดอร์โปรเจกต์จริง (`Service Rayong Imm app`) ไปที่ working copy ใน `/tmp` (เช่น `/tmp/rg_fresh` หรือ `/tmp/rayong-imm-checkin-git`) — ถ้า working copy นี้ไม่มีอยู่แล้วในเซสชันปัจจุบัน ต้อง `git clone` จาก GitHub มาใหม่ก่อน (repo เป็น public แล้ว clone ได้โดยไม่ต้องใช้ token) แล้วค่อยคัดลอกไฟล์ปัจจุบันทับ **⚠️ ห้ามใช้ `rsync` ทั้งโฟลเดอร์ตรงๆ** เพราะโฟลเดอร์จริงเป็นไฟล์แบนราบ (SQL/docs/edge function อยู่ root ปนกันหมด) แต่ git working copy จัดเป็นโฟลเดอร์ย่อย (`migrations/`, `edge-functions/`, `docs/`) ตามข้อ 23.1 — ต้องคัดลอกทีละไฟล์ไปยัง path ที่ถูกต้องในโครงสร้างใหม่ และ **ต้องอ่านเนื้อหาไฟล์ผ่าน `Read` tool เสมอ ไม่ใช่ bash `cp`/`cat`** สำหรับไฟล์ที่ถูกแก้ในเซสชันนั้น (ดูบั๊ก bash-mount staleness ในข้อ 2.10 — ไฟล์ในโฟลเดอร์จริงอาจดูค้าง/ตัดจบกลางบรรทัดถ้าอ่านผ่าน bash ตรงๆ ค้างได้นานถึงหลายวัน) **⚠️ ต้องไล่ทวนรายการไฟล์ที่แก้จริงทั้งหมดในเซสชันก่อน sync ทุกครั้ง (ข้อ 2.12) — ไม่ใช่แค่ไฟล์ในขอบเขต task ล่าสุดที่กำลังคุยอยู่**
2. `git add -A && git commit -m "..."` ใน working copy
3. `git push` ไปยัง `https://<username>:<token>@github.com/chuan4662/rayong-imm-checkin.git main` (ใส่ token ตรงใน URL ของคำสั่ง push ครั้งเดียว **ไม่ใช้ `git remote set-url`** เพื่อไม่ให้ token ค้างอยู่ใน `.git/config` ของ working copy)
4. **ต้องขอ confirm จากเจ้าของก่อนขั้นตอนที่ 3 เสมอ** ตามกติกาข้อ 2.1 ที่แก้ใหม่ — สรุปว่าจะแก้อะไร ให้เจ้าของ `present_files` ดูไฟล์จากโฟลเดอร์โปรเจกต์จริงก่อน (ไม่ใช่จาก `/tmp`)
5. โฟลเดอร์โปรเจกต์จริง (`Service Rayong Imm app`) ที่เจ้าของแก้ไฟล์เองอยู่เป็นปกติ **ไม่ถูกแตะต้องจากขั้นตอน git เลย** — เจ้าของทำงานเหมือนเดิมทุกประการ ไม่ต้องเปลี่ยนพฤติกรรม
6. **หลัง push ทุกครั้ง ต้อง verify บนเว็บจริง (`fetch()` เช็ก marker string เฉพาะของแต่ละไฟล์ที่แก้) ก่อนสรุปว่าเสร็จ** (ข้อ 2.12 — เคยพลาดเพราะลืม sync ไฟล์หนึ่งไปแล้วไม่ได้ verify จนผู้ใช้ไม่รู้)

### 23.5 ทดสอบแล้ว (verify ผ่านจริง)

- **Auto-deploy:** push commit ทดสอบ (เพิ่ม HTML comment 1 บรรทัดใน `index.html`) → Netlify build+publish เองภายในไม่กี่วินาที โดยไม่ต้องเปิด Netlify Drop เลย → verify ด้วย `fetch()` จริงบน `rayongimm.link` เห็น comment ที่เพิ่งเพิ่มขึ้นจริง
- **Rollback:** เลือก deploy เก่ากว่าในหน้า Netlify Deploys → กด "Publish deploy" → verify เว็บจริงย้อนกลับ (comment ทดสอบหายไปจริง) → กด "Publish deploy" ของตัวล่าสุดกลับคืน → verify เว็บจริงกลับมาเป็นปัจจุบันถูกต้อง ไม่มี regression กับฟีเจอร์เดิม
- **หมายเหตุการทดสอบปุ่ม "Publish deploy" บน Netlify UI:** ปุ่มนี้เปิด dialog ยืนยันแบบ toggle ที่บางครั้งคลิกไม่ติดในครั้งแรก (ต้องดูตำแหน่งจาก screenshot สดๆ ก่อนคลิกทุกครั้ง ไม่ใช้พิกัดจากภาพเก่า) ถ้าเจอปัญหาลักษณะนี้อีกให้ลองคลิกซ้ำพร้อม screenshot ยืนยันสถานะหลังคลิกทุกครั้ง

### 23.6 แพลน Netlify: ดาวน์เกรดจาก Personal เป็น Free

หลัง repo เป็น public แล้ว เหตุผลเดิมที่ต้องใช้แพลน Personal ($9/เดือน) หมดไป (ฟีเจอร์ที่ยังใช้จริงคือ custom domain SSL, serverless functions, global CDN ซึ่งมีครบใน Free plan เหมือนกัน) เช็ก usage จริงพบว่าใช้ไปแค่ ~61/1,000 เครดิตต่อเดือน (Free plan ให้ 300 เครดิต/เดือน เหลือเฟือ) จึง**ดำเนินการดาวน์เกรดเป็น Free แล้วตามที่เจ้าของสั่ง** (ปฏิเสธข้อเสนอส่วนลด 50% ที่ Netlify เสนอให้อยู่แพลน Personal ต่อ) — ตั้ง schedule ดาวน์เกรดสำเร็จ **มีผลจริงวันที่ 7 สิงหาคม 2569** (สิ้นสุดรอบบิลที่จ่ายไปแล้ว ไม่มีการคืนเงิน/เรียกเก็บเพิ่ม) ไม่ต้องทำอะไรเพิ่ม เว็บใช้งานต่อเนื่องไม่มีสะดุด — **สิ่งที่เสียไปหลังดาวน์เกรด:** smart secret detection, analytics ย้อนหลัง 7 วัน, priority email support (ไม่กระทบการทำงานหลักของระบบ)

**Agent ตัวถัดไปที่มาทำงานหลัง 7 ส.ค. 2569 ควรเช็กว่าดาวน์เกรดเกิดขึ้นจริงตามกำหนดหรือไม่** (เผื่อ Netlify มีปัญหาฝั่งระบบเอง) ที่หน้า `https://app.netlify.com/teams/okmyfish/billing/general`

### 23.7 เรื่องเครดิต/ต้นทุนที่ agent ตัวถัดไปต้องรู้

- **GitHub ไม่มีระบบเครดิตแบบ Netlify** — repo public เก็บฟรีไม่จำกัดในทางปฏิบัติ ไม่ได้ใช้ GitHub Actions (Netlify เป็นคนรัน build ทั้งหมด) จึง push ได้ตามปกติไม่ต้องกังวลเรื่องต้นทุนฝั่ง GitHub เลย
- **Netlify build credit ยังเป็นต้นทุนจริง แต่ไม่ใช่คอขวดจริงในสเกลนี้** — เฉลี่ย ~15 เครดิต/ครั้งที่ push (คำนวณจาก 60 เครดิต / 4 deploys ในรอบทดสอบ) แพลน Free ให้ 300 เครดิต/เดือน ใช้จริงต่อเดือนแค่หลักสิบ เหลือเฟือมาก — **ต้นทุนที่ควรใช้ชั่งใจจริงคือแรงงาน/เวลาพัฒนาและความเสี่ยง regression ต่องาน ไม่ใช่เครดิต Netlify** หลักการเดิม (สะสมงานแก้หลายจุดก่อนค่อย push รวมกัน) ยังคงดีเพราะลดจำนวนรอบ verify ไม่ใช่เพราะประหยัดเครดิต — ดูกติกาข้อ 2.1

---

## 24. บั๊ก "รูปเช็กอินกำพร้าใน Storage" (orphaned photos) — ✅ ปิดงานสมบูรณ์ (9-10 ก.ค. 2569)

**สถานะ: เสร็จสมบูรณ์ทุกขั้นตอน — push ขึ้น git แล้ว, เจ้าของ deploy Edge Function เวอร์ชันใหม่เองผ่าน Dashboard มือแล้ว (ยืนยัน Verify JWT ยังปิดอยู่), และ E2E test จริงผ่านหมดแล้ว 10 ก.ค. 2569 (ผลเต็มดูข้อ 24.1) — ไม่มีงานค้างจากบั๊กนี้อีกต่อไป**

**คำขอเดิม (ที่มา, รายงานโดยเจ้าของเอง ไม่ใช่ agent ค้นพบเอง):** "พบบั๊กใหม่: รูปเช็กอินกำพร้าใน Storage — index.html อัปโหลดรูปก่อนเรียก do_check_in ถ้า RPC ตอบ already_checked_in/bad_pin รูปจะค้างใน bucket ตลอดไปเพราะ delete-old-photos ลบตามแถว check_in เท่านั้น ให้แก้ 2 จุด: (1) เรียก do_get_today_status ตรวจ PIN+เช็กอินซ้ำก่อนอัปโหลดรูป (2) เพิ่มการกวาดรูปกำพร้าใน Edge Function"

**สาเหตุ (ยืนยันจากโค้ดจริง):** `doSubmitCheckin()` ใน `index.html` เดิมเรียก `sb.storage.from("checkin-photos").upload(...)` ทันที แล้วค่อยเรียก `sb.rpc("do_check_in", ...)` ต่อจากผลอัปโหลดสำเร็จ — ถ้า `do_check_in` ตอบ `ok:false` (error ใดก็ตาม เช่น `already_checked_in`, `bad_pin`, `officer_not_found`, `note_too_short`, `ready_required`) รูปที่อัปโหลดไปแล้วจะไม่มีแถว `check_in.photo_path` อ้างอิงถึงเลย ฝั่ง Edge Function `delete-old-photos` เดิม (migration 23) query หาแถวที่ต้องลบจากตาราง `check_in` โดยตรง จึงมองไม่เห็นไฟล์กำพร้าพวกนี้เลย — ค้างอยู่ใน bucket ถาวร เป็นทั้งปัญหาพื้นที่จัดเก็บสะสมและช่องโหว่ PDPA คู่ขนานกับที่ migration 23 ตั้งใจแก้แต่แรก

**Fix 1 — `index.html`: เช็ก `do_get_today_status` ก่อนอัปโหลดรูปเสมอ**

แก้ `doSubmitCheckin()` ให้เรียก `sb.rpc("do_get_today_status", { p_officer_id, p_pin })` เป็นขั้นแรกก่อนแตะ Storage ใดๆ ทั้งสิ้น แล้วแยกเงื่อนไข:
- `precheckRes.error` หรือไม่มี `data` (เช่นเน็ตหลุด) → **fail-open**: ปล่อยผ่านไปอัปโหลดรูป+เช็กอินตามปกติทันที ไม่บล็อกผู้ใช้ เพราะการมาทันเวลาสำคัญกว่า และ `do_check_in` ฝั่ง server ยังเป็นผู้ตัดสินสุดท้ายที่แท้จริงอยู่ดี
- `pre.ok === true` (แปลว่าเช็กอินไปแล้ววันนี้จริง) → เรียก `showAlreadyCheckedIn()` ทันที **ไม่อัปโหลดรูปเลย**
- `pre.error === "bad_pin"` → กลับไปหน้า login พร้อม `showLoginError("รหัส PIN ไม่ถูกต้อง กรุณาลองใหม่")` ไม่อัปโหลดรูป
- `pre.error === "officer_not_found"` → กลับไปหน้า login พร้อมข้อความเดียวกับที่ `handleCheckinError` ใช้อยู่เดิม ไม่อัปโหลดรูป
- `pre.error === "not_checked_in"` (เคสปกติ ส่วนใหญ่ที่สุด) หรือ error code อื่นที่ไม่รู้จัก → ดำเนินการอัปโหลดรูป+เรียก `do_check_in` ตามปกติ (logic เดิมทั้งหมดยังอยู่ครบ ย้ายเข้าไปอยู่ใน sub-function ใหม่ `proceedWithUploadAndCheckin()` ภายใน `doSubmitCheckin()` เดิม)

**Fix 2 — `edge_function_delete-old-photos.ts`: เพิ่ม orphan photo sweep** — สแกน bucket แบบ recursive, เทียบกับ `photo_path` ทั้งหมดใน `check_in`, ลบไฟล์กำพร้าที่เกิน grace period 24 ชม.

**สรุปสถานะสุดท้าย (10 ก.ค. 2569):** Push, deploy, E2E test — ✅ ครบทุกจุด (ผลเต็มดูข้อ 24.1)

### 24.1 ผลทดสอบ E2E จริง (10 ก.ค. 2569)

Baseline พบรูปกำพร้าเก่า 60 ไฟล์ (จาก 171 ไฟล์ทั้งหมด) — หลังเรียกฟังก์ชัน orphan sweep (ต้องตั้ง `timeout_milliseconds := 60000` เพราะ default 5 วิสั้นเกินไป) เหลือ 0 ไฟล์กำพร้าเก่า, ไฟล์ที่มีแถวอ้างอิงยังอยู่ครบ 106/106, ไฟล์ใหม่ 5 ไฟล์ที่ยังไม่ถึง grace period ถูกข้ามถูกต้อง — **สรุป: orphan sweep ทำงานถูกต้องสมบูรณ์ ✅**

---
## 25. P0.1 งานเก็บตกเล็ก (ตาม `90_ROADMAP_v2_PLAN.md`) — ✅ เสร็จสมบูรณ์ (10 ก.ค. 2569)

**สถานะ: เขียนโค้ดเสร็จ + verify syntax ผ่านทั้งคู่ + push ขึ้น git สำเร็จจริง (commit `37827bc`) + verify บนเว็บจริงผ่าน — frontend ล้วน ไม่มี migration ใหม่**

**Fix 1 — `report.html`: เพิ่มคอลัมน์ "สิทธิ์หัวหน้า"** ระหว่าง "วิธีเข้าระบบ" กับ "วันทำงาน" — ไม่ต้องแก้ RPC เพราะ `do_supervisor_list_officers` คืนคอลัมน์ `is_supervisor` มาอยู่แล้ว

**Fix 2 — ทั้ง 2 ไฟล์: error mapping ปุ่มกันลบรูป (`attachRetentionButtons`)** รวบรวม error code (`not_supervisor`, `officer_not_found`, `bad_pin`, `checkin_not_found`) มาเป็น `RETENTION_ERROR_MAP` เดียวกันทั้งสองไฟล์ แทนที่การโชว์โค้ดดิบเดิม

**Push:** เจ้าของ confirm แล้ว 10 ก.ค. 2569 — push สำเร็จจริง (commit `37827bc`) verify บนเว็บจริงหลัง push ยืนยันครบ

---

## 26. UX quick win รอบ 2 + GPS timeout ขยาย + บทเรียนเรื่อง PAT/credit/workflow บันทึกเอกสาร (10 ก.ค. 2569)

**สถานะ: เสร็จสมบูรณ์ทุกขั้นตอน — push 3 commit (`f58cd48`, `5f7cac2`, `977142f`) เรียบร้อย ไม่มีงานค้าง**

### 26.1 GPS geolocation timeout: 8 วิ → 20 วิ
`requestGeoNonBlocking()` ใน `index.html` เปลี่ยน `timeout: 8000` → `timeout: 20000` — จุดเดียว ไม่กระทบ logic อื่น

**บั๊กเชิงกระบวนการที่เจอ:** commit แรก (`37827bc`) ไม่มีการเปลี่ยนแปลงของ `index.html` ติดไปด้วย เพราะลืมคัดลอกไฟล์นี้ตอน sync — นี่คือเหตุการณ์ที่ทำให้เกิดกติกาถาวรข้อ 2.12

### 26.2 UX quick win รอบ 2 — 3 ฟีเจอร์ใน `index.html` (commit `5f7cac2`)
(1) จำชื่อล่าสุดใน localStorage (`rayong_checkin_last_officer_v1`) (2) ปุ่มลัดหมายเหตุ "⚡ ปฏิบัติงานปกติ" (3) สถานะ GPS ในหน้าตรวจสอบก่อนยืนยัน (`confirmGeoHint`) — verify `node --check` + `fetch()` เช็ก marker string ผ่านครบ

### 26.3 บทเรียนเรื่อง GitHub fine-grained PAT
ขั้นตอนที่เจ้าของติดจริง 3 รอบ: (1) ลืมกด "Add permissions" เลือก scope (2) พลาดหน้า one-time-reveal ต้องกด "Regenerate token" (3) สำเร็จ **ข้อตกลงใหม่จากเจ้าของ:** "ไม่ต้องการให้คุณขอ token ฉันบ่อยๆ" — agent ควรพยายามใช้ token เดิมซ้ำในเซสชันเดียวกันสำหรับหลาย push จนกว่าจะหมดอายุจริงหรือเจ้าของบอกให้เปลี่ยน

### 26.4 บทเรียนเรื่อง Netlify build credit
ทุก push (แม้แก้แค่ `.md`) เสีย ~15 เครดิตเท่ากันเสมอ ไม่แยกโค้ด/docs — แพลน Free 300 เครดิต/เดือน เหลือเฟือ ไม่ใช่คอขวดจริง

### 26.5 กติกาที่ยืนยันซ้ำ: ต้องอัปเดต + push CLAUDE.md ทุกครั้งที่ปิดงาน ไม่ใช่แค่โค้ด
**CLAUDE.md ไม่ใช่แค่ที่บันทึกโค้ดที่เปลี่ยน แต่รวมกระบวนการ/บทสนทนา/การตัดสินใจเชิงกระบวนการที่กระทบวิธีทำงานของ agent ตัวถัดไปด้วย**

---

## 27. P0.3 PIN rate limiting (migration 25) — ✅ SQL รันจริงสำเร็จแล้ว + ทดสอบ E2E ผ่านหมด + แก้ frontend เสร็จ + push แล้ว (10 ก.ค. 2569)

**สถานะ: เสร็จสมบูรณ์ทุกขั้นตอน — push ขึ้น git สำเร็จแล้ว (commit `4ccfa23`) — ⚠️ (11 ก.ค. 2569) ต่อมาพบว่า migration นี้มีบั๊ก regression บล็อกหัวหน้า PIN ล็อกอินไม่ได้ แก้แล้วด้วย migration 26 ดูข้อ 29**

### 27.1 สถาปัตยกรรม: thin wrapper function
1. `ALTER FUNCTION public.do_X(...) RENAME TO do_X_impl`
2. `REVOKE ALL ... FROM PUBLIC, anon, authenticated` บน `do_X_impl`
3. สร้าง `do_X` ใหม่เป็น wrapper เรียก `check_and_count_pin(p_officer_id, p_pin)` ก่อนเสมอ ถ้าผ่านค่อย delegate ไปยัง `do_X_impl(...)`

**ฟังก์ชันกลาง `check_and_count_pin`:** เช็ก active → `pin_locked_until` → เทียบ `crypt(p_pin, pin_hash)` ผิดครบ 5 ครั้งล็อก 15 นาที คอลัมน์ใหม่ `officer.pin_fail_count`/`pin_locked_until` ครอบคลุม 21 ฟังก์ชัน

### 27.2 ช่องโหว่เพิ่มเติมที่พบ: `do_reset_pin`/`do_supervisor_reset_pin_impl` ไม่ clear `pin_fail_count`/`pin_locked_until` ตอนรีเซ็ต — แก้พร้อมกัน

### 27.3 วิธีรัน SQL จริงผ่าน service_role key + ฟังก์ชันชั่วคราว (`tmp_get_functiondef`/`tmp_query_json`/`tmp_exec_sql`) แทนพิมพ์มือใน SQL Editor — **ค้นพบสำคัญ: bash sandbox เข้าถึง Supabase ไม่ได้เลย (บล็อกด้วย allowlist proxy) ต้องใช้ Chrome-based `fetch()` เท่านั้น** DROP ฟังก์ชันชั่วคราวทิ้งหลังใช้เสร็จเสมอ

### 27.4 ผลทดสอบ E2E: PIN ผิด 5 ครั้ง → ล็อก 15 นาที, PIN ถูกระหว่างล็อกยังถูกปฏิเสธ, รีเซ็ตแล้วปลดล็อกถูกต้อง, `_impl` เรียกตรงผ่าน REST ถูก reject `401` — ✅ ผ่านหมด

### 27.5 Frontend: เพิ่ม `formatPinLockedMessage()` + branch เช็ก `pin_locked` ใน `index.html` (3 จุด) และ `report.html` (11 จุด) — `dashboard.html` ไม่ต้องแก้ (auth-based ล้วน)

### 27.6 บันทึกไว้สำหรับ P0.4: bash/curl เข้าถึง Supabase ไม่ได้ อาจกระทบสถาปัตยกรรม backup แบบ scheduled task — ต้องทดสอบก่อนเริ่ม P0.4

---

## 28. P0.4 backup — ตรวจสอบสถานะจริง + เจ้าของตัดสินใจ "พักไว้ก่อน" (11 ก.ค. 2569)

**สถานะ: ไม่ได้ implement อะไรเลย — ห้าม agent ตัวถัดไปเริ่มเขียนโค้ด/migration ใดๆ สำหรับ P0.4 จนกว่าเจ้าของจะหยิบยกขึ้นมาเอง**

ตรวจสอบจริงผ่าน Chrome: Supabase Free Plan ไม่มี backup อัตโนมัติเลย, Pro Plan $25/เดือนได้ backup 7 วัน — นำเสนอ 2 ทางเลือก (อัปเกรด Pro vs DIY) เจ้าของตอบ **"ยังไม่ตัดสินใจตอนนี้ ควรมีระบบ backup เมื่อมีการขยายการใช้งานแผนอื่นๆเพิ่มเติม หรือให้ตม.จังหวัดอื่นๆใช้งาน"** = ผูกเงื่อนไขกับ P3 (multi-office) แทน **ห้าม agent เริ่มงาน P0.4 เอง** ต้องรอเจ้าของหยิบยกเรื่องขยายหน่วย/แผนขึ้นมาก่อนเท่านั้น

---

## 29. บั๊ก production จริง: `check_and_count_pin` (migration 25) บล็อกหัวหน้า PIN ล็อกอินไม่ได้ — ✅ แก้แล้ว migration 26 (11 ก.ค. 2569)

**สถานะ: วินิจฉัย+แก้+verify+push เสร็จสมบูรณ์ทุกขั้นตอน ไม่มีงานค้าง**

**ที่มา:** ศุภัตรา (หัวหน้า `login_method='pin'`) ล็อกอิน `report.html` ไม่ได้ ขึ้น `officer_not_found`

**วินิจฉัย:** `check_and_count_pin` เช็ก `WHERE ... AND active = true` แต่บัญชีหัวหน้า PIN มี `active=false` โดยตั้งใจ (กันไม่ให้โผล่ดรอปดาวน์เช็กอิน) ทำให้เงื่อนไขตกเสมอ — **ผลกระทบกว้างกว่ารายงาน:** ฟังก์ชันนี้เป็นฟังก์ชันกลางของ RPC ตระกูล `do_supervisor_*` เกือบทั้งหมด (20/21 ฟังก์ชัน) พังหมดตั้งแต่ migration 25 รัน จนถึงตอนแก้นี้ — เดชะบุญที่ทดสอบ E2E ตอน migration 25 ใช้ officer ทดสอบ `active=true` จึงไม่เจอบั๊กนี้ตอนทดสอบ → เป็นที่มาของกติกาข้อ 2.13

**ทางแก้ (migration 26):** เปลี่ยนเงื่อนไขเป็น `WHERE id = p_officer_id AND (active = true OR is_supervisor = true)` — รันตรงผ่าน SQL Editor ทันที (SQL migration ไม่ต้องรอ confirm)

**Verify:** เรียก RPC จริงผ่าน REST ยืนยันได้ `bad_pin` แทน `officer_not_found`, ม็อตโต้ที่เจ้าของตั้งไว้ยังอยู่ครบ (อาการ "ม็อตโต้หาย" ที่รายงานเป็นอาการเดียวกันของบั๊กนี้ — `loadMottoAdmin()` จับ error แบบเงียบ), เจ้าของทดสอบเองยืนยันล็อกอินได้ปกติแล้ว

**Push:** commit `310f123` (รวมกับ P0.5 mobile card layout + roadmap P1.3 doc + migration renumbering)

**ผลกระทบต่อเลข migration:** เลข `26` ที่จองไว้ให้ P1.1 (work_group) ถูกใช้ไปกับ hotfix นี้ก่อน — P1.1 เลื่อนเป็น migration 27

---
## 30. P1a — work_group + badge ทีม OT (migration 27+28, frontend, E2E) — ✅ เสร็จสมบูรณ์ทั้งหมด รวม push (13 ก.ค. 2569)

**สถานะ: backend (SQL, migration 27+28) + frontend (dashboard.html/report.html) + E2E test 4 สถานะ badge + push ขึ้น git ครบทุกจุด verify ผ่านหมดแล้ว — ไม่มีงานค้าง ดูรายละเอียด push ที่ข้อ 30.9**

**ที่มา:** เจ้าของปรึกษาแผน P1 (badge ทีม OT + work_group + Grace Card + เช็คเอาท์) แบบ Strategic Partner ตามสไตล์ที่ตั้งไว้ แล้วยืนยันว่า **ไม่ต้องรอถึง 20 ก.ค. ตามกำหนดเดิม เริ่มได้เลยเมื่อแผนนิ่งแล้ว** — จึงเริ่มเขียนโค้ด P1a (เฉพาะ backend ก่อน) ทันที ไม่ได้เริ่มเองก่อนถูกขอ

### 30.1 สถาปัตยกรรมที่เลือก

ทำตามที่ระบุใน `90_ROADMAP_v2_PLAN.md` ข้อ P1.1 ทุกจุด (ไม่ได้ปรับดีไซน์ใหม่):

```sql
create table public.work_group (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  is_ot_team  boolean not null default false,
  created_at  timestamptz not null default now()
);
alter table public.work_group enable row level security; -- ไม่เปิด policy อ่านตรง เข้าถึงผ่าน RPC (SECURITY DEFINER) เท่านั้น ตามแพทเทิร์นเดิมของโปรเจกต์
alter table public.officer add column work_group_id uuid references public.work_group(id);
alter table public.settings add column team_ok_before   time not null default '08:20';
alter table public.settings add column team_warn_before time not null default '09:00';
```

**⚠️ ตัดสินใจไม่ pre-seed กลุ่มงาน** — เจ้าของยืนยันว่าให้ชวนชัยจัดกลุ่มเอง 19 คนเองทั้งหมดผ่าน UI (P1.2) ไม่ hardcode ล่วงหน้า `work_group`/`officer.work_group_id` จึงว่างเปล่าโดยตั้งใจหลัง migration นี้ (verify แล้ว: `wg_count=0, officers_with_group=0`)

**ฟังก์ชันกลาง `do_team_coverage_json()`** (ไม่มี auth check ในตัว, REVOKE จาก public/anon/authenticated ทั้งหมด — เรียกได้เฉพาะจากภายในฟังก์ชัน SECURITY DEFINER อื่นที่ owner เดียวกันเท่านั้น) คำนวณ coverage ต่อกลุ่ม (เฉพาะ `is_ot_team=true`) จากเวลาเช็กอิน**จริง** (`checked_in_at`) เทียบกับ `team_ok_before`/`team_warn_before`:
- `ok` = มีคนเช็กอินก่อน `team_ok_before`
- `warn` = มีคนเช็กอินแต่ไม่ทันเกณฑ์ `ok`
- `none` = ยังไม่มีใครเช็กอินเลย **และ** เวลาปัจจุบัน (Bangkok) เลย `team_warn_before` ไปแล้ว
- `pending` = **สถานะภายในที่เพิ่มเอง นอกเหนือจาก 3 ค่าที่ยืนยันไว้ในสเปก** — ใช้ตอนยังไม่มีใครเช็กอินแต่ยังไม่เลย `team_warn_before` — **ถ้าเจ้าของเห็นว่าไม่ต้องการ 4 สถานะ ให้แจ้งจะได้ยุบรวมง่ายๆ**

**RPC:** `do_get_team_coverage()` (auth, ชวนชัย), `do_supervisor_get_team_coverage(p_officer_id, p_pin)` (PIN wrapper, แพทเทิร์นเดียวกับ migration 25)

**แก้ RPC เดิม 4 ตัวให้คืน `work_group_id`/ชื่อกลุ่มเพิ่ม:** `do_list_officers_admin()` (DROP ก่อนเพราะเปลี่ยน `RETURNS TABLE`), `do_supervisor_list_officers_impl(...)` (`RETURNS json` แก้ตรงๆ ได้), `do_get_settings()`, `do_set_settings(...)` (เพิ่ม 2 พารามิเตอร์ต่อท้าย — จุดนี้เจอบั๊กจริง ดู 30.2)

### 30.2 ⚠️ บั๊กที่เจอจริงระหว่างทำ + วิธีแก้ (สำคัญ — กติกาใหม่ข้อ 2.14)

หลังรัน `CREATE OR REPLACE FUNCTION do_set_settings(...)` ที่เพิ่ม 2 พารามิเตอร์ต่อท้าย verification query `select proname, count(*) from pg_proc where proname='do_set_settings' group by proname` ได้ **`count = 2`** — Postgres มองว่า parameter list ยาวกว่าเดิม (8 จาก 6 ตัว) เป็นคนละ signature จึง**สร้าง overload ใหม่แยกต่างหาก** ไม่ replace

**ทางแก้:** `DROP FUNCTION public.do_set_settings(double precision, double precision, time without time zone, time without time zone, time without time zone, time without time zone);` (ระบุ signature เดิม 6 ตัวชัดเจน) แล้ว `GRANT EXECUTE` ให้ฟังก์ชัน 8-arg ที่เหลืออยู่ตัวเดียว (grant ไม่สืบทอดอัตโนมัติ) — verify ซ้ำแล้ว `count = 1` ทุกฟังก์ชันที่แก้ในรอบนี้ (8 ตัว)

**บันทึกเป็นกติกาถาวรแล้วที่ข้อ 2.14**

### 30.3 Verify ที่ทำจริง

`count(*)` ทุกฟังก์ชัน = 1, `has_function_privilege` ตรงตามดีไซน์ (`do_supervisor_get_team_coverage` anon=true, `do_team_coverage_json` anon=false/authenticated=false), `settings` ค่า default `08:20:00/09:00:00`, `work_group`/`officer.work_group_id` ว่างเปล่า (0/0) ตามตั้งใจ, DROP ฟังก์ชันชั่วคราวทิ้งหมด

### 30.4 เทคนิคใหม่: อ่าน RPC source ยาวๆ ผ่าน `get_page_text` ตรงๆ หลังรัน query (ไม่ต้องเปิด modal ⤢) — เร็วกว่าเดิม แต่ไม่เสถียรถ้ามีหลาย query ก่อนหน้าในเซสชันเดียวกัน ให้ fallback ไปคลิกเปิด modal ถ้าไม่ได้ผล

### 30.5 บั๊กเชิงกระบวนการที่เจอซ้ำ: SQL Editor focus-loss (คลิกพื้นที่ว่างท้ายบรรทัดแทนกลางข้อความ), `type` timeout 30 วิ (เนื้อหามักพิมพ์ครบอยู่ดี), dialog "Potential issue detected" เด้งทุกครั้งที่มี `DROP FUNCTION`

### 30.6 Migration 28 — RPC จัดการกลุ่มงาน (auth-only) — ✅ เขียน+รัน+verify แล้ว

5 ฟังก์ชันใหม่ (ทั้งหมด `GRANT ... TO authenticated` เท่านั้น ไม่ให้ `anon`): `do_admin_list_work_groups()`, `do_admin_create_work_group(p_name, p_is_ot_team)`, `do_admin_update_work_group(p_id, p_name, p_is_ot_team)`, `do_admin_delete_work_group(p_id)` (unassign สมาชิกก่อนลบ), `do_admin_set_officer_group(p_officer_id, p_work_group_id)` — verify `count(*)=1` + `has_function_privilege('authenticated', ..., 'execute')=true` ทุกตัว

### 30.7 Frontend — การ์ด badge ทีม OT + UI จัดการกลุ่มงาน (dashboard.html + report.html) — ✅ เขียน+verify syntax แล้ว

**dashboard.html (ชวนชัย, auth):** การ์ด "🤝 จุดบริการกลุ่มงาน OT" ใน `group-daily` (เรียก `do_get_team_coverage()`), การ์ด "🤝 จัดการกลุ่มงาน OT (เฉพาะชวนชัย)" ใน `group-settings` (ฟอร์มเพิ่มกลุ่ม + ตารางแก้/ลบ), ตาราง "รายชื่อเจ้าหน้าที่ทั้งหมด" เพิ่มคอลัมน์ "กลุ่มงาน" เป็น `<select>` dropdown ต่อแถว, `checkSupervisorThenLoad()` โหลดคู่กับ `do_admin_list_work_groups`, mobile CSS ครบ

**report.html (ศุภัตรา/ผู้ช่วยแอดมิน, PIN) — อ่านอย่างเดียว:** การ์ดเดียวกันแต่เรียก `do_supervisor_get_team_coverage(p_officer_id, p_pin)` — **ไม่มีการ์ดจัดการกลุ่มงาน** (RPC `do_admin_*` grant `authenticated` เท่านั้น) ตาราง "กลุ่มงาน" เป็นข้อความอย่างเดียว

**⚠️ ข้อสังเกตจากเจ้าของ (13 ก.ค. 2569):** ไม่ชอบชื่อการ์ด "🤝 จุดบริการกลุ่มงาน OT" ต้องการเปลี่ยนชื่อภายหลัง — แก้ง่าย (HTML 1 บรรทัดในทั้ง 2 ไฟล์ ไม่กระทบ backend/RPC) รอเจ้าของบอกชื่อใหม่ที่ต้องการ

**Verify syntax:** `node --check` ผ่านทั้ง `dashboard.html` (1656 บรรทัด) และ `report.html` (1381 บรรทัด) ไม่มี syntax error

### 30.8 E2E Test — 4 สถานะ badge (ok/warn/none/pending) + verify สีรายคนไม่เปลี่ยน — ✅ ผ่านหมดทุกเคส

ใช้ officer ทดสอบ "สมาชิกใหม่" + กลุ่มทดสอบชั่วคราว เรียก `do_team_coverage_json()` ตรงๆ: ไม่มีเช็กอิน+เลย `team_warn_before` → `none` ✅ | เช็กอิน 08:00 (ก่อน `team_ok_before`) → `ok` ✅ | เช็กอิน 08:45 (ระหว่างสอง threshold) → `warn` ✅ | ไม่มีเช็กอิน+ยังไม่เลย `team_warn_before` (จำลองด้วยตั้ง threshold ชั่วคราว 23:59) → `pending` ✅

**Verify ไม่กระทบสีรายบุคคล:** snapshot `check_in.status`/`override_status` ของ 18 แถวจริงก่อน-หลังทดสอบ — ตรงกันทุกแถว 100% (ฟังก์ชันเป็น read-only ต่อ `check_in` ทั้งหมด)

**Cleanup:** ลบกลุ่ม/officer ทดสอบ, คืนค่า `team_warn_before`, DROP ฟังก์ชันชั่วคราวทิ้งหมด — verify ครบ

### 30.9 Push ขึ้น git — ✅ สำเร็จ (13 ก.ค. 2569)

เจ้าของสั่ง "push เลย" — sync ไฟล์ที่แก้ทั้งหมด (`dashboard.html`, `report.html`, `27_work_group_p1a.sql`, `28_admin_work_group_rpc.sql`, `CLAUDE.md`) เข้า git working copy แล้ว commit+push ขึ้น `main`

**⚠️ บั๊กเชิงกระบวนการที่เจอรุนแรงกว่าเดิมรอบนี้ (ยกระดับเป็นกติกาถาวรแล้วที่ข้อ 2.10):** bash-mount staleness คราวนี้ค้างนานถึง **3 วัน** (ไฟล์ที่เพิ่งแก้ในเซสชันนี้ `cp`/`cat` ผ่าน bash ตรงๆ ยังได้เนื้อหาเก่าของวันที่ 10 ก.ค.) ตรวจพบจาก `grep` หาข้อความที่เพิ่งเพิ่มไม่เจอในไฟล์ที่ `cp` มา ทั้งที่ `Grep` tool (ซึ่งอ่านจากไฟล์จริง) เจอปกติ — แก้โดย **re-clone repo สดจาก GitHub เข้า `/tmp` ใหม่ แล้วเขียน Python script replay ทุก `(old_string, new_string)` ที่ทำผ่าน Edit tool ในเซสชันนี้ทับไฟล์ที่ clone มา** (แทนที่จะ `cp` จาก mount ที่ค้าง) แล้ว verify ด้วยจำนวนบรรทัด+marker string+`node --check` ก่อน commit จริง — สำหรับไฟล์ที่ไม่เคยถูก Edit ในเซสชันนี้ (เช่น .sql ที่สร้างด้วย Write ครั้งเดียว) และ `CLAUDE.md` (ที่แก้เยอะจนไม่สะดวก replay ทีละ diff) ใช้วิธีอ่านเนื้อหาเต็มผ่าน `Read` tool แล้ว `Write` ไปที่ outputs (เชื่อถือได้) ก่อน แล้วค่อย `cp` จาก outputs เข้า git working copy

**Verify บนเว็บจริงหลัง push:** `fetch()` เช็ก marker string บน `rayongimm.link/dashboard.html` และ `/report.html` (`teamCoverageWrap`, `do_admin_create_work_group`, `TEAM_BADGE_MAP`, `groupsMgmtWrap` ฯลฯ) ครบทุกจุด

---
