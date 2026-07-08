> **หมายเหตุ (เพิ่มภายหลัง):** ไฟล์นี้คือสเปกตั้งต้น v1 ฉบับเต็ม ที่แต่เดิมถูกเก็บไว้ใน "Project Instructions" ของ Cowork project นี้เท่านั้น (ไม่ใช่ไฟล์ในโฟลเดอร์) — จึง**ไม่ติดไปกับโฟลเดอร์เวลาย้ายไปเปิด Cowork project ใหม่บนเครื่องอื่น** ผมจึงคัดลอกมาบันทึกเป็นไฟล์จริงไว้ที่นี่ เพื่อให้ agent ตัวถัดไป (ไม่ว่าจะรันบนเครื่องไหน) อ่านสเปกตั้งต้นได้ครบโดยไม่ต้องพึ่ง Cowork project เดิม
>
> **อ่านคู่กับ `CLAUDE.md`ในโฟลเดอร์นี้เสมอ** — ไฟล์นี้คือ "สเปกวันแรก" (ยังคงเป็นกติกาเหล็กหลัก) ส่วน `CLAUDE.md` คือ "บันทึกความคืบหน้าจริง" (มีของที่ทำเสร็จแล้ว, deviation จาก spec, บั๊กที่เจอ, backlog) — ถ้าสองไฟล์นี้ขัดกันเรื่องข้อเท็จจริง (เช่น สเปกเดิมบอก 3 สี แต่ระบบจริงมี 4 สีไปแล้ว) ให้เชื่อ `CLAUDE.md` เพราะเป็นของปัจจุบันกว่า แต่ **กติกาเหล็ก 6 ข้อในไฟล์นี้ยังบังคับใช้เสมอ ไม่มีการยกเลิก**

---

# โครงการ: ระบบเช็กอินเช้าเจ้าหน้าที่ (Morning Check-in) — Spec v1

> **เอกสารนี้คืออะไร:** handoff spec สำหรับส่งต่อให้ AI agent (Sonnet) รันต่อใน Cowork
> เพื่อสร้างแอปจริงบน **Netlify (frontend) + Supabase (backend)**
> เอกสาร model-agnostic — ใช้ Sonnet เวอร์ชันไหนที่มีใน Cowork ก็ได้ ตัวเลขเวอร์ชันไม่สำคัญ สาระอยู่ในสเปกนี้

---

## 0. กติกาเหล็ก (อ่านก่อนเขียนโค้ดบรรทัดแรก)

Agent ที่รับงานต่อ **ห้ามละเมิด 6 ข้อนี้** เด็ดขาด เพราะเป็นหัวใจความถูกต้องและความยุติธรรมของระบบ:

1. **เวลาที่ใช้ตัดสินสถานะ ต้องเป็นเวลาเซิร์ฟเวอร์ (`now()` ใน Postgres) เท่านั้น** — ห้ามเชื่อเวลาจากเครื่องผู้ใช้เด็ดขาด (ตั้งเวลาเครื่องเองแล้วโกงได้)
2. **การคำนวณสถานะไฟจราจร ต้องแปลงเป็นเวลา Asia/Bangkok ก่อนเทียบเกณฑ์** — Supabase เก็บ timestamp เป็น UTC ถ้าลืมแปลง status จะเพี้ยน 7 ชั่วโมง (บั๊กคลาสสิก)
3. **บังคับถ่ายภาพสดจากกล้องเท่านั้น** — ใช้ `getUserMedia` + canvas capture **ห้ามใช้ `<input type=file>` หรือ `capture` attribute** เพราะยังเปิดอัลบั้มได้บนหลายเครื่อง
4. **พิกัด GPS = บันทึกอย่างเดียว ไม่บล็อก** — ถ่ายจากที่ไหนก็เช็กอินได้ ระบบแค่บันทึกระยะห่างให้หัวหน้าเห็น ไม่ห้าม
5. **1 คน = 1 เช็กอิน ต่อวัน (นับตามวัน Asia/Bangkok)** — บังคับด้วย unique constraint ที่ระดับฐานข้อมูล ไม่ใช่เช็คที่ frontend
6. **v1 ไม่มีระบบให้คะแนน/รางวัล ไม่มี face recognition ไม่มีการ track พิกัดต่อเนื่อง** — เก็บพิกัดเฉพาะ "วินาทีที่กดเช็กอิน" เท่านั้น ห้าม scope creep

