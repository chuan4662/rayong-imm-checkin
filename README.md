# ระบบเช็กอินเช้าเจ้าหน้าที่ - ตม.จว.ระยอง

ระบบเช็กอินเช้าออนไลน์สำหรับเจ้าหน้าที่ ตม.จว.ระยอง พร้อมแดชบอร์ดหัวหน้างาน

## โครงสร้างโปรเจกต์

- `index.html` - หน้าเช็กอินเช้าสำหรับเจ้าหน้าที่
- `dashboard.html` - แดชบอร์ดหัวหน้างาน (Supabase Auth - ชวนชัย)
- `report.html` - แดชบอร์ดดูรายงาน (PIN login - ศุภัตรา/ผู้ช่วยแอดมิน)
- `migrations/` - SQL migration files (รันบน Supabase ตามลำดับ 01-23)
- `edge-functions/` - Supabase Edge Functions
- `docs/` - เอกสารสเปก, roadmap, คู่มือผู้ใช้
- `CLAUDE.md` - agent handoff log (บันทึกความคืบหน้าโปรเจกต์แบบละเอียด)

## Deploy

Netlify site: `comfy-gaufre-b6b83e` (custom domain: rayongimm.link)
Supabase project: `RayongImm-Service` (ref: `aamzsbuwfdyljdvwaifb`)

อ่าน `CLAUDE.md` ก่อนทำงานทุกครั้ง — มีกติกาเหล็กและประวัติการเปลี่ยนแปลงทั้งหมด
