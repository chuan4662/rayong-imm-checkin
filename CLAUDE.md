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

อัปเดตล่าสุด: 11 กรกฎาคม 2569 (พบ+แก้บั๊กจริงบน production: ศุภัตราเข้า report.html ไม่ได้ เพราะ `check_and_count_pin` migration 25 บล็อกหัวหน้า PIN ทุกคน — วินิจฉัยจริงผ่าน SQL Editor, แก้เป็น migration 26, verify ผ่าน REST จริง, เจ้าของยืนยันเข้าได้ปกติแล้ว, push ขึ้น git แล้ว (commit `310f123`) ดูข้อ 29 — ก่อนหน้านั้นวันเดียวกัน: P0.5 จัดกลุ่มการ์ด dashboard/report.html + mobile card layout report.html เสร็จสมบูรณ์+push แล้ว (commit `5d146fd`, `310f123`), เพิ่มดีไซน์ P1.3 Grace Card ใน roadmap (ยังไม่เขียนโค้ด), P0.4 backup ตรวจสอบสดแล้วเจ้าของสั่งพักไว้ก่อนผูกกับ P3 ดูข้อ 28 — ก่อนหน้านี้ (10 ก.ค. บ่าย): P0.3 PIN rate limiting SQL migration 25 รันจริง+ทดสอบ E2E+แก้ frontend+push ขึ้น git สำเร็จครบ (commit `4ccfa23`) ดูข้อ 27 — ก่อนหน้านั้นเช้า 10 ก.ค.: ปิดงานบั๊กรูปกำพร้า + แก้ cron timeout + P0.1 เสร็จครบทั้งหมด + GPS timeout quick win + UX quick win รอบ 2 push แล้ว + บันทึกกระบวนการทำงาน/บทเรียน PAT-credit ลงข้อ 26 ดูข้อ 24/24.1/25/26/27/28/29)

**📌 มีแผนงานใหม่ที่ยืนยันดีไซน์แล้วแต่ตั้งใจ "ยังไม่เริ่มทำ" — ดูข้อ 22 ใน CLAUDE_ARCHIVE.md:** ระบบ badge ระดับทีมสำหรับกลุ่มงานธุรกิจ/ครอบครัว (2 คน/กลุ่ม ที่มักต้อง OT ดึกเป็นประจำ) ดีไซน์ยืนยันกับเจ้าของแล้ว 6 ก.ค. 2569 — **เจ้าของขอให้รอ ~2 สัปดาห์ก่อน (ราวๆ 20 ก.ค. 2569) ค่อยเริ่มเขียนโค้ด** ห้าม agent ตัวถัดไปเริ่มทำเองก่อนถึงกำหนดนี้เว้นแต่เจ้าของหยิบยกขึ้นมาเอง

---

## 1. สถานะปัจจุบัน (สรุปสั้น)

ระบบ **ใช้งานจริงแล้ว** (live) — เจ้าหน้าที่เช็กอินจริงตั้งแต่เช้าวันที่ 3 กรกฎาคม 2569 (18+ คนเช็กอินสำเร็จ) หัวหน้าเข้าดูแดชบอร์ดได้ทั้ง 2 แบบ (Auth และ PIN) รวมถึงดูรูปย่อได้แล้วทั้งคู่ มีสถานะ **สีม่วง (เช็กอินไม่สมบูรณ์)** — แสดงคู่กับสีเวลาเดิม เมื่อเช็กอินห่างจากที่ทำงาน &gt;50 ม. หรือไม่เปิด/อนุญาต GPS (ข้อ 9 ใน archive) เพิ่ม **กล่องม็อตโต้หมุนเวียน 3 ข้อความ** (ข้อ 10, 17 ใน archive) และ **สถิติส่วนตัวรายเดือน** (เห็นเฉพาะตัวเอง รวมสีน้ำตาล "ขาดเช็กอิน", ข้อ 10, 16 ใน archive) แสดงหลังเช็กอินเสร็จทุกครั้ง

**ฟีเจอร์หลักที่ deploy แล้วและใช้งานจริง** (รายละเอียดเต็มทั้งหมดอยู่ใน `CLAUDE_ARCHIVE.md` ข้อ 9–22):
- แดชบอร์ดหัวหน้าครบสเปก v1 — ประวัติย้อนหลัง, override สถานะ, Export Excel (archive ข้อ 12)
- หมายเหตุเพิ่มเติมหลังเช็กอิน (write-once) + สรุปตามคีย์เวิร์ด 6 หมวด (archive ข้อ 14, 18)
- ระบบตารางเวรแบบง่าย (work_days) + วันหยุดนักขัตฤกษ์ + สีน้ำตาลเข้ม "ขาดเช็กอิน" (archive ข้อ 15)
- วันเริ่มนับสถิติรายเดือนแบบตั้งค่าได้ (archive ข้อ 16)
- ตั้งค่าระบบผ่าน UI + จัดการบัญชีหัวหน้า PIN (เฉพาะชวนชัย, archive ข้อ 19)
- PDPA auto photo-deletion (31 วัน rolling + retention hold, archive ข้อ 20)
- ตัดข้อความยาวในตาราง + การ์ด "วันนี้แจ้งไม่พร้อม" (archive ข้อ 21)
- **Git + Netlify CI (deploy อัตโนมัติ)** — ดูข้อ 23 ด้านล่าง (ยังอยู่ในไฟล์นี้ เพราะเป็นข้อมูล operational ที่ใช้ทุกเซสชัน)

**⚠️ ถ้ากำลังเปิดโปรเจกต์นี้จาก Cowork project ใหม่ (เช่น ย้ายมาทำต่อบนเครื่องอื่น):** อ่าน `00_SPEC_v1_ORIGINAL.md` ในโฟลเดอร์นี้ก่อนเสมอ — เป็นสเปกตั้งต้น v1 ฉบับเต็ม (กติกาเหล็ก 6 ข้อ) ที่แยกออกมาจาก Cowork Project Instructions เดิม เพราะ Project Instructions ไม่ติดไปกับโฟลเดอร์เวลาเปิดโปรเจกต์ใหม่ (รายละเอียดเต็มอยู่ใน `CLAUDE_ARCHIVE.md` ข้อ 11)

**✅ (4 ก.ค. 2569) แก้ข้อมูลเจ้าหน้าที่ในฐานข้อมูลจริง (ไม่ต้อง deploy เพราะไม่ใช่โค้ด):** แก้นามสกุล ร.ต.อ.หญิง กชพร จากสะกดผิด "จี้คีรี" (ไม้โท) เป็นถูกต้อง "จี๋คีรี" (ไม้จัตวา), ย้าย sort_order ให้อยู่ระหว่างนรินทร์กับพีระชัย, เพิ่มรายชื่อทดสอบ "สมาชิกใหม่" ไว้ล่างสุดของ dropdown (ยังไม่ตั้ง PIN — ใช้ทดสอบขั้นตอนตั้ง PIN ครั้งแรกได้) มีผลทันทีบนเว็บจริงเพราะเป็นการแก้ข้อมูลใน Supabase ตรงๆ

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
10. **⚠️ (ใหม่ 9 ก.ค. 2569) บั๊ก bash-mount staleness — ห้ามเชื่อ bash/shell เวลาอ่านไฟล์ในโฟลเดอร์นี้ (`Service Rayong Imm app`) เด็ดขาด ให้ใช้ `Read` tool เป็นความจริงหลักเสมอ** — เจอซ้ำหลายครั้ง (`cat`/`wc -l`/`python open()`/`dd` ทุกวิธีให้ผลค้างเก่าเหมือนกันหมด บางครั้ง staleness นี้ครอบคลุมถึง byte size/mtime ด้วย ไม่ใช่แค่เนื้อหา) แม้จะ `sleep` รอนานหรือลองหลายวิธีก็ไม่การันตีว่าจะได้ข้อมูลสด — Grep tool และ Read tool ดูเหมือนจะไม่ติดบั๊กนี้ (เชื่อถือได้กว่า raw bash) ถ้าต้อง syntax-check ไฟล์ด้วย `node --check` ให้คัดลอกเนื้อหาจาก `Read` tool ไปสร้างไฟล์ scratch **ชื่อใหม่ที่ไม่เคยใช้มาก่อน** ใน outputs ก่อนเสมอ (อย่าเขียนทับไฟล์ scratch เดิม เจอบั๊กเดียวกันซ้ำได้แม้เป็นไฟล์ที่เพิ่งสร้างเองในเซสชันเดียวกัน)
11. **⚠️ (ใหม่ 10 ก.ค. 2569) ห้าม agent พยายามแก้ไข/deploy Edge Function ผ่านหน้า "Edge Functions" ใน Supabase Dashboard ด้วยเบราว์เซอร์ (Chrome/computer-use) อีกเด็ดขาด** — เซสชันก่อนหน้า (9 ก.ค. 2569) พยายาม deploy `edge_function_delete-old-photos.ts` เวอร์ชันใหม่ผ่านหน้านี้ด้วยเบราว์เซอร์ แล้วโดน safeguard ของระบบตัดเซสชันกลางคัน จนเจ้าของต้องเข้าไป deploy เองด้วยมือแทน (ยืนยันว่า deploy สำเร็จ + Verify JWT ยังปิดอยู่ตามที่ต้องการ) **บทเรียน:** งาน deploy/แก้ไขโค้ด Edge Function ผ่านเบราว์เซอร์มีความเสี่ยงโดน safeguard ตัดกลางคันสูง ควรให้เจ้าของทำเองเสมอ (agent เตรียมโค้ดให้พร้อม paste) แทนที่ agent จะคุมเบราว์เซอร์ทำการ deploy เองทั้งหมด — ส่วนการ **ทดสอบ/verify** ฟังก์ชันหลัง deploy ยังทำได้ปกติผ่านหน้า **SQL Editor** (คนละหน้ากับ Edge Functions ไม่ติดข้อห้ามนี้) โดยเรียก `net.http_post` ตรงๆ พร้อม header `x-cron-secret` จาก `vault.decrypted_secrets` เหมือนวิธีทดสอบเดิมใน migration 23 (ตัวอย่างจริงดูข้อ 24.1)
    - **⚠️ ข้อควรระวังที่เจอจริงระหว่างทดสอบ (10 ก.ค. 2569):** `net.http_post` ค่า default timeout คือ 5 วินาที ซึ่ง**สั้นเกินไป**สำหรับ orphan sweep ใหม่ (ต้อง recursive-list ทุกไฟล์ในทุกโฟลเดอร์ officer/date) ทำให้ `net._http_response.timed_out = true` แม้ฟังก์ชันจะยังทำงานต่อจนเสร็จจริงฝั่ง server ก็ตาม (ยืนยันจากผลทดสอบจริงในข้อ 24.1) **ถ้าจะเรียกฟังก์ชันนี้ผ่าน SQL Editor เพื่อทดสอบ/monitor ในอนาคต ต้องระบุ `timeout_milliseconds := 60000` (หรือมากกว่า) ใน `net.http_post` เสมอ ไม่งั้นจะได้ `content`/`status_code` เป็น NULL ทั้งที่ฟังก์ชันทำงานถูกต้อง** — **✅ (10 ก.ค. 2569) แก้แล้ว:** อัปเดต `cron.schedule('delete-old-photos-daily', ...)` ให้ใส่ `timeout_milliseconds := 60000` ด้วยเช่นกัน (ดู migration `24_cron_timeout_fix.sql`) รันตรงผ่าน SQL Editor แล้ว verify ผ่าน — jobid=1 เดิม, schedule `'0 19 * * *'` เดิม, active=true, `has_timeout=true` ไม่มีงานค้างเรื่องนี้อีกต่อไป