> ถ้า agent เผลอทำสิ่งที่อยู่นอก v1 scope (เช่น เริ่มสร้างสูตรคะแนน, เพิ่มเช็กเอาต์, ทำระบบจองคิว) = **ผิด** ให้หยุดและถามเจ้าของโปรเจกต์ก่อน

---

## 1. ภาพรวมและขอบเขต

### สิ่งที่อยู่ใน v1 (ทำ)
- เจ้าหน้าที่เช็กอินตอนเช้า: เลือกชื่อ → ใส่ PIN → ถ่ายรูปสด → ระบบจับพิกัด+เวลา → กดยืนยัน → เห็นสถานะไฟจราจรทันที
- สถานะคำนวณอัตโนมัติฝั่งเซิร์ฟเวอร์: 🟢 ตรงเวลา / 🟡 ยอมรับได้ / 🔴 สาย
- กันเช็กอินซ้ำในวันเดียว
- ช่องหมายเหตุ (ไม่บังคับ)
- หน้าแจ้ง/ขอความยินยอมครั้งแรก
- แดชบอร์ดหัวหน้า (ล็อกอินแยก): ตารางวันนี้ / ประวัติย้อนหลัง / กรองรายคน / ดูรูป / override พร้อมเหตุผล / export Excel

### สิ่งที่ "ยังไม่ทำ" ใน v1 (ห้ามแตะ)
- ระบบให้คะแนน/รางวัล → รอเก็บข้อมูลจริง 1 เดือนก่อน แล้วค่อยออกแบบเกณฑ์จากพฤติกรรมจริง
- เช็กเอาต์ตอนเย็น
- ฝั่งฟีดแบ็กประชาชน + QR เคาน์เตอร์ → เฟสหลัง และ**ต้องได้รับอนุมัติจากผู้บังคับบัญชาเป็นลายลักษณ์อักษรก่อน**
- ระบบจองคิวออนไลน์ → คนละโปรเจกต์ ความเสี่ยงสูงกว่ามาก
- LINE / LIFF integration → เว็บแอป bookmark หน้าจอพอสำหรับ v1

> **หมายเหตุความรับผิด:** ฝั่งเช็กอินเจ้าหน้าที่ หัวหน้าสั่งลูกน้องใช้ได้เองในฐานะการกำกับภายใน — v1 นี้จึงเดินหน้าได้เลย แต่**ทุกฟีเจอร์ที่แตะประชาชนต้องรออนุมัติ** อย่าให้ agent ข้ามเส้นนี้

### ระบบนี้ใช้ทำอะไร / ไม่ใช้ทำอะไร
- **ใช้เป็น:** เครื่องมือกำกับภายในให้เจ้าหน้าที่ลงเวลาตามจริงด้วยความสุจริต + หัวหน้าเห็นภาพรวม
- **ไม่ใช่:** ระบบลงเวลาราชการทางการที่ใช้เป็นหลักฐานชี้ขาดวินัย ถ้าหน่วยมีระบบทางการอยู่แล้ว อันนี้ต้องไม่ขัดกัน

---

## 2. สถาปัตยกรรม

```
[ มือถือเจ้าหน้าที่ ]                    [ มือถือ/คอมหัวหน้า ]
   หน้า check-in                            หน้า dashboard
        |                                        |
        |  (1) ถ่ายรูปสด (getUserMedia)          |  login (Supabase Auth)
        |  (2) ขอ GPS                            |  อ่านข้อมูล / override / export
        v                                        v
  ============================ NETLIFY (static hosting, HTTPS) ============================
   เสิร์ฟไฟล์ HTML/JS ล้วน ไม่มี build step — เสถียร แก้ยาก แต่พังยาก
        |                                        |
        v  supabase-js (CDN)                     v
  ============================ SUPABASE ==================================================
   - Storage bucket: checkin-photos (private)
   - Postgres: settings / officer / check_in
   - RPC: do_check_in() [SECURITY DEFINER]  <- ออก server timestamp + คำนวณ status
   - RPC: do_override() [supervisor only]
   - Auth: บัญชีหัวหน้า
   - RLS: ล็อกไม่ให้ anon อ่าน/เขียนตารางตรงๆ
========================================================================================
```

