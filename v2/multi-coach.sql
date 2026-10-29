-- =========================================================
-- ProTrainerPlus · MULTI-COACH
-- Ejecutar UNA vez en Supabase → SQL Editor → New query → Run (después de supabase-v2.sql
-- y eliminar-cuenta.sql). Se puede volver a correr sin problema.
--
-- Qué hace:
--  · Cada coach ve SOLO a sus clientes (vínculo activo en pt_links). Ningún coach ve
--    los clientes de otro.
--  · Registro «Soy coach»: alta inmediata con 14 días de prueba (pt_coaches).
--  · Catálogo público de coaches para los clientes (pt_coach_profiles).
--  · Cliente → solicitud al coach → el coach acepta o rechaza.
--  · Todos los clientes actuales quedan asignados al coach principal
--    (coach@headcoachleonardopablo.com), así nada cambia para ellos.
--  · Las tablas del portal anterior (plans, sessions, profiles…) NO se tocan: siguen
--    siendo solo del coach principal.
-- =========================================================

-- ---------- Coaches de la plataforma ----------
create table if not exists public.pt_coaches (
  email         text primary key,
  user_id       uuid,
  name          text,
  status        text not null default 'trial' check (status in ('trial','active','suspended')),
  trial_ends_at timestamptz,
  created_at    timestamptz not null default now()
);
alter table public.pt_coaches enable row level security;
drop policy if exists "pt_coaches_read" on public.pt_coaches;
create policy "pt_coaches_read" on public.pt_coaches for select to authenticated
  using (email = public.pt_me() or public.is_coach());

