-- migration 34: daily_brief — "สรุปเช้า 3 บรรทัด" ส่งหัวหน้าทุกวันทำการ
-- APPLIED on prod (aamzsbuwfdyljdvwaifb) 17 ก.ย. 2569 ทีละบล็อกผ่าน pg-meta
--
-- Additive only. ไม่แตะฟังก์ชันเดิมใดๆ (โดยเฉพาะ queue_send_email ซึ่งไม่มี source ในรีโป — เรียกใช้อย่างเดียว)
-- ยังไม่ตั้ง cron ในไฟล์นี้ (ทำที่ขั้นเปิดใช้จริง):
--   select cron.schedule('daily-brief-request', '12 2 * * 1-5', 'select public.daily_brief_request();');
--   select cron.schedule('daily-brief-send',    '15 2 * * 1-5', 'select public.daily_brief_send();');
-- API key (เจ้าของรันเอง ครั้งเดียว) — ใช้ Gemini key ที่มีอยู่แล้ว:
--   select vault.create_secret('PASTE_KEY_HERE', 'gemini_api_key', 'daily brief AI');
-- รองรับ 2 provider ผ่าน settings.brief_ai_provider ('gemini' ค่าเริ่มต้น | 'anthropic')
-- ถ้าสลับไป anthropic ต้องมี secret ชื่อ anthropic_api_key และตั้ง brief_ai_model ให้ตรง

-- ============================================================
-- block 1: schema
-- ============================================================

create table if not exists public.daily_brief_log (
  id            bigserial primary key,
  brief_date    date not null unique,
  facts         jsonb not null,
  ai_request_id bigint,
  ai_provider   text,
  ai_raw        text,
  brief_text    text,
  source        text check (source in ('ai','fallback')),
  requested_at  timestamptz,
  sent_at       timestamptz,
  sent_to       text,
  send_status   text,
  error         text
);
alter table public.daily_brief_log enable row level security;
-- RLS เปิดโดยไม่มี policy: อ่านผ่าน RPC (do_admin_brief_preview) เท่านั้น

-- เผื่อกรณีตารางมีอยู่ก่อนแล้ว (prod ใช้ทางนี้)
alter table public.daily_brief_log add column if not exists ai_provider text;

alter table public.settings add column if not exists brief_enabled       boolean not null default true;
alter table public.settings add column if not exists brief_emails        text;
alter table public.settings add column if not exists brief_ai_model      text not null default 'gemini-2.5-flash';
alter table public.settings add column if not exists brief_line_group_id text;
alter table public.settings add column if not exists brief_ai_provider   text not null default 'gemini'
  check (brief_ai_provider in ('gemini','anthropic'));
alter table public.settings alter column brief_ai_model set default 'gemini-2.5-flash';

update public.settings set brief_emails = queue_digest_emails where id = 1 and brief_emails is null;
-- หมายเหตุ: gemini-2.0-flash ไม่มีใน models list ของคีย์นี้แล้ว (ping 17 ก.ย. 2569) ใช้ 2.5-flash
update public.settings set brief_ai_model = 'gemini-2.5-flash' where id = 1;

-- ============================================================
-- block 2: daily_brief_facts — ข้อเท็จจริงล้วน ไม่มีข้อมูลผู้รับบริการ
-- ============================================================