**ทำไมเลือก vanilla HTML/JS ไม่ใช้ framework หนัก:** คุณย้ำว่า "ต้องเสถียร" — static file บน Netlify + supabase-js จาก CDN ไม่มี build step ไม่มี dependency ให้พัง deploy ง่ายที่สุด และ agent ตัวต่อไปแก้แล้วทำพังยากกว่าระบบที่มี toolchain ซับซ้อน ปริมาณงานระดับหน่วยคุณ (เจ้าหน้าที่ไม่กี่คน วันละครั้ง) ไม่ต้องการอะไรมากกว่านี้

**เรื่องค่าใช้จ่าย:** ปริมาณการใช้ระดับนี้อยู่ในกรอบ free tier ของทั้ง Netlify และ Supabase สบายๆ ไม่แตะเพดานที่ต้องจ่าย

---

## 3. โครงสร้างฐานข้อมูล (Supabase / Postgres)

> **หมายเหตุ:** ส่วนนี้คือ schema **ตั้งต้น** ของ v1 — schema จริงบน Supabase ตอนนี้ผ่านการแก้ไขเพิ่มเติมมาแล้วหลายรอบ (ดูตาราง migration 01–16 ใน `CLAUDE.md`) ห้ามรันซ้ำ ใช้เพื่ออ้างอิงโครงสร้างพื้นฐานเท่านั้น

รันตามลำดับนี้ใน Supabase SQL Editor

### 3.1 Extension
```sql
create extension if not exists pgcrypto;   -- สำหรับ hash PIN
```

### 3.2 ตาราง settings (แถวเดียว — ตั้งค่ากลาง)
```sql
create table public.settings (
  id            int primary key default 1,
  office_lat    double precision not null,
  office_lng    double precision not null,
  green_before  time not null default '08:15',   -- ก่อนเวลานี้ = เขียว
  yellow_before time not null default '08:30',    -- ก่อนเวลานี้ = เหลือง, ตั้งแต่นี้ = แดง
  tz            text not null default 'Asia/Bangkok',
  photo_retention_days int,                        -- null = เก็บถาวร (ดูข้อ 9)
  constraint settings_singleton check (id = 1)
);
-- ใส่ค่าจริง: พิกัด ตม.ระยอง (ดูข้อ 11)
insert into public.settings (id, office_lat, office_lng)
values (1, 0.0, 0.0);   -- << แทนที่ด้วยพิกัดจริง
```

### 3.3 ตาราง officer (ทะเบียนเจ้าหน้าที่)
```sql
create table public.officer (
  id          uuid primary key default gen_random_uuid(),
  full_name   text not null,
  rank_title  text,
  pin_hash    text not null,          -- เก็บ hash ไม่เก็บ PIN ดิบ
  is_supervisor boolean not null default false,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
```
> **เพิ่มเจ้าหน้าที่** ให้ hash PIN ตอน insert:
> ```sql
> insert into public.officer (full_name, rank_title, pin_hash)
> values ('ชื่อ นามสกุล', 'ยศ/ตำแหน่ง', crypt('1234', gen_salt('bf')));
> ```

### 3.4 ตาราง check_in (หัวใจของระบบ)
```sql
create table public.check_in (
  id            uuid primary key default gen_random_uuid(),
  officer_id    uuid not null references public.officer(id),
  checked_in_at timestamptz not null default now(),   -- << server time เท่านั้น
  local_date    date generated always as
                ((checked_in_at at time zone 'Asia/Bangkok')::date) stored,
  photo_path    text not null,
  lat           double precision,
  lng           double precision,
  distance_m    integer,
  status        text not null check (status in ('green','yellow','red')),
  note          text,
  -- override โดยหัวหน้า (เก็บ audit trail ครบ)
  override_status text check (override_status in ('green','yellow','red')),
  override_by     uuid references public.officer(id),
  override_reason text,
  override_at     timestamptz,
  unique (officer_id, local_date)     -- << กันเช็กอินซ้ำ 1 คน/วัน
);
create index on public.check_in (local_date);
create index on public.check_in (officer_id, local_date);
```
> **สถานะที่แสดงผลจริง (effective status)** = `coalesce(override_status, status)` — เก็บ status เดิมไว้เสมอเพื่อตรวจสอบย้อนหลังได้ว่าใครแก้อะไร

