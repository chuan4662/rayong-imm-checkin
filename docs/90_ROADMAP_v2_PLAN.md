# 90_ROADMAP_v2_PLAN.md — แผนพัฒนาระยะ 2 (Roadmap + สเปกเทคนิค)

> **เอกสารนี้คืออะไร:** แผนพัฒนาต่อจาก v1 จัดทำ 6 ก.ค. 2569 โดย agent วางแผน (Cowork project "AI fable วางแผน ปรับระบบ เว็บเช็คอิน") ตามคำสั่งเจ้าของโปรเจกต์ (ชวนชัย) — เจ้าของยืนยันทิศทางผ่านการถาม-ตอบแล้ว 3 ข้อ: (1) เป้าหมาย = ใช้ภายในให้เป็นเลิศ **และ** เตรียมขยายให้ ตม.อื่น เท่ากัน (2) ระดับเอกสาร = roadmap + สเปกเทคนิคพร้อมลงมือ (3) ระบบคะแนน/รางวัล = ออกแบบ framework รอไว้เลย
>
> **สำหรับ agent ที่รับไปรัน:** อ่านคู่กับ `CLAUDE.md` (สถานะจริงปัจจุบัน) และ `00_SPEC_v1_ORIGINAL.md` (สเปกตั้งต้น) เสมอ — ถ้าเอกสารนี้ขัดกับสถานะจริงใน `CLAUDE.md` (เช่น มี migration ใหม่กว่าที่เอกสารนี้อ้าง) ให้ยึด `CLAUDE.md` แล้วปรับเลข migration ตามจริง เอกสารนี้กำหนด "จะทำอะไร ลำดับไหน ออกแบบอย่างไร" ไม่ใช่บันทึกสถานะ

---

## 0. หลักการคงที่ (Invariants) — สิ่งที่แผนนี้ไม่แตะ

เจ้าของให้อิสระเรื่องขอบเขตฟีเจอร์ (ยกเลิกการ freeze scope v1) **แต่กติกาความถูกต้องยังบังคับใช้ทุกข้อ:**

1. เวลาตัดสินสถานะ = server time (`now()`) เท่านั้น
2. คำนวณสถานะต้องแปลง Asia/Bangkok ก่อนเทียบเกณฑ์
3. บังคับกล้องสด (`getUserMedia`) ห้าม `<input type=file>`
4. GPS บันทึกอย่างเดียว ไม่บล็อกการเช็กอิน
5. 1 คน = 1 เช็กอิน/วัน บังคับที่ระดับ DB (unique constraint)
6. ~~ห้าม scope creep เกิน v1~~ → **ปรับเป็น:** scope ใหม่ = ตาม roadmap นี้ งานนอก roadmap ต้องถามเจ้าของก่อนเสมอ

**กติกา workflow ของโปรเจกต์ (CLAUDE.md ข้อ 2) ยังใช้ครบทุกข้อ:** ห้าม deploy ก่อนถาม, deploy ครบ 3 ไฟล์, ส่งไฟล์ให้ตรวจก่อน, verify จริงก่อนสรุปเสร็จ, เช็กไฟล์ตรงกับเว็บจริงก่อนแก้, ห้ามสร้างบัญชี Auth แทนเจ้าของ, อัปเดต `CLAUDE.md` ทุกครั้งที่งานเสร็จ

**เส้นแดงเดิมที่ยังอยู่:** ทุกฟีเจอร์ที่แตะประชาชน (ฟีดแบ็ก + QR เคาน์เตอร์) ต้องได้อนุมัติจากผู้บังคับบัญชาเป็นลายลักษณ์อักษรก่อนเริ่มเขียนโค้ด — ไม่มีข้อยกเว้น

---

## 1. วิเคราะห์สถาปัตยกรรมปัจจุบัน — จุดแข็งและความเสี่ยงเชิงโครงสร้าง