12. **⚠️ (ใหม่ 10 ก.ค. 2569) ก่อน `git add -A && git commit` ในขั้นตอน `/tmp` sync (ข้อ 23.4) ต้องเช็กให้ครบว่าคัดลอกไฟล์ที่แก้จริง "ทุกไฟล์" ในเซสชันนั้นแล้ว ไม่ใช่แค่ไฟล์ในขอบเขตงานที่กำลังพูดถึง** — เจอจริง 10 ก.ค. 2569: แก้ GPS timeout ใน `index.html` เสร็จไปแล้วแยกจากงาน P0.1 (คนละไฟล์ คนละบทสนทนาย่อย) พอถึงขั้น sync เข้า git clone ลืมคัดลอก `index.html` ไปด้วย ทำให้ commit แรกไม่มีการเปลี่ยนแปลงไฟล์นี้เลยทั้งที่บอกผู้ใช้ว่าทำแล้ว ต้อง push แก้เพิ่มอีกรอบ วิธีป้องกัน: ก่อน commit ให้ไล่ทวนรายการไฟล์ที่แก้จริงทั้งหมดในเซสชัน (ไม่ใช่แค่ที่เกี่ยวกับ task ล่าสุด) แล้ว **verify บนเว็บจริงหลัง push ทุกไฟล์ที่อ้างว่าแก้ไปเสมอ** (ใช้ `fetch()` เช็ก marker string ของแต่ละไฟล์ อย่าเชื่อว่า sync ไปแล้วเพราะจำได้)
13. **⚠️ (ใหม่ 11 ก.ค. 2569) migration ใดก็ตามที่แตะ logic การล็อกอิน/ยืนยันตัวตน (PIN หรือ auth) ต้องทดสอบ E2E ด้วยบัญชีที่จำลองสภาพ "หัวหน้า PIN" จริง (`active=false, is_supervisor=true`) เสมอ ไม่ใช่แค่ officer ทดสอบทั่วไปที่ `active=true`** — ที่มา: migration 25 (P0.3 PIN rate limiting) ทดสอบ E2E ผ่านหมดตอนแรกเพราะใช้ officer ทดสอบที่ `active=true` แต่ `check_and_count_pin` ที่เขียนขึ้นดันเช็กเงื่อนไข `active=true` ตรงๆ ซึ่งบัญชีหัวหน้า PIN จริง (ศุภัตรา, ผู้ช่วยแอดมิน) มี `active=false` โดยตั้งใจมาตั้งแต่ migration 11 (กันไม่ให้โผล่ในดรอปดาวน์เช็กอิน) ทำให้บั๊กหลุดรอดไปถึง production จริง บล็อกหัวหน้า PIN ล็อกอินไม่ได้เลยอยู่ 1 วันเต็ม (10-11 ก.ค. 2569) กว่าจะมีคนรายงานแล้วแก้เป็น migration 26 (ดูข้อ 29) — **บทเรียน:** โครงสร้างข้อมูลของโปรเจกต์นี้มีคอลัมน์ที่ความหมายไม่ตรงไปตรงมา (`active` ควบคุมทั้ง "โผล่ในดรอปดาวน์เช็กอินไหม" และถูกเข้าใจผิดว่าควบคุม "ยืนยันตัวตนได้ไหม" ด้วย) การทดสอบด้วย row ทดสอบทั่วไปที่ตั้งค่าเริ่มต้น (`active=true`) จึงไม่ครอบคลุมเคสจริงของบัญชีหัวหน้า ต่อไปนี้ทุก migration ที่แก้/เพิ่ม RPC ตระกูล `do_supervisor_*` หรือฟังก์ชันกลางที่ RPC เหล่านั้นเรียกร่วมกัน (เช่น `check_and_count_pin`) ต้องมีขั้นตอนทดสอบแยกด้วย officer ทดสอบที่ตั้ง `active=false, is_supervisor=true` (หรือ `supervisor_enabled=false` ถ้าเกี่ยวข้องกับ feature ที่ทดสอบ) อย่างน้อย 1 เคส ก่อนสรุปว่า "ทดสอบ E2E ผ่านหมด"

---

## 3. โครงสร้างฐานข้อมูล — ไฟล์ migration ทั้งหมด (รันตามลำดับ 01→24)

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

**⚠️ หมายเหตุเลข migration ถัดไป:** เลข 24 ถูกใช้ไปกับ cron timeout fix, เลข 26 ถูกใช้ไปกับ hotfix ฉุกเฉินข้างต้น (ไม่ใช่แผน P1.1 ตามที่ roadmap เขียนไว้เดิม) migration ถัดไปจริงคือ **27** ให้เลื่อนเลขที่เหลือทั้งหมดในแผนตามไปด้วย (P1.1=27, P2.2=28, P2.3=29, P3.1=30) — ดูตารางเต็มใน `90_ROADMAP_v2_PLAN.md` ข้อ 8

**ตารางหลัก:** `settings` (แถวเดียว), `officer` (19 เจ้าหน้าที่ + 3 หัวหน้า, `active=false` สำหรับหัวหน้าเพื่อไม่ให้โผล่ในดรอปดาวน์เช็กอิน), `check_in`

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

**ปิดงานแล้ว (10 ก.ค. 2569):** บั๊ก "รูปเช็กอินกำพร้าใน Storage" — push, deploy, และ E2E test ผ่านหมดแล้ว ดูข้อ 24 | P0.1 (คอลัมน์สิทธิ์หัวหน้าใน report.html + error mapping ปุ่มกันลบรูป 2 ไฟล์) — push แล้ว ดูข้อ 25 | GPS geolocation timeout ใน `index.html` (8 วิ → 20 วิ) — push แล้ว (commit `f58cd48`) | UX quick win รอบ 2 ใน `index.html` (จำชื่อล่าสุด localStorage + ปุ่มลัดหมายเหตุ + สถานะ GPS ในหน้าตรวจสอบก่อนยืนยัน) — push แล้ว (commit `5f7cac2`), verify บนเว็บจริงผ่านทั้งหมด | **P0.3 PIN rate limiting (migration 25)** — SQL รันจริงบน Supabase แล้ว + ทดสอบ E2E ผ่านหมด + แก้ frontend (`index.html`/`report.html`) เสร็จ + verify syntax ผ่าน — **⚠️ ไฟล์ .html ยังไม่ได้ push ขึ้น git ณ ตอนบันทึกนี้ (SQL ฝั่ง Supabase มีผลใช้งานจริงแล้วตามกติกาข้อ 2.1 ข้อยกเว้น แต่ frontend รอ confirm push) ดูข้อ 27**

**⏸️ พักไว้ก่อนตามคำสั่งเจ้าของ (11 ก.ค. 2569):** P0.4 backup — ตรวจสอบสดยืนยันแล้วว่า Supabase แพลน Free ไม่มี backup อัตโนมัติเลย เสนอทางเลือก (อัปเกรด Pro $25/เดือน vs DIY) แล้ว เจ้าของเลือก **"ยังไม่ตัดสินใจตอนนี้ ควรมีระบบ backup เมื่อมีการขยายการใช้งานแผนอื่นๆเพิ่มเติม หรือให้ตม.จังหวัดอื่นๆใช้งาน"** = ผูกเงื่อนไขกับ P3 (multi-office) ห้าม agent เริ่มเองก่อนเจ้าของหยิบยก ดูข้อ 28

**✅ (11 ก.ค. 2569) `.gitignore` สำหรับ `.service_role_key.local.txt` เพิ่มแล้ว** — ทำพร้อมกับ push P0.3 (commit `4ccfa23`) ไม่มีความเสี่ยงหลุดขึ้น GitHub อีกต่อไป

**✅ (11 ก.ค. 2569) P0.5 (บางส่วน) — จัดกลุ่มการ์ด dashboard.html + report.html เสร็จแล้ว push แล้ว (commit `5d146fd`), verify บนเว็บจริงผ่าน:** ทั้ง 2 ไฟล์แบ่งการ์ดเป็น 3 กลุ่ม "📋 ประจำวัน / 📊 รายงาน / ⚙️ ตั้งค่า" พร้อมเมนูลอย (sticky nav) กดเลื่อนไปแต่ละกลุ่มได้ — แก้เฉพาะ HTML/CSS ไม่แตะ RPC/JS logic เลย ครอบคลุมทั้งแดชบอร์ดชวนชัย (11 การ์ด) และ report.html ของศุภัตรา/ผู้ช่วยแอดมิน (9 การ์ด ไม่มีการ์ดตั้งค่าระบบ/จัดการบัญชีหัวหน้าเพราะเป็นสิทธิ์ชวนชัยเท่านั้น) **⚠️ บันทึกบั๊กใหม่ที่เจอระหว่างทำ:** บั๊ก bash-mount staleness (กติกาข้อ 2.10) เกิดกับ `dashboard.html`/`report.html` ระหว่างรอบนี้ด้วย (ไม่ใช่แค่ตอน sync เข้า git — คราวนี้เจอตอนจะรัน `node --check`/`wc -l` เพื่อ verify หลังแก้ไฟล์ในโฟลเดอร์โปรเจกต์ตรงๆ ก่อน sync เข้า git ด้วยซ้ำ) แก้โดยใช้ Grep tool (เชื่อถือได้) แทน bash เพื่อ verify โครงสร้าง และตอน sync เข้า git clone ก็เปลี่ยนวิธีจาก `cp` ตรงๆ เป็นการ apply string-replace ผ่าน Python บนไฟล์ที่ clone มาสดจาก GitHub (ไม่ผ่าน mount ที่ค้างเลย) แทน — ปลอดภัยกว่าและ verify ผ่านครบ (จำนวนการ์ด/id/`node --check` ตรงทุกจุด) **✅ (11 ก.ค. 2569) ส่วนที่เหลือของ P0.5 — report.html mobile card layout เสร็จแล้วเช่นกัน push แล้ว (commit `310f123`), verify บนเว็บจริงผ่าน:** เพิ่ม CSS `@media (max-width: 640px)` แปลงตารางข้อมูลทั้ง 8 ตัวใน report.html (เช็กอินวันนี้, ประวัติ, วันนี้แจ้งไม่พร้อม, ขาดเช็กอิน, สรุปหมายเหตุ, รายชื่อเจ้าหน้าที่, วันหยุด, วันเริ่มนับสถิติ) ให้แสดงเป็นการ์ดแนวตั้งแทนตารางกว้างบนจอมือถือ ใช้ `nth-child` แม็ปชื่อคอลัมน์ผ่าน `::before` ไม่แตะ JS เลยแม้แต่บรรทัดเดียว ความเสี่ยง regression ต่ำมาก **P0.5 ปิดงานสมบูรณ์ทั้งหมดแล้ว ไม่มีงานค้าง**
- ลำดับเต็มรวมกับ roadmap เดิม (P0.3 PIN rate limit, P0.4 backup, P1 badge ทีม ฯลฯ) อยู่ในบทสนทนาที่ปรึกษากับเจ้าของ 10 ก.ค. 2569 — สรุปตอนนั้น: ทำ backup ก่อน P1 badge — **⚠️ (11 ก.ค. 2569) แก้ไขลำดับนี้ทีหลัง:** เจ้าของทบทวนใหม่แล้วสั่ง**พัก P0.4 ไว้ก่อน** ผูกกับเงื่อนไข P3/multi-office แทน (ดูข้อ 28) ส่วน PIN rate limit (P0.3) ทำเสร็จแล้วจริงตามเดิม ไม่กระทบ, P1 badge คงกำหนดเดิม ~20 ก.ค. ห้ามเริ่มก่อน