---

## 4. Server logic (RPC — ตรรกะที่ต้องอยู่ฝั่งเซิร์ฟเวอร์)

### 4.1 `do_check_in()` — anon เรียกได้ แต่ทำงานแบบควบคุม
ฟังก์ชันนี้คือด่านเดียวที่ anon แตะฐานข้อมูลได้ มันจัดการ: verify PIN → ออก server time → คำนวณ status ตาม Bangkok time → คำนวณระยะทาง haversine → insert → กันซ้ำ

```sql
create or replace function public.do_check_in(
  p_officer_id uuid,
  p_pin        text,
  p_photo_path text,
  p_lat        double precision,
  p_lng        double precision,
  p_note       text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_set     settings%rowtype;
  v_off     officer%rowtype;
  v_now     timestamptz := now();          -- server time = แหล่งความจริง
  v_local   time;
  v_status  text;
  v_dist    integer;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;

  -- verify PIN (เทียบกับ hash)
  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select * into v_set from settings where id = 1;

  -- แปลงเวลาเป็น time-of-day ตามโซน Bangkok ก่อนเทียบเกณฑ์ (ห้ามลืม!)
  v_local := (v_now at time zone v_set.tz)::time;
  if    v_local <  v_set.green_before  then v_status := 'green';
  elsif v_local <  v_set.yellow_before then v_status := 'yellow';
  else                                      v_status := 'red';
  end if;

  -- ระยะห่างจากที่ทำงาน (haversine, เมตร) — บันทึกเฉยๆ ไม่บล็อก
  if p_lat is not null and p_lng is not null then
    v_dist := round(
      6371000 * 2 * asin(sqrt(
        power(sin(radians(p_lat - v_set.office_lat)/2), 2) +
        cos(radians(v_set.office_lat)) * cos(radians(p_lat)) *
        power(sin(radians(p_lng - v_set.office_lng)/2), 2)
      ))
    );
  end if;

  insert into check_in(officer_id, checked_in_at, photo_path, lat, lng, distance_m, status, note)
  values (p_officer_id, v_now, p_photo_path, p_lat, p_lng, v_dist, v_status, p_note);

  return json_build_object('ok', true, 'status', v_status,
                           'time', v_now, 'distance_m', v_dist);
exception
  when unique_violation then
    return json_build_object('ok', false, 'error', 'already_checked_in');
end;
$$;

grant execute on function public.do_check_in to anon;
```

### 4.2 `do_override()` — เฉพาะหัวหน้า
```sql
create or replace function public.do_override(
  p_check_in_id uuid,
  p_new_status  text,
  p_reason      text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_is_sup boolean;
begin
  -- ผู้เรียกต้องเป็น supervisor (map auth.uid() -> officer ดูข้อ 6)
  select is_supervisor into v_is_sup
  from officer where id = auth.uid();
  if coalesce(v_is_sup, false) = false then
    return json_build_object('ok', false, 'error', 'not_supervisor');
  end if;

  update check_in
     set override_status = p_new_status,
         override_by     = auth.uid(),
         override_reason = p_reason,
         override_at     = now()
   where id = p_check_in_id;

  return json_build_object('ok', true);
end;
$$;

grant execute on function public.do_override to authenticated;
```

---

## 5. RLS (Row Level Security) — ล็อกไม่ให้ใครแตะตารางตรงๆ