### จุดแข็ง (อย่าทำลาย)
- Vanilla HTML/JS ไม่มี build step → deploy ง่าย พังยาก agent รุ่นไหนมาแก้ต่อก็ได้
- ทุกการเขียน DB ผ่าน RPC SECURITY DEFINER เท่านั้น (ไม่มี direct insert/update จาก client) → ตรรกะรวมศูนย์ ตรวจสอบได้
- วินัย verify ก่อนสรุปเสร็จ + บันทึกบั๊กกันเจอซ้ำใน CLAUDE.md → คุณภาพส่งมอบสูงจริง

### ความเสี่ยงเชิงโครงสร้าง (เรียงตามความรุนแรง × โอกาสเกิด)

| # | ความเสี่ยง | หลักฐาน/ผลกระทบ |
|---|---|---|
| R1 | **ไม่มี version control** — Netlify Drop + ไฟล์ใน OneDrive คือ source of truth คู่ขนานที่เคย drift มาแล้ว | บั๊ก CLAUDE.md ข้อ 6.5 เกิดซ้ำหลายรอบ ถ้า deploy ทับด้วยไฟล์เก่า = ลบฟีเจอร์ production โดยไม่รู้ตัว |
| R2 | **โค้ดซ้ำ dashboard.html / report.html** — ตรรกะเดียวกันเขียน 2 ชุด (auth vs PIN) | ทุกฟีเจอร์จ่ายต้นทุน ×2 และเสี่ยง 2 ไฟล์ behave ไม่ตรงกัน (เคยเกิด: คอลัมน์สิทธิ์หัวหน้ามีใน dashboard แต่ไม่มีใน report) |
| R3 | **PIN ผ่าน anon RPC ไม่มี rate limit** — ยิง `do_check_in`/`do_get_my_month_stats` เดา PIN ได้ไม่จำกัด | PIN 4-6 หลัก brute force ได้ในหลักชั่วโมง เสี่ยงทั้งเช็กอินแทนกันและอ่านสถิติคนอื่น |
| R4 | **ไม่มี backup ประจำ** — Supabase free tier ไม่มี point-in-time recovery | ถ้า migration พลาด/ลบข้อมูลผิด = ข้อมูลเช็กอินจริงหายถาวร |
| R5 | **ค่าเฉพาะ ตม.ระยอง hardcode กระจายอยู่ในโค้ด** — ชื่อหน่วยใน UI, รัศมี 50 ม. ในตัว RPC, รายชื่อ/กลุ่มงานใน SQL | ขวางทาง Track B โดยตรง ทุกไฟล์ที่ clone ไปหน่วยอื่นต้องไล่แก้มือ |

แผนด้านล่างออกแบบให้งาน Track B (เตรียมขยาย) ส่วนใหญ่ = การแก้ R1–R5 ซึ่ง**ได้ประโยชน์กับ ตม.ระยองเองทันทีด้วย** ไม่ใช่งานลงทุนเปล่ารออนาคต

---

## 2. โครงแผน — 2 Track / 4 เฟส

```
Track A (ใช้ภายในให้เป็นเลิศ)        Track B (โครงสร้างเพื่อขยาย)
──────────────────────────────      ──────────────────────────────
P0  เก็บตก + อุดความเสี่ยงเร่งด่วน   ← ทำร่วมกัน (ก.ค. สัปดาห์ 2-3)
P1  Badge ทีม (เริ่ม ~20 ก.ค.)       P1' วางราก work_group (ทำพร้อม P1)
P2  คะแนน/รางวัล + แผนก + สิทธิ์     (ส.ค. — หลังข้อมูลครบเดือน 3 ส.ค.)
P3  ─                               P3 Multi-office packaging (ก.ย.+)
```

**หลักการจัดลำดับ:** งานที่ปลดล็อกงานอื่น (foundation) มาก่อน, งานที่มีกำหนดจากเจ้าของ (badge ทีม ~20 ก.ค., คะแนน ~3 ส.ค.) ยึดตามกำหนด, งานเสี่ยงสูงทำตอนระบบมี git + backup แล้ว