**แผนใหม่ที่ยืนยันดีไซน์แล้ว แต่ตั้งใจรอก่อน (บันทึก 6 ก.ค. 2569 — รายละเอียดเต็มใน `CLAUDE_ARCHIVE.md` ข้อ 22):**
- **Badge ระดับทีมสำหรับกลุ่มงานธุรกิจ/ครอบครัว** (ทีมละ 2 คนที่มัก OT ดึก) — ดีไซน์ยืนยันแล้ว (badge แยกระดับทีม ไม่แตะสีรายคน) แต่เจ้าของขอให้รอ **~2 สัปดาห์ (ราวๆ 20 ก.ค. 2569)** ค่อยเริ่มเขียนโค้ด — **ห้าม agent เริ่มทำเองก่อนถึงกำหนด**

**ค้างจาก spec เดิม (ยังไม่ทำ):**
- เช็กเอาต์ตอนเย็น — อยู่นอก scope v1 ตามสเปกเดิม
- **เฟส D ตาม spec เดิม**: ให้ใช้งานจริงต่อเนื่อง 1 เดือนก่อน แล้วค่อยตัดสินใจเรื่องระบบให้คะแนน/รางวัลจากข้อมูลจริง — **ห้ามเพิ่มฟีเจอร์นี้ก่อนถึงเวลา**
- ฟีดแบ็กประชาชน + QR เคาน์เตอร์ — ต้องรออนุมัติเป็นลายลักษณ์อักษรจากผู้บังคับบัญชาก่อน ตามสเปกเดิม
- คู่มือผู้ใช้ (ข้อ 8) — ยังไม่ได้อัปเดตให้ครบทุกฟีเจอร์ใหม่ตั้งแต่ข้อ 14 เป็นต้นมา (เจ้าของอัปเดตเองเป็นหลัก ไม่ต้องหยิบยกเว้นแต่เจ้าของถามเอง — ดูข้อ 8)
- P1–P3 ใน `90_ROADMAP_v2_PLAN.md` ยังไม่เริ่มทำ (นอกเหนือจาก P0.1/P0.2/P0.3 ที่เสร็จแล้ว, P0.4 ที่พักไว้ตามคำสั่งเจ้าของ ดูข้อ 28) — ดูหมายเหตุเลข migration ที่เลื่อนแล้วในข้อ 3
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
  migrations/01_*.sql ... 24_*.sql           (ย้ายเข้าโฟลเดอร์ย่อย)
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

1. sync ไฟล์ปัจจุบันจากโฟลเดอร์โปรเจกต์จริง (`Service Rayong Imm app`) ไปที่ working copy ใน `/tmp` (เช่น `/tmp/rayong-imm-checkin-git`) — ถ้า working copy นี้ไม่มีอยู่แล้วในเซสชันปัจจุบัน ต้อง `git clone` จาก GitHub มาใหม่ก่อน (repo เป็น public แล้ว clone ได้โดยไม่ต้องใช้ token) แล้วค่อยคัดลอกไฟล์ปัจจุบันทับ **⚠️ ห้ามใช้ `rsync` ทั้งโฟลเดอร์ตรงๆ** เพราะโฟลเดอร์จริงเป็นไฟล์แบนราบ (SQL/docs/edge function อยู่ root ปนกันหมด) แต่ git working copy จัดเป็นโฟลเดอร์ย่อย (`migrations/`, `edge-functions/`, `docs/`) ตามข้อ 23.1 — ต้องคัดลอกทีละไฟล์ไปยัง path ที่ถูกต้องในโครงสร้างใหม่ และ **ต้องอ่านเนื้อหาไฟล์ผ่าน `Read` tool เสมอ ไม่ใช่ bash `cp`/`cat`** (ดูบั๊ก bash-mount staleness ในข้อ 2.10 — ไฟล์ในโฟลเดอร์จริงอาจดูค้าง/ตัดจบกลางบรรทัดถ้าอ่านผ่าน bash ตรงๆ) **⚠️ ต้องไล่ทวนรายการไฟล์ที่แก้จริงทั้งหมดในเซสชันก่อน sync ทุกครั้ง (ข้อ 2.12) — ไม่ใช่แค่ไฟล์ในขอบเขต task ล่าสุดที่กำลังคุยอยู่**
2. `git add -A && git commit -m "..."` ใน `/tmp/rayong-imm-checkin-git`
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

**หมายเหตุเรื่อง race condition ที่ยังเหลืออยู่โดยตั้งใจ**: การเช็กก่อนแล้วค่อยอัปโหลดยังมีช่องว่างเล็กๆ ระหว่างสองขั้นตอนนี้ (เช่น เปิด 2 แท็บพร้อมกันแล้วกดเช็กอินพร้อมกัน) ที่ทำให้รูปกำพร้าเกิดขึ้นได้อยู่ดีในเคส edge case จริง — ยอมรับความเสี่ยงนี้เพราะ (1) ความน่าจะเป็นต่ำมากในการใช้งานจริง (2) แก้ที่ client เพียงอย่างเดียวไม่มีทางปิดสนิท 100% เพราะ client ไม่ใช่ single source of truth และ (3) มี **Edge Function orphan-sweep (Fix 2 ด้านล่าง) เป็นตาข่ายรองรับอีกชั้น** ที่จะกวาดรูปกำพร้าที่หลุดผ่านมาได้ทุกกรณีอยู่ดีภายใน 24 ชั่วโมง

**Fix 2 — `edge_function_delete-old-photos.ts`: เพิ่ม orphan photo sweep**

เพิ่ม logic ใหม่ต่อท้ายลูปลบรูปตามอายุเดิม (ไม่แตะ logic เดิมเลย แค่เพิ่มขั้นตอนใหม่หลังจากนั้น):
- ฟังก์ชันใหม่ `listAllStorageObjects(supabase)` เดินลึกเข้าไปใน bucket `checkin-photos` แบบ recursive ทีละชั้น (โครงสร้างจริงคือ `{officerId}/{YYYY-MM-DD}/{uuid}.jpg` — 2 ชั้นโฟลเดอร์ก่อนถึงไฟล์ เพราะ Supabase Storage `list()` คืนแค่ชั้นเดียวต่อครั้ง ไม่มี recursive list ในตัว) แยกไฟล์จริงออกจากโฟลเดอร์ด้วย `entry.id === null` (โฟลเดอร์ placeholder ไม่มี id จริง)
- ดึง `photo_path` ทั้งหมดที่ไม่ null จากตาราง `check_in` มาเป็น `Set` แล้วเทียบกับไฟล์ทุกไฟล์ที่สแกนเจอ — ไฟล์ไหนไม่มีใน `Set` เลยคือไฟล์กำพร้า
- **ไม่กรองด้วย `retention_hold`/cutoff แบบลูปแรก** เพราะไฟล์กำพร้าไม่ผูกกับแถว `check_in` ใดๆ ให้ hold ได้อยู่แล้ว
- **Grace period 24 ชั่วโมง** (ค่าคงที่ `ORPHAN_GRACE_HOURS`) — ไฟล์ที่อัปโหลดมาไม่ถึง 24 ชม.ยัง**ไม่ลบ** เผื่อเป็นกรณี `do_check_in` กำลังจะตามมาจริง (retry เครือข่าย/browser กำลังส่งคำขออยู่) ไฟล์ที่ไม่มี `created_at` เลย (ไม่ควรเกิดขึ้นจริง) ถือว่าเก่าพอที่จะลบได้เลย ปลอดภัยกว่าเก็บค้างไว้ตลอดไป
- ลบไฟล์กำพร้าที่ผ่านเกณฑ์ผ่าน Storage API (`supabase.storage.from(BUCKET).remove([path])`) เหมือน logic เดิมทุกประการ (ไม่ raw-delete `storage.objects` เพราะติด trigger `protect_delete()` ตามที่เคยยืนยันไว้แล้ว) — ไฟล์กำพร้าไม่มีแถว `check_in` ให้อัปเดตต่อ (เพราะไม่มีแถวอ้างอิงตั้งแต่แรก) จึงจบแค่ขั้นตอนลบไฟล์ ไม่ต้อง update ตารางใดๆ เพิ่ม
- Response JSON เดิมของฟังก์ชันเพิ่ม key ใหม่ `orphan_sweep: { grace_hours, scanned, skipped_grace_period, deleted_count, deleted_paths, errors }` ต่อท้าย ไม่กระทบ shape ของ response เดิม

