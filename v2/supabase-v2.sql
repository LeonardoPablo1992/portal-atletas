-- =====================================================================
-- ProTrainerPlus v2 · tablas nuevas para atletas.headcoachleonardopablo.com/v2
--
-- Qué hace:   crea tablas nuevas con prefijo pt_ y sus permisos (RLS).
-- Qué NO hace: no modifica ni borra plans, sessions, profiles, comments,
--              evidencias ni nada del portal actual.
-- Se puede correr más de una vez sin problema.
--
-- Cómo correrlo: Supabase → tu proyecto → SQL Editor → New query →
--                pega todo este archivo → Run.
-- =====================================================================

-- Correo del usuario que hace la consulta (en minúsculas)
create or replace function public.pt_me() returns text
language sql stable as $$
  select lower(coalesce(auth.jwt() ->> 'email', ''))
$$;

-- ---------- Tablas por atleta (cada fila pertenece a un correo) ----------
create table if not exists public.pt_tasks (
  id text primary key,
  athlete_email text not null,
  date date,
  doc jsonb not null,
  updated_at timestamptz not null default now()
);
create table if not exists public.pt_acts (
  id text primary key, athlete_email text not null, doc jsonb not null, updated_at timestamptz not null default now()
);
create table if not exists public.pt_evo (
  id text primary key, athlete_email text not null, doc jsonb not null, updated_at timestamptz not null default now()
);
create table if not exists public.pt_messages (
  id text primary key, athlete_email text not null, doc jsonb not null, updated_at timestamptz not null default now()
);
create table if not exists public.pt_activity (
  id text primary key, athlete_email text not null, doc jsonb not null, updated_at timestamptz not null default now()
);
create table if not exists public.pt_notifs (
  id text primary key, athlete_email text not null, doc jsonb not null, updated_at timestamptz not null default now()
);

-- ---------- Datos del coach ----------
-- Perfil extendido del atleta (edad, género, FC en reposo…); id = correo del atleta
create table if not exists public.pt_athletes (
  id text primary key, doc jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now()
);
-- Biblioteca de ejercicios (ejercicio, grupo muscular, tipo, link de video)
create table if not exists public.pt_library (
  id text primary key, doc jsonb not null, updated_at timestamptz not null default now()
);
-- Plantillas de plan (días por grupo muscular, 4 fases)
create table if not exists public.pt_templates (
  id text primary key, doc jsonb not null, updated_at timestamptz not null default now()
);

create index if not exists pt_tasks_athlete_idx    on public.pt_tasks (athlete_email, date);
create index if not exists pt_acts_athlete_idx     on public.pt_acts (athlete_email);
create index if not exists pt_evo_athlete_idx      on public.pt_evo (athlete_email);
create index if not exists pt_messages_athlete_idx on public.pt_messages (athlete_email);
create index if not exists pt_activity_athlete_idx on public.pt_activity (athlete_email);
create index if not exists pt_notifs_athlete_idx   on public.pt_notifs (athlete_email);

-- ---------- Permisos (RLS) ----------
-- Coach (public.is_coach(), la misma función del portal actual): acceso total.
-- Atleta: solo ve y edita sus propias filas (athlete_email = su correo). No puede borrar.
do $$
declare t text;
begin
  foreach t in array array['pt_tasks','pt_acts','pt_evo','pt_messages','pt_activity','pt_notifs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('drop policy if exists "pt_coach_all" on public.%I', t);
    execute format('create policy "pt_coach_all" on public.%I for all to authenticated using (public.is_coach()) with check (public.is_coach())', t);
    execute format('drop policy if exists "pt_athlete_select" on public.%I', t);
    execute format('create policy "pt_athlete_select" on public.%I for select to authenticated using (athlete_email = public.pt_me())', t);
    execute format('drop policy if exists "pt_athlete_insert" on public.%I', t);
    execute format('create policy "pt_athlete_insert" on public.%I for insert to authenticated with check (athlete_email = public.pt_me())', t);
    execute format('drop policy if exists "pt_athlete_update" on public.%I', t);
    execute format('create policy "pt_athlete_update" on public.%I for update to authenticated using (athlete_email = public.pt_me()) with check (athlete_email = public.pt_me())', t);
  end loop;
end $$;

-- pt_athletes: el coach administra; el atleta solo puede leer su propio perfil
alter table public.pt_athletes enable row level security;
grant select, insert, update, delete on public.pt_athletes to authenticated;
drop policy if exists "pt_coach_all" on public.pt_athletes;
create policy "pt_coach_all" on public.pt_athletes for all to authenticated using (public.is_coach()) with check (public.is_coach());
drop policy if exists "pt_athlete_select" on public.pt_athletes;
create policy "pt_athlete_select" on public.pt_athletes for select to authenticated using (id = public.pt_me());

-- pt_library: el coach administra; cualquier usuario con sesión puede leer (para ver los videos)
alter table public.pt_library enable row level security;
grant select, insert, update, delete on public.pt_library to authenticated;
drop policy if exists "pt_coach_all" on public.pt_library;
create policy "pt_coach_all" on public.pt_library for all to authenticated using (public.is_coach()) with check (public.is_coach());
drop policy if exists "pt_read_all" on public.pt_library;
create policy "pt_read_all" on public.pt_library for select to authenticated using (true);

-- pt_templates: solo el coach
alter table public.pt_templates enable row level security;
grant select, insert, update, delete on public.pt_templates to authenticated;
drop policy if exists "pt_coach_all" on public.pt_templates;
create policy "pt_coach_all" on public.pt_templates for all to authenticated using (public.is_coach()) with check (public.is_coach());

-- Verificación rápida: debe listar las 9 tablas pt_ con RLS activo (rowsecurity = true)
select tablename, rowsecurity from pg_tables where schemaname = 'public' and tablename like 'pt\_%' order by tablename;