```sql
alter table public.settings  enable row level security;
alter table public.officer   enable row level security;
alter table public.check_in  enable row level security;

-- anon: อ่านรายชื่อเจ้าหน้าที่ที่ active ได้ (เพื่อโชว์ใน dropdown) เท่านั้น
create policy officer_list_for_anon on public.officer
  for select to anon using (active = true);
-- หมายเหตุ: ต้องไม่ให้ anon เห็นคอลัมน์ pin_hash — ใช้ view ที่ select เฉพาะ id, full_name, rank_title
-- หรือเรียกผ่าน RPC do_list_officers() แทน (แนะนำ ดูหมายเหตุด้านล่าง)

-- supervisor (authenticated + is_supervisor): อ่าน check_in ทั้งหมดได้
create policy checkin_read_supervisor on public.check_in
  for select to authenticated
  using (exists (select 1 from officer o where o.id = auth.uid() and o.is_supervisor));

create policy officer_read_supervisor on public.officer
  for select to authenticated
  using (exists (select 1 from officer o where o.id = auth.uid() and o.is_supervisor));

-- ไม่มี policy insert/update/delete ตรงๆ ให้ใคร -> ทุกการเขียนผ่าน RPC เท่านั้น
```

> **แนะนำ (ปลอดภัยกว่า):** อย่าให้ anon `select` จากตาราง officer ตรงๆ เพราะเสี่ยงหลุด `pin_hash` ให้ทำ RPC `do_list_officers()` ที่ return เฉพาะ `id, full_name, rank_title` ของคน active แล้ว grant ให้ anon แทน ปิด policy `officer_list_for_anon` ทิ้ง

---

## 6. Auth หัวหน้า + การผูก auth.uid() กับ officer

- หัวหน้าใช้ **Supabase Auth (email + password)** สร้างบัญชีใน Dashboard > Authentication
- ต้องผูก `auth.users.id` เข้ากับแถวใน `officer` ที่ `is_supervisor = true`
- วิธีง่ายสุด: ตั้ง `officer.id` ของหัวหน้าให้ **เท่ากับ** `auth.users.id` ของบัญชีนั้น (insert officer โดยระบุ id = uid ของ auth user)
- RPC `do_override` และ RLS ใช้ `auth.uid()` เทียบกับ `officer.id` ตามนี้

---

## 7. Storage (รูปถ่าย)

- สร้าง bucket **`checkin-photos`** แบบ **private**
- **v1 (เริ่มแบบง่าย):** อนุญาต anon อัปโหลดเข้า bucket นี้ได้ ภายใต้ path pattern `officer_id/local_date/uuid.jpg` แล้วส่ง path เข้า RPC
  - ข้อดี: เขียนง่าย ข้อเสีย: anon อัปไฟล์เข้า bucket ได้ (ยอมรับได้สำหรับเครื่องมือภายใน)
- **แนวทาง hardened (อัปเกรดทีหลังถ้าจำเป็น):** ทำ Supabase **Edge Function** รับรูป+ข้อมูล → อัปโหลดฝั่งเซิร์ฟเวอร์ + เรียก insert เอง เพื่อไม่ให้ anon แตะ storage/DB เลย — **ทำแล้วจริงใน migration ทีหลัง ดู `CLAUDE.md` ข้อ 4 (Edge Function `supervisor-photo-url`)**
- การดูรูปในแดชบอร์ด: หัวหน้าสร้าง **signed URL** อายุสั้น (เช่น 60 วินาที) ไม่เปิด bucket เป็น public

Storage RLS policy (แบบ v1 simple):
```sql
-- ให้ anon upload เข้า bucket checkin-photos ได้เท่านั้น
create policy checkin_upload_anon on storage.objects
  for insert to anon
  with check (bucket_id = 'checkin-photos');
```

---

## 8. Frontend (สิ่งที่คนกดเห็น)

### 8.1 หน้าเจ้าหน้าที่ — `index.html` (หน้าเดียวจบ)

ลำดับการทำงาน:
1. **ครั้งแรกที่เปิด:** แสดง consent notice — "ระบบจะบันทึกรูป พิกัด และเวลาเช็กอินของคุณ และหัวหน้าสามารถเห็นได้" → กดยอมรับ → เก็บ flag ใน `localStorage` (ใช้ได้ปกติ เพราะรันบนเว็บของคุณเอง ไม่ใช่ sandbox)
2. เลือกชื่อตัวเองจาก dropdown (โหลดจาก `do_list_officers()`) + ใส่ PIN
3. กดปุ่มใหญ่ **"เช็กอิน"** → เปิดกล้องสดด้วย `getUserMedia({ video: { facingMode: 'user' } })` แสดง preview
4. กด "ถ่าย" → วาด video frame ลง `<canvas>` → แปลงเป็น blob (JPEG)
5. ขอพิกัดด้วย `navigator.geolocation.getCurrentPosition` (ถ้าปฏิเสธ → ยังเช็กอินได้ แต่ distance = null)
6. อัปโหลด blob เข้า Storage → ได้ `photo_path`
7. เรียก RPC `do_check_in(officer_id, pin, photo_path, lat, lng, note)`
8. แสดงผลลัพธ์: 🟢/🟡/🔴 + เวลาเซิร์ฟเวอร์ + "ห่างที่ทำงาน ~120 ม."
9. ถ้า return `already_checked_in` → แสดง "เช็กอินแล้ววันนี้" กดซ้ำไม่ได้