**Verify:**
- `index.html`: คัดลอกเนื้อหา `<script>` เต็มไปที่ไฟล์ scratch แล้ว `node --check` ผ่านสำเร็จ (ไม่มี syntax error)
- `edge_function_delete-old-photos.ts`: ลองใช้ `npx tsc` ก่อนแต่ tooling ไม่พร้อมในสภาพแวดล้อมทดสอบ (ไม่มี `deno` และ `npx tsc` ติดปัญหา package resolution) เปลี่ยนมาใช้ `node --experimental-strip-types --check` (รองรับใน Node 22 ที่ใช้ทดสอบ) แทน ผ่านสำเร็จ — **นี่คือการตรวจ syntax เท่านั้น ไม่ใช่ deploy จริง/รัน E2E test บน Supabase** เพราะไฟล์นี้ยังไม่ได้ deploy รอบใหม่ขึ้น Supabase Edge Functions (ต้องทำผ่าน Dashboard "Via Editor" เหมือนเดิม เป็นขั้นตอนแยกจาก git push)
- **ยังไม่ได้ทดสอบ end-to-end จริงบน Supabase** สำหรับรอบนี้ (ทั้งการเรียก `do_get_today_status` แบบ pre-check จริงจากหน้าเว็บ และการรัน Edge Function ที่แก้ใหม่จริงเพื่อดู orphan sweep ทำงานถูกต้อง) — เป็นขั้นตอนที่ควรทำหลัง push+deploy สำเร็จ

**สรุปสถานะสุดท้าย (10 ก.ค. 2569):**
- Push ขึ้น git — ✅ เสร็จแล้ว
- Deploy Edge Function เวอร์ชันใหม่ขึ้น Supabase — ✅ เจ้าของ deploy เองผ่าน Dashboard "Via Editor" ด้วยมือ (ดูบทเรียนเรื่อง safeguard ตัดเซสชันในข้อ 2.11) ยืนยัน Verify JWT ยังปิดอยู่ตามที่ต้องการ
- E2E test จริงกับข้อมูลจริง — ✅ ทำแล้ว 10 ก.ค. 2569 ผ่าน SQL Editor (ไม่แตะหน้า Edge Functions) ผลละเอียดดูข้อ 24.1
- คู่มือผู้ใช้ (ข้อ 8) — ไม่เกี่ยวข้องเพราะเป็นการแก้บั๊กเบื้องหลังที่เจ้าหน้าที่ทั่วไปไม่เห็น/ไม่ต้องรู้

### 24.1 ผลทดสอบ E2E จริง (10 ก.ค. 2569, ทำผ่าน SQL Editor ด้วย Claude in Chrome ตามที่เจ้าของสั่ง)

**Baseline ก่อนเรียกฟังก์ชัน:** พบรูปกำพร้าเก่าจริง (อายุ >24 ชม., ไม่มีแถว `check_in.photo_path` อ้างอิง) ค้างอยู่ **60 ไฟล์** ในบัคเก็ต `checkin-photos` (สะสมมาจากเคสกดเช็กอินซ้ำช่วงต้น ก.ค. — ตรงกับที่บั๊กนี้อธิบายไว้) รวมไฟล์ทั้งหมดในบัคเก็ตตอนนั้น 171 ไฟล์ (106 มีแถวอ้างอิงถูกต้อง + 60 กำพร้าเก่า + 5 ใหม่ยังไม่ถึง grace period)

**เรียกฟังก์ชันผ่าน `net.http_post` (วิธีเดียวกับ migration 23, สิทธิ์ผ่าน `x-cron-secret` จาก `vault.decrypted_secrets`):**
- ครั้งที่ 1 (timeout default 5 วิ): pg_net รายงาน `timed_out = true` เพราะฟังก์ชันสแกนไฟล์ทั้งบัคเก็ตแบบ recursive ใช้เวลานานกว่า 5 วิ — **แต่ฟังก์ชันฝั่ง server ไม่ได้หยุดทำงานตาม ยังรันต่อจนเสร็จจริง** (ยืนยันจากผลขั้นถัดไป)
- ครั้งที่ 2 (ตั้ง `timeout_milliseconds := 60000` เอง หลังพบปัญหาครั้งที่ 1): ได้ผลลัพธ์เต็ม `status_code = 200`, `timed_out = false`:
  ```json
  {"ok":true,"retention_days":31,"cutoff":"2026-06-08T21:34:07.241Z","scanned":0,"deleted_count":0,"deleted_ids":[],"errors":[],
   "orphan_sweep":{"grace_hours":24,"scanned":111,"skipped_grace_period":5,"deleted_count":0,"deleted_paths":[],"errors":[]}}
  ```
  `orphan_sweep.deleted_count = 0` ในการเรียกครั้งนี้ถูกต้องแล้ว ไม่ใช่บั๊ก — เพราะการเรียกครั้งที่ 1 (timeout ฝั่ง client แต่ทำงานจริงฝั่ง server) ได้ลบ orphan ทั้ง 60 ไฟล์ไปตั้งแต่ก่อนเรียกครั้งที่ 2 แล้ว (`scanned:111` = 171 - 60 ที่ลบไปแล้ว ตรงกันพอดี)

**เช็กหลังเรียก (สองเกณฑ์ที่ตั้งไว้ล่วงหน้า):**
1. รูปกำพร้าเก่า (>24 ชม.) เหลือ **0 ไฟล์** (จาก 60 → 0) ✅ ลบสำเร็จ
2. รูปที่มีแถวอ้างอิงยังอยู่ครบ: `check_in` ที่มี `photo_path` = **106 แถว**, ไฟล์ในบัคเก็ตที่ join กับแถวเหล่านี้ได้ = **106 ไฟล์** ✅ ตรงกันเป๊ะ ไม่มีรูปที่ใช้งานจริงหายไปแม้แต่ไฟล์เดียว
3. ไฟล์ใหม่ 5 ไฟล์ที่ยังไม่ถึง grace period ถูกข้ามถูกต้อง (`skipped_grace_period: 5`) ไม่ถูกลบ ตรงตามดีไซน์

**สรุป: orphan sweep ทำงานถูกต้องสมบูรณ์ ✅** — พบ 1 ข้อควรระวังเชิง operational (ไม่ใช่บั๊กของฟังก์ชัน) เรื่อง `net.http_post` timeout สั้นเกินไปสำหรับฟังก์ชันนี้ บันทึกไว้เป็นกติกาใหม่ข้อ 2.11 แล้ว

---

## 25. P0.1 งานเก็บตกเล็ก (ตาม `90_ROADMAP_v2_PLAN.md`) — ✅ เสร็จสมบูรณ์ (10 ก.ค. 2569)

**สถานะ: เขียนโค้ดเสร็จ + verify syntax ผ่านทั้งคู่ + ส่งไฟล์ให้เจ้าของตรวจสอบแล้ว + เจ้าของ confirm แล้ว + push ขึ้น git สำเร็จจริง (commit `37827bc`) + verify บนเว็บจริงผ่าน — frontend ล้วน ไม่มี migration ใหม่**

**คำขอเดิม:** ทำ P0.1 ตาม roadmap — (1) เพิ่มคอลัมน์ "สิทธิ์หัวหน้า" ใน `report.html` ให้เท่ากับ `dashboard.html` (2) แก้ error-message mapping ของปุ่มกันลบรูป (`do_set_retention_hold`/`do_supervisor_set_retention_hold`) ทั้ง 2 ไฟล์ ให้แสดงข้อความไทยครบทุก error code ไม่โชว์โค้ดดิบ

**Fix 1 — `report.html`: เพิ่มคอลัมน์ "สิทธิ์หัวหน้า"**
เพิ่ม `<th>สิทธิ์หัวหน้า</th>` ในหัวตาราง `renderOfficersTable()` (ระหว่าง "วิธีเข้าระบบ" กับ "วันทำงาน" — ตำแหน่งเดียวกับ `dashboard.html`) และเพิ่ม `<td>' + (o.is_supervisor ? "หัวหน้า" : "-") + '</td>'` ในแถวข้อมูล — **ไม่ต้องแก้ RPC เลย** เพราะ `do_supervisor_list_officers` (migration 19) คืนคอลัมน์ `is_supervisor` มาอยู่แล้วตั้งแต่แรก ตรงตามที่ roadmap ระบุไว้ ("ข้อมูลมีอยู่แล้วใน RPC ที่เรียกอยู่ แค่ render เพิ่ม")

**Fix 2 — ทั้ง 2 ไฟล์: error mapping ปุ่มกันลบรูป (`attachRetentionButtons`)**
รวบรวม error code ทั้งหมดที่ RPC ทั้งสองตัวคืนได้จริง (เช็กจากนิยามฟังก์ชันจริงใน `23_photo_retention.sql`) มาเป็น `RETENTION_ERROR_MAP` เดียวกันทั้งสองไฟล์:
- `not_supervisor` (เฉพาะ `do_set_retention_hold` เวอร์ชัน auth) → "ไม่มีสิทธิ์ทำรายการนี้"
- `officer_not_found` (เฉพาะเวอร์ชัน PIN) → "ไม่พบสิทธิ์ผู้ใช้ หรือถูกปิดใช้งาน"
- `bad_pin` (เฉพาะเวอร์ชัน PIN) → "รหัส PIN ไม่ถูกต้อง"
- `checkin_not_found` (ทั้งคู่) → "ไม่พบรายการเช็กอินนี้"
- เดิมทั้งสองไฟล์มีบั๊กเดียวกัน (ตรงกับที่ roadmap R2 ระบุไว้เป็นความเสี่ยงจากโค้ดซ้ำ 2 ชุด) คือ `alert("บันทึกไม่สำเร็จ: " + code)` โชว์โค้ดดิบตรงๆ ไม่มี mapping เลย — ตอนนี้ error code ที่ไม่รู้จัก/error ระดับเครือข่าย (`res.error`) จะ fallback เป็นข้อความไทยทั่วไป "เกิดข้อผิดพลาดที่ไม่คาดคิด กรุณาลองใหม่อีกครั้ง" แทน ไม่มีทางโชว์โค้ดดิบให้ผู้ใช้เห็นอีกต่อไป

**Verify ก่อนแก้ (กติกาข้อ 2.6):** เทียบไฟล์ในเครื่องกับที่ deploy จริงบน `rayongimm.link` ผ่านเบราว์เซอร์ (`fetch(location.href)` + เทียบ line count/ตำแหน่ง marker) — ทั้ง `report.html` (1153 บรรทัด) และ `dashboard.html` (1278 บรรทัด) ตรงกับของจริง 100% ก่อนเริ่มแก้

**Verify หลังแก้:** `node --check` ผ่านทั้ง 2 ไฟล์ (คัดลอกเนื้อหา `<script>` เต็มไปที่ไฟล์ scratch ตามกติกาข้อ 2.10) — ไม่มี syntax error