---

## 3. เฟส P0 — เก็บตก + อุดความเสี่ยง (ก.ค. สัปดาห์ 2-3, ก่อน 20 ก.ค.)

### P0.1 งานเก็บตกเล็ก (ครึ่งวัน — quick win)
- `report.html`: เพิ่มคอลัมน์ "สิทธิ์หัวหน้า" ในตารางรายชื่อ ให้เท่ากับ `dashboard.html` (ข้อมูลมีอยู่แล้วใน RPC ที่เรียกอยู่ แค่ render เพิ่ม)
- error-message mapping ของปุ่มกันลบรูป (`do_set_retention_hold`/`do_supervisor_set_retention_hold`): map ทุก error code ที่ RPC คืนได้ → ข้อความไทย ไม่โชว์โค้ดดิบ
- ไม่มี migration ใหม่ ทั้งคู่เป็น frontend ล้วน deploy รวมกับ P0 อื่นได้

### P0.2 Git + Netlify CI — แก้ R1 (สำคัญที่สุดของ P0)
**สิ่งที่ทำ:**
1. เจ้าของสร้าง GitHub repo แบบ **private** (agent ห้ามสร้างบัญชี/login แทน — เหมือนกติกา Supabase Auth) แนะนำชื่อ `rayong-imm-checkin`
2. โครง repo: `index.html`, `dashboard.html`, `report.html`, โฟลเดอร์ `migrations/` (ย้ายไฟล์ .sql 01–23 เข้าไป), `edge-functions/`, `docs/` (CLAUDE.md, 00_SPEC, เอกสารนี้)
3. ผูก Netlify site `comfy-gaufre-b6b83e` กับ repo (Site settings → Build & deploy → Link repository, ไม่มี build command, publish directory = root)
4. **กติกาใหม่หลังผูก git:** `git push` = deploy อัตโนมัติ ดังนั้นกติกา "ห้าม deploy ก่อนถาม" แปลงร่างเป็น **"ห้าม push ก่อนถาม"** — commit ในเครื่องได้ตลอด, push ต้องรอ confirm และได้ **Deploy Preview URL ฟรี** จาก branch/PR ซึ่งแก้ข้อจำกัดเดิมที่ไม่มี staging ให้เจ้าของตรวจก่อนขึ้นจริง
5. อัปเดต CLAUDE.md ข้อ 2.3 (ไม่ต้องอัปโหลด 3 ไฟล์มือแล้ว) และข้อ 2.6 (source of truth = git ไม่ใช่การ fetch เทียบเว็บ)

**เกณฑ์ผ่าน:** push commit ทดสอบ (แก้ comment 1 บรรทัด) → Netlify auto-deploy สำเร็จ → เว็บจริงไม่มี regression → rollback ผ่าน Netlify UI ได้

### P0.3 PIN rate limiting — แก้ R3 (migration 24)
- เพิ่มคอลัมน์ `officer.pin_fail_count int default 0`, `officer.pin_locked_until timestamptz`
- สร้างฟังก์ชันกลาง `check_and_count_pin(p_officer_id, p_pin)` ให้ RPC ตระกูล PIN ทุกตัวเรียกแทนการเทียบ `crypt()` ตรงๆ: ผิด → count+1, ครบ 5 ครั้ง → ล็อก 15 นาที (`pin_locked_until`), ถูก → reset count เป็น 0, ระหว่างล็อก → คืน error `pin_locked` พร้อมเวลาปลด
- frontend ทุกจุดที่กรอก PIN: map error `pin_locked` → "ใส่ PIN ผิดหลายครั้ง กรุณารอ X นาที"
- ปลดล็อกทันทีได้ด้วยการรีเซ็ต PIN โดยหัวหน้า (กลไก `do_reset_pin` เดิม)
- **ระวัง:** RPC ที่ต้องแก้มีจำนวนมาก (ทุกตัวที่ชื่อ `do_supervisor_*` + `do_check_in` + `do_get_my_month_stats` + `do_save_remark` + `do_set_initial_pin`) — ไล่รายการจาก `pg_proc` จริงก่อนแก้ อย่าเดาจากเอกสาร