> **จุดที่ agent มักพลาด:**
> - อย่าใช้ `<input type="file" capture>` — ต้อง `getUserMedia` เท่านั้น (กติกาข้อ 3)
> - `getUserMedia` และ `geolocation` **ต้องรันบน HTTPS** — Netlify ให้ HTTPS อยู่แล้ว แต่ถ้าเทสต์ local ต้องใช้ https/localhost
> - เวลาที่โชว์ให้ผู้ใช้ ให้ใช้เวลาที่ RPC ส่งกลับ (server time) **ไม่ใช่** `new Date()` ฝั่ง client

### 8.2 หน้าหัวหน้า — `dashboard.html` (ล็อกอินแยก)

1. Login ด้วย Supabase Auth
2. **ตารางวันนี้:** ชื่อ / เวลา / สถานะ (effective) / ระยะห่าง / thumbnail รูป (signed URL) / หมายเหตุ
3. **ประวัติย้อนหลัง:** เลือกช่วงวันที่ / กรองรายบุคคล
4. **ปุ่ม override:** เลือกแถว → เลือกสถานะใหม่ → **บังคับใส่เหตุผล** → เรียก `do_override` → แสดง badge ว่า "แก้โดย…เมื่อ…"
5. **Export Excel:** ใช้ SheetJS (xlsx) จาก CDN แปลงข้อมูลที่ดึงมาเป็นไฟล์ .xlsx

---

## 9. PDPA / ความเป็นส่วนตัว (ทำตั้งแต่ v1 อย่ารอ)

- consent notice ครั้งแรก (ข้อ 8.1) — ตัดปัญหาร้องเรียนภายหลัง
- bucket รูปเป็น private + ใช้ signed URL เท่านั้น
- **การลบรูปอัตโนมัติ:** ตั้ง `photo_retention_days` ใน settings (เช่น 90 วัน) แล้วทำ scheduled job (pg_cron) ลบรูปเก่า — เก็บรูปพนักงานไว้ถาวรโดยไม่จำเป็นคือความเสี่ยง ควรมีนโยบายลบ **(ยังไม่ได้ทำจริง ดู backlog ใน `CLAUDE.md`)**
- ข้อมูล "มาสาย" ให้เห็นเฉพาะหัวหน้า ไม่ทำกระดานสาธารณะ

---

## 10. ลำดับการสร้าง (Build order) + เกณฑ์ผ่านแต่ละเฟส

> **สถานะจริง:** เฟส A–C ทำเสร็จและใช้งานจริงแล้วตั้งแต่ 3 ก.ค. 2569 (ดู `CLAUDE.md`) ตอนนี้อยู่ระหว่างเฟส D

Agent ทำทีละเฟส **ห้ามข้าม** และต้องผ่านเกณฑ์ก่อนไปเฟสถัดไป

**เฟส A — Backend รากฐาน**
- [x] สร้าง extension + 3 ตาราง + insert settings (พิกัดจริง) + เพิ่ม officer ทดสอบ 2–3 คน
- [x] เขียน RPC `do_check_in`, `do_override`, `do_list_officers`
- [x] เปิด RLS + policies
- **ผ่านเมื่อ:** เรียก `do_check_in` จาก SQL editor แล้ว insert ได้จริง, เรียกซ้ำวันเดียวกันได้ error `already_checked_in`, status ตรงกับเวลา Bangkok