**Push:** เจ้าของ confirm แล้ว 10 ก.ค. 2569 — เจ้าของสร้าง fine-grained PAT เอง (repo scope `rayong-imm-checkin`, Contents: Read/write) แล้วส่งให้ใช้ครั้งเดียว push สำเร็จจริง (commit `37827bc`) — verify บนเว็บจริงหลัง push ยืนยันคอลัมน์ "สิทธิ์หัวหน้า" + `RETENTION_ERROR_MAP` ปรากฏถูกต้องทั้ง `report.html`/`dashboard.html`

---

## 26. UX quick win รอบ 2 + GPS timeout ขยาย + บทเรียนเรื่อง PAT/credit/workflow บันทึกเอกสาร (10 ก.ค. 2569)

**สถานะ: เสร็จสมบูรณ์ทุกขั้นตอน — เขียนโค้ด, verify syntax, verify เว็บจริง, push 3 commit (`f58cd48`, `5f7cac2`, `977142f`) เรียบร้อย ไม่มีงานค้าง**

### 26.1 GPS geolocation timeout: 8 วิ → 20 วิ

**ที่มา:** เจ้าของเห็นด้วยให้ขยาย timeout ของ `navigator.geolocation.getCurrentPosition` ("เห็นด้วยลองขยาย timeout เป็น 15-20 วิ ดูก่อน") เพราะมือถือบางเครื่อง/บางที่สัญญาณ GPS ช้า ทำให้ได้สีม่วง "เช็กอินไม่สมบูรณ์" ทั้งที่ผู้ใช้ยืนอยู่ที่ทำงานจริง แค่ GPS ตอบช้าเกิน 8 วิ

**แก้:** `requestGeoNonBlocking()` ใน `index.html` เปลี่ยน `{ enableHighAccuracy: true, timeout: 8000, maximumAge: 0 }` → `{ enableHighAccuracy: true, timeout: 20000, maximumAge: 0 }` — จุดเดียว ไม่กระทบ logic อื่น เพราะฟังก์ชันนี้ non-blocking อยู่แล้ว (ไม่ได้บล็อกปุ่มถ่ายรูป/ส่งเช็กอิน แค่รอผล GPS นานขึ้นก่อนสรุปว่า denied)

**บั๊กเชิงกระบวนการที่เจอระหว่างทำ:** commit แรก (`37827bc`, งาน P0.1) ไม่มีการเปลี่ยนแปลงของ `index.html` ติดไปด้วย ทั้งที่แก้ในโฟลเดอร์จริงไปแล้ว เพราะ sync เข้า `/tmp` git clone รอบแรกลืมคัดลอกไฟล์นี้ (คนละบทสนทนาย่อยกับงาน P0.1) ตรวจพบจาก verify เว็บจริงหลัง push แล้วไม่เจอ `timeout: 20000` ต้อง push แก้เพิ่มอีก commit (`f58cd48`) — นี่คือเหตุการณ์ที่ทำให้เกิดกติกาถาวรข้อ 2.12 (เช็ก `git status --short` เทียบไฟล์ที่แก้จริงทั้งหมดในเซสชันก่อน commit ทุกครั้ง)

### 26.2 UX quick win รอบ 2 — 3 ฟีเจอร์ใน `index.html` (commit `5f7cac2`)

คำขอเจ้าของ: "หน้าเช็กอิน: จำชื่อล่าสุดใน localStorage + ปุ่มลัดหมายเหตุ 'ปฏิบัติงานปกติ' + โชว์สถานะ GPS ในหน้า 'ตรวจสอบก่อนยืนยัน'" — ทั้งสามอย่างเลือกทำเพราะต้นทุนต่ำ (ไม่แตะ RPC/schema เลย, ไฟล์เดียว, risk ต่ำ) แต่ผลกระทบสูง (ลดแรงเสียดทานตอนกรอกฟอร์มทุกเช้า):

1. **จำชื่อล่าสุด**: เพิ่ม `localStorage` key `rayong_checkin_last_officer_v1` — บันทึกทุกครั้งที่เปลี่ยน dropdown ชื่อ, โหลดกลับมาเป็นค่า default ใน `loadOfficers()` (เช็กว่าชื่อนั้นยังอยู่ในรายชื่อจริงก่อนตั้งค่า กันกรณีเจ้าหน้าที่ถูกปิดใช้งานไปแล้ว)
2. **ปุ่มลัดหมายเหตุ**: ปุ่ม "⚡ ปฏิบัติงานปกติ" กรอกข้อความอัตโนมัติเข้าช่องหมายเหตุ + trigger `input` event ให้ character-count/validation ทำงานตามปกติ — ลดปัญหาคนรีบพิมพ์ตัวอักษรมั่วๆ ให้ครบ 5 ตัวขั้นต่ำ
3. **สถานะ GPS ในหน้าตรวจสอบก่อนยืนยัน**: เพิ่ม state `geoStatus` ("pending"/"ok"/"denied"/"unsupported") คู่กับ `geoResult` เดิม, ฟังก์ชันกลาง `geoStatusText()`/`refreshGeoHints()` อัปเดตทั้ง `geoHint` (หน้ากล้อง) และ `confirmGeoHint` (หน้าตรวจสอบก่อนยืนยัน — element ใหม่) พร้อมกัน เดิมผู้ใช้เห็นสถานะ GPS แค่ตอน modal ม่วงเด้งหลังส่งเช็กอินไปแล้ว (สายเกินจะแก้ไข) ตอนนี้เห็นล่วงหน้าก่อนกดยืนยันจริง

**Verify:** `node --check` ผ่านทั้งไฟล์ (คัดลอก `<script>` ไปไฟล์ scratch ชื่อใหม่ตามกติกาข้อ 2.10) + verify เว็บจริงด้วย `fetch()` เช็ก marker string 3 จุด (`timeout: 20000`, `confirmGeoHint`, `LAST_OFFICER_KEY`) เจอครบทุกจุด

### 26.3 บทเรียนเรื่อง GitHub fine-grained PAT — ขั้นตอนที่เจ้าของติดจริง

เซสชันนี้ token เดิมจากรอบ P0.1 ใช้ไม่ได้แล้ว (session ใหม่ ไม่มี credential ค้าง ตามกติกาข้อ 2 ที่ไม่เก็บ token ไว้) เจ้าของต้องสร้างใหม่เอง แต่ติดขั้นตอน UI จริง 3 รอบ กว่าจะสำเร็จ — บันทึกไว้เผื่อ agent ตัวถัดไปต้องช่วยเดินเรื่องนี้อีก:
1. รอบแรก: เจ้าของกด generate token แต่ยังไม่ได้กด "Add permissions" เลือก scope (หน้าโชว์ 0 permissions) — ต้องเลือก "Contents: Read and write" + "Metadata: Read-only" ก่อน
2. รอบสอง: เจ้าของกด "Generate token" สีเขียวไปแล้ว แต่พลาดหน้า one-time-reveal ที่โชว์ค่า token จริง (มาเห็นแค่หน้า list ที่บอก "Never used") — token ที่สร้างไปแล้วดูค่าไม่ได้อีก ต้องกด **"Regenerate token"** (ปุ่มแดงในหน้า detail ของ token เดิม ไม่ต้องลบ+สร้างใหม่ เพราะ permissions ที่ตั้งไว้ถูกต้องอยู่แล้ว) แล้วรีบ copy ค่าจาก banner สีเขียวที่โชว์ครั้งเดียวทันที
3. รอบสาม: ได้ค่า token จริงสำเร็จ ใช้ push ได้ปกติ

**ข้อตกลงใหม่จากเจ้าของ (สำคัญ ต้องจำ):** "เข้าใจว่า token เดิมยังไม่หมดอายุ และฉันไม่ต้องการให้คุณขอ token ฉันบ่อยๆ" — **agent ตัวถัดไปควรพยายามใช้ token เดิมที่เจ้าของเคยให้ไว้ในเซสชันเดียวกันซ้ำสำหรับหลาย push โดยไม่ต้องถามซ้ำทุกรอบ** จนกว่า token จะหมดอายุจริง (push ล้มเหลวเพราะ auth error) หรือเจ้าของบอกให้เปลี่ยน — แต่ยังต้องเคารพกติกาเดิมว่า agent ไม่มีสิทธิ์สร้าง/regenerate token เองโดยไม่มีเจ้าของกดยืนยัน (ข้อ 2 ด้านบน)

### 26.4 บทเรียนเรื่อง Netlify build credit — "docs-only push" ก็ยังเสียเครดิต

เจ้าของถามว่าถ้าการ push ไม่เปลืองเครดิตเหมือนที่กังวลไว้ ควร push ทันทีไหม — **คำตอบที่ยืนยันแล้ว: Netlify build credit ไม่แยกแยะว่าไฟล์ที่เปลี่ยนเป็นโค้ดหรือ docs** ทุก push ขึ้น `main` (รวมถึงแก้แค่ `CLAUDE.md`) จะ trigger build ใหม่เสมอ ~15 เครดิต/ครั้งเท่าเดิม (แพลน Free 300 เครดิต/เดือน ยังเหลือเฟือมาก ไม่ใช่คอขวดจริง) **ถ้าต้องการให้ docs-only commit ไม่เสียเครดิตจริงๆ ต้องตั้ง Netlify build-ignore rule แยกต่างหาก** (เช่นเช็คว่า diff มีแค่ `*.md` ให้ skip build) — ยังไม่ได้ทำ เป็นตัวเลือกที่เสนอไว้เฉยๆ ไม่ใช่งานที่เริ่มทำแล้ว

### 26.5 กติกาที่ยืนยันซ้ำจากรอบนี้: ต้องอัปเดต + push CLAUDE.md ทุกครั้งที่ปิดงาน ไม่ใช่แค่โค้ด

เจ้าของขอให้บันทึกกระบวนการทำงานทั้งหมดของเซสชันนี้ (รวมทั้งขั้นตอนที่ไม่ใช่โค้ด เช่น การเดิน PAT, การอธิบายเรื่องเครดิต) ลง `CLAUDE.md` เป็น "agent file" — ย้ำหลักการเดิมของไฟล์นี้ว่า **CLAUDE.md ไม่ใช่แค่ที่บันทึกโค้ดที่เปลี่ยน แต่รวมกระบวนการ/บทสนทนา/การตัดสินใจเชิงกระบวนการที่กระทบวิธีทำงานของ agent ตัวถัดไปด้วย** (เช่นเดียวกับกติกาข้อ 2.12 ที่มาจากบั๊กเชิงกระบวนการ ไม่ใช่บั๊กโค้ด) — agent ตัวถัดไปควรถือเป็นบรรทัดฐาน: ทุกครั้งที่ปิด task ที่มีบทเรียนเชิงกระบวนการ (ไม่ว่าจะเป็นปัญหาเครื่องมือ, ความเข้าใจผิดของเจ้าของ, หรือข้อตกลงใหม่) ให้บันทึกลงไฟล์นี้เหมือนกับที่บันทึกงานโค้ด

