// Supabase Edge Function: delete-old-photos
// =========================================================================
// PDPA auto photo-deletion — ลบรูปเซลฟี่เช็กอิน/เช็คเอาต์ที่เก่ากว่า settings.photo_retention_days
// (rolling window นับจาก checked_in_at / checked_out_at) ยกเว้นแถว check_in ที่ retention_hold = true
// เก็บ metadata อื่นๆ ไว้ถาวรเหมือนเดิม — ลบแค่ตัวรูปจริงออกจาก Storage bucket "checkin-photos"
// ผ่าน Storage API แล้วตั้ง check_in.photo_path = null, photo_deleted_at = now()
//
// เรียกผ่าน pg_cron + pg_net ทุกวัน (migration 23/24) — ตรวจสิทธิ์ด้วย header "x-cron-secret"
// เทียบกับ Function Secret CRON_SECRET (service role key ใช้แค่ภายในฟังก์ชัน)
//
// ⚠️ (26 ต.ค. 2569) ฉบับแก้ — ไม่เคยลบได้จริงเลยเพราะ 401 และพบบั๊กที่จะลบเกินถ้าปล่อยให้ผ่าน:
//   1. orphan sweep เดิมรู้จักแค่ check_in.photo_path → รูปเช็คเอาต์ (migration 31,
//      `<officer>/<date>/checkout_….jpg` อ้างอิงจาก check_out.photo_path) ถูกมองเป็นกำพร้าทั้งหมด
//   2. select ไม่แบ่งหน้า → PostgREST คืนสูงสุด 1,000 แถว รายการ "รูปที่ยังมีคนใช้" ขาด
//      รูปเช็กอินที่ยังไม่ถึงกำหนดจึงเสี่ยงถูกลบเป็นกำพร้า
//   3. รูปเช็คเอาต์ไม่เคยถูกลบตามอายุ (check_out.photo_path เป็น not null และไม่มี photo_deleted_at
//      จึงลบแค่ไฟล์ ไม่แก้แถว — หน้าแดชบอร์ดไม่ได้แสดงรูปเช็คเอาต์)
//   4. ไม่มีโหมดลอง → เพิ่ม body {"dry_run": true} คืนจำนวน/ตัวอย่างที่ "จะลบ" โดยไม่ลบอะไรเลย
//   5. ถ้าอ่านรายการอ้างอิงหรือรายการไฟล์ไม่ครบ ให้ข้าม orphan sweep ทั้งรอบ (ไม่เดาว่าเป็นกำพร้า)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

const DEFAULT_RETENTION_DAYS = 31;
const BUCKET = "checkin-photos";
const ORPHAN_GRACE_HOURS = 24;
const PAGE = 1000;        // ขนาดหน้าของ select/list (เพดาน PostgREST/Storage)
const REMOVE_BATCH = 100; // จำนวนไฟล์ต่อการเรียก storage.remove()
const SAMPLE = 20;        // จำนวนตัวอย่าง path ที่คืนในผลลัพธ์

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ดึงทุกแถวแบบแบ่งหน้า — build() ต้องสร้าง query ใหม่ทุกหน้า (และควร order ด้วยคอลัมน์ unique)
async function selectAll<T>(build: () => any): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await build().range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    out.push(...(data ?? []));
    if (!data || data.length < PAGE) return out;
  }
}

// เดินทุกชั้นของ bucket ({officerId}/{YYYY-MM-DD}/{file}.jpg) แบบแบ่งหน้า — error ใดๆ โยนออกไป
// (ฉบับเดิมกลืน error เงียบๆ ทำให้ได้รายการไม่ครบโดยไม่รู้ตัว)
async function listAllStorageObjects(
  supabase: SupabaseClient,
): Promise<{ path: string; created_at: string | null }[]> {
  const result: { path: string; created_at: string | null }[] = [];

  async function walk(prefix: string, depth: number) {
    for (let offset = 0; ; offset += PAGE) {
      const { data, error } = await supabase.storage.from(BUCKET).list(prefix, {
        limit: PAGE,
        offset,
        sortBy: { column: "name", order: "asc" },
      });
      if (error) throw new Error(`list(${prefix || "/"}): ${error.message}`);
      for (const entry of data ?? []) {
        const fullPath = prefix ? `${prefix}/${entry.name}` : entry.name;
        if (entry.id === null) {
          if (depth < 5) await walk(fullPath, depth + 1);
        } else {
          result.push({ path: fullPath, created_at: entry.created_at ?? null });
        }
      }
      if (!data || data.length < PAGE) return;
    }
  }

  await walk("", 0);
  return result;
}