**เฟส B — หน้าเจ้าหน้าที่**
- [x] consent → เลือกคน+PIN → กล้องสด → GPS → upload → RPC → แสดงไฟจราจร
- **ผ่านเมื่อ:** เช็กอินจริงจากมือถือได้, บังคับกล้องสด (เลือกอัลบั้มไม่ได้), เช็กอินซ้ำถูกบล็อก, ปฏิเสธ GPS แล้วยังเช็กอินได้ (distance=null)

**เฟส C — แดชบอร์ดหัวหน้า**
- [x] login → ตารางวันนี้ + กรอง + ดูรูป (ประวัติย้อนหลัง/override UI/export ยังไม่ทำ ดู backlog)
- **ผ่านเมื่อ:** หัวหน้า login เห็นข้อมูล, anon เข้า dashboard ไม่ได้, override แล้ว log ครบ, export ได้ไฟล์

**เฟส D — ใช้จริง 1 เดือน (สำคัญที่สุด แต่ไม่ใช่การเขียนโค้ด)**
- [ ] ให้ลูกน้องใช้จริงทุกวัน เก็บข้อมูลดิบ **ห้ามเพิ่มฟีเจอร์ใดๆ** ← **อยู่ตรงนี้ตอนนี้ (เริ่ม 3 ก.ค. 2569)**
- **ผ่านเมื่อ:** มีข้อมูลจริง ≥ 1 เดือน + รู้ปัญหาจริง (กล้อง/GPS/การใช้งาน) → ค่อยตัดสินใจเรื่องเกณฑ์รางวัลจากข้อมูลจริง ไม่ใช่จากการเดา

---

## 11. สิ่งที่คุณ (เจ้าของโปรเจกต์) ต้องยืนยันก่อน/ระหว่างสร้าง

> ยืนยันไปแล้วทั้งหมดในรอบที่ผ่านมา — เก็บไว้เป็นประวัติ

| # | รายการ | Default ที่ผมตั้งไว้ | ต้องทำ |
|---|--------|------------------|--------|
| 1 | พิกัด ตม.ระยอง (lat/lng) | `0.0, 0.0` (placeholder) | **ต้องใส่ค่าจริง** — เปิด Google Maps คลิกที่อาคารสำนักงาน คัดลอกพิกัด |
| 2 | เกณฑ์เวลา | 🟢 ก่อน 08:15 / 🟡 ก่อน 08:30 / 🔴 ตั้งแต่ 08:30 | ยืนยันหรือปรับ (ปัจจุบันขยายเป็น 4 สี ดู `CLAUDE.md`) |
| 3 | รายชื่อเจ้าหน้าที่ + PIN เริ่มต้น | — | เตรียมรายชื่อ + ยศ (ทำแล้ว 19 คน) |
| 4 | บัญชีหัวหน้า (email/password) | — | เตรียม email (ทำแล้ว 3 บัญชี) |
| 5 | เก็บรูปกี่วันแล้วลบ | ยังไม่ตั้ง (เก็บถาวร) | แนะนำตั้ง 90 วัน (ยังไม่ได้ทำจริง) |

---

## 12. คำเตือนถึง agent ที่รับงานต่อ (Sonnet ใน Cowork)

1. **อย่า gold-plate** — เจ้าของโปรเจกต์มีแนวโน้มอยากเพิ่มของ (เคยอยากพันฟีดแบ็กประชาชน + จองคิว + รางวัลเข้ามาพร้อมกัน) v1 นี้จงใจตัดออกหมดแล้ว ถ้าถูกขอให้เพิ่มนอก scope ให้ทำ v1 ให้เสร็จก่อน แล้วเตือนว่ามันคือเฟสถัดไปที่ต้องรอ (บางเฟสต้องรออนุมัติผู้บังคับบัญชา)
2. **6 กติกาเหล็กในข้อ 0 ห้ามละเมิด** โดยเฉพาะ server timestamp + timezone Bangkok
3. **ทดสอบ timezone จริง** — insert แล้วเช็คว่า `local_date` และ `status` ตรงกับเวลาไทย ไม่ใช่ UTC
4. ถ้าติดสิ่งที่ตัดสินใจแทนเจ้าของไม่ได้ (เช่น พิกัด, รายชื่อ) → หยุดถาม อย่าเดาค่าจริง
