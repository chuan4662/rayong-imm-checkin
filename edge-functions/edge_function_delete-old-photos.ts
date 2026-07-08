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

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

const DEFAULT_RETENTION_DAYS = 31;
const BUCKET = "checkin-photos";

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

    return new Response(
      JSON.stringify({
        ok: true,
        retention_days: retentionDays,
        cutoff: cutoffIso,
        scanned: (rows ?? []).length,
        deleted_count: deleted.length,
        deleted_ids: deleted,
        errors,
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
