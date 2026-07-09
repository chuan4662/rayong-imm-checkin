// Supabase Edge Function: delete-old-photos
// =========================================================================
// PDPA auto photo-deletion — ลบรูปเซลฟี่เช็กอินที่เก่ากว่า settings.photo_retention_days
// (rolling window นับจาก checked_in_at ไม่ใช่ตามเดือนปฏิทิน) ยกเว้นแถวที่ retention_hold = true
// เก็บ metadata อื่นๆ (สถานะ/เวลา/ระยะทาง/override/หมายเหตุ) ไว้ถาวรเหมือนเดิม — แค่ลบตัวรูปจริง
// ออกจาก Storage bucket "checkin-photos" ผ่าน Storage API (ไม่ใช้ raw SQL delete บน storage.objects
// เพราะจะทำให้ blob ค้าง/orphan) แล้วตั้ง photo_path = null, photo_deleted_at = now()
//
// เรียกผ่าน pg_cron + pg_net ทุกวัน (ดู migration 23 ส่วน cron.schedule) — ไม่ได้เปิดให้ browser
// เรียกตรงๆ จึงตรวจสิทธิ์ด้วย custom header "x-cron-secret" เทียบกับ Function Secret ชื่อ CRON_SECRET
// (ไม่ใช้ service role key เป็นตัวยืนยันสิทธิ์เรียก เพราะเสี่ยงถ้าหลุด — service role key ใช้แค่
// ภายในฟังก์ชันเพื่อคุย Storage/DB เท่านั้น ซึ่ง Supabase inject เป็น env var ให้อัตโนมัติเสมอ
// ไม่ต้องตั้งเอง เหมือนฟังก์ชัน supervisor-photo-url ที่มีอยู่แล้วในโปรเจกต์นี้)
//
// ⚠️ (9 ก.ค. 2569) เพิ่ม "orphan photo sweep" — บั๊กที่พบ: index.html อัปโหลดรูปขึ้น Storage ก่อน
// เรียก do_check_in เสมอ ถ้า do_check_in ตอบ error (already_checked_in/bad_pin/officer_not_found/
// note_too_short/ready_required) รูปที่เพิ่งอัปโหลดไปจะไม่มีแถว check_in.photo_path อ้างอิงถึงเลย —
// ลอจิกลบรูปเดิมด้านบน (ตาม checked_in_at ของแถว check_in) มองไม่เห็นรูปพวกนี้เพราะมันไม่ผูกกับแถวใดๆ
// เลยค้างอยู่ใน bucket ตลอดไป ส่วนนี้จึงสแกนทุกไฟล์ใน bucket แล้วเทียบกับ photo_path ที่มีอยู่จริงใน
// check_in ทั้งหมด (ไม่กรอง retention_hold เพราะไฟล์กำพร้าไม่ผูกกับแถวไหนให้ hold ได้อยู่แล้ว) ไฟล์ที่ไม่มี
// แถวอ้างอิงและอัปโหลดมาเกิน ORPHAN_GRACE_HOURS ชั่วโมงแล้ว ถือว่าเป็นรูปกำพร้าจริง (ให้ grace period กัน
// ลบรูปที่เพิ่งอัปโหลดเสร็จแต่ do_check_in ยังไม่ทันตอบกลับ/อยู่ระหว่าง retry จริงๆ)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

const DEFAULT_RETENTION_DAYS = 31;
const BUCKET = "checkin-photos";
const ORPHAN_GRACE_HOURS = 24;