**เกณฑ์ผ่าน:** ใส่ PIN ผิด 5 ครั้ง → ล็อก, ครั้งที่ 6 แม้ถูกก็ถูกปฏิเสธจนพ้นเวลา, PIN ถูกก่อนครบ 5 → count reset, รีเซ็ต PIN → ปลดล็อก (ทดสอบด้วยแถวทดสอบชั่วคราวแล้วลบทิ้งตามวินัยเดิม)

### P0.4 Backup ประจำ — แก้ R4
- ทางเลือกที่แนะนำ (ต้นทุนศูนย์): scheduled task ของ Cowork เดือนละ 2 ครั้ง export ตาราง `check_in`, `officer`, `settings`, `public_holiday`, `stats_period_override` เป็น CSV เก็บลงโฟลเดอร์ `backups/` ใน repo (private อยู่แล้ว) — รูปถ่ายไม่ต้อง backup (มีนโยบายลบ 31 วันอยู่แล้ว โดยธรรมชาติเป็นข้อมูลชั่วคราว)
- ทางเลือกเสริมถ้าเจ้าของยอมจ่าย: Supabase Pro plan ($25/เดือน) ได้ daily backup + PITR — ยังไม่จำเป็นที่สเกลนี้

---

## 4. เฟส P1 — Badge ระดับทีม + วางราก work_group (เริ่ม ~20 ก.ค. ตามกำหนดที่เจ้าของขอ)

### ⚠️ การปรับดีไซน์จากที่ยืนยันไว้ (ต้องแจ้งเจ้าของก่อนเริ่ม)
ดีไซน์เดิม (CLAUDE.md ข้อ 22) ระบุ "เพิ่มคอลัมน์ `officer.team_name` text พอ" — **แผนนี้เสนอเปลี่ยนเป็นตาราง `work_group` ตั้งแต่แรก** เพราะฟีเจอร์เฟส P2 อีก 2 ตัว (ระบบแผนก + สิทธิ์หัวหน้าตามแผนก) ต้องการโครงสร้าง "กลุ่มงาน" แบบเดียวกันเป๊ะ ถ้าใช้ text ตอนนี้จะต้อง migrate ซ้ำใน 1 เดือน ต้นทุนเพิ่มขึ้นเปล่าๆ ส่วนตรรกะ badge/เกณฑ์เวลา/UI คงตามดีไซน์ที่ยืนยันแล้วทุกอย่าง — ถ้าเจ้าของไม่เห็นด้วย ให้ถอยกลับไปใช้ `team_name` text ตามดีไซน์เดิมได้โดย badge ทีมไม่กระทบ

### P1.1 Backend (migration 25)
```sql
create table public.work_group (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,          -- 'กลุ่มงานธุรกิจ', 'กลุ่มงานครอบครัว', ...
  is_ot_team  boolean not null default false, -- true = เข้าเกณฑ์ badge ทีม (คู่ OT)
  created_at  timestamptz not null default now()
);
alter table public.officer add column work_group_id uuid references public.work_group(id);
-- seed: insert กลุ่มงานธุรกิจ + ครอบครัว (is_ot_team=true) แล้ว update officer 4 คนที่เกี่ยวข้อง
--       (รายชื่อจริงให้ถามเจ้าของตอนรัน — อย่าเดา)
alter table public.settings add column team_ok_before   time not null default '08:20';
alter table public.settings add column team_warn_before time not null default '09:00';
```
- RPC `do_get_team_coverage()` (auth) / `do_supervisor_get_team_coverage(p_officer_id, p_pin)` (PIN): ต่อ work_group ที่ `is_ot_team=true` คืน `{group_name, first_checkin_time, member_names[], badge}` โดย badge = `ok` (มีคนเช็กอินก่อน `team_ok_before`) / `warn` (มีคนก่อน `team_warn_before`) / `none` (เลยแล้วยังไม่มีใคร — แสดงเฉพาะเมื่อเวลาปัจจุบัน Bangkok > `team_warn_before`)
- คำนวณจากเวลาเช็กอิน**จริง** (`checked_in_at`) ไม่ใช่ effective status — override สถานะสีไม่ควรเปลี่ยนข้อเท็จจริงว่าจุดบริการมีคนตอนกี่โมง
- แก้ `do_list_officers_admin`/`do_supervisor_list_officers` คืน `work_group_id`+ชื่อกลุ่มเพิ่ม (DROP ก่อน — เปลี่ยน return columns ตามบั๊กคลาสสิก 6.1)
- แก้ `do_get_settings`/`do_set_settings` (migration 22) รองรับ 2 ค่าเวลาใหม่