---

## 27. P0.3 PIN rate limiting (migration 25) — ✅ SQL รันจริงสำเร็จแล้ว + ทดสอบ E2E ผ่านหมด + แก้ frontend เสร็จ + push แล้ว (10 ก.ค. 2569)

**สถานะ: เสร็จสมบูรณ์ทุกขั้นตอน — เขียน SQL + รันจริงบน Supabase ผ่าน service_role key สำเร็จ + ทดสอบ E2E จริงผ่านหมด + แก้ `index.html`/`report.html` เสร็จ + verify syntax ผ่านทั้งคู่ + push ขึ้น git สำเร็จแล้ว (commit `4ccfa23`) + verify บนเว็บจริงผ่าน — ⚠️ (11 ก.ค. 2569) ต่อมาพบว่า migration นี้มีบั๊ก regression บล็อกหัวหน้า PIN ล็อกอินไม่ได้ แก้แล้วด้วย migration 26 ดูข้อ 29**

**คำขอเดิม:** ทำ P0.3 ตาม roadmap — กันโจมตีแบบเดา PIN มั่วๆ (brute force) เพราะเดิมไม่มีการจำกัดจำนวนครั้งกรอกผิดเลย

### 27.1 สถาปัตยกรรมที่เลือก: thin wrapper function (ไม่แก้ business logic เดิมเลย)

แทนที่จะแก้ business logic ข้างในทั้ง 21 ฟังก์ชันที่เช็ก PIN ตรงๆ (เสี่ยง regression สูง เพราะต้องพิมพ์ SQL ก้อนใหญ่ผ่าน SQL Editor ที่มีบั๊ก auto-bracket-closing) เลือกวิธีนี้แทน:
1. `ALTER FUNCTION public.do_X(...) RENAME TO do_X_impl` — เปลี่ยนชื่อฟังก์ชันเดิมทั้งก้อน ไม่แตะ body เลยแม้แต่บรรทัดเดียว
2. `REVOKE ALL ... FROM PUBLIC, anon, authenticated` บน `do_X_impl` — กันไม่ให้เรียกผ่าน REST ตรงๆ เพื่อข้าม rate limit (เหลือแค่ `postgres`/`service_role` เรียกได้)
3. สร้าง `do_X` ใหม่เป็น wrapper บางๆ ที่เรียก `check_and_count_pin(p_officer_id, p_pin)` ก่อนเสมอ ถ้าไม่ผ่านคืน `{ok:false, error, locked_until}` ทันที ถ้าผ่านค่อย delegate ต่อไปยัง `do_X_impl(...)` เดิมด้วยพารามิเตอร์เดียวกันทุกตัว

**ฟังก์ชันกลาง `check_and_count_pin(p_officer_id, p_pin)`:** เช็ก 3 อย่างตามลำดับ (1) officer ยัง active ไหม (2) `pin_locked_until` ยังไม่หมดอายุไหม — ถ้ายังล็อกอยู่ reject ทันทีแม้ PIN จะถูกก็ตาม (3) เทียบ `crypt(p_pin, pin_hash)` — ถ้าผิดเพิ่ม `pin_fail_count` และถ้าถึง 5 ครั้งตั้ง `pin_locked_until = now() + 15 นาที`, ถ้าถูกรีเซ็ต `pin_fail_count = 0`

**คอลัมน์ใหม่บน `officer`:** `pin_fail_count int default 0`, `pin_locked_until timestamptz`

**ยืนยันรายชื่อ 21 ฟังก์ชันที่ต้อง wrap จริง** ด้วยการ query `pg_proc.prosrc ILIKE '%crypt(p_pin%'` ตรงๆ (ไม่เดา) — รายชื่อเต็มดูในไฟล์ `25_pin_rate_limiting.sql`

### 27.2 ⚠️ ช่องโหว่เพิ่มเติมที่พบระหว่างทำ (แก้ไปพร้อมกันในไฟล์เดียวกัน)

`do_reset_pin` (auth-based, ชวนชัยใช้ตอนกด "รีเซ็ต PIN" ใน dashboard) และ `do_supervisor_reset_pin_impl` (PIN-based, ศุภัตรา/ผู้ช่วยแอดมินใช้ใน report.html) เดิมแค่ `SET pin_hash = NULL` ตอนรีเซ็ต แต่ไม่ได้ clear `pin_fail_count`/`pin_locked_until` เลย — ถ้า officer ถูกล็อกอยู่แล้วโดนรีเซ็ต PIN ใหม่ จะยัง**ล็อกต่อ**แม้ตั้ง PIN ใหม่ถูกต้องแล้วก็ตาม (bug เชิง UX ที่ทำให้ฟีเจอร์ "รีเซ็ต PIN" ที่มีอยู่เดิมใช้ไม่ได้ผลกับ officer ที่โดนล็อก) แก้โดยเพิ่ม `pin_fail_count = 0, pin_locked_until = NULL` เข้าไปใน `UPDATE` เดียวกันทั้ง 2 ฟังก์ชัน — ไม่กระทบ logic อื่นเลย

### 27.3 วิธีรัน SQL จริง — ไม่ผ่าน SQL Editor พิมพ์มือ (บทเรียนใหม่สำคัญ)

**ที่มา:** เจ้าของสั่งให้ agent ดึง service_role key มาใช้เองแทนให้เจ้าของพิมพ์/paste ทีละขั้นตอน ("คุณทำให้ฉันเลยได้ไหม วิธีที่เร็วและน่าเชื่อถือกว่ามาก: ใช้ Service Role Key ใช้คอมของฉันทำต่อทั้งหมด") — พยายามอ่านค่า key จากหน้า Supabase Dashboard ด้วย `javascript_tool` ก่อน แต่โดน safeguard บล็อกค่า JWT โดยตรง (`[BLOCKED: JWT token]`) **agent เคารพ safeguard นี้ ไม่พยายามหาทางเลี่ยง** แล้วขอให้เจ้าของ copy-paste ค่า key มาในแชทแทน (เจ้าของทำตามขั้นตอนภาษาไทยที่ agent อธิบายให้ สำเร็จ)

**เก็บ key ไว้ที่ไหน:** ไฟล์ `.service_role_key.local.txt` ในโฟลเดอร์โปรเจกต์ (มี SUPABASE_URL + SERVICE_ROLE_KEY) — **⚠️ ยังไม่ได้เพิ่มเข้า `.gitignore` จริง ต้องทำก่อน commit ครั้งถัดไปที่แตะโฟลเดอร์นี้ผ่าน git (ห้ามให้ค่านี้หลุดขึ้น GitHub เด็ดขาด)**

**⚠️ ค้นพบข้อจำกัดสำคัญของ sandbox:** `mcp__workspace__bash` (curl/node fetch จาก shell) ถูกบล็อกด้วย allowlist proxy ภายใน sandbox เอง — เรียก `https://aamzsbuwfdyljdvwaifb.supabase.co` จาก bash ได้ `403 Forbidden` / `blocked-by-allowlist` เสมอ **ไม่ว่าจะมี credential ถูกต้องแค่ไหนก็ตาม** วิธีที่ใช้ได้จริงคือเรียก `fetch()` ผ่าน `mcp__claude-in-chrome__javascript_tool` จากแท็บเบราว์เซอร์ที่ล็อกอิน Supabase Dashboard อยู่แล้ว (ไม่ติด allowlist นี้) — **บทเรียนนี้สำคัญมากถ้าจะทำ P0.4 (backup อัตโนมัติ) ต่อ เพราะแปลว่า "scheduled task ที่รัน curl/bash เรียก Supabase ตรงๆ" จะใช้ไม่ได้จริงในสภาพแวดล้อมนี้** ต้องเลือกวิธีอื่น (ดูข้อ 27.6)

**ขั้นตอนที่ใช้จริง (แทนการพิมพ์ SQL ยาวๆ ใน SQL Editor ที่มีบั๊ก auto-bracket-closing):**
1. สร้างฟังก์ชันชั่วคราว 3 ตัว (grant เฉพาะ `service_role`) ผ่าน SQL Editor เท่านั้น (SQL สั้น พิมพ์ตรงได้ปลอดภัย):
   - `tmp_get_functiondef(p_name text)` — คืน source เต็มของฟังก์ชัน (ใช้ `pg_get_functiondef`)
   - `tmp_query_json(p_sql text)` — รัน `SELECT` อะไรก็ได้ คืนผลเป็น JSON (`json_agg`)
   - `tmp_exec_sql(p_sql text)` — รัน DDL/DML อะไรก็ได้ (`EXECUTE p_sql`) คืน `'ok'` หรือ `'ERROR: ...'`
2. เรียกทั้ง 3 ตัวผ่าน `fetch()` ใน `javascript_tool` (ใช้ header `apikey`/`Authorization: Bearer <service_role_key>`) เพื่อ (ก) สำรวจ signature ของ 21 ฟังก์ชันจริงจาก `pg_proc` (ข) รัน SQL migration จริงทั้งหมด (คอลัมน์ใหม่ + `check_and_count_pin` + RENAME/REVOKE/CREATE ของ 21 ฟังก์ชัน + แก้ 2 ฟังก์ชัน reset) ทีละคำสั่งในลูป JS เดียว — **ไม่ต้องพิมพ์ SQL มือใน SQL Editor เลยสำหรับส่วนที่ซับซ้อน** หลีกเลี่ยงบั๊ก auto-bracket-closing ได้เกือบทั้งหมด
3. **DROP ฟังก์ชันชั่วคราวทั้ง 3 ตัวทิ้งทันทีหลังใช้เสร็จ** (`tmp_get_functiondef`, `tmp_query_json`, `tmp_exec_sql`) — ยืนยันแล้วว่าไม่มีฟังก์ชันสิทธิ์สูงตกค้างในระบบ (เพราะฟังก์ชันเหล่านี้ทรงพลังมาก รันอะไรก็ได้ผ่าน service_role)