// ลบไฟล์เป็นชุด คืน path ที่ลบสำเร็จ (ไฟล์ที่ไม่มีอยู่แล้วถือว่าสำเร็จ เพื่อความ idempotent)
async function removeInBatches(
  supabase: SupabaseClient,
  paths: string[],
  errors: { path: string; error: string }[],
): Promise<Set<string>> {
  const ok = new Set<string>();
  for (let i = 0; i < paths.length; i += REMOVE_BATCH) {
    const chunk = paths.slice(i, i + REMOVE_BATCH);
    const { error } = await supabase.storage.from(BUCKET).remove(chunk);
    if (error && !/not.?found/i.test(error.message ?? "")) {
      for (const p of chunk) errors.push({ path: p, error: error.message });
      continue;
    }
    for (const p of chunk) ok.add(p);
  }
  return ok;
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
      return json({ ok: false, error: "unauthorized" }, 401);
    }

    // ---- body (ไม่บังคับ): {"dry_run": true} = นับอย่างเดียว ไม่ลบ ----
    let dryRun = false;
    try {
      const body = await req.json();
      dryRun = body?.dry_run === true;
    } catch (_) { /* cron ส่ง body ว่าง/{} ได้ */ }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: settingsRow, error: settingsErr } = await supabase
      .from("settings")
      .select("photo_retention_days")
      .eq("id", 1)
      .single();
    if (settingsErr) {
      return json({ ok: false, error: "settings_read_failed", detail: settingsErr.message }, 500);
    }

    const retentionDays = settingsRow?.photo_retention_days ?? DEFAULT_RETENTION_DAYS;
    const cutoffIso = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000).toISOString();
    const graceThresholdMs = Date.now() - ORPHAN_GRACE_HOURS * 60 * 60 * 1000;

    // ---- อ่านข้อมูลทั้งหมดก่อนลบอะไร (ถ้าส่วนไหนพัง ให้หยุดทั้งรอบ) ----
    let checkinRefs: { id: string; photo_path: string; checked_in_at: string; retention_hold: boolean }[];
    let checkoutRefs: { id: string; photo_path: string; checked_out_at: string }[];
    let objects: { path: string; created_at: string | null }[];
    try {
      checkinRefs = await selectAll(() =>
        supabase.from("check_in")
          .select("id, photo_path, checked_in_at, retention_hold")
          .not("photo_path", "is", null)
          .order("id")
      );
      checkoutRefs = await selectAll(() =>
        supabase.from("check_out")
          .select("id, photo_path, checked_out_at")
          .not("photo_path", "is", null)
          .order("id")
      );
      objects = await listAllStorageObjects(supabase);
    } catch (e) {
      return json({ ok: false, error: "read_failed", detail: String(e) }, 500);
    }

    const existing = new Set(objects.map((o) => o.path));

    // 1) check_in เกินกำหนด (ไม่ hold) — ลบไฟล์ + ตั้ง photo_path = null
    const ciExpired = checkinRefs.filter((r) => r.checked_in_at < cutoffIso && !r.retention_hold);
    const ciExpiredPaths = new Set(ciExpired.map((r) => r.photo_path));

    // 2) check_out เกินกำหนด — ลบเฉพาะไฟล์ที่ยังอยู่ใน bucket (แถวคง photo_path ไว้ เพราะ not null)
    const coExpiredPaths = new Set(
      checkoutRefs.filter((r) => r.checked_out_at < cutoffIso && existing.has(r.photo_path))
        .map((r) => r.photo_path),
    );

    // 3) กำพร้า = ไม่มีแถว check_in หรือ check_out ใดอ้างอิงเลย + อัปโหลดเกิน grace
    const referenced = new Set<string>([
      ...checkinRefs.map((r) => r.photo_path),
      ...checkoutRefs.map((r) => r.photo_path),
    ]);
    let orphanSkippedGrace = 0;
    const orphanPaths: string[] = [];
    for (const obj of objects) {
      if (referenced.has(obj.path)) continue;
      if (obj.created_at && new Date(obj.created_at).getTime() > graceThresholdMs) {
        orphanSkippedGrace++;
        continue;
      }
      orphanPaths.push(obj.path);
    }

    // รูปที่ "ต้องคง" (ยังไม่ถึงกำหนด หรือ hold) — ห้ามอยู่ในรายการลบเด็ดขาด (ตรวจซ้ำอีกชั้น)
    const keep = new Set<string>();
    for (const r of checkinRefs) if (!ciExpiredPaths.has(r.photo_path)) keep.add(r.photo_path);
    for (const r of checkoutRefs) if (!coExpiredPaths.has(r.photo_path)) keep.add(r.photo_path);
    const ciFilesToRemove = [...ciExpiredPaths].filter((p) => !keep.has(p));
    const coFilesToRemove = [...coExpiredPaths].filter((p) => !keep.has(p));
    const orphanToRemove = orphanPaths.filter((p) => !keep.has(p));

    const summary = {
      retention_days: retentionDays,
      cutoff: cutoffIso,
      bucket_files: objects.length,
      checkin_rows_with_photo: checkinRefs.length,
      checkout_rows_with_photo: checkoutRefs.length,
      kept_files: [...keep].filter((p) => existing.has(p)).length,
      kept_checkin_hold: checkinRefs.filter((r) => r.retention_hold).length,
    };

    if (dryRun) {
      return json({
        ok: true,
        dry_run: true,
        ...summary,
        checkin_expired: {
          rows: ciExpired.length,
          files_present: ciFilesToRemove.filter((p) => existing.has(p)).length,
          sample: ciFilesToRemove.slice(0, SAMPLE),
        },
        checkout_expired: { files: coFilesToRemove.length, sample: coFilesToRemove.slice(0, SAMPLE) },
        orphan_sweep: {
          grace_hours: ORPHAN_GRACE_HOURS,
          skipped_grace_period: orphanSkippedGrace,
          files: orphanToRemove.length,
          sample: orphanToRemove.slice(0, SAMPLE),
        },
        would_delete_files:
          ciFilesToRemove.filter((p) => existing.has(p)).length + coFilesToRemove.length + orphanToRemove.length,
      });
    }

    // ---- ลบจริง ----
    const fileErrors: { path: string; error: string }[] = [];
    const rowErrors: { id: string; error: string }[] = [];

    const ciRemoved = await removeInBatches(supabase, ciFilesToRemove, fileErrors);
    // อัปเดตเฉพาะแถวที่ไฟล์ลบสำเร็จ (หรือไม่มีไฟล์อยู่แล้ว) — แถวที่ไฟล์ลบไม่ได้จะลองใหม่คืนถัดไป
    const ciDoneIds = ciExpired.filter((r) => ciRemoved.has(r.photo_path)).map((r) => r.id);
    let ciRowsUpdated = 0;
    for (let i = 0; i < ciDoneIds.length; i += REMOVE_BATCH) {
      const chunk = ciDoneIds.slice(i, i + REMOVE_BATCH);
      const { error } = await supabase
        .from("check_in")
        .update({ photo_path: null, photo_deleted_at: new Date().toISOString() })
        .in("id", chunk);
      if (error) for (const id of chunk) rowErrors.push({ id, error: error.message });
      else ciRowsUpdated += chunk.length;
    }

    const coRemoved = await removeInBatches(supabase, coFilesToRemove, fileErrors);
    const orphanRemoved = await removeInBatches(supabase, orphanToRemove, fileErrors);

    return json({
      ok: fileErrors.length === 0 && rowErrors.length === 0,
      dry_run: false,
      ...summary,
      checkin_expired: { rows: ciExpired.length, rows_updated: ciRowsUpdated, files_removed: ciRemoved.size },
      checkout_expired: { files_removed: coRemoved.size },
      orphan_sweep: {
        grace_hours: ORPHAN_GRACE_HOURS,
        skipped_grace_period: orphanSkippedGrace,
        files_removed: orphanRemoved.size,
      },
      file_errors: fileErrors.slice(0, 50),
      file_error_count: fileErrors.length,
      row_errors: rowErrors.slice(0, 50),
      row_error_count: rowErrors.length,
    });
  } catch (e) {
    return json({ ok: false, error: "unexpected", detail: String(e) }, 500);
  }
});