create or replace function public.daily_brief_facts(p_date date default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_tz      text;
  v_date    date;
  v_prev    date;
  v_isodow  smallint;
  v_workday boolean;
  v_guard   int := 0;
  v_dash    jsonb;
  v_cov     jsonb;
  v_facts   jsonb;
begin
  select coalesce(nullif(btrim(s.tz), ''), 'Asia/Bangkok') into v_tz from settings s where s.id = 1;
  v_tz   := coalesce(v_tz, 'Asia/Bangkok');
  v_date := coalesce(p_date, (now() at time zone v_tz)::date);
  v_isodow := extract(isodow from v_date)::smallint;
  v_workday := (v_isodow between 1 and 5)
               and not exists (select 1 from public_holiday h where h.holiday_date = v_date);

  -- วันทำการก่อนหน้า: ถอยจาก p_date-1 ข้ามเสาร์อาทิตย์และวันหยุด
  v_prev := v_date - 1;
  while v_guard < 30
        and ( extract(isodow from v_prev)::int > 5
              or exists (select 1 from public_holiday h where h.holiday_date = v_prev) ) loop
    v_prev  := v_prev - 1;
    v_guard := v_guard + 1;
  end loop;

  v_dash := public.do_queue_dashboard_data()::jsonb;
  v_cov  := public.do_team_coverage_json()::jsonb;

  with expected as (
    select o.id, coalesce(nullif(btrim(o.nickname), ''), o.full_name) as nick
    from officer o
    where o.active and not o.is_supervisor and coalesce(o.sort_order, 0) < 1000
      and v_isodow = any(o.work_days)
  ),
  ci as (
    select e.nick,
           to_char(c.checked_in_at at time zone v_tz, 'HH24:MI')  as t,
           coalesce(c.override_status, c.status)                  as st,
           coalesce(c.incomplete_checkin, false)                  as incomplete,
           coalesce(c.stagger_applied, false)                     as stagger,
           case c.daily_rank when 1 then 'gold' when 2 then 'silver' else null end as medal,
           c.checked_in_at                                        as ord
    from check_in c join expected e on e.id = c.officer_id
    where c.local_date = v_date
  )
  select jsonb_build_object(
    'date',         v_date::text,
    'tz',           v_tz,
    'is_workday',   v_workday,
    'prev_workday', v_prev::text,
    'attendance', jsonb_build_object(
      'expected',    (select count(*) from expected),
      'checked_in_n',(select count(*) from ci),
      'counts',      (select coalesce(jsonb_object_agg(st, n), '{}'::jsonb)
                        from (select st, count(*) n from ci group by st) q),
      'yesterday_counts', (select coalesce(jsonb_object_agg(st, n), '{}'::jsonb)
                        from (select coalesce(c.override_status, c.status) st, count(*) n
                              from check_in c join officer o on o.id = c.officer_id
                              where c.local_date = v_prev and o.active and not o.is_supervisor
                                and coalesce(o.sort_order, 0) < 1000
                              group by 1) q),
      'checked_in',  (select coalesce(jsonb_agg(jsonb_build_object(
                              'nick', nick, 'time', t, 'status', st,
                              'incomplete', incomplete, 'stagger', stagger, 'medal', medal)
                              order by ord), '[]'::jsonb)
                        from (select * from ci order by ord limit 30) z),
      'not_yet',     (select coalesce(jsonb_agg(jsonb_build_object('nick', nick) order by nick), '[]'::jsonb)
                        from (select e.nick from expected e
                              where not exists (select 1 from check_in c
                                                where c.officer_id = e.id and c.local_date = v_date)
                              order by e.nick limit 30) z)
    ),
    'team_coverage', (select coalesce(jsonb_agg(jsonb_build_object(
                              'group', g->>'group_name', 'badge', g->>'badge',
                              'members', coalesce(jsonb_array_length(g->'member_names'), 0))), '[]'::jsonb)
                        from (select g from jsonb_array_elements(coalesce(v_cov->'groups', '[]'::jsonb)) g
                              where coalesce(g->>'badge', 'ok') <> 'ok' limit 30) z),
    'notes_today',   (select coalesce(jsonb_agg(jsonb_build_object('nick', nick, 'time', t, 'note', note)
                              order by ord), '[]'::jsonb)
                        from (select coalesce(nullif(btrim(o.nickname), ''), o.full_name) nick,
                                     to_char(c.checked_in_at at time zone v_tz, 'HH24:MI') t,
                                     left(btrim(c.note), 200) note, c.checked_in_at ord
                              from check_in c join officer o on o.id = c.officer_id
                              where c.local_date = v_date and coalesce(btrim(c.note), '') <> ''
                              order by c.checked_in_at limit 30) z),
    -- check_in ไม่มีคอลัมน์เวลาเขียน remark → ใช้ local_date ของวันนี้กับวันทำการก่อนหน้า
    'remarks_recent',(select coalesce(jsonb_agg(jsonb_build_object('nick', nick, 'date', d::text, 'remark', remark)
                              order by ord desc), '[]'::jsonb)
                        from (select coalesce(nullif(btrim(o.nickname), ''), o.full_name) nick,
                                     c.local_date d, left(btrim(c.remark), 300) remark, c.checked_in_at ord
                              from check_in c join officer o on o.id = c.officer_id
                              where c.local_date in (v_date, v_prev) and coalesce(btrim(c.remark), '') <> ''
                              order by c.checked_in_at desc limit 30) z),
    'checkout_yesterday', jsonb_build_object(
      'date',  v_prev::text,
      'count', (select count(*) from check_out co where co.local_date = v_prev),
      'items', (select coalesce(jsonb_agg(jsonb_build_object('nick', nick, 'time', t, 'tier', tier)
                              order by ord desc), '[]'::jsonb)
                  from (select coalesce(nullif(btrim(o.nickname), ''), o.full_name) nick,
                               to_char(co.checked_out_at at time zone v_tz, 'HH24:MI') t,
                               co.tier_label tier, co.checked_out_at ord
                        from check_out co join officer o on o.id = co.officer_id
                        where co.local_date = v_prev
                        order by co.checked_out_at desc limit 30) z)
    ),
    'queue', jsonb_build_object(
      'today_appts_n', (select count(*) from booking b
                          where b.appt_date = v_date
                            and b.status in ('assigned','claimed','confirmed')
                            and not coalesce(b.is_test, false)),
      'holders',       (select coalesce(jsonb_agg(jsonb_build_object('nick', nick, 'n', n)
                                order by n desc, nick), '[]'::jsonb)
                          from (select coalesce(nullif(btrim(o.nickname), ''), o.full_name, 'ยังไม่มอบหมาย') nick,
                                       count(*) n
                                from booking b left join officer o on o.id = b.assigned_officer_id
                                where b.appt_date = v_date
                                  and b.status in ('assigned','claimed','confirmed')
                                  and not coalesce(b.is_test, false)
                                group by 1 order by 2 desc, 1 limit 30) z),
      'unassigned',    coalesce((v_dash->'summary'->>'unassigned')::int, 0),
      'unclaimed',     coalesce(v_dash->'summary'->'unclaimed', '[]'::jsonb),
      -- สร้างเองแทนการใช้ do_queue_stale_impl() ตรงๆ เพราะ items ของมันมี applicant_name
      'overdue',       (select coalesce(jsonb_agg(jsonb_build_object(
                                'ref', ref, 'nick', nick, 'working_days', wd, 'level', lvl)
                                order by lvl desc, wd desc), '[]'::jsonb)
                          from (select b.ref,
                                       coalesce(nullif(btrim(o.nickname), ''), o.full_name, '-') nick,
                                       public.count_working_days(b.assigned_at, now())::int wd,
                                       coalesce(b.escalate_level, 0)::int lvl
                                from booking b left join officer o on o.id = b.assigned_officer_id
                                where b.status in ('assigned','claimed')
                                  and coalesce(b.escalate_level, 0) > 0
                                  and not coalesce(b.is_test, false)
                                order by b.escalate_level desc, b.assigned_at limit 30) z),
      'new_since_yesterday', (select count(*) from booking b
                                where b.created_at > now() - interval '24 hours'
                                  and not coalesce(b.is_test, false)),
      'officers_accepting',  (select count(*) from officer o
                                where o.active and coalesce(o.accepts_online_queue, false))
    ),
    -- feedback: นับอย่างเดียว ไม่ส่งข้อความร้องเรียนของประชาชนออกไป
    'feedback', jsonb_build_object(
      'issues_unreviewed', (select count(*) from feedback f where f.kind = 'issue' and f.reviewed_at is null),
      'issues_new_24h',    (select count(*) from feedback f where f.kind = 'issue' and f.created_at > now() - interval '24 hours'),
      'praise_pending',    (select count(*) from feedback f where f.kind = 'praise' and f.praise_approved is distinct from true),
      'praise_new_24h',    (select count(*) from feedback f where f.kind = 'praise' and f.created_at > now() - interval '24 hours'),
      'discuss_flagged',   (select count(*) from feedback f where f.discuss_flag is true)
    )
  ) into v_facts;

  return v_facts;
end;
$fn$;

-- ============================================================
-- block 3: daily_brief_fallback_text — 3 บรรทัดตามกฎตายตัว (ใช้เมื่อ AI ล่ม/ไม่มี key)
-- ============================================================

create or replace function public.daily_brief_fallback_text(p_facts jsonb)
returns text
language plpgsql
immutable
security definer
set search_path to 'public'
as $fn$
declare
  v_exp   int := coalesce((p_facts->'attendance'->>'expected')::int, 0);
  v_in    int := coalesce((p_facts->'attendance'->>'checked_in_n')::int, 0);
  v_notyet_n int := coalesce(jsonb_array_length(p_facts->'attendance'->'not_yet'), 0);
  v_late_n   int := 0;
  v_l1 text; v_l2 text; v_l3 text;
  v_s  text; v_n int;
begin
  select count(*) into v_late_n
  from jsonb_array_elements(coalesce(p_facts->'attendance'->'checked_in', '[]'::jsonb)) e
  where e->>'status' in ('orange','red');

  -- line 1: attendance
  if v_notyet_n = 0 and v_late_n = 0 then
    v_l1 := '1) เช็กอินครบ ' || v_in::text || ' คน ตรงเวลาทุกคน';
  else
    v_l1 := '1) เช็กอินแล้ว ' || v_in::text || '/' || v_exp::text;
    if v_notyet_n > 0 then
      select string_agg(x, ', ') into v_s from (
        select e->>'nick' x from jsonb_array_elements(p_facts->'attendance'->'not_yet') e limit 3) z;
      v_l1 := v_l1 || ' · ยังไม่มา: ' || coalesce(v_s, '-')
              || case when v_notyet_n > 3 then ' และอีก ' || (v_notyet_n - 3)::text || ' คน' else '' end;
    end if;
    if v_late_n > 0 then
      select string_agg(x, ', ') into v_s from (
        select (e->>'nick') || ' ' || coalesce(e->>'time', '') x
        from jsonb_array_elements(p_facts->'attendance'->'checked_in') e
        where e->>'status' in ('orange','red') limit 3) z;
      v_l1 := v_l1 || ' · สาย: ' || coalesce(v_s, '-')
              || case when v_late_n > 3 then ' และอีก ' || (v_late_n - 3)::text || ' คน' else '' end;
    end if;
  end if;

  -- line 2: service work
  v_l2 := '2) คิวออนไลน์วันนี้ ' || coalesce((p_facts->'queue'->>'today_appts_n'), '0') || ' นัด';
  if coalesce((p_facts->'queue'->>'today_appts_n')::int, 0) > 0 then
    select string_agg((e->>'nick') || ' ' || (e->>'n'), ', ') into v_s from (
      select e from jsonb_array_elements(coalesce(p_facts->'queue'->'holders', '[]'::jsonb)) e limit 3) z;
    if v_s is not null then v_l2 := v_l2 || ' (' || v_s || ')'; end if;
  end if;
  v_n := coalesce(jsonb_array_length(p_facts->'queue'->'overdue'), 0);
  if v_n > 0 then v_l2 := v_l2 || ' · คิวค้าง ' || v_n::text; end if;
  if coalesce((p_facts->'queue'->>'unassigned')::int, 0) > 0 then
    v_l2 := v_l2 || ' · ยังไม่มอบหมาย ' || (p_facts->'queue'->>'unassigned');
  end if;
  select coalesce(sum((e->>'n')::int), 0) into v_n
    from jsonb_array_elements(coalesce(p_facts->'queue'->'unclaimed', '[]'::jsonb)) e;
  if v_n > 0 then v_l2 := v_l2 || ' · ยังไม่รับงาน ' || v_n::text; end if;
  v_l2 := v_l2 || ' · คำติรอจัดการ ' || coalesce(p_facts->'feedback'->>'issues_unreviewed', '0');
  if coalesce((p_facts->'feedback'->>'praise_pending')::int, 0) > 0 then
    v_l2 := v_l2 || ' · คำชมรออนุมัติ ' || (p_facts->'feedback'->>'praise_pending');
  end if;

  -- line 3: other notable
  v_l3 := '3)';
  v_n := coalesce((p_facts->'checkout_yesterday'->>'count')::int, 0);
  if v_n > 0 then
    select string_agg((e->>'nick') || ' ' || coalesce(e->>'time', ''), ', ') into v_s from (
      select e from jsonb_array_elements(coalesce(p_facts->'checkout_yesterday'->'items', '[]'::jsonb)) e limit 2) z;
    v_l3 := v_l3 || ' เช็คเอาต์เย็นเมื่อวาน ' || v_n::text || ' คน'
            || case when v_s is not null then ' (' || v_s || ')' else '' end;
  end if;
  select count(*) into v_n
    from jsonb_array_elements(coalesce(p_facts->'notes_today', '[]'::jsonb)) e
    where coalesce(e->>'note', '') not like '%ปฏิบัติงานปกติ%';
  v_n := v_n + coalesce(jsonb_array_length(p_facts->'remarks_recent'), 0);
  if v_n > 0 then
    v_l3 := v_l3 || case when v_l3 <> '3)' then ' ·' else '' end
            || ' หมายเหตุเพิ่มเติม ' || v_n::text || ' รายการ (ดูแดชบอร์ด)';
  end if;
  v_n := coalesce(jsonb_array_length(p_facts->'team_coverage'), 0);
  if v_n > 0 then
    v_l3 := v_l3 || case when v_l3 <> '3)' then ' ·' else '' end
            || ' ทีมที่ยังไม่ครบ ' || v_n::text || ' กลุ่ม';
  end if;
  select string_agg((e->>'nick') || case when e->>'medal' = 'gold' then ' ทอง' else ' เงิน' end, ', ')
    into v_s
    from jsonb_array_elements(coalesce(p_facts->'attendance'->'checked_in', '[]'::jsonb)) e
   where e->>'medal' is not null;
  if v_s is not null then
    v_l3 := v_l3 || case when v_l3 <> '3)' then ' ·' else '' end || ' เหรียญ: ' || v_s;
  end if;
  if v_l3 = '3)' then v_l3 := '3) ไม่มีเรื่องอื่นที่ต้องรายงาน'; end if;

  if char_length(v_l1) > 120 then v_l1 := left(v_l1, 119) || '…'; end if;
  if char_length(v_l2) > 120 then v_l2 := left(v_l2, 119) || '…'; end if;
  if char_length(v_l3) > 120 then v_l3 := left(v_l3, 119) || '…'; end if;

  return v_l1 || chr(10) || v_l2 || chr(10) || v_l3;
end;
$fn$;

-- ============================================================
-- block 4a: daily_brief_prompt — system prompt (ไทย)
-- ============================================================

create or replace function public.daily_brief_prompt()
returns text
language sql
immutable
security definer
set search_path to 'public'
as $fn$
  select 'คุณเป็นผู้ช่วยหัวหน้า ตม.จว.ระยอง สรุปสถานการณ์ประจำวันให้หัวหน้าอ่านตอนเช้า' || chr(10) || chr(10) ||
'รูปแบบคำตอบ (บังคับ):' || chr(10) ||
'- ตอบ 3 บรรทัดพอดี ขึ้นต้นด้วย "1) " "2) " "3) " ตามลำดับ' || chr(10) ||
'- แต่ละบรรทัดยาวไม่เกิน 110 ตัวอักษร' || chr(10) ||
'- ห้ามใช้ markdown ห้ามมีคำนำหรือคำลงท้าย ตอบเฉพาะ 3 บรรทัดเท่านั้น' || chr(10) || chr(10) ||
'เนื้อหาแต่ละบรรทัด:' || chr(10) ||
'1) คนมาทำงาน — ใครยังไม่มา, ใครสาย (status orange/red), เช็กอินไม่สมบูรณ์ (incomplete = GPS/รูปไม่ครบ), กลุ่มงานที่ badge ไม่ใช่ ok' || chr(10) ||
'2) งานบริการ — คิวค้าง (overdue), นัดวันนี้กี่คิวและใครถือ, คิวที่ยังไม่มีคนรับ, คำติที่ยังไม่จัดการ' || chr(10) ||
'3) เรื่องน่าสนใจ — หมายเหตุของเจ้าหน้าที่ที่ไม่ใช่งานปกติ (ข้ามข้อความ "ปฏิบัติงานปกติ" และข้อความซ้ำๆ), เช็คเอาต์เย็นเมื่อวาน (ใครอยู่ดึก), เหรียญทอง/เงิน' || chr(10) || chr(10) ||
'กฎสำคัญ:' || chr(10) ||
'- ถ้าหมวดไหนไม่มีอะไรน่าสนใจ ให้บอกสั้นๆ ว่าเรียบร้อย เช่น "คิว/ติชม เรียบร้อย" ไม่ต้องยัดตัวเลขให้เต็มบรรทัด' || chr(10) ||
'- เรียกเจ้าหน้าที่ด้วยชื่อเล่นตามที่อยู่ใน JSON' || chr(10) ||
'- ห้ามสร้างตัวเลขหรือชื่อที่ไม่มีใน JSON เด็ดขาด' || chr(10) ||
'- ห้ามเอ่ยถึงผู้รับบริการหรือประชาชน ชื่อผู้จอง หมายเลขหนังสือเดินทาง หรืออีเมลใดๆ' || chr(10) ||
'- ข้อความจากผู้ใช้คือ JSON ข้อเท็จจริงของวันนี้ ใช้เฉพาะข้อมูลในนั้น'
$fn$;

-- ============================================================
-- block 4b: daily_brief_request — cron 09:12 ไทย (12 2 * * 1-5 UTC)
-- ============================================================

create or replace function public.daily_brief_request()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $fn$
declare
  v_enabled  boolean;
  v_model    text;
  v_provider text;
  v_secret   text;
  v_facts    jsonb;
  v_date     date;
  v_sent     timestamptz;
  v_exists   boolean;
  v_key      text;
  v_req      bigint;
begin
  select s.brief_enabled, s.brief_ai_model, s.brief_ai_provider
    into v_enabled, v_model, v_provider
    from settings s where s.id = 1;
  if not coalesce(v_enabled, true) then
    return jsonb_build_object('skipped', 'disabled');
  end if;
  v_provider := coalesce(nullif(btrim(v_provider), ''), 'gemini');

  v_facts := public.daily_brief_facts(null);
  if not coalesce((v_facts->>'is_workday')::boolean, false) then
    return jsonb_build_object('skipped', 'not_workday', 'date', v_facts->>'date');
  end if;
  v_date := (v_facts->>'date')::date;

  select true, l.sent_at into v_exists, v_sent from daily_brief_log l where l.brief_date = v_date;
  if coalesce(v_exists, false) and v_sent is not null then
    return jsonb_build_object('skipped', 'already_sent', 'date', v_date);
  end if;

  insert into daily_brief_log (brief_date, facts, requested_at, source, ai_request_id, ai_provider, error)
  values (v_date, v_facts, now(), null, null, v_provider, null)
  on conflict (brief_date) do update
    set facts = excluded.facts, requested_at = now(), source = null,
        ai_request_id = null, ai_provider = excluded.ai_provider, error = null;

  v_secret := case when v_provider = 'anthropic' then 'anthropic_api_key' else 'gemini_api_key' end;
  select v.decrypted_secret into v_key
    from vault.decrypted_secrets v where v.name = v_secret limit 1;

  -- ไม่มี key ใน vault → ข้ามการเรียก AI ไปเลย (send จะใช้ fallback)
  if v_key is null or btrim(v_key) = '' then
    update daily_brief_log set error = 'no_api_key:' || v_provider where brief_date = v_date;
    return jsonb_build_object('ok', true, 'date', v_date, 'provider', v_provider,
                              'ai_requested', false, 'reason', 'no_api_key');
  end if;

  if v_provider = 'anthropic' then
    select net.http_post(
      url     := 'https://api.anthropic.com/v1/messages',
      headers := jsonb_build_object(
                   'x-api-key', v_key,
                   'anthropic-version', '2023-06-01',
                   'content-type', 'application/json'),
      body    := jsonb_build_object(
                   'model', coalesce(v_model, 'claude-haiku-4-5-20251001'),
                   'max_tokens', 400,
                   'system', public.daily_brief_prompt(),
                   'messages', jsonb_build_array(
                     jsonb_build_object('role', 'user', 'content', v_facts::text))),
      timeout_milliseconds := 30000
    ) into v_req;
  else
    -- key อยู่ใน header เท่านั้น ห้ามใส่ใน query string (pg_net เก็บ url ไว้ใน log)
    select net.http_post(
      url     := 'https://generativelanguage.googleapis.com/v1beta/models/'
                 || coalesce(v_model, 'gemini-2.0-flash') || ':generateContent',
      headers := jsonb_build_object(
                   'x-goog-api-key', v_key,
                   'content-type', 'application/json'),
      body    := jsonb_build_object(
                   'system_instruction', jsonb_build_object(
                     'parts', jsonb_build_array(jsonb_build_object('text', public.daily_brief_prompt()))),
                   'contents', jsonb_build_array(jsonb_build_object(
                     'role', 'user',
                     'parts', jsonb_build_array(jsonb_build_object('text', v_facts::text)))),
                   'generationConfig', jsonb_build_object('maxOutputTokens', 400, 'temperature', 0.3)),
      timeout_milliseconds := 30000
    ) into v_req;
  end if;

  update daily_brief_log set ai_request_id = v_req where brief_date = v_date;

  return jsonb_build_object('ok', true, 'date', v_date, 'provider', v_provider,
                            'ai_requested', v_req is not null);
end;
$fn$;

-- ============================================================
-- block 5: daily_brief_send — cron 09:15 ไทย (15 2 * * 1-5 UTC)
-- ============================================================

create or replace function public.daily_brief_send(p_dry_run boolean default false, p_to text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_tz      text;
  v_date    date;
  v_log     daily_brief_log%rowtype;
  v_provider text;
  v_status  int;
  v_content text;
  v_ai      text;
  v_http_err text;
  v_lines   text[];
  v_ok      boolean := false;
  v_source  text;
  v_text    text;
  v_months  text[] := array['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.','ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
  v_thdate  text;
  v_subject text;
  v_html    text;
  v_recipients text;
  v_addr    text;
  v_li      text;
  v_sent    text[] := '{}';
  v_errs    text[] := '{}';
  v_send_status text;
begin
  select coalesce(nullif(btrim(s.tz), ''), 'Asia/Bangkok') into v_tz from settings s where s.id = 1;
  v_date := (now() at time zone coalesce(v_tz, 'Asia/Bangkok'))::date;

  select * into v_log from daily_brief_log l where l.brief_date = v_date;
  if not found then
    return jsonb_build_object('skipped', 'no_request', 'date', v_date);
  end if;
  if v_log.sent_at is not null and not coalesce(p_dry_run, false) then
    return jsonb_build_object('skipped', 'already_sent', 'date', v_date);
  end if;

  v_provider := coalesce(nullif(btrim(v_log.ai_provider), ''), 'gemini');

  if v_log.ai_request_id is not null then
    select r.status_code, r.content into v_status, v_content
      from net._http_response r where r.id = v_log.ai_request_id;
    if coalesce(v_status, 0) = 200 and v_content is not null then
      begin
        if v_provider = 'anthropic' then
          v_ai := (v_content::jsonb)->'content'->0->>'text';
        else
          v_ai := (v_content::jsonb)->'candidates'->0->'content'->'parts'->0->>'text';
        end if;
      exception when others then
        v_ai := null;
      end;
    else
      -- HTTP status ไม่ใช่ 200: เก็บ 500 ตัวแรกไว้ debug แล้วตกไปใช้ fallback
      v_http_err := left(coalesce(v_content, 'http_status=' || coalesce(v_status::text, 'null')), 500);
    end if;
  end if;

  -- validator: 3 บรรทัด non-empty, ขึ้นต้น "n) ", <=120 ตัวอักษร, ไม่มี code fence
  if v_ai is not null then
    v_lines := array(select btrim(l) from unnest(string_to_array(replace(v_ai, chr(13), ''), chr(10))) l
                     where btrim(l) <> '');
    v_ok := coalesce(array_length(v_lines, 1), 0) = 3
        and left(v_lines[1], 3) = '1) '
        and left(v_lines[2], 3) = '2) '
        and left(v_lines[3], 3) = '3) '
        and char_length(v_lines[1]) <= 120
        and char_length(v_lines[2]) <= 120
        and char_length(v_lines[3]) <= 120
        and position(repeat(chr(96), 3) in v_ai) = 0;
  end if;

  if coalesce(v_ok, false) then
    v_source := 'ai';
    v_text   := array_to_string(v_lines, chr(10));
  else
    v_source := 'fallback';
    v_text   := public.daily_brief_fallback_text(v_log.facts);
    v_lines  := array(select btrim(l) from unnest(string_to_array(v_text, chr(10))) l where btrim(l) <> '');
  end if;

  v_thdate := extract(day from v_date)::int::text || ' '
              || v_months[extract(month from v_date)::int] || ' '
              || (extract(year from v_date)::int + 543)::text;
  v_subject := 'สรุปเช้า ตม.ระยอง ' || v_thdate || ' — ' || left(substr(v_lines[1], 4), 60);

  v_html := '<div style="font-family:sans-serif;font-size:16px;line-height:1.7"><h3>สรุปเช้า ตม.ระยอง '
            || v_thdate || '</h3><ol>';
  foreach v_li in array v_lines loop
    v_html := v_html || '<li>'
              || replace(replace(replace(substr(v_li, 4), '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
              || '</li>';
  end loop;
  v_html := v_html || '</ol><p><a href="https://rayongimm.link/dashboard.html">เปิดแดชบอร์ด</a></p>'
            || '<p style="color:#888;font-size:13px">ข้อมูล ณ 09:15 · สรุปโดย '
            || case when v_source = 'ai' then 'AI' else 'ระบบ' end || '</p></div>';

  update daily_brief_log
     set brief_text = v_text, source = v_source, ai_raw = coalesce(v_ai, v_http_err, ai_raw)
   where brief_date = v_date;

  if coalesce(p_dry_run, false) then
    return jsonb_build_object('dry_run', true, 'date', v_date, 'source', v_source,
                              'provider', v_provider, 'subject', v_subject,
                              'brief_text', v_text, 'html', v_html);
  end if;

  v_recipients := coalesce(nullif(btrim(p_to), ''), (select s.brief_emails from settings s where s.id = 1));
  for v_addr in select btrim(a) from unnest(string_to_array(coalesce(v_recipients, ''), ',')) a
                where btrim(a) <> '' loop
    begin
      perform public.queue_send_email(v_addr, v_subject, v_html);
      v_sent := v_sent || v_addr;
    exception when others then
      v_errs := v_errs || (v_addr || ': ' || sqlerrm);
    end;
  end loop;

  v_send_status := case when coalesce(array_length(v_sent, 1), 0) = 0 then 'failed'
                        when coalesce(array_length(v_errs, 1), 0) > 0 then 'partial'
                        else 'ok' end;

  update daily_brief_log
     set sent_at = now(),
         sent_to = array_to_string(v_sent, ','),
         send_status = v_send_status,
         error = nullif(array_to_string(v_errs, ' ;; '), '')
   where brief_date = v_date;

  return jsonb_build_object('ok', v_send_status <> 'failed', 'date', v_date, 'source', v_source,
                            'provider', v_provider, 'subject', v_subject,
                            'sent_to', array_to_string(v_sent, ','),
                            'send_status', v_send_status,
                            'errors', array_to_string(v_errs, ' ;; '));
end;
$fn$;

-- ============================================================
-- block 6: do_admin_brief_preview — หัวหน้าเรียกดูได้ (authenticated + is_supervisor)
-- ============================================================

create or replace function public.do_admin_brief_preview(p_date date default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_tz    text;
  v_date  date;
  v_facts jsonb;
  v_row   jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if not exists (select 1 from officer o
                 where o.id = auth.uid() and o.is_supervisor and o.active) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  select coalesce(nullif(btrim(s.tz), ''), 'Asia/Bangkok') into v_tz from settings s where s.id = 1;
  v_date  := coalesce(p_date, (now() at time zone coalesce(v_tz, 'Asia/Bangkok'))::date);
  v_facts := public.daily_brief_facts(v_date);

  select to_jsonb(l) into v_row from daily_brief_log l where l.brief_date = v_date;

  return jsonb_build_object(
    'ok', true,
    'facts', v_facts,
    'fallback_text', public.daily_brief_fallback_text(v_facts),
    'log_row', v_row
  );
end;
$fn$;

-- ============================================================
-- block 6b: daily_brief_ai_ping — ทดสอบว่า gemini key ใช้ได้และมีโมเดลอะไรบ้าง
--           (read-only, ไม่ได้เรียกตอน migrate เพราะยังไม่มี key)
-- ============================================================

create or replace function public.daily_brief_ai_ping()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $fn$
declare
  v_key text;
  v_req bigint;
begin
  select v.decrypted_secret into v_key
    from vault.decrypted_secrets v where v.name = 'gemini_api_key' limit 1;
  if v_key is null or btrim(v_key) = '' then
    return jsonb_build_object('ok', false, 'error', 'no_api_key:gemini');
  end if;

  -- key อยู่ใน header เท่านั้น ห้ามใส่ใน query string
  select net.http_get(
    url     := 'https://generativelanguage.googleapis.com/v1beta/models',
    headers := jsonb_build_object('x-goog-api-key', v_key),
    timeout_milliseconds := 15000
  ) into v_req;

  return jsonb_build_object('ok', true, 'request_id', v_req,
    'hint', 'select status_code, left(content, 2000) from net._http_response where id = <request_id>;');
end;
$fn$;

-- ============================================================
-- block 7: grants
-- ============================================================

revoke all on function public.daily_brief_facts(date)          from public, anon, authenticated;
revoke all on function public.daily_brief_fallback_text(jsonb) from public, anon, authenticated;
revoke all on function public.daily_brief_prompt()             from public, anon, authenticated;
revoke all on function public.daily_brief_request()            from public, anon, authenticated;
revoke all on function public.daily_brief_send(boolean, text)  from public, anon, authenticated;
revoke all on function public.daily_brief_ai_ping()            from public, anon, authenticated;
revoke all on function public.do_admin_brief_preview(date)     from public, anon, authenticated;
grant execute on function public.do_admin_brief_preview(date)  to authenticated;

-- ============================================================
-- Verify — queries ที่รันจริงบน prod 17 ก.ย. 2569 (ผลอยู่ท้ายบรรทัด)
-- ============================================================
--
-- 1) ทุกฟังก์ชันมีตัวเดียว + security definer + สิทธิ์ถูกต้อง  → ผ่านทั้ง 6
-- select p.proname, count(*) n, bool_and(p.prosecdef) secdef,
--        string_agg(p.proconfig::text, ',') cfg,
--        bool_or(has_function_privilege('anon', p.oid, 'execute')) anon_x,
--        bool_or(has_function_privilege('authenticated', p.oid, 'execute')) auth_x,
--        bool_or(has_function_privilege('public', p.oid, 'execute')) pub_x
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public' and p.proname in
--        ('daily_brief_facts','daily_brief_fallback_text','daily_brief_prompt',
--         'daily_brief_request','daily_brief_send','daily_brief_ai_ping','do_admin_brief_preview')
--  group by 1 order by 1;
--   -> n=1 / secdef=true / anon=false / public=false ทุกตัว
--   -> authenticated=true เฉพาะ do_admin_brief_preview
--
-- 2) settings + RLS
-- select brief_enabled, brief_emails, brief_ai_provider, brief_ai_model, brief_line_group_id,
--        (select relrowsecurity from pg_class where relname = 'daily_brief_log') rls,
--        (select count(*) from pg_policies where tablename = 'daily_brief_log') npol
--   from settings where id = 1;
--   -> brief_enabled=t, brief_emails คัดลอกจาก queue_digest_emails (3 อีเมล),
--      brief_ai_provider='gemini', brief_ai_model='gemini-2.5-flash', rls=t, npol=0
--
-- 9) step 4 (17 ก.ย. 2569, หลังเจ้าของใส่ gemini_api_key ลง vault)
-- select name, created_at from vault.secrets order by 1;   -> มี gemini_api_key
-- select public.daily_brief_ai_ping();                     -> status 200, 50 models
--   -> gemini-2.5-flash มี (รองรับ generateContent), gemini-2.0-flash ไม่มีแล้ว
-- select public.daily_brief_request();                     -> ai_requested=true
--   -> net._http_response status_code = 404 ทั้ง gemini-2.0-flash และ gemini-2.5-flash
--   -> ยังหาสาเหตุ 404 ของ :generateContent ไม่จบ (ดู ai_raw ในแถว log วันที่ 2026-09-17)
-- select public.daily_brief_send(p_dry_run := true);       -> source='fallback' (ถูกต้องตาม design)
--   -> ai_raw เก็บ 500 ตัวแรกของ body ไว้ debug, sent_at ยังเป็น null
--
-- 3) facts ไม่มีข้อมูลผู้รับบริการ
-- select (public.daily_brief_facts()::text ~* '(passport|applicant|nationality|email|@)') pii_regex,
--        jsonb_path_exists(public.daily_brief_facts(),
--          '$.** ? (@ like_regex "passport|applicant|email")') pii_path;
--   -> false / false
--
-- 4) วันหยุด/เสาร์
-- select public.daily_brief_facts('2026-10-13')->>'is_workday',   -- วันหยุดนักขัตฤกษ์ -> false
--        public.daily_brief_facts('2026-10-13')->>'prev_workday', -- -> 2026-10-12
--        public.daily_brief_facts('2026-09-19')->>'is_workday';   -- เสาร์ -> false
--
-- 5) fallback 3 บรรทัด
-- select public.daily_brief_fallback_text(public.daily_brief_facts());
--   -> 3 บรรทัด ขึ้นต้น "1) " "2) " "3) " ตามกฎ
--
-- 6) request แบบไม่มี key ใน vault (vault.secrets มีแค่ cron_secret กับ resend_api_key)
-- select public.daily_brief_request();
--   -> {"ok":true,"date":"2026-09-17","provider":"gemini","ai_requested":false,"reason":"no_api_key"}
--   -> daily_brief_log: ai_provider='gemini', ai_request_id is null, error='no_api_key:gemini'
--
-- 7) dry run (ไม่ส่งเมล)
-- select public.daily_brief_send(p_dry_run := true);
--   -> source='fallback', provider='gemini', มี subject/html, daily_brief_log.sent_at ยังเป็น null
--   (แถวทดสอบของวันนี้ถูก delete ออกแล้วเพื่อให้รันจริงเริ่มสะอาด)
--
-- 8) cron ไม่ถูกแตะ
-- select count(*) from cron.job;                                  -- -> 9 (เท่าเดิม)
-- select count(*) from cron.job where jobname = 'queue-digest-mwf' and active;  -- -> 1