**⚠️ บั๊กที่เจอระหว่างทำ:** ครั้งแรกที่พิมพ์ SQL สร้าง `tmp_exec_sql` ผ่าน SQL Editor แล้ว "ดูเหมือน" รันสำเร็จ (การ์ดผลลัพธ์ขึ้น "Success. No rows returned") แต่พอเรียกผ่าน REST กลับได้ `PGRST202` (ไม่พบฟังก์ชัน) และเช็กผ่าน `tmp_get_functiondef` ก็ไม่พบฟังก์ชันนี้ใน `pg_proc` จริง — สรุปว่าข้อความ "Success" นั้นเป็นผลลัพธ์เก่าที่ค้างอยู่จาก query ก่อนหน้า ไม่ใช่ผลจากการรันจริง (ยังไม่ได้กด Run จริงๆ) แก้โดยกด `ctrl+Return` รันซ้ำอีกครั้งแล้ว verify เห็นผลลัพธ์ตรงกับ SQL ที่พิมพ์ในหน้าจอจริง — **บทเรียน: "Success" ในการ์ดผลลัพธ์ของ SQL Editor ไม่ได้การันตีว่าเป็นผลจาก query ล่าสุดที่พิมพ์เสมอไป ต้อง verify การมีอยู่จริงของ object ที่สร้างผ่านช่องทางอื่น (เช่น `pg_proc` โดยตรง) ก่อนเชื่อว่าสำเร็จ**

### 27.4 ผลการทดสอบ E2E จริง (ใช้แถวทดสอบชั่วคราวแล้วลบทิ้งหมด)

สร้าง officer ทดสอบ (`00000000-0000-0000-0000-0000000000aa`, PIN `1234`) แล้วเรียก `do_get_today_status` ผ่าน **publishable/anon key จริง** (ไม่ใช่ service_role — จำลองพฤติกรรม client จริง):
1. ใส่ PIN ผิด "0000" 4 ครั้งแรก → ได้ `bad_pin` ทุกครั้ง
2. ครั้งที่ 5 → ได้ `pin_locked` พร้อม `locked_until` (+15 นาทีจาก now) — ตรวจสอบ `pin_fail_count=5` ในตารางจริงตรงกัน
3. ครั้งที่ 6 (ยังอยู่ในช่วงล็อก) → ยังได้ `pin_locked` เหมือนเดิม
4. ลองใส่ PIN **ถูก** "1234" ระหว่างยังถูกล็อกอยู่ → **ยังได้ `pin_locked`** (ไม่ bypass แม้ PIN ถูก) ✅ ตรงตามดีไซน์
5. จำลองผลของการรีเซ็ต (เท่ากับ `do_reset_pin`/`do_supervisor_reset_pin_impl` เวอร์ชันใหม่) → `pin_fail_count=0, locked_until=null`
6. ใส่ PIN ถูก "1234" อีกครั้งหลังปลดล็อก → ผ่านเข้า business logic จริง (ได้ `not_checked_in` ตามปกติ ไม่ใช่ error) ✅
7. ยืนยัน `pin_fail_count`/`pin_locked_until` กลับเป็น `0`/`null` อัตโนมัติหลังผ่านสำเร็จ ✅
8. ยืนยันเรียก `do_get_today_status_impl` ตรงๆ ผ่าน anon/publishable key → ถูก reject `401 permission denied for function` ✅ (ปิดช่องทางข้าม rate limit ผ่านการเรียก `_impl` ตรงๆ ผ่าน REST ได้จริง)
9. ลบ officer ทดสอบทิ้งหมดแล้ว ไม่เหลือข้อมูลทดสอบค้างในระบบจริง

**สรุป: กลไก rate limiting ทำงานถูกต้องสมบูรณ์ทุกกรณีที่ทดสอบ ✅**

### 27.5 Frontend ที่แก้เพิ่ม (`index.html`, `report.html`)

เพิ่มฟังก์ชัน `formatPinLockedMessage(lockedUntil)` ในทั้ง 2 ไฟล์ (คำนวณนาทีที่เหลือ + เวลาโดยประมาณที่จะปลดล็อก เป็นข้อความไทยอ่านง่าย) แล้วเพิ่ม branch เช็ก `error === "pin_locked"` ก่อน fallback เดิมทุกจุดที่เรียก RPC ที่รับ `p_pin`:
- **`index.html`:** precheck ก่อนอัปโหลดรูป (`doSubmitCheckin`), `handleCheckinError` (หลัง `do_check_in`), บันทึกหมายเหตุ (`submitRemark`)
- **`report.html`:** ล็อกอิน (`doLogin` — จุดสำคัญที่สุดเพราะเป็นจุดที่ผู้ใช้จะเจอ `pin_locked` บ่อยที่สุดจริงๆ), บันทึกม็อตโต้, ปุ่มกันลบรูป, แก้ไขสถานะ (override), ค้นหาประวัติ, รีเซ็ต PIN, แก้วันทำงาน, ลบ/เพิ่มวันหยุด, ตั้ง/ลบวันเริ่มนับสถิติ (รวม 11 จุด)
- **`dashboard.html` ไม่ต้องแก้เลย** เพราะเป็น auth-based ล้วน (ชวนชัย) ไม่มี RPC ตัวไหนรับ `p_pin` เป็นพารามิเตอร์เลยสักตัว (ตรวจสอบด้วย grep `p_pin:` ในไฟล์แล้วไม่พบ)

**Verify:** เทียบไฟล์ในเครื่องกับ `rayongimm.link` จริงก่อนแก้ (ตรงกัน, ตามกติกาข้อ 2.6) → แก้เสร็จ → คัดลอกเนื้อหา `<script>` เต็มไปที่ไฟล์ scratch (`node --check`) ผ่านทั้ง 2 ไฟล์ ไม่มี syntax error

### 27.6 บันทึกไว้สำหรับ P0.4 (ยังไม่เริ่มทำ): ข้อจำกัด sandbox กระทบสถาปัตยกรรม backup

