-- =========================================================
-- ProTrainerPlus · Eliminar cuenta
--   · delete_my_account()            → la propia clienta / cliente borra su cuenta
--   · coach_delete_client(correo)    → el coach borra a un cliente
-- Ejecutar en Supabase → SQL Editor → New query → Run.
-- Se puede volver a correr sin problema (reemplaza la versión anterior).
--
-- Se borra TODO lo de esa persona: pt_tasks, pt_acts, pt_evo (incluye foto de perfil),
-- pt_messages, pt_activity, pt_notifs, pt_athletes, su plan personal en pt_templates,
-- comments, evidence, sessions, plans, profiles, sus archivos del bucket «evidencias»
-- y su usuario de acceso (auth.users). Después puede registrarse de nuevo, en blanco.
-- La cuenta del coach nunca se puede borrar por estas vías.
-- =========================================================

-- Rutina interna (no se puede llamar desde la app)
create or replace function public._pt_purge_email(em text)
returns json
language plpgsql
security definer
set search_path = public, auth, storage
as $$
declare
  t text;
  c int;
  total int := 0;
  files int := 0;
begin
  em := lower(trim(coalesce(em, '')));
  if em = '' then raise exception 'invalid_email'; end if;

  foreach t in array array['comments','evidence','sessions','plans',
                           'pt_tasks','pt_acts','pt_evo','pt_messages','pt_activity','pt_notifs'] loop
    if to_regclass('public.' || t) is not null then
      execute format('delete from public.%I where lower(athlete_email) = $1', t) using em;
      get diagnostics c = row_count; total := total + c;
    end if;
  end loop;

  if to_regclass('public.pt_athletes') is not null then
    delete from public.pt_athletes where lower(id) = em;
    get diagnostics c = row_count; total := total + c;
  end if;

  if to_regclass('public.pt_templates') is not null then
    delete from public.pt_templates where lower(coalesce(doc ->> 'athleteId', '')) = em;
    get diagnostics c = row_count; total := total + c;
  end if;

  if to_regclass('public.profiles') is not null then
    delete from public.profiles where lower(email) = em;
    get diagnostics c = row_count; total := total + c;
  end if;

  -- respaldo: archivos de evidencias (la app ya los borra antes con la API de Storage)
  begin
    delete from storage.objects where bucket_id = 'evidencias' and lower(split_part(name, '/', 1)) = em;
    get diagnostics files = row_count;
  exception when others then
    files := -1;
  end;

  delete from auth.users where lower(email) = em;

  return json_build_object('ok', true, 'rows', total, 'files', files);
end;
$$;
revoke all on function public._pt_purge_email(text) from public, anon, authenticated;

-- 1) La propia persona borra su cuenta
create or replace function public.delete_my_account()
returns json
language plpgsql
security definer
set search_path = public, auth, storage
as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null or em = '' then raise exception 'not_authenticated'; end if;
  if public.is_coach() then raise exception 'coach_cannot_delete'; end if;
  return public._pt_purge_email(em);
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- 2) El coach borra a un cliente
create or replace function public.coach_delete_client(target_email text)
returns json
language plpgsql
security definer
set search_path = public, auth, storage
as $$
declare
  em text := lower(trim(coalesce(target_email, '')));
begin
  if not public.is_coach() then raise exception 'not_coach'; end if;
  if em = '' or em = lower(coalesce(auth.jwt() ->> 'email', '')) then raise exception 'invalid_target'; end if;
  return public._pt_purge_email(em);
end;
$$;
revoke all on function public.coach_delete_client(text) from public, anon;
grant execute on function public.coach_delete_client(text) to authenticated;

-- Permisos para borrar archivos de evidencias con la API de Storage
drop policy if exists "evidencias_owner_delete" on storage.objects;
create policy "evidencias_owner_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'evidencias' and lower(split_part(name, '/', 1)) = public.pt_me());

drop policy if exists "evidencias_coach_delete" on storage.objects;
create policy "evidencias_coach_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'evidencias' and public.is_coach());