-- ---------- Vínculo cliente ↔ coach ----------
create table if not exists public.pt_links (
  id            bigserial primary key,
  athlete_email text not null,
  coach_email   text not null,
  status        text not null check (status in ('pending','invited','active','rejected','ended')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists pt_links_coach_idx   on public.pt_links (coach_email, status);
create index if not exists pt_links_athlete_idx on public.pt_links (athlete_email, status);
create unique index if not exists pt_links_one_active on public.pt_links (athlete_email) where status = 'active';
alter table public.pt_links enable row level security;
drop policy if exists "pt_links_read" on public.pt_links;
create policy "pt_links_read" on public.pt_links for select to authenticated
  using (athlete_email = public.pt_me() or coach_email = public.pt_me());

-- ---------- Ficha pública del coach (catálogo) ----------
create table if not exists public.pt_coach_profiles (
  email      text primary key,
  doc        jsonb not null default '{}'::jsonb,
  public     boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.pt_coach_profiles enable row level security;

-- ---------- Funciones de apoyo ----------
create or replace function public.pt_is_coach() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_coach()
      or exists (select 1 from public.pt_coaches where email = public.pt_me() and status <> 'suspended');
$$;

create or replace function public.pt_coach_of(em text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.pt_links
                 where coach_email = public.pt_me() and athlete_email = lower(em) and status = 'active');
$$;

drop policy if exists "pt_cp_read"  on public.pt_coach_profiles;
drop policy if exists "pt_cp_write" on public.pt_coach_profiles;
create policy "pt_cp_read"  on public.pt_coach_profiles for select to authenticated
  using (public or email = public.pt_me());
create policy "pt_cp_write" on public.pt_coach_profiles for all to authenticated
  using (email = public.pt_me() and public.pt_is_coach())
  with check (email = public.pt_me() and public.pt_is_coach());

-- ---------- Permisos de las tablas de la app nueva: cada coach, solo sus clientes ----------
do $$
declare t text;
begin
  foreach t in array array['pt_tasks','pt_acts','pt_evo','pt_messages','pt_activity','pt_notifs'] loop
    execute format('drop policy if exists "pt_coach_all" on public.%I', t);
    execute format('drop policy if exists "pt_coach_linked" on public.%I', t);
    execute format('create policy "pt_coach_linked" on public.%I for all to authenticated using (public.pt_coach_of(athlete_email)) with check (public.pt_coach_of(athlete_email))', t);
  end loop;
end $$;

drop policy if exists "pt_coach_all"    on public.pt_athletes;
drop policy if exists "pt_coach_linked" on public.pt_athletes;
create policy "pt_coach_linked" on public.pt_athletes for all to authenticated
  using (public.pt_coach_of(id)) with check (public.pt_coach_of(id));

-- Biblioteca compartida: la leen todos; la alimentan todos los coaches; borra solo el coach principal
drop policy if exists "pt_coach_all"   on public.pt_library;
drop policy if exists "pt_lib_insert"  on public.pt_library;
drop policy if exists "pt_lib_update"  on public.pt_library;
drop policy if exists "pt_lib_delete"  on public.pt_library;
create policy "pt_lib_insert" on public.pt_library for insert to authenticated with check (public.pt_is_coach());
create policy "pt_lib_update" on public.pt_library for update to authenticated using (public.pt_is_coach()) with check (public.pt_is_coach());
create policy "pt_lib_delete" on public.pt_library for delete to authenticated using (public.is_coach());

-- Plantillas: de cada coach
alter table public.pt_templates add column if not exists coach_email text;
update public.pt_templates set coach_email = 'coach@headcoachleonardopablo.com' where coach_email is null;
alter table public.pt_templates alter column coach_email set default public.pt_me();
drop policy if exists "pt_coach_all"  on public.pt_templates;
drop policy if exists "pt_tpl_owner"  on public.pt_templates;
create policy "pt_tpl_owner" on public.pt_templates for all to authenticated
  using (coach_email = public.pt_me()) with check (coach_email = public.pt_me());

-- ---------- RPC: rol de quien entra ----------
create or replace function public.pt_my_role() returns json
language plpgsql stable security definer set search_path = public as $$
declare em text := public.pt_me(); c record; l record;
begin
  select * into c from public.pt_coaches where email = em;
  select * into l from public.pt_links where athlete_email = em and status = 'active' limit 1;
  return json_build_object(
    'coach',  public.pt_is_coach(),
    'admin',  public.is_coach(),
    'status', coalesce(c.status, case when public.is_coach() then 'active' else null end),
    'trial_ends_at', c.trial_ends_at,
    'linked', l.id is not null,
    'coach_email', l.coach_email);
end $$;

-- ---------- RPC: registrarse como coach (prueba de 14 días) ----------
create or replace function public.pt_register_coach(p_name text) returns json
language plpgsql security definer set search_path = public, auth as $$
declare em text := public.pt_me();
begin
  if auth.uid() is null or em = '' then raise exception 'not_authenticated'; end if;
  if exists (select 1 from public.pt_links where athlete_email = em and status = 'active') then
    raise exception 'already_athlete';
  end if;
  insert into public.pt_coaches(email, user_id, name, status, trial_ends_at)
  values (em, auth.uid(), nullif(trim(p_name), ''), 'trial', now() + interval '14 days')
  on conflict (email) do nothing;
  insert into public.pt_coach_profiles(email, doc, public)
  values (em, jsonb_build_object('name', coalesce(nullif(trim(p_name), ''), split_part(em, '@', 1))), true)
  on conflict (email) do nothing;
  return public.pt_my_role();
end $$;

-- ---------- RPC: clientes y solicitudes del coach ----------
create or replace function public.pt_my_clients() returns table(email text, full_name text, since timestamptz)
language sql stable security definer set search_path = public as $$
  select l.athlete_email, coalesce(p.full_name, ''), l.updated_at
  from public.pt_links l left join public.profiles p on lower(p.email) = l.athlete_email
  where l.coach_email = public.pt_me() and l.status = 'active' and public.pt_is_coach();
$$;

create or replace function public.pt_coach_requests() returns table(athlete_email text, full_name text, status text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.athlete_email, coalesce(p.full_name, ''), l.status, l.created_at
  from public.pt_links l left join public.profiles p on lower(p.email) = l.athlete_email
  where l.coach_email = public.pt_me() and l.status in ('pending','invited') and public.pt_is_coach()
  order by l.created_at desc;
$$;

-- ---------- RPC: el cliente pide entrenar con un coach ----------
create or replace function public.pt_request_coach(p_coach text) returns text
language plpgsql security definer set search_path = public as $$
declare em text := public.pt_me(); co text := lower(trim(coalesce(p_coach, '')));
begin
  if auth.uid() is null or em = '' then raise exception 'not_authenticated'; end if;
  if public.pt_is_coach() then raise exception 'coach_cannot_request'; end if;
  if not exists (select 1 from public.pt_coach_profiles where email = co and public) then raise exception 'coach_not_found'; end if;
  if exists (select 1 from public.pt_links where athlete_email = em and status = 'active') then raise exception 'already_linked'; end if;
  update public.pt_links set status = 'ended', updated_at = now() where athlete_email = em and status = 'pending';
  insert into public.pt_links(athlete_email, coach_email, status) values (em, co, 'pending');
  return 'pending';
end $$;

create or replace function public.pt_cancel_request() returns text
language sql security definer set search_path = public as $$
  update public.pt_links set status = 'ended', updated_at = now()
  where athlete_email = public.pt_me() and status = 'pending';
  select 'ended';
$$;

-- ---------- RPC: el coach acepta o rechaza ----------
create or replace function public.pt_respond_request(p_athlete text, p_accept boolean) returns text
language plpgsql security definer set search_path = public as $$
declare em text := lower(trim(coalesce(p_athlete, ''))); n int;
begin
  if not public.pt_is_coach() then raise exception 'not_coach'; end if;
  if p_accept and exists (select 1 from public.pt_links where athlete_email = em and status = 'active') then
    update public.pt_links set status = 'rejected', updated_at = now() where athlete_email = em and coach_email = public.pt_me() and status = 'pending';
    raise exception 'already_linked';
  end if;
  update public.pt_links set status = case when p_accept then 'active' else 'rejected' end, updated_at = now()
  where athlete_email = em and coach_email = public.pt_me() and status = 'pending';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'request_not_found'; end if;
  return case when p_accept then 'active' else 'rejected' end;
end $$;

-- ---------- RPC: el coach da de alta un cliente ----------
-- Cuenta recién creada por el coach (o sin cuenta) → queda vinculada.
-- Si la persona ya existía o ya tiene coach → se le envía una invitación que debe aceptar.
create or replace function public.pt_coach_add_client(p_athlete text) returns text
language plpgsql security definer set search_path = public as $$
declare em text := lower(trim(coalesce(p_athlete, ''))); me text := public.pt_me(); fresh boolean;
begin
  if not public.pt_is_coach() then raise exception 'not_coach'; end if;
  if em = '' or em = me then raise exception 'invalid_target'; end if;
  if exists (select 1 from public.pt_links where athlete_email = em and coach_email = me and status = 'active') then return 'active'; end if;
  fresh := not exists (select 1 from public.profiles where lower(email) = em and created_at < now() - interval '30 minutes');
  if fresh and not exists (select 1 from public.pt_links where athlete_email = em and status in ('active','pending','invited')) then
    insert into public.pt_links(athlete_email, coach_email, status) values (em, me, 'active');
    return 'active';
  end if;
  update public.pt_links set status = 'ended', updated_at = now() where athlete_email = em and coach_email = me and status = 'invited';
  insert into public.pt_links(athlete_email, coach_email, status) values (em, me, 'invited');
  return 'invited';
end $$;

-- ---------- RPC: el cliente responde una invitación ----------
create or replace function public.pt_respond_invite(p_coach text, p_accept boolean) returns text
language plpgsql security definer set search_path = public as $$
declare em text := public.pt_me(); co text := lower(trim(coalesce(p_coach, ''))); n int;
begin
  if p_accept and exists (select 1 from public.pt_links where athlete_email = em and status = 'active') then raise exception 'already_linked'; end if;
  update public.pt_links set status = case when p_accept then 'active' else 'rejected' end, updated_at = now()
  where athlete_email = em and coach_email = co and status = 'invited';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'invite_not_found'; end if;
  if p_accept then
    update public.pt_links set status = 'ended', updated_at = now() where athlete_email = em and status = 'pending';
  end if;
  return case when p_accept then 'active' else 'rejected' end;
end $$;

-- ---------- RPC: confirmar el correo de un cliente recién creado por el coach ----------
create or replace function public.pt_coach_confirm_email(p_email text) returns boolean
language plpgsql security definer set search_path = public, auth as $$
declare em text := lower(trim(coalesce(p_email, '')));
begin
  if not public.pt_coach_of(em) then raise exception 'not_your_client'; end if;
  update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now())
  where lower(email) = em and created_at > now() - interval '30 minutes';
  return true;
end $$;

-- ---------- Eliminar: ahora respeta el coach de cada cliente ----------
create or replace function public.coach_delete_client(target_email text) returns json
language plpgsql security definer set search_path = public, auth, storage as $$
declare em text := lower(trim(coalesce(target_email, '')));
begin
  if not public.pt_is_coach() then raise exception 'not_coach'; end if;
  if em = '' or em = public.pt_me() then raise exception 'invalid_target'; end if;
  if not public.pt_coach_of(em) then raise exception 'not_your_client'; end if;
  delete from public.pt_links where athlete_email = em;
  return public._pt_purge_email(em);
end $$;

create or replace function public.delete_my_account() returns json
language plpgsql security definer set search_path = public, auth, storage as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null or em = '' then raise exception 'not_authenticated'; end if;
  if public.pt_is_coach() then raise exception 'coach_cannot_delete'; end if;
  delete from public.pt_links where athlete_email = em;
  return public._pt_purge_email(em);
end $$;

-- ---------- Permisos de ejecución ----------
do $$
declare f text;
begin
  foreach f in array array['pt_my_role()','pt_register_coach(text)','pt_my_clients()','pt_coach_requests()',
    'pt_request_coach(text)','pt_cancel_request()','pt_respond_request(text,boolean)','pt_coach_add_client(text)',
    'pt_respond_invite(text,boolean)','pt_coach_confirm_email(text)','pt_is_coach()','pt_coach_of(text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ---------- Migración: el coach principal y sus clientes actuales ----------
insert into public.pt_coaches(email, user_id, name, status)
select lower(email), user_id, 'Head Coach Leonardo Pablo', 'active' from public.coaches
on conflict (email) do update set status = 'active';

insert into public.pt_coach_profiles(email, doc, public) values (
  'coach@headcoachleonardopablo.com',
  jsonb_build_object(
    'name', 'Head Coach Leonardo Pablo',
    'title', 'Entrenamiento personalizado y nutrición deportiva',
    'bio', 'Planes de entrenamiento y alimentación con base científica: periodización en 4 fases, control de cargas (sesión-RPE, ACWR), zonas de frecuencia cardiaca y ajuste según tu ciclo menstrual. Seguimiento cercano desde la app.',
    'specialties', jsonb_build_array('Hipertrofia','Recomposición corporal','Fuerza','Nutrición deportiva','Entrenamiento femenino'),
    'city', 'Ciudad de México',
    'modality', 'En línea y presencial',
    'prices', jsonb_build_array(
      jsonb_build_object('label','Plan de entrenamiento','price',599),
      jsonb_build_object('label','Plan de nutrición','price',599),
      jsonb_build_object('label','Combo entrenamiento + nutrición','price',987)),
    'web', 'https://headcoachleonardopablo.com'),
  true)
on conflict (email) do nothing;

insert into public.pt_links(athlete_email, coach_email, status)
select distinct x.e, 'coach@headcoachleonardopablo.com', 'active'
from (
  select lower(email) e from public.profiles
  union select lower(athlete_email) from public.plans
  union select lower(id) from public.pt_athletes
  union select lower(athlete_email) from public.pt_tasks
) x
where x.e is not null and x.e like '%@%'
  and x.e not in (select lower(email) from public.coaches)
  and x.e not in (select email from public.pt_coaches)
  and not exists (select 1 from public.pt_links l where l.athlete_email = x.e and l.status = 'active');