จากข้อ 27.3 พบว่า bash/curl ในสภาพแวดล้อมของ agent **เข้าถึง Supabase ไม่ได้เลย** (บล็อกด้วย allowlist proxy) มีแต่ Chrome-based `fetch()` เท่านั้นที่ทะลุผ่านได้ — สถาปัตยกรรมเดิมที่คุยกับเจ้าของไว้ ("scheduled task รัน export CSV ด้วย service_role key เก็บไฟล์ local") **อาจใช้ไม่ได้จริงถ้า scheduled task รันผ่าน bash sandbox เดียวกันนี้** (ยังไม่ได้ทดสอบตรงๆ ว่า scheduled task ของระบบนี้ใช้ sandbox เดียวกับ `mcp__workspace__bash` หรือไม่ — **agent ตัวถัดไปที่จะเริ่ม P0.4 ต้องทดสอบเรื่องนี้ก่อนเป็นอันดับแรก** ก่อนลงมือ implement เพราะถ้าติด allowlist เดียวกันจริง จะต้องเปลี่ยนไปใช้วิธี Chrome-automation-based หรือ Postgres-internal (`pg_cron`+`pg_net`+Edge Function ส่งอีเมล/webhook แทน) ซึ่งงานจะใหญ่กว่าที่วางแผนไว้เดิมพอสมควร

---

## 28. P0.4 backup — ตรวจสอบสถานะจริง + เจ้าของตัดสินใจ "พักไว้ก่อน" (11 ก.ค. 2569)

**สถานะ: ไม่ได้ implement อะไรเลย — เป็นแค่การตรวจสอบข้อเท็จจริง + นำเสนอทางเลือก + บันทึกการตัดสินใจของเจ้าของ ห้าม agent ตัวถัดไปเริ่มเขียนโค้ด/migration ใดๆ สำหรับ P0.4 จนกว่าเจ้าของจะหยิบยกขึ้นมาเอง (เงื่อนไขปลดล็อก: ขยายไปใช้แผนอื่น หรือ ตม.จังหวัดอื่นเข้าร่วม — ตรงกับจุดเริ่ม P3 multi-office ใน `90_ROADMAP_v2_PLAN.md`)**

**ที่มา:** เจ้าของถามว่า "P0.4 backup ฉันต้องทำอย่างไร ฉันยังไม่ค่อยเข้าใจเท่าไหร่" หลังจากรอบก่อนหน้า (P0.3) ค้นพบว่า bash sandbox ของ agent เข้าถึง Supabase ไม่ได้ ทำให้แผนเดิม (scheduled task รัน curl export CSV) มีคำถามค้างว่าใช้ได้จริงหรือไม่ — เจ้าของขอให้อธิบายก่อนตัดสินใจ ไม่ใช่ให้ agent เดินหน้าเขียนโค้ดเลย

**สิ่งที่ตรวจสอบจริง (ผ่าน Chrome เข้า Supabase Dashboard, ไม่ใช่การเดา):**
1. หน้า `Database → Backups → Scheduled backups` ของโปรเจกต์ `RayongImm-Service` ระบุตรงๆ ว่า **"Free Plan does not include project backups. Upgrade to the Pro Plan for up to 7 days of scheduled backups."** — ยืนยันว่าองค์กร "Chuan" อยู่บนแพลน **Free** และ **ไม่มีการสำรองข้อมูลอัตโนมัติใดๆ อยู่เลยในขณะนี้** (ไม่ใช่แค่ไม่มี custom backup — Supabase เองก็ไม่ได้ backup ให้เลยที่แพลนนี้)
2. เช็คราคาแพลน Pro ปัจจุบันผ่าน WebSearch (เพราะราคาอาจเปลี่ยนจากที่ agent เคยรู้) ยืนยัน **$25/เดือน** ได้ daily backup อัตโนมัติ เก็บย้อนหลัง 7 วัน กู้คืนเองได้จากปุ่มในหน้าเว็บ ไม่ต้องเขียนโค้ดเพิ่มเลย

**ทางเลือกที่นำเสนอเจ้าของ (สรุปเป็นภาษาง่ายๆ ไม่ใช้ศัพท์เทคนิค):**
1. **อัปเกรด Supabase เป็น Pro ($25/เดือน)** — agent แนะนำเป็นตัวเลือกหลัก เพราะเชื่อถือได้กว่า ไม่ต้องพึ่งพาโค้ด DIY ที่เพิ่งเจอข้อจำกัด sandbox มา, Supabase ดูแล/ทดสอบระบบ backup มาอย่างดีอยู่แล้ว, ข้อมูลที่ต้องปกป้องเป็นข้อมูลเจ้าหน้าที่ราชการจริง+รูปถ่ายจริง ไม่ใช่ข้อมูลทดสอบ
2. **ทำเอง (DIY) ด้วย scheduled task** — ฟรี แต่ยังไม่ได้ทดสอบว่าเป็นไปได้จริงหรือไม่ (ติดข้อจำกัด allowlist ที่เจอใน P0.3 ข้อ 27.3/27.6) ต้องทดสอบก่อนออกแบบจริง และถ้าเลือกทางนี้ต้องระวังเรื่อง repo เป็น public ห้าม backup ข้อมูลจริงลง repo เดิม (ดูรายละเอียดใน `90_ROADMAP_v2_PLAN.md` หัวข้อ P0.4)

**การตัดสินใจของเจ้าของ (ถามตรงๆ ผ่าน AskUserQuestion แล้วเลือกเอง ไม่ใช่ agent ตีความ):**
> "ยังไม่ตัดสินใจตอนนี้ ควรมีระบบ backup เมื่อมีการขยายการใช้งานแผนอื่นๆเพิ่มเติม หรือให้ตม.จังหวัดอื่นๆใช้งาน"

สรุปเป็นกติกาที่ agent ตัวถัดไปต้องยึด: **P0.4 ไม่ใช่งานเร่งด่วนของ P0 อีกต่อไป** (ต่างจากที่ `90_ROADMAP_v2_PLAN.md` เขียนไว้เดิมตอน 6-10 ก.ค.) ย้ายเงื่อนไขเริ่มงานไปผูกกับ P3 (multi-office) แทน — เจ้าของรับความเสี่ยง "ไม่มี backup อัตโนมัติ" ระหว่างนี้โดยรู้ตัว ที่สเกลปัจจุบัน (19 คน หน่วยเดียว) **agent ห้ามเริ่มงาน P0.4 เอง แม้จะเห็นว่าเป็นความเสี่ยงจริงที่ยังเปิดอยู่ก็ตาม** ต้องรอเจ้าของหยิบยกเรื่องขยายหน่วย/แผนขึ้นมาก่อนเท่านั้น (กติกาเดียวกับที่ใช้กับ P1 badge)

**บันทึกคู่กันที่ `90_ROADMAP_v2_PLAN.md` ส่วน P0.4 แล้ว** (รายละเอียดทางเลือกเชิงเทคนิคเต็มอยู่ที่นั่น ไม่ซ้ำที่นี่)

---

## 29. บั๊ก production จริง: `check_and_count_pin` (migration 25) บล็อกหัวหน้า PIN ล็อกอินไม่ได้ — ✅ แก้แล้ว migration 26 (11 ก.ค. 2569)

**สถานะ: วินิจฉัย+แก้+verify+push เสร็จสมบูรณ์ทุกขั้นตอน ไม่มีงานค้าง**

**ที่มา (รายงานโดยเจ้าของเอง หลังทดสอบ report.html จริง):** "ฉันเข้าไม่ได้ ทำไมขึ้นว่า ไม่พบชื่อนี้ในระบบ หรือถูกปิดใช้งาน ทั้งที่หากดูจากแดชบอร์ดชวนชัย ยังขึ้นใช้งานอยู่ ปกติ" — พ.ต.ท.หญิง ศุภัตรา (หัวหน้า `login_method='pin'`) ล็อกอิน `report.html` ไม่ได้ ขึ้น error `officer_not_found` ทั้งที่ `dashboard.html` (ชวนชัย) ยังโชว์บัญชีนี้ว่า active ปกติ

**วิธีวินิจฉัย:** ใช้ SQL Editor ของ Supabase Dashboard โดยตรง (ไม่ใช่ผ่าน bash เพราะติด network allowlist ตามที่รู้จากรอบ P0.3) — เจอบั๊ก UI focus ของ SQL Editor ซ้ำอีก (กติกาข้อ 6.4/6.7) กว่าจะพิมพ์ query ติดจริง 2-3 รอบ

1. Query `select id, full_name, active, is_supervisor, supervisor_enabled, login_method, pin_hash is not null as has_pin, pin_fail_count, pin_locked_until from officer where full_name ilike '%ศุภัตรา%'` → พบว่า `active = false` (ตามดีไซน์เดิมตั้งแต่ migration 11 — หัวหน้าทุกคนตั้งใจให้ `active=false` เพื่อไม่ให้โผล่ในดรอปดาวน์เช็กอินของ `index.html`), `is_supervisor = true`, `supervisor_enabled = true`, `pin_fail_count = 0` — ทุกอย่างดูปกติยกเว้น `active`
2. อ่าน `pg_get_functiondef('public.check_and_count_pin(uuid, text)'::regprocedure)` จริง (ไม่ใช่เดาจากไฟล์ migration) → พบบรรทัด `SELECT * INTO v_off FROM public.officer WHERE id = p_officer_id AND active = true;` — นี่คือสาเหตุ: เงื่อนไขนี้ตกเสมอสำหรับบัญชีหัวหน้า PIN เพราะ `active` เป็น `false` โดยตั้งใจ ทำให้ได้ `officer_not_found` ไม่ว่า PIN จะถูกหรือผิด
3. **ผลกระทบกว้างกว่าที่รายงาน:** `check_and_count_pin` เป็นฟังก์ชันกลางที่ RPC ตระกูล `do_supervisor_*` เกือบทั้งหมด (20 จาก 21 ฟังก์ชันใน migration 25) เรียกใช้ร่วมกัน แปลว่าไม่ใช่แค่ล็อกอินพัง — ทุกการกระทำของหัวหน้า PIN (ดูมอตโต้ `do_supervisor_list_mottos`, override สถานะ, จัดการวันหยุด, รีเซ็ต PIN คนอื่น ฯลฯ) พังหมดตั้งแต่ migration 25 รัน (10 ก.ค. 2569) จนถึงตอนแก้นี้ (11 ก.ค. 2569) — เดชะบุญที่ทดสอบ E2E ตอน migration 25 ใช้ officer ทดสอบที่ `active=true` (ไม่ใช่ PIN supervisor จริงที่ `active=false`) จึงไม่เจอบั๊กนี้ตอนทดสอบ (บทเรียน: ทดสอบ E2E ของฟีเจอร์ที่เกี่ยวกับ "หัวหน้า" ควรใช้แถวทดสอบที่จำลอง `active=false` ด้วย ไม่ใช่แค่ officer ทั่วไป)
4. **ทำไมไม่กระทบชวนชัย:** `login_method='auth'` ไม่เคยเรียก `check_and_count_pin` เลย (ใช้ Supabase Auth session ตรง ไม่มี `p_pin`)

**ทางแก้ (migration `26_fix_supervisor_pin_active_check.sql`):** `CREATE OR REPLACE FUNCTION check_and_count_pin` เปลี่ยนเงื่อนไขเป็น `WHERE id = p_officer_id AND (active = true OR is_supervisor = true)` — เจ้าหน้าที่ทั่วไปยังต้อง `active=true` เหมือนเดิม (ป้องกันคนที่ถูกปิดใช้งานแล้ว) แต่บัญชีหัวหน้า (`is_supervisor=true`) ผ่านเงื่อนไขนี้เสมอไม่ว่า `active` จะเป็นเท่าไหร่ — ตรงกับดีไซน์เดิมที่ตั้งใจให้ `active=false` เฉพาะกันโผล่ดรอปดาวน์เช็กอิน ไม่ได้ตั้งใจปิดกั้นสิทธิ์ล็อกอินหัวหน้า รันตรงผ่าน SQL Editor ทันที (ไม่ต้องรอ confirm ตามกติกาข้อ 2.1 ข้อยกเว้น เพราะเป็น SQL migration)

**Verify จริง (ก่อนบอกเจ้าของว่าแก้แล้ว):**
- เรียก `do_supervisor_get_today` ผ่าน REST จริง (publishable key) ด้วย PIN ผิด `"0000"` ไปที่บัญชีศุภัตรา → ได้ `{"ok":false,"error":"bad_pin"}` (ไม่ใช่ `officer_not_found` อีกต่อไป) ✅ แปลว่าผ่านเงื่อนไข active-check แล้ว เข้าสู่การเทียบ PIN จริง
- เรียก `do_supervisor_list_mottos` ด้วยวิธีเดียวกัน → ได้ `bad_pin` เช่นกัน ✅ (ยืนยันว่า RPC อื่นที่ใช้ `check_and_count_pin` ร่วมกันหายด้วย ไม่ต้องแก้แยกทีละตัว)
- ตรวจ `settings.service_motto_1/2/3` → ข้อความม็อตโต้ที่เจ้าของตั้งไว้ยังอยู่ครบ ไม่ได้หายไปไหน (ที่ ศุภัตรา รายงานว่า "ไม่เห็นข้อความม็อตโต้" เป็นอาการเดียวกันของบั๊กนี้ — `loadMottoAdmin()` ใน `report.html`/`dashboard.html` เช็ก `if (res.error || !res.data || res.data.ok !== true) return;` แล้วเงียบไม่โชว์ error banner ใดๆ เลย ทำให้ดูเหมือนข้อมูลหาย ทั้งที่จริงแค่ RPC error แล้ว JS จับแบบเงียบ — **จุดอ่อนเชิง UX ที่ควรพิจารณาแก้ในอนาคต: เพิ่ม error banner ให้ `loadMottoAdmin()` แทนการ `return` เงียบๆ** ยังไม่ได้ทำตอนนี้ เป็นแค่ข้อสังเกต)
- ล้าง `pin_fail_count`/`pin_locked_until` ของบัญชีศุภัตราที่เพิ่มจากการทดสอบ PIN ผิดข้างต้นกลับเป็น `0`/`NULL` ไม่ให้ตกค้างกระทบบัญชีจริง
- เจ้าของทดสอบเองจริง (ไม่ใช่ agent จำลอง) ยืนยันว่าล็อกอินได้ปกติแล้ว

**ข้อเสนอเพิ่มเติมที่ยังไม่ทำ (แจ้งเจ้าของไว้เป็นข้อสังเกต ไม่ใช่บั๊กเร่งด่วน):** ตอนนี้ไม่มีการบันทึกว่า "ใครแก้ม็อตโต้ล่าสุดเมื่อไหร่" ถ้าเจ้าของอยากกันชนกันระหว่างชวนชัย/ศุภัตราแก้ข้อความเดียวกันคนละเวลาโดยไม่รู้ตัว อาจเพิ่ม "แก้ล่าสุดโดย X เมื่อ Y" ในอนาคตได้ — ยังไม่จำเป็นเร่งด่วน

**Push:** commit `310f123` (รวมกับ P0.5 mobile card layout + roadmap P1.3 doc + migration renumbering) verify บนเว็บจริงผ่านแล้วผ่าน `fetch()` จาก `rayongimm.link/report.html` จริง

**ผลกระทบต่อเลข migration:** เลข `26` ที่ `90_ROADMAP_v2_PLAN.md` เดิมจองไว้ให้ P1.1 (work_group) ถูกใช้ไปกับ hotfix นี้ก่อน — P1.1 เลื่อนเป็น migration 27, P2.2=28, P2.3=29, P3.1=30 (อัปเดตทั้งในไฟล์นี้ข้อ 3 และใน `90_ROADMAP_v2_PLAN.md` ข้อ 8 แล้ว)

---