// เดินลึกเข้าไปใน bucket ทีละชั้น (โครงสร้างจริงคือ {officerId}/{YYYY-MM-DD}/{uuid}.jpg — 2 ชั้นโฟลเดอร์
// ก่อนถึงไฟล์) Supabase Storage list() คืนแค่ชั้นเดียวต่อครั้ง ต้องเรียกซ้ำแบบ recursive เอง
// entry.id === null หมายถึงเป็น "โฟลเดอร์" (placeholder) ส่วน entry.id ที่มีค่าจริงหมายถึงไฟล์จริง
async function listAllStorageObjects(
  supabase: ReturnType<typeof createClient>,
): Promise<{ path: string; created_at: string | null }[]> {
  const result: { path: string; created_at: string | null }[] = [];

  async function walk(prefix: string, depth: number) {
    const { data, error } = await supabase.storage.from(BUCKET).list(prefix, { limit: 1000 });
    if (error || !data) return;
    for (const entry of data) {
      const fullPath = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id === null) {
        // กันวนลูปไม่รู้จบถ้าโครงสร้างจริงลึกผิดคาด (ปกติลึกแค่ 2 ชั้น)
        if (depth < 5) await walk(fullPath, depth + 1);
      } else {
        result.push({ path: fullPath, created_at: entry.created_at ?? null });
      }
    }
  }

  await walk("", 0);
  return result;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ---- ตรวจสิทธิ์เรียก: ต้องมี header x-cron-secret ตรงกับ Function Secret CRON_SECRET ----
    const cronSecret = Deno.env.get("CRON_SECRET");
    const gotSecret = req.headers.get("x-cron-secret");
    if (!cronSecret || !gotSecret || gotSecret !== cronSecret) {
      return new Response(
        JSON.stringify({ ok: false, error: "unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // ---- อ่านค่า photo_retention_days จาก settings (fallback 31 ถ้า null) ----
    const { data: settingsRow, error: settingsErr } = await supabase
      .from("settings")
      .select("photo_retention_days")
      .eq("id", 1)
      .single();

    if (settingsErr) {
      return new Response(
        JSON.stringify({ ok: false, error: "settings_read_failed", detail: settingsErr.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const retentionDays = settingsRow?.photo_retention_days ?? DEFAULT_RETENTION_DAYS;
    const cutoffIso = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000).toISOString();

    // ---- หาแถวที่เข้าเกณฑ์ลบ: เก่ากว่า cutoff, ไม่ถูก hold, มี photo_path, ยังไม่เคยลบ ----
    const { data: rows, error: selErr } = await supabase
      .from("check_in")
      .select("id, photo_path")
      .lt("checked_in_at", cutoffIso)
      .eq("retention_hold", false)
      .not("photo_path", "is", null)
      .is("photo_deleted_at", null);

    if (selErr) {
      return new Response(
        JSON.stringify({ ok: false, error: "select_failed", detail: selErr.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const deleted: string[] = [];
    const errors: { id: string; error: string }[] = [];

    for (const row of rows ?? []) {
      try {
        // ลบตัวไฟล์จริงออกจาก Storage bucket ก่อนเสมอ (ไม่ใช้ raw SQL delete บน storage.objects)
        const { error: rmErr } = await supabase.storage.from(BUCKET).remove([row.photo_path]);
        // ถ้าไฟล์ไม่มีอยู่แล้วในบัคเก็ต (เช่นเคยถูกลบไปก่อนหน้า) ถือว่าไม่ error เพื่อความ idempotent
        if (rmErr && !/not.?found/i.test(rmErr.message ?? "")) {
          errors.push({ id: row.id, error: rmErr.message });
          continue;
        }

        const { error: updErr } = await supabase
          .from("check_in")
          .update({ photo_path: null, photo_deleted_at: new Date().toISOString() })
          .eq("id", row.id);

        if (updErr) {
          errors.push({ id: row.id, error: updErr.message });
          continue;
        }

        deleted.push(row.id);
      } catch (e) {
        errors.push({ id: row.id, error: String(e) });
      }
    }

    // =====================================================================
    // ---- กวาดรูปกำพร้า (orphan sweep) — ดูคำอธิบายเต็มที่หัวไฟล์ ----
    // สแกนทุกไฟล์จริงใน bucket แล้วเทียบกับ photo_path ที่มีแถว check_in อ้างอิงอยู่ทั้งหมด
    // (ไม่กรองด้วย cutoff/retention_hold เหมือนลูปด้านบน เพราะไฟล์กำพร้าไม่ผูกกับแถวใดเลย)
    // ไฟล์ที่ไม่มีใครอ้างอิง + อัปโหลดมาเกิน ORPHAN_GRACE_HOURS ชม.แล้ว ถือว่ากำพร้าจริง ลบได้ปลอดภัย
    // =====================================================================
    const orphanDeleted: string[] = [];
    const orphanErrors: { path: string; error: string }[] = [];
    let orphanScanned = 0;
    let orphanSkippedGrace = 0;

    try {
      const allObjects = await listAllStorageObjects(supabase);
      orphanScanned = allObjects.length;

      const { data: refRows, error: refErr } = await supabase
        .from("check_in")
        .select("photo_path")
        .not("photo_path", "is", null);

      if (refErr) {
        orphanErrors.push({ path: "*", error: "refs_read_failed: " + refErr.message });
      } else {
        const referenced = new Set((refRows ?? []).map((r: { photo_path: string }) => r.photo_path));
        const graceThresholdMs = Date.now() - ORPHAN_GRACE_HOURS * 60 * 60 * 1000;

        for (const obj of allObjects) {
          if (referenced.has(obj.path)) continue;

          // ไม่มี created_at (ไม่ควรเกิดขึ้นจริง) ให้ถือว่าเก่าพอที่จะลบได้ ปลอดภัยกว่าเก็บค้างไว้ตลอดไป
          if (obj.created_at) {
            const createdMs = new Date(obj.created_at).getTime();
            if (createdMs > graceThresholdMs) {
              orphanSkippedGrace++;
              continue; // ยังไม่ครบ grace period — เผื่อ do_check_in กำลังจะตามมา
            }
          }

          const { error: rmErr } = await supabase.storage.from(BUCKET).remove([obj.path]);
          if (rmErr && !/not.?found/i.test(rmErr.message ?? "")) {
            orphanErrors.push({ path: obj.path, error: rmErr.message });
            continue;
          }
          orphanDeleted.push(obj.path);
        }
      }
    } catch (e) {
      orphanErrors.push({ path: "*", error: "orphan_sweep_unexpected: " + String(e) });
    }

    return new Response(
      JSON.stringify({
        ok: true,
        retention_days: retentionDays,
        cutoff: cutoffIso,
        scanned: (rows ?? []).length,
        deleted_count: deleted.length,
        deleted_ids: deleted,
        errors,
        orphan_sweep: {
          grace_hours: ORPHAN_GRACE_HOURS,
          scanned: orphanScanned,
          skipped_grace_period: orphanSkippedGrace,
          deleted_count: orphanDeleted.length,
          deleted_paths: orphanDeleted,
          errors: orphanErrors,
        },
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: "unexpected", detail: String(e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
