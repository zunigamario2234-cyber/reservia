begin;

drop policy if exists fotos_insert_dueno on storage.objects;
drop policy if exists fotos_update_dueno on storage.objects;
drop policy if exists fotos_delete_dueno on storage.objects;
drop policy if exists fotos_select_propia on storage.objects;

create policy "subir fotos" on storage.objects
  for insert to public
  with check (bucket_id = 'fotos');

create policy "actualizar fotos" on storage.objects
  for update to public
  using (bucket_id = 'fotos')
  with check (bucket_id = 'fotos');

create policy "eliminar fotos" on storage.objects
  for delete to public
  using (bucket_id = 'fotos');

create policy "ver fotos" on storage.objects
  for select to public
  using (bucket_id = 'fotos');

commit;
