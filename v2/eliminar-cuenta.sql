-- =========================================================
-- ProTrainerPlus · Eliminar cuenta (la hace la propia clienta / cliente)
-- Ejecutar UNA vez en Supabase → SQL Editor → New query → Run.
-- Se puede volver a correr sin problema.
--
-- Qué hace public.delete_my_account():
--   1. Solo funciona para la persona con sesión iniciada y NUNCA para el coach.
--   2. Borra todas sus filas de: pt_tasks, pt_acts, pt_evo (incluye foto de perfil),
--      pt_messages, pt_activity, pt_notifs, pt_athletes, comments, evidence,
--      sessions, plans y profiles.
--   3. Intenta borrar sus archivos del bucket «evidencias» (la app ya los borra antes
--      con la API de Storage; esto es un respaldo).
--   4. Borra su usuario de acceso (auth.users) para que pueda registrarse de nuevo
--      con el mismo correo, sin historial.
-- =========================================================

create or replace function public.delete_my_account()
returns json
language plpgsql
security definer
set search_path = public, auth, storage
as $$
declare
  em  text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  t   text;
  c   int;
  total int := 0;
  files int := 0;
begin
  if uid is null or em = '' then
    raise exception 'not_authenticated';
  end if;
  if public.is_coach() then
    raise exception 'coach_cannot_delete';
  end if;

  -- tablas con columna athlete_email (hijas primero)
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

  if to_regclass('public.profiles') is not null then
    delete from public.profiles where lower(email) = em;
    get diagnostics c = row_count; total := total + c;
  end if;

  -- respaldo: archivos de evidencias (carpeta = correo)
  begin
    delete from storage.objects where bucket_id = 'evidencias' and lower(split_part(name, '/', 1)) = em;
    get diagnostics files = row_count;
  exception when others then
    files := -1;  -- Supabase no permite borrar directo: la app ya los borró con la API
  end;

  -- usuario de acceso
  delete from auth.users where id = uid;

  return json_build_object('ok', true, 'rows', total, 'files', files);
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Permiso para que cada persona borre SUS archivos de evidencias (carpeta con su correo)
drop policy if exists "evidencias_owner_delete" on storage.objects;
create policy "evidencias_owner_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'evidencias' and lower(split_part(name, '/', 1)) = public.pt_me());
