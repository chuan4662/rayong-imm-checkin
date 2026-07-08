-- ============================================================
-- เฟส B (เพิ่มเติมหลัง feedback): RPC สำหรับดึงสถานะเช็กอินของ "ตัวเอง" วันนี้
-- ใช้แสดงไฟจราจรจริงตอนเจอ already_checked_in แทนข้อความเฉยๆ
-- ต้องผ่าน PIN เหมือน do_check_in — กันไม่ให้ anon สุ่ม officer_id (ที่เห็นได้จาก dropdown)
-- มาไล่เช็กสถานะของคนอื่นได้
-- ============================================================
create or replace function public.do_get_today_status(
  p_officer_id uuid,
  p_pin        text
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_off officer%rowtype;
  v_row check_in%rowtype;
  v_tz  text;
begin
  select * into v_off from officer where id = p_officer_id and active = true;
  if not found then
    return json_build_object('ok', false, 'error', 'officer_not_found');
  end if;

  if v_off.pin_hash <> crypt(p_pin, v_off.pin_hash) then
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;

  select tz into v_tz from settings where id = 1;

  select * into v_row from check_in
   where officer_id = p_officer_id
     and local_date = (now() at time zone v_tz)::date
   limit 1;

  if not found then
    return json_build_object('ok', false, 'error', 'not_found');
  end if;

  return json_build_object(
    'ok', true,
    'status', coalesce(v_row.override_status, v_row.status),
    'time', v_row.checked_in_at,
    'distance_m', v_row.distance_m
  );
end;
$$;

grant execute on function public.do_get_today_status to anon;
