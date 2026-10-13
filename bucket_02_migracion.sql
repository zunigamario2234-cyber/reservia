begin;

alter function public.auth_barberia_id() set search_path = public, pg_temp;
alter function public.auth_rol() set search_path = public, pg_temp;

drop policy if exists "subir fotos" on storage.objects;
drop policy if exists "actualizar fotos" on storage.objects;
drop policy if exists "eliminar fotos" on storage.objects;
drop policy if exists "ver fotos" on storage.objects;

create policy fotos_insert_dueno on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'fotos'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] in ('logos','portadas','profesionales','servicios','alianzas')
    and (storage.foldername(name))[2] = public.auth_barberia_id()::text
    and public.auth_rol() = 'dueno'
  );

create policy fotos_update_dueno on storage.objects
  for update to authenticated
  using (
    bucket_id = 'fotos'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] in ('logos','portadas','profesionales','servicios','alianzas')
    and (storage.foldername(name))[2] = public.auth_barberia_id()::text
    and public.auth_rol() = 'dueno'
  )
  with check (
    bucket_id = 'fotos'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] in ('logos','portadas','profesionales','servicios','alianzas')
    and (storage.foldername(name))[2] = public.auth_barberia_id()::text
    and public.auth_rol() = 'dueno'
  );

create policy fotos_delete_dueno on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'fotos'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] in ('logos','portadas','profesionales','servicios','alianzas')
    and (storage.foldername(name))[2] = public.auth_barberia_id()::text
    and public.auth_rol() = 'dueno'
  );

create policy fotos_select_propia on storage.objects
  for select to authenticated
  using (
    bucket_id = 'fotos'
    and (storage.foldername(name))[2] = public.auth_barberia_id()::text
  );

commit;