### P1.2 Frontend
- `dashboard.html`/`report.html`: การ์ด "🤝 จุดบริการกลุ่มงาน OT" วางเหนือการ์ด "ขาดเช็กอิน" แสดง badge ต่อกลุ่ม + เวลาคนแรกเช็กอิน — **ไม่แตะสีรายคนใดๆ ทั้งสิ้น** (ตามดีไซน์ยืนยัน)
- `dashboard.html` (เฉพาะชวนชัย): จัดการกลุ่มงานในการ์ดตั้งค่าระบบ — เพิ่ม/แก้ชื่อกลุ่ม, ติ๊ก `is_ot_team`, มอบสมาชิก (dropdown ต่อ officer ในตารางรายชื่อ)
- `index.html`: ไม่แตะ

**เกณฑ์ผ่าน:** จำลอง 3 เคส (คนแรกก่อน 08:20 / ระหว่าง 08:20–09:00 / ไม่มีใครถึง 09:01) ด้วยแถวทดสอบชั่วคราว badge ถูกทั้ง 3, สีรายคนของสมาชิกทีมไม่เปลี่ยนจากเดิมแม้แต่เคสเดียว, ลบข้อมูลทดสอบครบ

---

## 5. เฟส P2 — คะแนน/รางวัล + แผนก + สิทธิ์ (ส.ค. — หลังข้อมูลครบ 1 เดือน 3 ส.ค.)

### P2.1 วิเคราะห์ข้อมูลจริง 1 เดือนก่อนตั้งเกณฑ์ (ทำก่อน ห้ามข้าม)
ก่อนเขียน scoring ให้รันวิเคราะห์จากข้อมูล 3 ก.ค.–3 ส.ค. (ผ่าน SQL อ่านอย่างเดียว):
- distribution สี per คน per work_days (คนทำงาน 3 วัน/สัปดาห์ vs 5 วัน ต้องเทียบเป็น**อัตราส่วน** ไม่ใช่ยอดดิบ)
- อัตราม่วง (incomplete) per คน — ถ้าคนใดม่วงถี่ผิดปกติ อาจเป็นปัญหามือถือ/GPS ไม่ใช่พฤติกรรม **ห้ามให้ม่วงถ่วงคะแนนจนกว่าจะแยกสาเหตุได้**
- ผลของวันเริ่มนับ (`stats_period_override` ก.ค. เริ่ม 6 ก.ค.) ต้อง apply เหมือนสถิติส่วนบุคคล
- สรุปเป็นรายงานสั้นให้เจ้าของดูก่อนตัดสินใจ weights

### P2.2 Scoring framework (migration 26)
```sql
create table public.scoring_config (
  id int primary key default 1 check (id = 1),
  enabled boolean not null default false,      -- ปิดไว้จนเจ้าของสั่งเปิด
  weights jsonb not null default
    '{"green":3, "yellow":2, "orange":1, "red":0, "absent":-1, "incomplete":0}'::jsonb,
  normalize_by_workdays boolean not null default true
);
```
- RPC `do_get_month_scores(p_year, p_month)` (auth) / เวอร์ชัน PIN: คำนวณจาก `coalesce(override_status, status)` + absent (ตรรกะเดียวกับ `do_get_my_month_stats` — พิจารณา refactor เป็นฟังก์ชันภายในร่วมกันเพื่อไม่ให้เกณฑ์ 2 ที่ drift กัน) คืน ranking พร้อม raw counts เพื่อความโปร่งใส
- UI: การ์ด "🏆 สรุปคะแนนประจำเดือน" ใน dashboard/report แสดงเฉพาะเมื่อ `enabled=true` — **เห็นเฉพาะหัวหน้า** ใน v นี้ (ยังไม่โชว์ ranking ให้เจ้าหน้าที่เห็นกันเอง — กระดานจัดอันดับสาธารณะมีความเสี่ยงด้านขวัญกำลังใจ ให้เจ้าของตัดสินใจแยกทีหลังจากเห็นข้อมูลจริง)
- การให้รางวัลจริง = การตัดสินใจของเจ้าของนอกระบบ ระบบมีหน้าที่แค่คำนวณอย่างโปร่งใส ตรวจย้อนได้

### P2.3 ระบบแผนกเต็มรูป + สิทธิ์หัวหน้าตามแผนก (migration 27)
- ใช้ `work_group` จาก P1 เป็นแผนกได้เลย (เพิ่มกลุ่มที่เหลือจนครบทุกคนใน 19 คน) — นี่คือผลตอบแทนของการตัดสินใจใน P1
- ตาราง `supervisor_scope (supervisor_id uuid, work_group_id uuid, primary key ทั้งคู่)` — **ไม่มีแถว = เห็นทุกแผนก** (backward compatible: หัวหน้า 3 คนปัจจุบันไม่มีแถว → พฤติกรรมเหมือนเดิมเป๊ะ ไม่ต้อง migrate สิทธิ์)
- แก้ RPC อ่านข้อมูลฝั่งหัวหน้า (`*_get_today`, `*_get_history`, `*_get_absentees`, `*_get_team_coverage`) ให้ join กรองตาม scope ของผู้เรียก
- UI จัดการ scope อยู่ใน `dashboard.html` เฉพาะชวนชัย (แพทเทิร์นเดียวกับจัดการบัญชีหัวหน้า migration 22)
- **คำเตือน:** ฟีเจอร์นี้แตะ RPC จำนวนมากที่สุดในแผน — ทำเป็นงานเดี่ยว อย่าพ่วงกับงานอื่นในรอบ deploy เดียว และ verify ทุก RPC ที่แก้ด้วยแถวทดสอบทั้งเคส "มี scope" และ "ไม่มี scope"

---

## 6. เฟส P3 — Multi-office packaging (ก.ย. เป็นต้นไป)

### การตัดสินใจสถาปัตยกรรม: แยก instance ต่อสำนักงาน (แนะนำ) ไม่ใช่ multi-tenant DB เดียว

| ประเด็น | Option A: DB เดียว multi-tenant | Option B: แยก Supabase+Netlify ต่อหน่วย ✅ |
|---|---|---|
| ความเสี่ยงข้อมูลปนกัน | ต้องทำ RLS `office_id` ทุกตาราง/ทุก RPC — พลาดจุดเดียว = ข้อมูลข้ามหน่วย | เป็นศูนย์โดยโครงสร้าง (คนละ DB) |
| PDPA/ความเป็นเจ้าของข้อมูล | ข้อมูลทุกหน่วยอยู่ในบัญชี Supabase ของระยอง — หน่วยราชการอื่นมักไม่ยอมรับ | แต่ละหน่วยถือบัญชี/ข้อมูลของตัวเอง |
| ต้นทุน | รวมทุกหน่วยอาจชน free tier limit | free tier ต่อหน่วย — สเกล 19-30 คน/หน่วยสบาย |
| ต้นทุน refactor | สูงมาก (แก้ทุก RPC ทุกตาราง) | ต่ำ — โค้ดเดิมใช้ได้เกือบทั้งหมด |
| งาน maintain | อัปเดตครั้งเดียวได้ทุกหน่วย | ต้อง update หลาย instance — แก้ด้วย git template (ดูล่าง) |

### P3.1 กวาด hardcode ออกจากโค้ด — แก้ R5 (migration 28)
- เพิ่ม `settings.office_name text` (แสดงใน header ทุกหน้า + ชื่อหัวกล่องม็อตโต้ "Rayong Immigration Service" → ดึงจาก settings), `settings.incomplete_radius_m int default 50` (แก้ 50 ม. ที่ hardcode ใน `do_check_in`/`do_check_distance`)
- ไล่ grep ทั้ง 3 ไฟล์ HTML หา string เฉพาะระยอง แล้วย้ายเข้า settings หรือตัวแปร config หัวไฟล์
- ผูกเข้า `do_get_settings`/`do_set_settings` ให้แก้ผ่าน UI ได้

### P3.2 Bootstrap kit
- `migrations/00_bootstrap.sql` — รวม 01→2x เป็นสคริปต์เดียว idempotent สำหรับ**โปรเจกต์ Supabase ใหม่เปล่าๆ เท่านั้น** (ห้ามรันกับ production ระยองเด็ดขาด — ใส่ guard เช็คว่าตาราง settings ยังไม่มีก่อนรัน)
- `SETUP_GUIDE.md` — คู่มือติดตั้งสำหรับหน่วยใหม่: สร้าง Supabase project → รัน bootstrap → สร้าง bucket + Edge Functions 2 ตัว → ตั้ง secrets/cron → fork repo → ผูก Netlify → กรอก settings (พิกัด, ชื่อหน่วย, เกณฑ์เวลา) → เพิ่มรายชื่อเจ้าหน้าที่ → checklist ทดสอบรับงาน (ยึดเกณฑ์ผ่านเฟส A–C จากสเปกเดิม)
- ทดสอบ kit ด้วยการติดตั้งจริง 1 รอบบน Supabase project เปล่า (ใช้ฟรี tier ที่ 2 ขององค์กร Chuan ได้) — **นี่คือ verify จริงของเฟสนี้ ห้ามส่งมอบ kit ที่ไม่เคยติดตั้งจริง**

### P3.3 โมเดลการส่งมอบ (คำถามเปิด — เจ้าของตัดสินใจ ไม่ใช่งานเทคนิค)
ให้ฟรีแบบราชการช่วยราชการ (MOU/หนังสือราชการ) vs คิดค่าติดตั้ง/ดูแล — มีผลต่อว่าใครถือบัญชี Supabase/Netlify ของหน่วยใหม่ และใครรับผิดชอบตอนระบบล่ม แนะนำตอบคำถามนี้ให้ชัดก่อนเสนอหน่วยแรก

---

## 7. สิ่งที่ gate ไว้ (ยังไม่อยู่ในแผน — ต้องผ่านเงื่อนไขก่อน)

| ฟีเจอร์ | เงื่อนไขปลดล็อก |
|---|---|
| ฟีดแบ็กประชาชน + QR เคาน์เตอร์ | อนุมัติจากผู้บังคับบัญชาเป็นลายลักษณ์อักษร (เส้นแดงเดิม — ไม่มีข้อยกเว้น) |
| เช็กเอาต์ตอนเย็น | ยังไม่มีโจทย์ชัดว่าแก้ปัญหาอะไร — ข้อมูล "เลิกดึก/OT" ตอนนี้มาจากกล่องหมายเหตุอยู่แล้ว ถ้าเจ้าของอยากได้ ให้ตอบก่อนว่าหมายเหตุที่มีไม่พอตรงไหน แล้วค่อยออกแบบ |
| แสดง ranking คะแนนให้เจ้าหน้าที่เห็นกันเอง | ตัดสินใจหลังหัวหน้าเห็นข้อมูลคะแนนจริงอย่างน้อย 1 เดือน (P2.2 ให้หัวหน้าเห็นก่อน) |
| LINE/LIFF integration | นอกขอบเขตเช่นเดิม — bookmark เพียงพอ |

---

## 8. สรุปลำดับ migration + dependency

| Migration | เฟส | เนื้อหา | ขึ้นกับ |
|---|---|---|---|
| 24 | P0.3 | PIN rate limiting | — |
| 25 | P1.1 | work_group + team coverage + เกณฑ์เวลาทีม | ควรมี git (P0.2) ก่อน |
| 26 | P2.2 | scoring_config + month scores | ข้อมูลครบเดือน + P2.1 |
| 27 | P2.3 | supervisor_scope + กรอง RPC ตาม scope | 25 (ใช้ work_group) |
| 28 | P3.1 | office_name + incomplete_radius_m + กวาด hardcode | — (ทำก่อน 27 ได้ถ้าอยากสลับ) |

กติกาเดิมยังใช้: migration รันบน Supabase ได้ทันทีไม่ต้องรอ confirm, ห้ามรัน 01–23 ซ้ำ, DROP FUNCTION ก่อนเมื่อเปลี่ยน return columns, ทดสอบด้วยแถวชั่วคราวแล้วลบทิ้ง, ตาราง `settings` ต้อง backup/restore ค่าจริงเมื่อทดสอบเขียน

---

## 9. ความเสี่ยงของแผนนี้เอง (ให้เจ้าของ + agent ที่รันต่อชั่งใจ)

1. **P0.2 (git) เปลี่ยน workflow ที่ใช้มาตลอด** — ช่วงเปลี่ยนผ่านอาจสับสน แนะนำทำตอนไม่มีฟีเจอร์ค้าง deploy และ verify rollback ให้ได้ก่อนถือว่าเสร็จ ถ้าเจ้าของไม่สะดวก GitHub เลย ให้ถอยมาที่ minimum: โฟลเดอร์ `releases/` เก็บ snapshot 3 ไฟล์ทุกครั้งที่ deploy + คอมเมนต์ `<!-- vYYYYMMDD-HHMM -->` หัวไฟล์
2. **R2 (โค้ดซ้ำ 2 ไฟล์) แผนนี้จงใจยังไม่แก้** — การรวมเป็น shared JS คือ refactor ใหญ่ที่เสี่ยงพัง production โดยไม่เพิ่มฟีเจอร์ให้ผู้ใช้เลย คุ้มก็ต่อเมื่อมี git + preview URL แล้วเท่านั้น เสนอพิจารณาใหม่หลัง P1 เสร็จ ถ้าจะทำให้ทำเฉพาะ layer ฟังก์ชัน render ร่วม (เช่น `renderCheckinTable`) ไม่ใช่รวมทั้งไฟล์
3. **แผน P2 ตั้งอยู่บนสมมติฐานว่าข้อมูล 1 เดือนเพียงพอ** — ก.ค. มีวันหยุด/วันทดสอบปน ถ้าข้อมูลจริงบางเกินไป เลื่อนการเปิด scoring ได้โดยไม่กระทบส่วนอื่น (นี่คือเหตุผลที่ `scoring_config.enabled` default false)
4. **อย่ารันหลายงานพร้อมกัน** — แผนนี้มีงานเยอะ แต่กติกา "ทีละงาน ส่งตรวจ ถาม deploy" ยังศักดิ์สิทธิ์ agent ที่รับไปรันควรทำตามลำดับ ไม่ pipeline

---

*จัดทำ 6 ก.ค. 2569 — อัปเดตเอกสารนี้เมื่อเจ้าของเปลี่ยนทิศทาง และบันทึกงานที่เสร็จลง `CLAUDE.md` ตามวินัยเดิม*
